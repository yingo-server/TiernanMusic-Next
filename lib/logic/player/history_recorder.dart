// L5 logic/player · 播放历史记录器
// 职责：一次播放事件 → HistoryDao.record（去重累计）+ SongDao.markPlayed（计数/最近播放）。
// SongRecord 不存在（在线曲未入库）时先 put 建档，保证 markPlayed 生效。
// 铁律：每方法 try/catch + Log('logic.history')；可 import core/kernel；禁 import surface/flutter。

import '../../core/database/dao.dart';
import '../../core/database/entities.dart';
import '../../core/net/endpoints/models.dart' show SongBrief;
import '../../kernel/kernel.dart' show Log;

const String _tag = 'logic.history';

/// 播放历史记录器：注入 HistoryDao + SongDao。
class HistoryRecorder {
  HistoryRecorder({
    required HistoryDao historyDao,
    required SongDao songDao,
  })  : _history = historyDao,
        _songs = songDao;

  final HistoryDao _history;
  final SongDao _songs;

  /// 记录一次播放：
  /// 1) SongRecord 不存在（在线曲未入库）→ 先 put 建档；
  /// 2) HistoryDao.record（同 hash 去重：刷新 playedAt 并累计 durationPlayedMs）；
  /// 3) SongDao.markPlayed（playCount+1、lastPlayedAt=now）。
  /// playedMs：本次实际播放毫秒数。
  Future<void> recordPlay(SongBrief song, int playedMs) async {
    final hash = song.hash.trim().toLowerCase();
    try {
      if (hash.isEmpty) {
        Log.w(_tag, 'recordPlay empty hash, skip');
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // 1) 建档（若不存在）。
      final existing = await _songs.getByHash(hash);
      if (existing == null) {
        final rec = SongRecord()
          ..hash = hash
          ..fileName = song.name.isEmpty ? hash : song.name
          ..singerName = song.singer
          ..albumName = song.albumName
          ..durationMs = song.durationSec * 1000
          ..mixSongId = song.mixSongId > 0 ? '${song.mixSongId}' : ''
          ..albumAudioId = song.albumAudioId > 0 ? '${song.albumAudioId}' : ''
          ..addedAt = nowMs;
        await _songs.put(rec);
        Log.d(_tag, 'recordPlay created SongRecord $hash');
      }
      // 2) 历史去重记录。
      await _history.record(
        hash: hash,
        fileName: song.name.isEmpty ? hash : song.name,
        singerName: song.singer,
        playedAt: nowMs,
        durationPlayedMs: playedMs < 0 ? 0 : playedMs,
      );
      // 3) 曲库计数/最近播放。
      await _songs.markPlayed(hash, nowMs: nowMs);
      Log.d(_tag, 'recordPlay $hash playedMs=$playedMs');
    } catch (e, st) {
      Log.e(_tag, 'recordPlay $hash playedMs=$playedMs', e, st);
    }
  }
}
