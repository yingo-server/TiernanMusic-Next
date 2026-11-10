// L4 core/net/endpoints · 搜索端点封装（song / suggest / hot）
// 输入 KugouClient + 参数，返回强类型结果；字段路径以 .test_creds/FINDINGS.md 为准：
// 搜索列表在 data.lists[]（FileHash/FileName/SingerName/MixSongID/AlbumAudioId/...），
// total 在 data.total。EndpointRegistry 声明保留在 kugou_client.dart，不在此重复。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart';

const String _tag = 'ep.search';

/// 关键词搜歌。page 从 1 起。
Future<SearchResult> searchSongs(
  KugouClient client,
  String keyword,
  int page,
  int pageSize,
) async {
  try {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      Log.w(_tag, 'searchSongs empty keyword');
      return const SearchResult();
    }
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    final res = await client.request(EndpointRegistry.searchSong, <String, Object?>{
      'keyword': kw,
      'page': p,
      'pagesize': ps,
      'albumhide': 0,
      'iscorrection': 1,
      'nocollect': 0,
      'platform': 'AndroidFilter',
    });
    final data = dataOf(res);
    final lists = listOf(data['lists']);
    final items = lists.map(SongBrief.fromSearchList).toList(growable: false);
    final total = safeInt(data['total']);
    Log.d(_tag, 'searchSongs kw=$kw page=$p got=${items.length} total=$total');
    return SearchResult(total: total, items: items);
  } catch (e, st) {
    Log.e(_tag, 'searchSongs failed kw=$keyword page=$page', e, st);
    return const SearchResult();
  }
}

/// 搜索联想（/v2/getSearchTip）：MusicTip 为主，聚合各分类 tip。
Future<List<SearchSuggestItem>> searchSuggest(
  KugouClient client,
  String keyword,
) async {
  try {
    final kw = keyword.trim();
    if (kw.isEmpty) return const <SearchSuggestItem>[];
    final res = await client.request(
        EndpointRegistry.searchSuggest, <String, Object?>{
      'keyword': kw,
      'AlbumTipCount': 10,
      'CorrectTipCount': 10,
      'MVTipCount': 10,
      'MusicTipCount': 10,
      'radiotip': 1,
    });
    final data = dataOf(res);
    final out = <SearchSuggestItem>[];
    // data.records 是各分类容器：music/album/author/mv…每类内 lists[]/info[]
    final records = data['records'];
    if (records is Map) {
      records.forEach((cat, bucket) {
        final m = bucket is Map
            ? bucket.map((k, v) => MapEntry('$k', v))
            : const <String, dynamic>{};
        final lists = listOf(m['lists'] ?? m['info']);
        for (final item in lists) {
          final kw2 = safeStr(
              item['keyword'] ?? item['FileName'] ?? item['name'] ?? '');
          if (kw2.isNotEmpty) {
            out.add(SearchSuggestItem(keyword: kw2, type: safeStr(cat)));
          }
        }
      });
    }
    // 兜底：部分响应直接给 data.lists[]
    if (out.isEmpty) {
      for (final item in listOf(data['lists'])) {
        final kw2 = safeStr(item['keyword'] ?? item['FileName'] ?? '');
        if (kw2.isNotEmpty) {
          out.add(SearchSuggestItem(keyword: kw2, type: 'music'));
        }
      }
    }
    Log.d(_tag, 'searchSuggest kw=$kw got=${out.length}');
    return out;
  } catch (e, st) {
    Log.e(_tag, 'searchSuggest failed kw=$keyword', e, st);
    return const <SearchSuggestItem>[];
  }
}

/// 热搜榜（/api/v3/search/hot_tab）：取 music / special 标签下的热词。
Future<List<SearchSuggestItem>> searchHot(KugouClient client) async {
  try {
    final res = await client.request(EndpointRegistry.searchHot,
        <String, Object?>{'navid': 1, 'plat': 2});
    final data = dataOf(res);
    final out = <SearchSuggestItem>[];
    // 响应形如 data.list[]（每组含 list[] 热词），容错聚合。
    for (final group in listOf(data['list'] ?? data['info'])) {
      final gName = safeStr(group['tabname'] ?? group['name'] ?? 'hot');
      for (final item in listOf(group['list'])) {
        final kw = safeStr(item['keyword'] ?? item['word'] ?? item['name'] ?? '');
        if (kw.isNotEmpty) {
          out.add(SearchSuggestItem(keyword: kw, type: gName));
        }
      }
    }
    Log.d(_tag, 'searchHot got=${out.length}');
    return out;
  } catch (e, st) {
    Log.e(_tag, 'searchHot failed', e, st);
    return const <SearchSuggestItem>[];
  }
}
