// L5 logic/download · 曲库同步（下载提交后写 SongDao）
// 从 download_manager 拆出：便于 manager 控制文件长度（≤500 行）。
// 同层同包互调合法。铁律：仅经 core 桥访问数据层，无 flutter 依赖。

import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart'
    show DownloadRecord, SongBrief, SongDao, SongRecord;

const String _tag = 'logic.download';

/// 同步曲库：存在则补 localPath/quality，否则新建 SongRecord。
Future<void> syncSongRecord({
  required SongDao songDao,
  required SongBrief song,
  required DownloadRecord rec,
  String? localPath,
}) async {
  try {
    final existing = await songDao.getByHash(rec.hash);
    if (existing != null) {
      existing.localPath = localPath ?? existing.localPath;
      existing.quality = rec.quality;
      await songDao.put(existing);
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
      await songDao.put(s);
    }
    Log.d(_tag, 'song db synced ${rec.hash} -> ${rec.fileName}');
  } catch (e, st) {
    Log.e(_tag, 'syncSongRecord ${rec.hash} failed', e, st);
  }
}
