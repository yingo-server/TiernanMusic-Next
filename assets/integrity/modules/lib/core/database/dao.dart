// L4 core/database · DAO 层
// SongDao / PlaylistDao / HistoryDao：封装 Isar 查询与写事务。
// 铁律：仅依赖 isar、kernel Log 与本域实体；每方法 try/catch 留痕，失败 rethrow。

import 'package:isar/isar.dart';

import '../../bridges/bridge_kernel.dart' show Log;
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
      final all = await _isar.songRecords.where().findAll();
      return _sorted(all, sort, order);
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
      final hits = await _isar.songRecords
          .filter()
          .fileNameContains(kw, caseSensitive: false)
          .or()
          .singerNameContains(kw, caseSensitive: false)
          .findAll();
      hits.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return hits;
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

  /// 内存排序（本地曲库量级 ≤万条，避免依赖 codegen 阶段扩展方法）。
  List<SongRecord> _sorted(List<SongRecord> list, SortKey key, SortOrder order) {
    final asc = order == SortOrder.asc;
    int cmp(SongRecord a, SongRecord b) {
      final av = switch (key) {
        SortKey.addedAt => a.addedAt,
        SortKey.playCount => a.playCount,
        SortKey.lastPlayedAt => a.lastPlayedAt ?? 0,
        SortKey.fileName => 0,
      };
      final bv = switch (key) {
        SortKey.addedAt => b.addedAt,
        SortKey.playCount => b.playCount,
        SortKey.lastPlayedAt => b.lastPlayedAt ?? 0,
        SortKey.fileName => 0,
      };
      if (key == SortKey.fileName) {
        return asc ? a.fileName.compareTo(b.fileName) : b.fileName.compareTo(a.fileName);
      }
      return asc ? av.compareTo(bv) : bv.compareTo(av);
    }

    list.sort(cmp);
    return list;
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
      final all = await _isar.playlistMetas.where().findAll();
      all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return all;
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
      final sameHash = await _isar.playHistoryEntrys
          .where()
          .hashEqualTo(hash)
          .findAll();
      PlayHistoryEntry? existing;
      for (final e in sameHash) {
        if (existing == null || e.playedAt > existing.playedAt) existing = e;
      }
      if (existing != null) {
        // 去重：同 hash 仅保留一条，刷新时间与累计时长。
        final cur = existing;
        cur.playedAt = playedAt;
        cur.durationPlayedMs += durationPlayedMs;
        cur.fileName = fileName;
        cur.singerName = singerName;
        await _isar.writeTxn(() => _isar.playHistoryEntrys.put(cur));
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
      final all = await _isar.playHistoryEntrys.where().findAll();
      all.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      return all.take(limit).toList();
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

// ─── 多账号（批2-A） ───

/// 账号档案 DAO：封装 Isar 查询与写事务；每方法 try/catch 留痕，失败 rethrow。
class AccountDao {
  static const String _tag = 'db.account';
  Isar get _isar => DatabaseService.isar;

  /// 全量列出，按 lastUsedAt 倒序（最近使用在前）。
  Future<List<AccountRecord>> listAll() async {
    try {
      final all = await _isar.accountRecords.where().findAll();
      all.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return all;
    } catch (e, st) {
      Log.e(_tag, 'listAll', e, st);
      rethrow;
    }
  }

  /// 取当前激活账号；无激活账号返回 null。
  Future<AccountRecord?> getActive() async {
    try {
      return await _isar.accountRecords
          .filter()
          .isActiveEqualTo(true)
          .findFirst();
    } catch (e, st) {
      Log.e(_tag, 'getActive', e, st);
      rethrow;
    }
  }

  /// 按业务 accountId 取账号；不存在返回 null。
  Future<AccountRecord?> getByAccountId(String accountId) async {
    try {
      return await _isar.accountRecords
          .filter()
          .accountIdEqualTo(accountId)
          .findFirst();
    } catch (e, st) {
      Log.e(_tag, 'getByAccountId $accountId', e, st);
      rethrow;
    }
  }

  /// 写入（accountId 唯一索引 replace，同业务 id 覆盖更新）。
  Future<void> put(AccountRecord account) async {
    try {
      await _isar.writeTxn(() => _isar.accountRecords.put(account));
      Log.d(_tag, 'put ${account.accountId}');
    } catch (e, st) {
      Log.e(_tag, 'put ${account.accountId}', e, st);
      rethrow;
    }
  }

  /// 切换激活账号：单个 writeTxn 内先清全部 isActive 为 false，再置目标为 true。
  /// 幂等：重复调用状态一致；目标不存在时全库保持无激活账号。
  Future<void> setActive(Id id) async {
    try {
      await _isar.writeTxn(() async {
        // ① 清全部 isActive（无条件置 false 并写回，保证幂等与排他）。
        final all = await _isar.accountRecords.where().findAll();
        for (final a in all) {
          a.isActive = false;
          await _isar.accountRecords.put(a);
        }
        // ② 置目标为 true；目标不存在则全库保持无激活账号。
        final target = await _isar.accountRecords.get(id);
        if (target != null) {
          target.isActive = true;
          await _isar.accountRecords.put(target);
        } else {
          Log.w(_tag, 'setActive: account id=$id not found');
        }
      });
      Log.d(_tag, 'setActive id=$id');
    } catch (e, st) {
      Log.e(_tag, 'setActive $id', e, st);
      rethrow;
    }
  }

  /// 按 Isar id 删除账号；返回是否删除了记录。
  Future<bool> remove(Id id) async {
    try {
      final removed =
          await _isar.writeTxn(() => _isar.accountRecords.delete(id));
      Log.d(_tag, 'remove id=$id removed=$removed');
      return removed;
    } catch (e, st) {
      Log.e(_tag, 'remove $id', e, st);
      rethrow;
    }
  }
}
