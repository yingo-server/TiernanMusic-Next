// L4 core/net/endpoints · 六类分类搜索端点封装（批F1-C 降级接线版）
// ⚠️ 批F1-C 实测（docs/API_FIELDS_TRUTH.md §A4-3'）：/v6/search/complex
//   上游模块失效（恒 152 Parameter Error），端点不可达——v6 依赖已移除，
//   综合搜索降级为「v3/song + special + album」三段组合（由 surface 组合，
//   各段独立分页/缓存，经 SearchTypedLogic.typed 的 type+page 缓存键）。
// 出处：docs/KUGOU_API.md §3.1：
//   - 分类搜索 GET /{v3|v1}/search/<type>，x-router complexsearch.kugou.com，
//     type ∈ song(v3)/special/lyric/album/author/mv(v1)。
// 装配方式：本文件不注册 EndpointRegistry（不改动 kugou_client.dart），
//   song 复用 EndpointRegistry.searchSong 声明，其余五类以 const Endpoint
//   本地声明；调用方经 logic/catalog/search_typed_logic.dart 门面使用。
// 字段路径容错：data.lists[] / data.info[] 双路映射（FINDINGS.md 实测 lists[]）。
// 只连酷狗官方域名（complexsearch.kugou.com）。
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
/// page 从 1 起；返回 SearchResult（items 按类型映射，见 parseSearchItems）。
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
    final items = parseSearchItems(res, type: type);
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

/// 【批F1-C 降级】v6 complex 已实测不可达（恒 152 Parameter Error，
/// docs/API_FIELDS_TRUTH.md §A4-3'）。为保 logic 门面签名兼容（不改
/// logic/bridges），本函数保留原名降级为 v3/song 分类搜索的薄委托：
/// 不再请求 /v6/search/complex，不猜 v6 字段。综合搜索的新构成见
/// search_page.dart（song+special+album 三段组合）。
Future<SearchResult> searchComplexV6(
  KugouClient client,
  String keyword,
  int page,
) async {
  try {
    Log.w(_tag,
        'searchComplexV6 degraded: v6 complex unreachable(ec=152), '
        'fallback to v3/song kw=$keyword page=$page');
    return await searchTyped(client, SearchType.song, keyword, page, 30);
  } catch (e, st) {
    Log.e(_tag, 'searchComplexV6 degrade failed kw=$keyword page=$page', e, st);
    return const SearchResult();
  }
}

/// 列表字段容错解析：优先 data.lists[]，退 data.info[]，再退顶层 lists/info。
/// type=song 用 SongBrief.fromSearchList；special/album 用下方专用映射
///（A1-2/A1-3 实测键集，不猜 v6 字段）。
List<SongBrief> parseSearchItems(Map<String, dynamic> res,
    {SearchType type = SearchType.song}) {
  try {
    final data = dataOf(res);
    var lists = listOf(data['lists']);
    if (lists.isEmpty) lists = listOf(data['info']);
    if (lists.isEmpty) lists = listOf(res['lists']);
    if (lists.isEmpty) lists = listOf(res['info']);
    SongBrief Function(Map<String, dynamic>) map;
    switch (type) {
      case SearchType.special:
        map = songBriefFromSearchSpecial;
      case SearchType.album:
        map = songBriefFromSearchAlbum;
      default:
        map = SongBrief.fromSearchList;
    }
    final items = <SongBrief>[];
    for (final m in lists) {
      final s = map(m);
      if (s.name.isNotEmpty) items.add(s);
    }
    return items;
  } catch (e, st) {
    Log.e(_tag, 'parseSearchItems failed type=${type.name}', e, st);
    return const <SongBrief>[];
  }
}

/// 歌单搜索项映射（A1-2 实测键集：specialname/img/song_count/nickname/
/// play_count/specialid）。字段落位：name←specialname，singer←nickname（创建者），
/// durationSec←song_count（歌单曲目数，仅作展示计数），mixSongId←specialid，
/// isVip←isvip。封面 url 需拼 img（本模型无封面字段，列表页不展示封面）。
SongBrief songBriefFromSearchSpecial(Map<String, dynamic> m) {
  try {
    return SongBrief(
      name: safeStr(m['specialname'], safeStr(m['name'])),
      singer: safeStr(m['nickname']),
      mixSongId: safeInt(m['specialid']),
      durationSec: safeInt(m['song_count'], safeInt(m['count'])),
      isVip: safeBool(m['isvip']),
    );
  } catch (e, st) {
    Log.e(_tag, 'songBriefFromSearchSpecial failed', e, st);
    return const SongBrief();
  }
}

/// 专辑搜索项映射（A1-3 实测键集：albumid/albumname/title/singer/img/
/// publish_time/songcount）。字段落位：name←albumname（title 兜底），
/// singer←singer，albumId←albumid，durationSec←songcount（曲目数展示计数）。
SongBrief songBriefFromSearchAlbum(Map<String, dynamic> m) {
  try {
    return SongBrief(
      name: safeStr(m['albumname'], safeStr(m['title'], safeStr(m['name']))),
      singer: safeStr(m['singer']),
      albumId: safeStr(m['albumid'], safeStr(m['AlbumID'])),
      mixSongId: safeInt(m['albumid']),
      durationSec: safeInt(m['songcount'], safeInt(m['song_count'])),
    );
  } catch (e, st) {
    Log.e(_tag, 'songBriefFromSearchAlbum failed', e, st);
    return const SongBrief();
  }
}
