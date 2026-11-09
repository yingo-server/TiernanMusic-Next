// L4 core/database · DAO 层
// SongDao / PlaylistDao / HistoryDao：封装 Isar 查询与写事务。
// 铁律：仅依赖 isar、kernel Log 与本域实体；每方法 try/catch 留痕，失败 rethrow。

import 'package:isar/isar.dart';

import '../../kernel/kernel.dart' show Log;
import 'db.dart';
import 'entities.dart';

/// 排序键。
enum SortKey { addedAt, playCount, lastPlayedAt, fileName }

/// 排序方向。
enum SortOrder { asc, desc }

// ─── 歌曲库 ───

class SongDao {
  static const String _tag = 'db.song';
  Isar get _isar => DatabaseService.isar;

  /// 按 hash 取单曲；不存在返回 null。
  Future<SongRecord?> getByHash(String hash) async {
    try {
      return await _isar.songRecords.filter().hashEqualTo(hash).findFirst();
    } catch (e, st) {
      Log.e(_tag, 'getByHash $hash', e, st);
      rethrow;
    }
  }

  /// 按 hash 同步取（Isar 同步 API，仅本库打开后可用）。
  SongRecord? getByHashSync(String hash) {
    try {
      return _isar.songRecords.filter().hashEqualTo(hash).findFirstSync();
    } catch (e, st) {
      Log.e(_tag, 'getByHashSync $hash', e, st);
      rethrow;
    }
  }

  /// 写入（hash 唯一索引 replace，重复 hash 覆盖更新）。
  Future<void> put(SongRecord song) async {
    try {
      await _isar.writeTxn(() => _isar.songRecords.put(song));
      Log.d(_tag, 'put ${song.hash}');
    } catch (e, st) {
      Log.e(_tag, 'put ${song.hash}', e, st);
      rethrow;
    }
  }

  /// 按 hash 删除；返回是否删除了记录。
  Future<bool> delete(String hash) async {
    try {
      final song = await getByHash(hash);
      if (song == null) return false;
      await _isar.writeTxn(() => _isar.songRecords.delete(song.id));
      Log.d(_tag, 'delete $hash');
      return true;
    } catch (e, st) {
      Log.e(_tag, 'delete $hash', e, st);
      rethrow;
    }
  }

  /// 全量列出，支持排序键与方向。
  Future<List<SongRecord>> list({
    SortKey sort = SortKey.addedAt,
    SortOrder order = SortOrder.desc,
  }) async {
    try {
      var q = _isar.songRecords.filter();
      final sorter = _sorted(q, sort, order);
      return await sorter.findAll();
    } catch (e, st) {
      Log.e(_tag, 'list', e, st);
      rethrow;
    }
  }

  /// 搜索：fileName / singerName 任一 contains（不区分大小写）。
  Future<List<SongRecord>> search(String keyword) async {
    try {
      final kw = keyword.trim();
      if (kw.isEmpty) return const [];
      return await _isar.songRecords
          .filter()
          .fileNameContains(kw, caseSensitive: false)
          .or()
          .singerNameContains(kw, caseSensitive: false)
          .sortByAddedAtDesc()
          .findAll();
    } catch (e, st) {
      Log.e(_tag, 'search "$keyword"', e, st);
      rethrow;
    }
  }

  /// 播放完成时更新计数与时间。
  Future<void> markPlayed(String hash, {int nowMs = 0}) async {
    try {
      final song = await getByHash(hash);
      if (song == null) return;
      song.playCount += 1;
      song.lastPlayedAt = nowMs > 0 ? nowMs : DateTime.now().millisecondsSinceEpoch;
      await put(song);
    } catch (e, st) {
      Log.e(_tag, 'markPlayed $hash', e, st);
      rethrow;
    }
  }

  QueryBuilder<SongRecord, SongRecord, QAfterSortBy> _sorted(
    QueryBuilder<SongRecord, SongRecord, QAfterFilterCondition> q,
    SortKey key,
    SortOrder order,
  ) {
    final asc = order == SortOrder.asc;
    switch (key) {
      case SortKey.addedAt:
        return asc ? q.sortByAddedAt() : q.sortByAddedAtDesc();
      case SortKey.playCount:
        return asc ? q.sortByPlayCount() : q.sortByPlayCountDesc();
      case SortKey.lastPlayedAt:
        return asc ? q.sortByLastPlayedAt() : q.sortByLastPlayedAtDesc();
      case SortKey.fileName:
        return asc ? q.sortByFileName() : q.sortByFileNameDesc();
    }
  }
}

// ─── 歌单 ───

class PlaylistDao {
  static const String _tag = 'db.playlist';
  Isar get _isar => DatabaseService.isar;

  /// 按 playlistId 取歌单；不存在返回 null。
  Future<PlaylistMeta?> getByPlaylistId(String playlistId) async {
    try {
      return await _isar.playlistMetas
          .filter()
          .playlistIdEqualTo(playlistId)
          .findFirst();
    } catch (e, st) {
      Log.e(_tag, 'getByPlaylistId $playlistId', e, st);
      rethrow;
    }
  }

  /// 写入（含 updatedAt 自动刷新）。
  Future<void> put(PlaylistMeta playlist) async {
    try {
      playlist.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _isar.writeTxn(() => _isar.playlistMetas.put(playlist));
      Log.d(_tag, 'put ${playlist.playlistId}');
    } catch (e, st) {
      Log.e(_tag, 'put ${playlist.playlistId}', e, st);
      rethrow;
    }
  }

  /// 删除歌单。
  Future<bool> delete(String playlistId) async {
    try {
      final p = await getByPlaylistId(playlistId);
      if (p == null) return false;
      await _isar.writeTxn(() => _isar.playlistMetas.delete(p.id));
      Log.d(_tag, 'delete $playlistId');
      return true;
    } catch (e, st) {
      Log.e(_tag, 'delete $playlistId', e, st);
      rethrow;
    }
  }

  /// 全量列出，按 updatedAt 倒序（最近操作在前）。
  Future<List<PlaylistMeta>> list() async {
    try {
      return await _isar.playlistMetas.filter().sortByUpdatedAtDesc().findAll();
    } catch (e, st) {
      Log.e(_tag, 'list', e, st);
      rethrow;
    }
  }

  /// 向歌单追加歌曲 hash（已存在则跳过，保持顺序稳定）。
  Future<void> addSong(String playlistId, String songHash) async {
    try {
      final p = await getByPlaylistId(playlistId);
      if (p == null) {
        Log.w(_tag, 'addSong: playlist $playlistId not found');
        return;
      }
      if (p.songHashes.contains(songHash)) {
        Log.d(_tag, 'addSong: $songHash already in $playlistId');
        return;
      }
      p.songHashes.add(songHash);
      await put(p);
    } catch (e, st) {
      Log.e(_tag, 'addSong $playlistId <- $songHash', e, st);
      rethrow;
    }
  }

  /// 从歌单移除歌曲 hash。
  Future<void> removeSong(String playlistId, String songHash) async {
    try {
      final p = await getByPlaylistId(playlistId);
      if (p == null) {
        Log.w(_tag, 'removeSong: playlist $playlistId not found');
        return;
      }
      if (p.songHashes.remove(songHash)) {
        await put(p);
      }
    } catch (e, st) {
      Log.e(_tag, 'removeSong $playlistId ~ $songHash', e, st);
      rethrow;
    }
  }

  /// 重排歌单：以传入 hash 有序列表整体替换（仅保留列表内存在的 hash）。
  Future<void> reorder(String playlistId, List<String> orderedHashes) async {
    try {
      final p = await getByPlaylistId(playlistId);
      if (p == null) {
        Log.w(_tag, 'reorder: playlist $playlistId not found');
        return;
      }
      p.songHashes = List<String>.of(orderedHashes);
      await put(p);
      Log.d(_tag, 'reorder $playlistId len=${orderedHashes.length}');
    } catch (e, st) {
      Log.e(_tag, 'reorder $playlistId', e, st);
      rethrow;
    }
  }
}

// ─── 播放历史 ───

class HistoryDao {
  static const String _tag = 'db.history';
  Isar get _isar => DatabaseService.isar;

  /// 记录一次播放：同 hash 去重——更新既有条目的 playedAt 并累加 durationPlayedMs
  /// 与 PlayHistoryEntry 无计数字段，计数落在 SongRecord.playCount（SongDao.markPlayed）。
  /// 这里语义：存在同 hash 的最近一条 → 更新 playedAt；否则新建。
  Future<void> record({
    required String hash,
    required String fileName,
    required String singerName,
    required int playedAt,
    required int durationPlayedMs,
  }) async {
    try {
      final existing = await _isar.playHistoryEntrys
          .filter()
          .hashEqualTo(hash)
          .sortByPlayedAtDesc()
          .findFirst();
      if (existing != null) {
        // 去重：同 hash 仅保留一条，刷新时间与累计时长。
        existing.playedAt = playedAt;
        existing.durationPlayedMs += durationPlayedMs;
        existing.fileName = fileName;
        existing.singerName = singerName;
        await _isar.writeTxn(() => _isar.playHistoryEntrys.put(existing));
      } else {
        final entry = PlayHistoryEntry()
          ..hash = hash
          ..fileName = fileName
          ..singerName = singerName
          ..playedAt = playedAt
          ..durationPlayedMs = durationPlayedMs;
        await _isar.writeTxn(() => _isar.playHistoryEntrys.put(entry));
      }
      Log.d(_tag, 'record $hash');
    } catch (e, st) {
      Log.e(_tag, 'record $hash', e, st);
      rethrow;
    }
  }

  /// 最近播放，倒序，limit 条。
  Future<List<PlayHistoryEntry>> recent({int limit = 50}) async {
    try {
      return await _isar.playHistoryEntrys
          .filter()
          .sortByPlayedAtDesc()
          .limit(limit)
          .findAll();
    } catch (e, st) {
      Log.e(_tag, 'recent limit=$limit', e, st);
      rethrow;
    }
  }

  /// 清空历史。
  Future<void> clear() async {
    try {
      await _isar.writeTxn(() => _isar.playHistoryEntrys.clear());
      Log.d(_tag, 'cleared');
    } catch (e, st) {
      Log.e(_tag, 'clear', e, st);
      rethrow;
    }
  }
}
