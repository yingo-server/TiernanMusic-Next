// L5 logic/download · 下载管理器（并发队列 + 分块进度下载）
// 职责：enqueue/pause/resume/cancel/retry/listTasks；并发上限 3（Future 队列调度，
// 不引 isolate）。下载经 PlaybackService.resolvePlaySource 拿 URL 后由本类
// HttpClient 分块读流，每 chunk 更新 task 进度并 onTask 回调；落盘走
// DownloadStore.commitDownload 语义——逐块写 <final>.dlpart 临时文件，完成后
// 收尾（rename 由 core 层 commitDownload 承担；本类只把 .dlpart 改名为
// 移交前的 staging，或直接读回 bytes 后 commit，见 _finishCommit）。
// 持久化策略：任务队列为内存态，启动不恢复（进程结束未完成任务自然丢弃，
// 用户可手动 retry）——刻意不存 KeyValueSettings，避免半成品文件悬空引用。
// 铁律：每方法 try/catch + Log('logic.download')；禁 surface/flutter。
// 可 import logic/player/playback_service（同级 logic 互调合法）与 core 桥依赖。

import 'dart:async';
import 'dart:io';

import '../../bridges/bridge_kernel.dart' show Log;
import '../player/playback_service.dart';
import 'download_models.dart';
import 'download_job.dart';
import '../../bridges/bridge_core.dart' show DownloadRecord, DownloadStore, SongBrief, SongDao, SongRecord;

const String _tag = 'logic.download';

/// 下载管理器。构造注入 PlaybackService + SongDao + DownloadStore。
class DownloadManager {
  DownloadManager({
    required PlaybackService playbackService,
    required SongDao songDao,
    required DownloadStore downloadStore,
    int maxConcurrent = 3,
  })  : _playback = playbackService,
        _songDao = songDao,
        _store = downloadStore,
        _maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  final PlaybackService _playback;
  final SongDao _songDao;
  final DownloadStore _store;
  final int _maxConcurrent;

  /// 入队顺序的任务表（hash → task）。
  final Map<String, DownloadTask> _tasks = {};
  final List<String> _order = [];

  /// 运行中的分块下载 Future（hash → 运行 future），用于 pause/cancel 中断。
  final Map<String, RunningJob> _running = {};

  /// 任务变更回调（UI 经桥订阅；回调内异常由 _emit 捕获）。
  void Function(DownloadEvent event)? onTask;

  bool _disposed = false;

  // ─── 查询 ───

  /// 当前任务快照（入队顺序的不可变副本）。
  List<DownloadTask> listTasks() {
    try {
      return List.unmodifiable(
          _order.map((h) => _tasks[h]).whereType<DownloadTask>().toList());
    } catch (e, st) {
      Log.e(_tag, 'listTasks failed', e, st);
      return const [];
    }
  }

  DownloadTask? taskOf(String hash) {
    try {
      return _tasks[hash.trim().toLowerCase()];
    } catch (e, st) {
      Log.e(_tag, 'taskOf($hash) failed', e, st);
      return null;
    }
  }

  // ─── 入队 ───

  /// 入队：同 hash 且 pending/running 已存在则去重跳过（返回已有任务）；
  /// done/failed/paused 同 hash 重复入队允许（重新排队）。
  Future<DownloadTask?> enqueue(SongBrief song, String quality) async {
    final hash = song.hash.trim().toLowerCase();
    try {
      if (hash.isEmpty) {
        Log.w(_tag, 'enqueue empty hash ignored');
        return null;
      }
      final existing = _tasks[hash];
      if (existing != null &&
          (existing.status == DownloadStatus.pending ||
              existing.status == DownloadStatus.running)) {
        Log.d(_tag, 'enqueue dedup hit $hash (${existing.status.name})');
        return existing;
      }
      final q = quality.trim().isEmpty ? '128' : quality.trim();
      final task = DownloadTask(song: song, quality: q);
      _tasks[hash] = task;
      if (!_order.contains(hash)) _order.add(hash);
      Log.d(_tag, 'enqueued $hash q=$q');
      _emit(task);
      _pump();
      return task;
    } catch (e, st) {
      Log.e(_tag, 'enqueue $hash failed', e, st);
      return null;
    }
  }

  // ─── 控制 ───

  /// 暂停：running 请求中断（下载循环检测标志退出并清 .dlpart），
  /// pending 直接置 paused。恢复后从头重下（分块流不支持可靠续传偏移）。
  void pause(String hash) {
    final h = hash.trim().toLowerCase();
    try {
      final t = _tasks[h];
      if (t == null) return;
      if (t.status == DownloadStatus.pending) {
        t.status = DownloadStatus.paused;
        Log.d(_tag, 'pause pending $h');
        _emit(t);
        return;
      }
      if (t.status == DownloadStatus.running) {
        final job = _running[h];
        job?.abort = true; // 下载循环自检退出；收尾在 _runOne
        Log.d(_tag, 'pause requested running $h');
        // _runOne 异常路径（DownloadAborted 被 _runOne 外层 catch 捕获）会把任务
        // 置 failed；此处预置 paused 意图，_runOne 结束后校正见 _runOne 的
        // aborted 分支。这里立即 emit paused 让 UI 不悬挂在「下载中」。
        t.status = DownloadStatus.paused;
        t.error = null;
        _emit(t);
      }
    } catch (e, st) {
      Log.e(_tag, 'pause $h failed', e, st);
    }
  }

  /// 恢复：paused → pending 重新排队（从头下载）。
  void resume(String hash) {
    final h = hash.trim().toLowerCase();
    try {
      final t = _tasks[h];
      if (t == null || t.status != DownloadStatus.paused) return;
      t.status = DownloadStatus.pending;
      t.error = null;
      Log.d(_tag, 'resume $h');
      _emit(t);
      _pump();
    } catch (e, st) {
      Log.e(_tag, 'resume $h failed', e, st);
    }
  }

  /// 取消：running 请求中断；移出任务表；清理 .dlpart 残留（尽力）。
  Future<void> cancel(String hash) async {
    final h = hash.trim().toLowerCase();
    try {
      final t = _tasks[h];
      if (t == null) return;
      // 按运行句柄（而非 status）判定：pause() 会把 status 预置成 paused，
      // 但运行体可能仍在收尾；必须等它彻底退出再删 .dlpart，否则旧体
      // 可能在清理之后再写临时文件，留下残留。
      final job = _running[h];
      if (job != null) {
        job.abort = true;
        job.cancelled = true; // 收尾不得再 emit 已取消任务的 paused 幽灵事件
        // 等待运行体退出（有上限，避免调用方悬挂）。
        await job.done.future.timeout(const Duration(seconds: 10),
            onTimeout: () {});
      }
      _tasks.remove(h);
      _order.remove(h);
      // .dlpart 残留清理：任务已移除，无运行体再写它（running 已等 done）。
      // 尽力删除，失败留痕不阻断。
      try {
        final dir = await _storeDir();
        final part = File('$dir${Platform.pathSeparator}$h.dlpart');
        if (part.existsSync()) part.deleteSync();
      } catch (e, st) {
        Log.w(_tag, 'cancel cleanup .dlpart $h failed ERR=$e ST=$st');
      }
      Log.d(_tag, 'cancelled $h');
      _emit(null);
    } catch (e, st) {
      Log.e(_tag, 'cancel $h failed', e, st);
    }
  }

  /// 重试：failed → pending 重新排队（清零进度与错误）。
  void retry(String hash) {
    final h = hash.trim().toLowerCase();
    try {
      final t = _tasks[h];
      if (t == null || t.status != DownloadStatus.failed) return;
      t.status = DownloadStatus.pending;
      t.bytesDownloaded = 0;
      t.bytesTotal = 0;
      t.error = null;
      Log.d(_tag, 'retry $h');
      _emit(t);
      _pump();
    } catch (e, st) {
      Log.e(_tag, 'retry $h failed', e, st);
    }
  }

  /// 释放资源（进程级，通常不调用）。等待运行体退出并清回调。
  Future<void> dispose() async {
    try {
      _disposed = true;
      for (final job in _running.values) {
        job.abort = true;
      }
      await Future.wait(_running.values.map((j) => j.done.future));
      onTask = null;
      Log.d(_tag, 'disposed');
    } catch (e, st) {
      Log.e(_tag, 'dispose failed', e, st);
    }
  }

  // ─── 并发调度 ───
  // 语义：_pump 在收到新任务/任务退出时被调；统计 running 数，有空闲槽则
  // 取队首 pending（FIFO 按 _order）启动 _runOne；running 数达上限即停。
  // _runOne 结束时再次 _pump，形成级联调度。等待 Future 队列，不引 isolate。

  void _pump() {
    try {
      if (_disposed) return;
      while (_running.length < _maxConcurrent) {
        final next = _nextPending();
        if (next == null) return;
        final job = RunningJob();
        _running[next.hash] = job;
        next.status = DownloadStatus.running;
        Log.d(_tag, 'start ${next.hash} (running=${_running.length})');
        _emit(next);
        _runOne(next, job).catchError((Object e) {
          Log.e(_tag, 'runOne uncaught ${next.hash}', e, StackTrace.current);
        }).whenComplete(() {
          _running.remove(next.hash);
          job.done.complete();
          _pump();
        });
      }
    } catch (e, st) {
      Log.e(_tag, '_pump failed', e, st);
    }
  }

  DownloadTask? _nextPending() {
    for (final h in _order) {
      final t = _tasks[h];
      if (t != null && t.status == DownloadStatus.pending) return t;
    }
    return null;
  }

  // ─── 单任务执行 ───

  Future<void> _runOne(DownloadTask task, RunningJob job) async {
    final hash = task.hash;
    try {
      final src = await _playback.resolvePlaySource(task.song, task.quality);
      if (job.abort) return _markAborted(task, job);
      if (src.error != null || src.urls.isEmpty) {
        task.error = 'resolve: ${src.error?.name ?? 'notFound'}';
        return _mark(task, DownloadStatus.failed, task.error);
      }
      // 备用链降级：主链失败后逐个尝试 backupUrls。
      final candidates = <String>[...src.urls, ...src.backupUrls];
      Object? lastErr;
      for (final url in candidates) {
        if (job.abort) return _markAborted(task, job);
        try {
          await _downloadUrl(task, job, url, src.extName);
          lastErr = null;
          break;
        } on DownloadAborted {
          // pause/cancel 主动中断不是 URL 失败：不得降级备用链、不得置 failed。
          return _markAborted(task, job);
        } catch (e) {
          lastErr = e;
          Log.w(_tag, 'chunked download $hash via $url failed ERR=$e');
        }
      }
      if (lastErr != null) {
        task.error = '$lastErr';
        return _mark(task, DownloadStatus.failed, task.error);
      }
      if (job.abort) return _markAborted(task, job);
      await _finishCommit(task, src.extName);
    } on DownloadAborted {
      return _markAborted(task, job);
    } catch (e, st) {
      Log.e(_tag, '_runOne $hash failed', e, st);
      task.error = '$e';
      _mark(task, DownloadStatus.failed, task.error);
    }
  }

  /// 分块下载单个 URL：写 <hash>.dlpart 临时文件，每 chunk 刷新进度并 emit。
  Future<void> _downloadUrl(
      DownloadTask task, RunningJob job, String url, String extName) async {
    final http = HttpClient()
      ..userAgent = 'TiernanMusicNext'
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    File? part;
    var lastEmitted = 0;
    try {
      final req = await http.getUrl(Uri.parse(url));
      req.headers.set('Range', 'bytes=0-');
      final res = await req.close();
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw HttpException('http ${res.statusCode}');
      }
      task.bytesTotal = res.contentLength > 0 ? res.contentLength : 0;
      task.bytesDownloaded = 0;
      part = File('${(await _storeDir())}${Platform.pathSeparator}${task.hash}.dlpart');
      if (part.existsSync()) part.deleteSync();
      sink = part.openWrite();
      await for (final chunk in res) {
        if (job.abort) break;
        sink.add(chunk);
        task.bytesDownloaded += chunk.length;
        // 进度节流：每累计 ≥256KB 或下载完成才 emit，避免每 chunk 回调
        // 风暴（大文件 → 上万次 UI rebuild）。
        final bytes = task.bytesDownloaded;
        if (bytes - lastEmitted >= 256 * 1024) {
          lastEmitted = bytes;
          _emit(task);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      _emit(task); // 终态进度（含未达 256KB 阈值的小文件）
      if (job.abort) {
        _cleanupPart(part);
        throw const DownloadAborted();
      }
    } catch (e, st) {
      _cleanupPart(part);
      Log.e(_tag, '_downloadUrl ${task.hash} failed', e, st);
      rethrow;
    } finally {
      // 只 close 尚未关闭的 sink；正常路径已 close 置 null，防 double-close
      // 抛 StateException 被误吞为下载失败。
      try {
        await sink?.close();
      } catch (e) {
        Log.w(_tag, 'sink close on error path ${task.hash} ERR=$e');
      }
      http.close();
    }
  }

  /// 收尾提交：.dlpart 读回 bytes → DownloadStore.commitDownload（rename
  /// + 索引由 core 层完成）→ SongDao 建档/补 localPath。
  Future<void> _finishCommit(DownloadTask task, String extName) async {
    final hash = task.hash;
    try {
      final part =
          File('${await _storeDir()}${Platform.pathSeparator}$hash.dlpart');
      if (!part.existsSync()) {
        task.error = 'part file missing';
        _mark(task, DownloadStatus.failed, task.error);
        return;
      }
      final data = await part.readAsBytes();
      final fileName = _buildFileName(task.song, extName);
      final rec = _store.commitDownload(
        hash: hash,
        fileName: fileName,
        data: data,
        quality: task.quality,
      );
      _cleanupPart(part);
      if (rec == null) {
        task.error = 'commitDownload failed';
        _mark(task, DownloadStatus.failed, task.error);
        return;
      }
      final localPath = _store.absolutePathOf(rec);
      await _upsertSong(task.song, rec, localPath);
      task.bytesDownloaded = rec.bytes;
      task.bytesTotal = rec.bytes;
      _mark(task, DownloadStatus.done, null);
    } catch (e, st) {
      Log.e(_tag, '_finishCommit $hash failed', e, st);
      task.error = '$e';
      _mark(task, DownloadStatus.failed, task.error);
    }
  }

  /// SongDao 同步：存在补 localPath/quality，否则新建 SongRecord。
  Future<void> _upsertSong(
      SongBrief song, DownloadRecord rec, String? localPath) async {
    try {
      final existing = await _songDao.getByHash(rec.hash);
      if (existing != null) {
        existing.localPath = localPath ?? existing.localPath;
        existing.quality = rec.quality;
        await _songDao.put(existing);
      } else {
        final s = SongRecord()
          ..hash = rec.hash
          ..fileName = rec.fileName
          ..singerName = song.singer
          ..albumName = song.albumName
          ..durationMs = song.durationSec * 1000
          ..mixSongId = '${song.mixSongId}'
          ..albumAudioId = '${song.albumAudioId}'
          ..quality = rec.quality
          ..localPath = localPath
          ..addedAt = DateTime.now().millisecondsSinceEpoch;
        await _songDao.put(s);
      }
      Log.d(_tag, 'song db synced ${rec.hash} -> ${rec.fileName}');
    } catch (e, st) {
      Log.e(_tag, '_upsertSong ${rec.hash} failed', e, st);
    }
  }

  /// 中断收尾：pause → 置 paused 并 emit；cancel → 任务已移出任务表，
  /// 不得再 emit 该任务的 paused 幽灵事件（否则 UI 收到已取消任务的状态变更）。
  void _markAborted(DownloadTask task, RunningJob job) {
    try {
      if (!shouldEmitPausedOnAbort(cancelled: job.cancelled)) {
        Log.d(_tag, '${task.hash} aborted (cancelled, no emit)');
        return;
      }
      _mark(task, DownloadStatus.paused, null);
    } catch (e, st) {
      Log.e(_tag, '_markAborted ${task.hash} failed', e, st);
    }
  }

  void _mark(DownloadTask task, DownloadStatus s, String? err) {
    try {
      task.status = s;
      task.error = err;
      Log.d(_tag, '${task.hash} -> ${s.name}${err == null ? '' : ' err=$err'}');
      _emit(task);
    } catch (e, st) {
      Log.e(_tag, '_mark ${task.hash} failed', e, st);
    }
  }

  void _emit(DownloadTask? task) {
    try {
      final cb = onTask;
      if (cb == null) return;
      cb(DownloadEvent(task: task, tasks: listTasks()));
    } catch (e, st) {
      Log.e(_tag, '_emit failed', e, st);
    }
  }

  Future<String> _storeDir() async {
    // R3-C #4：直接取 DownloadStore.targetDir（downloads 目录绝对路径），
    // 不再从索引第一条记录猜目录；空索引也不再退化系统临时目录。
    try {
      final dir = _store.targetDir;
      if (dir.isNotEmpty) return dir;
      Log.w(_tag, '_storeDir empty targetDir, fallback temp');
    } catch (e, st) {
      Log.e(_tag, '_storeDir failed', e, st);
    }
    return Directory.systemTemp.path;
  }

  String _buildFileName(SongBrief song, String ext) {
    try {
      final raw =
          song.singer.isEmpty ? song.name : '${song.singer} - ${song.name}';
      final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final name = cleaned.isEmpty ? song.hash : cleaned;
      final e = ext.trim().isEmpty ? 'mp3' : ext.trim().toLowerCase();
      return '$name.$e';
    } catch (e, st) {
      Log.e(_tag, '_buildFileName failed', e, st);
      return '${song.hash}.mp3';
    }
  }

  void _cleanupPart(File? part) {
    try {
      if (part != null && part.existsSync()) part.deleteSync();
    } catch (e, st) {
      Log.e(_tag, '_cleanupPart failed', e, st);
    }
  }
}
