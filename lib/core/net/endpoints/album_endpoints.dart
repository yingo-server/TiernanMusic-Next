// L4 core/net/endpoints · 专辑与相似歌单端点封装（功能对齐批4-B，主会话实现）
// 端点声明已在 kugou_client.dart：albumSongs / playlistSimilar / albumDetail。
// 契约：字段缺失一律给默认值不崩；每函数 try/catch + Log('ep.album')。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import '../signing.dart' show KugouSign;
import 'models.dart'
    show
        SongBrief,
        TrackPage,
        PlaylistBrief,
        safeInt,
        safeStr,
        dataOf,
        listOf;

const String _tag = 'ep.album';

/// 专辑详情（纯数据模型）。
class AlbumDetail {
  const AlbumDetail({
    this.id = '',
    this.name = '',
    this.cover = '',
    this.intro = '',
    this.publishDate = '',
  });
  final String id;
  final String name;
  final String cover;
  final String intro;
  final String publishDate;

  bool get isEmpty => id.isEmpty && name.isEmpty;
}

/// 专辑详情（/kmr/v2/albums，body data:[{album_id}]）。
Future<AlbumDetail> getAlbumDetail(KugouClient client, String albumId) async {
  try {
    final id = albumId.trim();
    if (id.isEmpty) {
      Log.w(_tag, 'getAlbumDetail empty id');
      return const AlbumDetail();
    }
    final res = await client.request(
      EndpointRegistry.albumDetail,
      <String, Object?>{},
      body: <String, Object?>{
        'data': [
          <String, Object?>{'album_id': id}
        ],
      },
    );
    final data = dataOf(res);
    final list = listOf(data['data'] ?? data['list'] ?? data['info']);
    final m = list.isEmpty ? <String, dynamic>{} : list.first;
    final d = AlbumDetail(
      id: safeStr(m['album_id'] ?? m['id'] ?? id),
      name: safeStr(m['album_name'] ?? m['name'] ?? m['albumname']),
      cover: safeStr(m['sizable_cover'] ?? m['imgurl'] ?? m['cover']),
      intro: safeStr(m['intro'] ?? m['description']),
      publishDate: safeStr(m['publish_date'] ?? m['publish_time']),
    );
    Log.d(_tag, 'getAlbumDetail id=$id name=${d.name}');
    return d;
  } catch (e, st) {
    Log.e(_tag, 'getAlbumDetail failed id=$albumId', e, st);
    return const AlbumDetail();
  }
}

/// 专辑歌曲（/v1/album_audio/lite，响应 {songs,total} 或 data.songs[]）。
Future<TrackPage> getAlbumSongs(
  KugouClient client,
  String albumId,
  int page,
  int pageSize,
) async {
  try {
    final id = albumId.trim();
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    if (id.isEmpty) return const TrackPage();
    final res = await client.request(
      EndpointRegistry.albumSongs,
      <String, Object?>{},
      body: <String, Object?>{
        'album_id': id,
        'page': p,
        'pagesize': ps,
        'is_buy': 0,
      },
    );
    final data = dataOf(res);
    final raw = data['songs'] ?? data['list'] ?? data['info'] ??
        res['songs'] ?? res['list'];
    final items = listOf(raw)
        .map(SongBrief.fromTrackInfo)
        .where((s) => s.hash.isNotEmpty)
        .toList(growable: false);
    final total = safeInt(data['total'] ?? res['total'] ?? items.length);
    Log.d(_tag, 'getAlbumSongs id=$id page=$p got=${items.length}/$total');
    return TrackPage(
      total: total,
      beginIdx: (p - 1) * ps,
      pageSize: ps,
      items: items,
    );
  } catch (e, st) {
    Log.e(_tag, 'getAlbumSongs failed id=$albumId page=$page', e, st);
    return const TrackPage();
  }
}

/// 相似歌单（/pubsongs/v1/kmr_get_similar_lists）。
/// 批N2-C 实测（API_FIELDS_TRUTH.md A3-3，2026-11-12）：
/// - body 全参不缺参：appid/clientver/clienttime(秒)/key/userid/ugc/show_list/need_songs
///   + data:[{global_collection_id}]；key 盐 Or2onSUDL9kpyMys0NsMqDcYC0NVvEIf（实测
///   body 同入 android 签名，key 内容仅作 body 校验，两种公式均 status=1）。
/// - 响应 data **直接是数组**，item = {collection_list[], tag_info[]}——相似歌单在
///   双层 collection_list[] 内（40 项），需平铺；tag_info 是 [{tag_id,tag_name}] 数组。
/// - collection_list item 键（22 个）：global_collection_id/collection_id/collection_name/
///   cover(完整URL)/flexible_cover({size}模板)/intro/heat/song_count/publish_date/type/
///   user_id/user_name/user_avatar 等；内嵌 songs[]（hash/name/mixsongid/cover/
///   privilege/level/sort/trans_param，无 duration——不映射不猜）。
Future<List<PlaylistBrief>> getSimilarPlaylists(
  KugouClient client,
  String playlistId,
) async {
  try {
    final id = playlistId.trim();
    if (id.isEmpty) return const <PlaylistBrief>[];
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final res = await client.request(
      EndpointRegistry.playlistSimilar,
      <String, Object?>{},
      body: <String, Object?>{
        'appid': KugouSign.appid,
        'clientver': KugouSign.clientver,
        'clienttime': nowSec,
        'key': KugouSign.signParamsKey('$nowSec'),
        'userid': client.session.userid.isEmpty
            ? 0
            : int.tryParse(client.session.userid) ?? 0,
        'ugc': 1,
        'show_list': 1,
        'need_songs': 1,
        'data': [
          <String, Object?>{'global_collection_id': id}
        ],
      },
    );
    final data = dataOf(res);
    // data 是数组形态：listOf(data) 直接取；容错兼容 data.data / data.lists 旧路径。
    final groups = listOf(data['data']).isEmpty
        ? listOf(res['data'])
        : listOf(data['data']);
    final items = <PlaylistBrief>[];
    for (final g in groups) {
      for (final m in listOf(g['collection_list'])) {
        final p = PlaylistBrief.fromMap(m);
        if (p.id.isNotEmpty) items.add(p);
      }
    }
    Log.d(_tag, 'getSimilarPlaylists id=$id got=${items.length}');
    return List<PlaylistBrief>.unmodifiable(items);
  } catch (e, st) {
    Log.e(_tag, 'getSimilarPlaylists failed id=$playlistId', e, st);
    return const <PlaylistBrief>[];
  }
}
