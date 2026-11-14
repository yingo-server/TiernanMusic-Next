// L5 logic/catalog · 排行榜门面（缓存接入）
// rankList/rankInfo + LruCache(ns:'rank')。schemaVer v1（顶部常量）。
// 铁律：禁 surface/flutter；每方法 try/catch + Log('logic.rank')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as misc show rankInfo, rankList;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, RankBrief, SongBrief, buildKey, prefixOf, rankInfo, rankList;

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
      // 审查修复：空结果不落缓存（失败不固化）。
      if (items.isNotEmpty) _cache.put(key, items);
      Log.d(_tag, 'rankList got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'rankList failed', e, st);
      return const <RankBrief>[];
    }
  }

  /// 榜单详情（data.songs[]/data.list[]）。缓存 path:/ocean/v6/rank/info。
  /// 批3-F2：page/pageSize 透传 misc.rankInfo 并纳入缓存键（分页不串页）；
  /// 旧调用方只传 rankId 时仍走 page=1/pageSize=30，surface 无需改动。
  Future<List<SongBrief>> rankInfo(int rankId,
      {int page = 1, int pageSize = 30}) async {
    try {
      final p = page < 1 ? 1 : page;
      final ps = pageSize < 1 ? 30 : pageSize;
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _rankInfoPath,
        params: <String, Object?>{
          'rankid': rankId, 'rank_cid': 0, 'page': p, 'pagesize': ps,
        },
        schemaVer: kRankCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<SongBrief>) {
        Log.d(_tag, 'rankInfo cache hit rankId=$rankId page=$p');
        return hit;
      }
      final items =
          await misc.rankInfo(_client, rankId, page: p, pageSize: ps);
      // 审查修复：空结果不落缓存（失败不固化）。
      if (items.isNotEmpty) _cache.put(key, items);
      Log.d(_tag, 'rankInfo rankId=$rankId page=$p got=${items.length}');
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
