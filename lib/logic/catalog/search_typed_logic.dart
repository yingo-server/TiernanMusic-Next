// L5 logic/catalog · 六类分类搜索 + 综合搜索 v6 门面（功能对齐批5-C）
// 风格照 search_logic.dart：注入 KugouClient + LruCache；
// typed() 缓存优先（ns:'search_typed'，schemaVer 1，buildKey/prefixOf），
// complex() 同样缓存优先（同 ns，path 区分 /v6/search/complex）。
// 装配方式：由主会话 assembly 注入（client + cache），经 bridge_logic
// export SearchTypedLogic 暴露给 surface；surface 不直接 import 本文件。
// 铁律：禁 surface/flutter、禁 IO 直连；每方法 try/catch + Log('logic.search.typed')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as ep show searchComplexV6, searchTypePath, searchTyped;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, SearchResult;

/// 搜索分类域缓存 schema 版本（模型变更升版自动失效老键）。
const int kSearchTypedCacheSchemaVer = 1;

const String _tag = 'logic.search.typed';
const String _ns = 'search_typed';
const int _defaultPageSize = 30;

class SearchTypedLogic {
  SearchTypedLogic({
    required KugouClient client,
    required LruCache<String, SearchResult> cache,
  })  : _client = client,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, SearchResult> _cache;

  /// 六类分类搜索（page 从 1 起）。缓存键含 type/page/pagesize 全维度。
  /// 命中直接返回；未命中调 searchTyped 后 put（空结果也落缓存防重复打网）。
  Future<SearchResult> typed(SearchType type, String keyword, int page,
      {int pageSize = _defaultPageSize}) async {
    try {
      final kw = keyword.trim();
      if (kw.isEmpty) {
        Log.w(_tag, 'typed empty keyword type=${type.name}');
        return const SearchResult();
      }
      final p = page < 1 ? 1 : page;
      final ps = pageSize < 1 ? _defaultPageSize : pageSize;
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: ep.searchTypePath(type),
        params: <String, Object?>{
          'type': type.name, 'kw': kw, 'page': p, 'pagesize': ps,
        },
        schemaVer: kSearchTypedCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit != null) {
        Log.d(_tag, 'typed cache hit type=${type.name} kw=$kw page=$p');
        return hit;
      }
      final res = await ep.searchTyped(_client, type, kw, p, ps);
      _cache.put(key, res);
      Log.d(_tag,
          'typed miss→network type=${type.name} kw=$kw page=$p '
          'got=${res.items.length} cacheSize=${_cache.length}');
      return res;
    } catch (e, st) {
      Log.e(_tag, 'typed failed type=${type.name} kw=$keyword page=$page',
          e, st);
      return const SearchResult();
    }
  }

  /// 综合搜索 v6（page 从 1 起）。缓存 path:/v6/search/complex。
  Future<SearchResult> complex(String keyword, int page) async {
    try {
      final kw = keyword.trim();
      if (kw.isEmpty) {
        Log.w(_tag, 'complex empty keyword');
        return const SearchResult();
      }
      final p = page < 1 ? 1 : page;
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: '/v6/search/complex',
        params: <String, Object?>{'kw': kw, 'page': p},
        schemaVer: kSearchTypedCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit != null) {
        Log.d(_tag, 'complex cache hit kw=$kw page=$p');
        return hit;
      }
      final res = await ep.searchComplexV6(_client, kw, p);
      _cache.put(key, res);
      Log.d(_tag, 'complex kw=$kw page=$p got=${res.items.length}');
      return res;
    } catch (e, st) {
      Log.e(_tag, 'complex failed kw=$keyword page=$page', e, st);
      return const SearchResult();
    }
  }

  /// 按命名空间+用户前缀失效（登出清缓存用）。
  int invalidatePrefix({String userid = ''}) {
    try {
      final removed = _cache.invalidatePrefix(prefixOf(_ns, userid));
      Log.d(_tag, 'invalidatePrefix ns=$_ns uid=$userid removed=${removed.length}');
      return removed.length;
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
      return 0;
    }
  }
}
