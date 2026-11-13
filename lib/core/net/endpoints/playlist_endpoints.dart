// L4 core/net/endpoints · 歌单端点封装（recommend / detail / tracks / addSongs）
// playlistTracks 分页换算：page/pagesize → begin_idx=(page-1)*pagesize（docs §3.3）。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import '../signing.dart' show KugouSign;
import 'models.dart';
import 'playlist_write_endpoints.dart' as write;

const String _tag = 'ep.playlist';

/// 推荐歌单列表（/v2/special_recommend）。categoryId 0=推荐，11292=HI-RES。
Future<List<PlaylistBrief>> recommendPlaylists(
  KugouClient client, {
  int page = 1,
  int pageSize = 30,
  int categoryId = 0,
}) async {
  try {
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final res = await client.request(EndpointRegistry.playlistRecommend,
        <String, Object?>{}, body: <String, Object?>{
      // 实测修正：body 必须全参（缺 mid/appid/clientver 或 key 用毫秒 → 200101/500）。
      'appid': KugouSign.appid,
      'mid': client.session.mid,
      'clientver': KugouSign.clientver,
      'special_recommend': <String, Object?>{
        'categoryid': categoryId,
        'withtag': 1,
        'withsong': 1,
        'sort': 1,
        'ugc': 1,
        'is_selected': 0,
        'withrecommend': 1,
        'area_code': 1,
      },
      'page': p,
      'pagesize': ps,
      'module_id': 1,
      'platform': 'android',
      'clienttime': '$nowSec',
      'userid': client.session.userid,
      'key': KugouSign.signParamsKey('$nowSec'),
      'req_multi': 1,
      'retrun_min': 5,
      'return_special_falg': 1,
    });
    final data = dataOf(res);
    // 实测修正（批N1-C，A2-1）：响应在 data.special_list[]，列表项含
    // global_collection_id/specialid/specialname/imgurl/play_count/nickname。
    final raw = listOf(data['special_list'] ?? data['special'] ??
        data['list'] ?? data['info']);
    final items = raw.map(PlaylistBrief.fromMap).toList(growable: false);
    Log.d(_tag, 'recommendPlaylists page=$p got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'recommendPlaylists failed page=$page', e, st);
    return const <PlaylistBrief>[];
  }
}

/// 歌单详情（/v3/get_list_info）：data[] 首项。
Future<PlaylistDetail> playlistDetail(
  KugouClient client,
  String playlistId,
) async {
  try {
    final id = playlistId.trim();
    if (id.isEmpty) {
      Log.w(_tag, 'playlistDetail empty id');
      return const PlaylistDetail();
    }
    final res = await client.request(EndpointRegistry.playlistDetail,
        <String, Object?>{}, body: <String, Object?>{
      'data': [
        <String, Object?>{'global_collection_id': id},
      ],
      'userid': client.session.userid,
      'token': client.session.token,
    });
    final data = dataOf(res);
    // 批2-C 修正（docs/API_FIELDS_TRUTH.md §A2-2）：/v3/get_list_info 响应
    // `data` 是**数组**（data[] 首项）；dataOf() 只收 Map，旧写法
    // data['data'] 恒 null → 详情恒返回空 PlaylistDetail。主路径直接取
    // res['data'] 数组，旧包裹形态保留兜底。
    final direct = listOf(res['data']);
    final list = direct.isNotEmpty
        ? direct
        : listOf(data['data'] ?? data['info'] ?? res['info']);
    final first = list.isEmpty ? const <String, dynamic>{} : list.first;
    // tags 兼容 List<String> / List<Map>
    final tags = <String>[];
    try {
      final rawTags = first['tags'];
      if (rawTags is String && rawTags.trim().isNotEmpty) {
        // 批N1-B 实测：get_list_info 的 tags 是逗号分隔字符串。
        for (final t in rawTags.split(',')) {
          final s = t.trim();
          if (s.isNotEmpty) tags.add(s);
        }
      } else {
        for (final t in (rawTags as List? ?? const [])) {
          if (t is Map) {
            tags.add(safeStr(t['tagname'] ?? t['tag_name'] ?? t['name'] ?? ''));
          } else {
            tags.add(safeStr(t));
          }
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'parse tags failed', e, st);
    }
    final d = PlaylistDetail(
      // 批N1-B 实测（docs/API_FIELDS_TRUTH.md A2-2）：get_list_info data[0]
      // 键为 name/pic/list_create_username（无 specialname/imgurl/username），
      // 无 playcount；tags 是逗号分隔字符串（非数组）。
      id: safeStr(first['global_collection_id'] ?? id),
      name: safeStr(first['name'], safeStr(first['specialname'])),
      cover: safeStr(first['pic'], safeStr(first['imgurl'])),
      playCount: safeInt(first['playcount'] ?? first['play_count']),
      trackCount: safeInt(first['count']),
      intro: safeStr(first['intro']),
      creator: safeStr(first['list_create_username'],
          safeStr(first['username'])),
      tags: tags,
      // 批N3-B 实测（API_FIELDS_TRUTH.md A2-2）：data[0].list_ver 存在。
      listVer: safeInt(first['list_ver']),
    );
    Log.d(_tag, 'playlistDetail id=$id name=${d.name} listVer=${d.listVer}');
    return d;
  } catch (e, st) {
    Log.e(_tag, 'playlistDetail failed id=$playlistId', e, st);
    return const PlaylistDetail();
  }
}

/// 歌单全部歌曲（旧版 /pubsongs/v2/get_other_list_file_nofilt）。
/// page 从 1 起；begin_idx=(page-1)*pagesize（docs §3.3 显式换算）。
Future<TrackPage> playlistTracks(
  KugouClient client,
  String playlistId,
  int page,
  int pageSize,
) async {
  try {
    final id = playlistId.trim();
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    if (id.isEmpty) {
      Log.w(_tag, 'playlistTracks empty id');
      return const TrackPage();
    }
    final beginIdx = (p - 1) * ps;
    final res = await client.request(EndpointRegistry.playlistTracks,
        <String, Object?>{
      // 实测修正（2026-11-10）：参数键必须是 specialid，
      // 传 global_collection_id 一律 20010 get other list file fail。
      'specialid': id,
      'begin_idx': beginIdx,
      'pagesize': ps,
      'area_code': 1,
      'plat': 1,
      'type': 1,
      'mode': 1,
      'personal_switch': 1,
      'extend_fields': 'abtags,hot_cmt,popularization',
    });
    final data = dataOf(res);
    // 实测修正：歌曲列表在 data.songs[]（hash/name/audio_id/size…），
    // 非 data.info[]；err=0 也可能空列表，总数看 data.count。
    final items = listOf(data['songs'] ?? data['info'])
        .map(SongBrief.fromTrackInfo)
        .toList(growable: false);
    final total = safeInt(data['count']);
    Log.d(_tag,
        'playlistTracks id=$id page=$p begin=$beginIdx got=${items.length}/$total');
    return TrackPage(
        total: total, beginIdx: beginIdx, pageSize: ps, items: items);
  } catch (e, st) {
    Log.e(_tag, 'playlistTracks failed id=$playlistId page=$page', e, st);
    return const TrackPage();
  }
}

/// 歌单加歌（/v2/add_songs_by_hash）。songIds 用 MixSongID；hash+albumId 必带。
/// 返回是否成功（响应 status==1 视为成功，容错）。
Future<bool> addSongsToPlaylist(
  KugouClient client,
  String playlistId,
  List<SongBrief> songs, {
  int listVer = 0,
}) async {
  // 批R3：旧猜测契约（resource/songid）已被 N3-B 实测证伪；统一转发到
  // playlist_write_endpoints 的真实 /v6/add_song 契约（data 全字段 + list_ver）。
  try {
    final rows = await write.addSongsToPlaylist(
      client,
      playlistId,
      <Map<String, String>>[
        for (final s in songs)
          <String, String>{
            'name': s.name,
            'hash': s.hash,
            'albumId': s.albumId,
            'mixsongid': '${s.mixSongId}',
            'size': '${s.fileSize}',
            'timelen': '${s.durationSec * 1000}',
            'bitrate': '${s.bitrate}',
          },
      ],
      listVer: listVer,
    );
    return rows.isNotEmpty;
  } catch (e, st) {
    Log.e(_tag, 'addSongsToPlaylist failed id=$playlistId', e, st);
    return false;
  }
}
