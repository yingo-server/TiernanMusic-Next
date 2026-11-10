// L5 logic/catalog · 搜索门面（缓存接入）
// 注入 KugouClient + LruCache<String, SearchResult>(capacity 128)。
// search 走缓存（ns:'search'），suggestions/hotSearch 直通不缓存。
// 缓存键经 core/memory/cache_keys.buildKey，schemaVer v1（顶部常量）。
// 铁律：禁 surface/flutter；每方法 try/catch + Log('logic.search')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, SearchResult, SearchSuggestItem, searchSongs, searchSuggest, searchHot;

/// 搜索域缓存 schema 版本：模型变更升版自动失效老键。
const int kSearchCacheSchemaVer = 1;

const String _tag = 'logic.search';
const String _ns = 'search';
const String _searchPath = '/v3/search/song';

class SearchLogic {
  SearchLogic({
    required KugouClient client,
    required LruCache<String, SearchResult> cache,
  })  : _client = client,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, SearchResult> _cache;

  /// 关键词搜歌（page 从 1 起）。命中缓存直接返回，未命中调 searchSongs 后 put。
  Future<SearchResult> search(String keyword, int page, {int pageSize = 30}) async {
    try {
      final kw = keyword.trim();
      if (kw.isEmpty) {
        Log.w(_tag, 'search empty keyword');
        return const SearchResult();
      }
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _searchPath,
        params: <String, Object?>{'kw': kw, 'page': page, 'pagesize': pageSize},
        schemaVer: kSearchCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit != null) {
        Log.d(_tag, 'search cache hit kw=$kw page=$page');
        return hit;
      }
      final res = await searchSongs(_client, kw, page, pageSize);
      _cache.put(key, res);
      Log.d(_tag,
          'search miss→network kw=$kw page=$page got=${res.items.length} '
          'cacheSize=${_cache.length}');
      return res;
    } catch (e, st) {
      Log.e(_tag, 'search failed kw=$keyword page=$page', e, st);
      return const SearchResult();
    }
  }

  /// 搜索联想：直通（不缓存，联想随输入实时变化）。
  Future<List<SearchSuggestItem>> suggestions(String keyword) async {
    try {
      final out = await searchSuggest(_client, keyword);
      Log.d(_tag, 'suggestions kw=$keyword got=${out.length}');
      return out;
    } catch (e, st) {
      Log.e(_tag, 'suggestions failed kw=$keyword', e, st);
      return const <SearchSuggestItem>[];
    }
  }

  /// 热搜榜：直通（不缓存）。
  Future<List<SearchSuggestItem>> hotSearch() async {
    try {
      final out = await searchHot(_client);
      Log.d(_tag, 'hotSearch got=${out.length}');
      return out;
    } catch (e, st) {
      Log.e(_tag, 'hotSearch failed', e, st);
      return const <SearchSuggestItem>[];
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
