// L5 logic/download · 下载路径与临时文件工具（纯工具，无状态）
// 从 download_manager 拆出：目录解析 / 文件名生成 / 临时分片清理，
// 便于 manager 控制文件长度（≤500 行）。同层同包互调合法。
// 铁律：仅依赖 core 桥与 dart:io，无 flutter 依赖。

import 'dart:io';

import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show SongBrief;

const String _tag = 'logic.download';

/// 解析下载目录：优先用 DownloadStore.targetDir（绝对路径），
/// 空目录退回系统临时目录（不再从索引记录猜目录）。
String resolveStoreDir(String targetDir) {
  try {
    if (targetDir.isNotEmpty) return targetDir;
    Log.w(_tag, 'resolveStoreDir empty targetDir, fallback temp');
  } catch (e, st) {
    Log.e(_tag, 'resolveStoreDir failed', e, st);
  }
  return Directory.systemTemp.path;
}

/// 生成落盘文件名：「歌手 - 标题.ext」，非法字符替换为 _，空则回退 hash。
String buildDownloadFileName(SongBrief song, String ext) {
  try {
    final raw = song.singer.isEmpty ? song.name : '${song.singer} - ${song.name}';
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final name = cleaned.isEmpty ? song.hash : cleaned;
    final e = ext.trim().isEmpty ? 'mp3' : ext.trim().toLowerCase();
    return '$name.$e';
  } catch (e, st) {
    Log.e(_tag, 'buildDownloadFileName failed', e, st);
    return '${song.hash}.mp3';
  }
}

/// 删除 .dlpart 临时分片（尽力，失败不阻断主流程）。
void cleanupPartFile(File? part) {
  try {
    if (part != null && part.existsSync()) part.deleteSync();
  } catch (e, st) {
    Log.e(_tag, 'cleanupPartFile failed', e, st);
  }
}
