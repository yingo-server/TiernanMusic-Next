// L5 logic/catalog · 每日推荐门面（功能对齐批3-C · GAP #20，风格照 rank_logic.dart）
// 消费已声明端点 EndpointRegistry.recommendSongs（/everyday_song_recommend）
// 的封装 getDailyRecommend；缓存优先（ns:'recommend'，schemaVer 1，buildKey/prefixOf）。
// 批3-F2：端点返回显式分态结果（ok / empty / loginRequired / error，结果对象
// 同时实现 List<SongBrief>），本门面保持 Future<List<SongBrief>> 以兼容未改造的
// home_page；loginRequired / error 一律不写缓存（失败不固化）。
// 铁律：禁 surface/flutter、禁 IO 直连；每方法 try/catch + Log('logic.recommend')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as ep show SongBrief, getDailyRecommend, kDailyRecommendPath;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, SongBrief, buildKey, prefixOf;

/// 每日推荐域缓存 schema 版本（模型变更升版自动失效老键）。
const int kRecommendCacheSchemaVer = 1;

const String _tag = 'logic.recommend';
const String _ns = 'recommend';
const int _defaultPageSize = 30;

class RecommendLogic {
  RecommendLogic({
    required KugouClient client,
    required LruCache<String, dynamic> cache,
  })  : _client = client,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, dynamic> _cache;

  /// 每日推荐分页（page 从 1 起）。缓存优先：命中直接返回列表；未命中调端点封装。
  /// 批3-F2：端点结果自带 state（ok/empty/loginRequired/error），仅 ok / empty
  /// 且非空落缓存；loginRequired / error 绝不写缓存——旧实现把失败固化，
  /// 登录后仍恒命中空缓存。签名保留 Future<List<SongBrief>> 以兼容未改造的
  /// home_page；实际返回 DailyRecommendResult（同时是 List<SongBrief>），
  /// 后续 UI 可直接从结果取 .state 区分「需登录」与「暂无推荐」。
  Future<List<SongBrief>> daily(int page, {int pageSize = _defaultPageSize}) async {
    try {
      final p = page < 1 ? 1 : page;
      final ps = pageSize < 1 ? _defaultPageSize : pageSize;
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: ep.kDailyRecommendPath,
        params: <String, Object?>{'page': p, 'pagesize': ps},
        schemaVer: kRecommendCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<SongBrief>) {
        Log.d(_tag, 'daily cache hit page=$p');
        return hit;
      }
      final res = await ep.getDailyRecommend(_client, page: p, pageSize: ps);
      // 只缓存确实拿到（或确实为空）的列表；未登录/失败不固化，下次可重试。
      if (res.cacheable && res.isNotEmpty) _cache.put(key, res.toList());
      Log.d(_tag, 'daily page=$p state=${res.state.name} got=${res.length}');
      return res;
    } catch (e, st) {
      Log.e(_tag, 'daily failed page=$page', e, st);
      return const <SongBrief>[];
    }
  }

  /// 按 (ns, userid) 前缀失效（登出/换号清缓存；默认当前会话用户）。
  int invalidatePrefix({String? userid}) {
    try {
      final uid = userid ?? _client.session.userid;
      final removed = _cache.invalidatePrefix(prefixOf(_ns, uid));
      Log.d(_tag, 'invalidatePrefix uid=$uid removed=${removed.length}');
      return removed.length;
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
      return 0;
    }
  }
}
