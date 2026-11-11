// L4 core/storage 级 · 下载记录与文件管理（基于 dart:io 文件系统）
// 索引 JSON 存 <root>/downloads/index.json；.part 临时文件 rename 提交防半成品。
import 'dart:convert';
import 'dart:io';

import '../../bridges/bridge_kernel.dart' show Log;
import 'paths.dart';

/// 单条下载记录（索引条目）。
class DownloadRecord {
  const DownloadRecord({
    required this.hash,
    required this.fileName,
    required this.relativePath,
    required this.bytes,
    required this.downloadedAt,
    required this.quality,
    this.complete = false,
  });

  final String hash; // 文件 FileHash（酷狗曲目唯一键）
  final String fileName; // 落盘文件名（冲突时已带序号）
  final String relativePath; // 相对 downloads/ 的路径
  final int bytes; // 文件字节数
  final String downloadedAt; // ISO8601
  final String quality; // 128/320/flac/high
  final bool complete; // 是否已完整提交（rename 成功）

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'fileName': fileName,
        'relativePath': relativePath,
        'bytes': bytes,
        'downloadedAt': downloadedAt,
        'quality': quality,
        'complete': complete,
      };

  static DownloadRecord fromJson(Map<String, dynamic> j) => DownloadRecord(
        hash: j['hash'] as String? ?? '',
        fileName: j['fileName'] as String? ?? '',
        relativePath: j['relativePath'] as String? ?? '',
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        downloadedAt: j['downloadedAt'] as String? ?? '',
        quality: j['quality'] as String? ?? '',
        complete: j['complete'] as bool? ?? false,
      );
}

/// 下载存储门面。
///
/// 职责：维护下载索引（JSON）与实体文件。写入流程：临时 .part 文件 → 完整落盘 →
/// rename 提交为最终文件（防半成品）。同名冲突自动追加序号。所有公开方法
/// try/catch 失败必 Log.e 留痕不静默。
class DownloadStore {
  DownloadStore(StoragePaths paths) : _downloadsDir = paths.downloads();

  final Directory _downloadsDir;
  final Map<String, DownloadRecord> _index = {};
  bool _loaded = false;

  File get _indexFile =>
      File('${_downloadsDir.path}${Platform.pathSeparator}index.json');

  // ─── 索引 ───

  /// 加载索引（内存缓存，进程内一次；forceReload 可强制重读）。
  Map<String, DownloadRecord> loadIndex({bool forceReload = false}) {
    try {
      if (_loaded && !forceReload) return Map.unmodifiable(_index);
      _index.clear();
      final f = _indexFile;
      if (f.existsSync()) {
        final raw = f.readAsStringSync();
        final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final j in arr) {
          final r = DownloadRecord.fromJson(j);
          if (r.hash.isNotEmpty) _index[r.hash] = r;
        }
      }
      _loaded = true;
      Log.d('dlstore', 'index loaded: ${_index.length} records');
    } catch (e, st) {
      Log.e('dlstore', 'loadIndex failed', e, st);
    }
    return Map.unmodifiable(_index);
  }

  /// 保存索引（先写 .part 再原子 rename）。
  bool saveIndex() {
    try {
      final arr = _index.values.map((r) => r.toJson()).toList();
      final tmp = File('${_indexFile.path}.part');
      tmp.writeAsStringSync(jsonEncode(arr), flush: true);
      if (_indexFile.existsSync()) _indexFile.deleteSync();
      tmp.renameSync(_indexFile.path);
      Log.d('dlstore', 'index saved: ${arr.length} records');
      return true;
    } catch (e, st) {
      Log.e('dlstore', 'saveIndex failed', e, st);
      return false;
    }
  }

  void upsert(DownloadRecord r) {
    try {
      _index[r.hash] = r;
      saveIndex();
    } catch (e, st) {
      Log.e('dlstore', 'upsert(${r.hash}) failed', e, st);
    }
  }

  DownloadRecord? remove(String hash) {
    DownloadRecord? old;
    try {
      old = _index.remove(hash);
      if (old != null) saveIndex();
      Log.d('dlstore', 'removed $hash (${old != null})');
    } catch (e, st) {
      Log.e('dlstore', 'remove($hash) failed', e, st);
    }
    return old;
  }

  DownloadRecord? getByHash(String hash) {
    try {
      loadIndex();
      return _index[hash];
    } catch (e, st) {
      Log.e('dlstore', 'getByHash($hash) failed', e, st);
      return null;
    }
  }

  List<DownloadRecord> listAll() {
    try {
      loadIndex();
      final list = _index.values.toList()
        ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      return List.unmodifiable(list);
    } catch (e, st) {
      Log.e('dlstore', 'listAll failed', e, st);
      return const [];
    }
  }

  // ─── 文件写入 ───

  /// 解析落盘目标文件：同名冲突自动追加序号（name-1.mp3, name-2.mp3 …）。
  File _resolveTarget(String dirPath, String fileName) {
    final sep = Platform.pathSeparator;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var candidate = '$dirPath$sep$fileName';
    var n = 0;
    while (File(candidate).existsSync()) {
      n++;
      candidate = '$dirPath$sep$stem-$n$ext';
    }
    return File(candidate);
  }

  /// 提交一次下载：data 写 .part 后 rename 为最终文件（防半成品），
  /// 并登记索引。返回最终记录；失败返回 null（不静默）。
  DownloadRecord? commitDownload({
    required String hash,
    required String fileName,
    required List<int> data,
    required String quality,
  }) {
    try {
      final target = _resolveTarget(_downloadsDir.path, fileName);
      final part = File('${target.path}.part');
      part.writeAsBytesSync(data, flush: true);
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
      final rec = DownloadRecord(
        hash: hash,
        fileName: target.uri.pathSegments.last,
        relativePath: target.uri.pathSegments.last, // 扁平存放于 downloads/
        bytes: data.length,
        downloadedAt: DateTime.now().toIso8601String(),
        quality: quality,
        complete: true,
      );
      _index[hash] = rec;
      saveIndex();
      Log.d('dlstore', 'committed ${rec.fileName} (${rec.bytes}B)');
      return rec;
    } catch (e, st) {
      Log.e('dlstore', 'commitDownload($hash) failed', e, st);
      return null;
    }
  }

  /// 打开记录对应实体文件的绝对路径；不存在返回 null。
  String? absolutePathOf(DownloadRecord r) {
    try {
      final f = File('${_downloadsDir.path}${Platform.pathSeparator}${r.relativePath}');
      return f.existsSync() ? f.path : null;
    } catch (e, st) {
      Log.e('dlstore', 'absolutePathOf(${r.hash}) failed', e, st);
      return null;
    }
  }

  /// 删除记录及其实体文件（文件缺失不视为错误）。
  bool deleteWithFile(String hash) {
    try {
      final rec = _index[hash] ?? getByHash(hash);
      if (rec != null) {
        final f =
            File('${_downloadsDir.path}${Platform.pathSeparator}${rec.relativePath}');
        if (f.existsSync()) f.deleteSync();
      }
      remove(hash);
      return true;
    } catch (e, st) {
      Log.e('dlstore', 'deleteWithFile($hash) failed', e, st);
      return false;
    }
  }
}
