// L5 logic/catalog · 排行榜门面（缓存接入）
// rankList/rankInfo + LruCache(ns:'rank')。schemaVer v1（顶部常量）。
// 铁律：禁 surface/flutter；每方法 try/catch + Log('logic.rank')。
import '../../kernel/kernel.dart' show Log;
import '../../core/memory/cache_keys.dart';
import '../../core/memory/lru_cache.dart';
import '../../core/net/kugou_client.dart';
import '../../core/net/endpoints/models.dart';
import '../../core/net/endpoints/misc_endpoints.dart' as misc;

/// 排行榜域缓存 schema 版本。
const int kRankCacheSchemaVer = 1;

const String _tag = 'logic.rank';
const String _ns = 'rank';
const String _rankListPath = '/ocean/v6/rank/list';
const String _rankInfoPath = '/ocean/v6/rank/info';

class RankLogic {
  RankLogic({
    required KugouClient client,
    required LruCache<String, dynamic> cache,
  })  : _client = client,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, dynamic> _cache;

  /// 榜单列表（data.info[]）。缓存 path:/ocean/v6/rank/list。
  Future<List<RankBrief>> rankList() async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _rankListPath,
        params: const <String, Object?>{'plat': 2, 'parentid': 0},
        schemaVer: kRankCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<RankBrief>) {
        Log.d(_tag, 'rankList cache hit');
        return hit;
      }
      final items = await misc.rankList(_client);
      _cache.put(key, items);
      Log.d(_tag, 'rankList got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'rankList failed', e, st);
      return const <RankBrief>[];
    }
  }

  /// 榜单详情（data.songs[]/data.list[]）。缓存 path:/ocean/v6/rank/info。
  Future<List<SongBrief>> rankInfo(int rankId) async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _rankInfoPath,
        params: <String, Object?>{'rankid': rankId, 'rank_cid': 0},
        schemaVer: kRankCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<SongBrief>) {
        Log.d(_tag, 'rankInfo cache hit rankId=$rankId');
        return hit;
      }
      final items = await misc.rankInfo(_client, rankId);
      _cache.put(key, items);
      Log.d(_tag, 'rankInfo rankId=$rankId got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'rankInfo failed rankId=$rankId', e, st);
      return const <SongBrief>[];
    }
  }

  /// 按 (ns, userid) 前缀失效（登出清缓存）。
  int invalidatePrefix({String userid = ''}) {
    try {
      final removed = _cache.invalidatePrefix(prefixOf(_ns, userid));
      Log.d(_tag, 'invalidatePrefix removed=${removed.length}');
      return removed.length;
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
      return 0;
    }
  }
}
