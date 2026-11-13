// L5 logic/download · 下载提交收尾（.dlpart → 正式文件 + 曲库建档）
// 从 download_manager 拆出：便于 manager 控制文件长度（≤500 行）。
// 同层同包互调合法。铁律：经 core 桥访问存储/数据层，无 flutter 依赖。

import 'dart:io';

import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show DownloadStore, SongDao;
import 'download_models.dart';
import 'download_job.dart';
import 'download_paths.dart';
import 'download_song_sync.dart';

const String _tag = 'logic.download';

/// 下载提交器：读回 .dlpart → DownloadStore.commitDownload → 曲库建档。
class DownloadCommitter {
  DownloadCommitter({
    required DownloadStore store,
    required SongDao songDao,
    required void Function(DownloadTask task, DownloadStatus status, String? err)
        mark,
  })  : _store = store,
        _songDao = songDao,
        _mark = mark;

  final DownloadStore _store;
  final SongDao _songDao;
  final void Function(DownloadTask task, DownloadStatus status, String? err) _mark;

  /// 收尾提交：.dlpart 读回 bytes → commitDownload（rename + 索引由 core 层
  /// 完成）→ SongDao 建档/补 localPath。取消语义：abort 置位后不落盘。
  Future<void> commit(
    DownloadTask task,
    String extName,
    RunningJob job,
  ) async {
    final hash = task.hash;
    try {
      final part =
          File('${_storeDir()}${Platform.pathSeparator}$hash.dlpart');
      // 提交前复核中断标志：cancel 在提交阶段到达时不得落盘（否则任务已
      // 移出任务表却留下已提交文件与曲库记录）。
      if (job.abort) {
        cleanupPartFile(part);
        return;
      }
      if (!part.existsSync()) {
        task.error = 'part file missing';
        _mark(task, DownloadStatus.failed, task.error);
        return;
      }
      final data = await part.readAsBytes();
      // 读回 bytes 期间可能收到 cancel：提交前再复核一次，避免留下已落盘文件。
      if (job.abort) {
        cleanupPartFile(part);
        return;
      }
      final fileName = buildDownloadFileName(task.song, extName);
      final rec = _store.commitDownload(
        hash: hash,
        fileName: fileName,
        data: data,
        quality: task.quality,
      );
      cleanupPartFile(part);
      if (rec == null) {
        task.error = 'commitDownload failed';
        _mark(task, DownloadStatus.failed, task.error);
        return;
      }
      // 提交后、落曲库前到达的 cancel：文件已完整提交并入索引，视为下载完成
      // （不删除，以免误删同 hash 的既有下载记录）；仅不再写曲库。
      if (job.abort) {
        Log.w(_tag, 'commit $hash 已完成落盘但收到取消，保留文件不入曲库');
        return;
      }
      final localPath = _store.absolutePathOf(rec);
      await syncSongRecord(
        songDao: _songDao,
        song: task.song,
        rec: rec,
        localPath: localPath,
      );
      task.bytesDownloaded = rec.bytes;
      task.bytesTotal = rec.bytes;
      _mark(task, DownloadStatus.done, null);
    } catch (e, st) {
      if (job.abort) {
        Log.d(_tag, 'commit $hash aborted');
        return;
      }
      Log.e(_tag, 'commit $hash failed', e, st);
      task.error = '$e';
      _mark(task, DownloadStatus.failed, task.error);
    }
  }

  String _storeDir() {
    try {
      return resolveStoreDir(_store.targetDir);
    } catch (e, st) {
      Log.e(_tag, '_storeDir failed', e, st);
      return Directory.systemTemp.path;
    }
  }
}
