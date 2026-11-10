// L4 core/net/endpoints · 六类分类搜索 + 综合搜索 v6 端点封装
// （功能对齐批5-C · GAP_ANALYSIS #1 增强项 / PARITY_NOTES §4「13 方法：联想/热词/歌词/多类型」）
// 出处：docs/KUGOU_API.md §3.1：
//   - 分类搜索 GET /{v3|v1}/search/<type>，x-router complexsearch.kugou.com，
//     type ∈ song(v3)/special/lyric/album/author/mv(v1)；
//   - 综合搜索 v6 GET https://complexsearch.kugou.com/v6/search/complex，
//     参数 platform=AndroidFilter, keyword, page, pagesize, cursor=0。
// 装配方式：本文件不注册 EndpointRegistry（不改动 kugou_client.dart），
//   song 复用 EndpointRegistry.searchSong/searchComplex 声明，其余五类在此
//   以 const Endpoint 本地声明；调用方经 logic/catalog/search_typed_logic.dart
//   门面使用，surface 经 bridge_logic → SearchTypedLogic 间接消费。
// 字段路径容错：data.lists[] / data.info[] 双路映射 SongBrief.fromSearchList
//   （FINDINGS.md 实测 lists[]；info[] 为旧版/其他类型响应兜底）。
// 只连酷狗官方域名（complexsearch.kugou.com / gateway.kugou.com）。
// dfid/mid/uuid 由 KugouClient 默认参数恒显式携带并参与签名（android 签名）。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart';

const String _tag = 'ep.search.typed';

/// 六类搜索类型（铁律 6：每类型独立可替换，路径映射集中在此）。
enum SearchType { song, special, lyric, album, author, mv }

/// 分类搜索路径映射：song 走 v3，其余走 v1（KUGOU_API.md §3.1）。
String searchTypePath(SearchType t) {
  try {
    switch (t) {
      case SearchType.song:
        return '/v3/search/song';
      case SearchType.special:
        return '/v1/search/special';
      case SearchType.lyric:
        return '/v1/search/lyric';
      case SearchType.album:
        return '/v1/search/album';
      case SearchType.author:
        return '/v1/search/author';
      case SearchType.mv:
        return '/v1/search/mv';
    }
  } catch (e, st) {
    Log.e(_tag, 'searchTypePath failed', e, st);
    return '/v3/search/song';
  }
}

/// 六类搜索。song→/v3/search/song（复用注册表声明），其余→/v1/search/<type>
/// （本地 Endpoint 声明，同 router complexsearch.kugou.com）。
/// page 从 1 起；返回 SearchResult（items 经 lists[]/info[] 容错映射）。
Future<SearchResult> searchTyped(
  KugouClient client,
  SearchType type,
  String keyword,
  int page,
  int pageSize,
) async {
  try {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      Log.w(_tag, 'searchTyped empty keyword type=${type.name}');
      return const SearchResult();
    }
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    final path = searchTypePath(type);
    // song 复用既有注册表声明；五类本地声明（与注册表同 router，便于日后
    // 三态实测后统一收编进 EndpointRegistry，只改此处不改 request）。
    final ep = type == SearchType.song
        ? EndpointRegistry.searchSong
        : Endpoint(
            id: 'search_${type.name}', path: path,
            router: 'complexsearch.kugou.com');
    final res = await client.request(ep, <String, Object?>{
      'keyword': kw,
      'page': p,
      'pagesize': ps,
      'albumhide': 0,
      'iscorrection': 1,
      'nocollect': 0,
      'platform': 'AndroidFilter',
    });
    final items = parseSearchItems(res);
    final total = safeInt(dataOf(res)['total']);
    Log.d(_tag,
        'searchTyped type=${type.name} kw=$kw page=$p '
        'got=${items.length} total=$total');
    return SearchResult(total: total, items: items);
  } catch (e, st) {
    Log.e(_tag, 'searchTyped failed type=${type.name} kw=$keyword page=$page',
        e, st);
    return const SearchResult();
  }
}

/// 综合搜索 v6（推荐首选）：GET https://complexsearch.kugou.com/v6/search/complex，
/// 复用 EndpointRegistry.searchComplex 声明（base 已指向 complexsearch 官方域）。
/// 字段容错：v6 响应结构未完全留样，lists[]/info[]/data 三路兜底。
Future<SearchResult> searchComplexV6(
  KugouClient client,
  String keyword,
  int page,
) async {
  try {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      Log.w(_tag, 'searchComplexV6 empty keyword');
      return const SearchResult();
    }
    final p = page < 1 ? 1 : page;
    final res = await client.request(EndpointRegistry.searchComplex,
        <String, Object?>{
      'platform': 'AndroidFilter',
      'keyword': kw,
      'page': p,
      'pagesize': 30,
      'cursor': 0,
    });
    final items = parseSearchItems(res);
    final total = safeInt(dataOf(res)['total']);
    Log.d(_tag,
        'searchComplexV6 kw=$kw page=$p got=${items.length} total=$total');
    return SearchResult(total: total, items: items);
  } catch (e, st) {
    Log.e(_tag, 'searchComplexV6 failed kw=$keyword page=$page', e, st);
    return const SearchResult();
  }
}

/// 列表字段容错解析：优先 data.lists[]，退 data.info[]，再退顶层 lists/info。
/// 每项经 SongBrief.fromSearchList（内部已做字段缺失防御）。
List<SongBrief> parseSearchItems(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    var lists = listOf(data['lists']);
    if (lists.isEmpty) lists = listOf(data['info']);
    if (lists.isEmpty) lists = listOf(res['lists']);
    if (lists.isEmpty) lists = listOf(res['info']);
    final items = <SongBrief>[];
    for (final m in lists) {
      final s = SongBrief.fromSearchList(m);
      // 过滤全空项（hash 与名称皆空视为无效）。
      if (s.hash.isNotEmpty || s.name.isNotEmpty) items.add(s);
    }
    return items;
  } catch (e, st) {
    Log.e(_tag, 'parseSearchItems failed', e, st);
    return const <SongBrief>[];
  }
}
