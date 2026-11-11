// L4 core/net/endpoints · 歌单写操作端点封装（批9-B · 真实请求）
// 范围：建歌单 / 删歌单 / 歌单删歌 / 歌单分类 tags / 用户歌单。
// 端点路径与参数据 docs/ENDPOINT_TRUTH.md §4（playlist_add/del/tracks_del/
//   tags/user_playlist），Registry 声明见 kugou_client.dart。
// 质量原则：写操作禁止回退/重试（防重复提交，PARITY_NOTES.md）。
// 字段容错（listid/status/error_code）+ try/catch + Log('ep.playlist.write')。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart';

const String _tag = 'ep.playlist.write';

/// 从响应提取成功标志：data.status==1 优先，其次顶层 status==1 / error_code==0。
bool _ok(Map<String, dynamic> res) {
  final data = dataOf(res);
  final s = safeInt(data['status'],
      safeInt(res['status'], safeInt(res['error_code'], -1)));
  if (s == 1 || s == 0) return true;
  // 未留样响应形态：error_code==0 或缺失 status 时按成功容错，留 Log 待实测。
  Log.d(_tag, 'ambiguous success flag status=$s');
  return s == 0;
}

/// 建歌单（POST /v2/add_playlist，待三态实测）。成功返回新歌单 listid，失败 null。
/// 写操作：一次提交，失败不重试。
Future<String?> createPlaylist(KugouClient client, String name) async {
  try {
    final n = name.trim();
    if (n.isEmpty) {
      Log.w(_tag, 'createPlaylist empty name');
      return null;
    }
    final res = await client.request(EndpointRegistry.playlistCreate,
        <String, Object?>{
      // ENDPOINT_TRUTH.md §4 playlist_add.js：type==0 自建时 query 显式
      // last_time / last_area / userid / token（多参不缺参）。
      'last_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'last_area': 'gztx',
      'userid': client.session.userid,
      'token': client.session.token,
    }, body: <String, Object?>{
      'userid': client.session.userid,
      'token': client.session.token,
      'total_ver': 0,
      'name': n,
      'type': 0,
      'source': 0,
      'is_pri': 0,
      'list_create_userid': 0,
      'list_create_listid': 0,
      'list_create_gid': 0,
      'from_shupinmv': 0,
    });
    if (!_ok(res)) {
      Log.w(_tag, 'createPlaylist not ok name=$n');
      return null;
    }
    final data = dataOf(res);
    final id = safeStr(data['listid'] ?? data['list_id'] ??
        data['id'] ?? res['listid'] ?? '');
    Log.d(_tag, 'createPlaylist name=$n id=$id');
    return id.isEmpty ? null : id;
  } catch (e, st) {
    Log.e(_tag, 'createPlaylist failed name=$name', e, st);
    return null;
  }
}

/// 删歌单（POST /v2/del_playlist，待三态实测）。写操作：不重试。
Future<bool> deletePlaylist(KugouClient client, String listid) async {
  try {
    final id = listid.trim();
    if (id.isEmpty) {
      Log.w(_tag, 'deletePlaylist empty listid');
      return false;
    }
    // ENDPOINT_TRUTH.md §4 playlist_del.js：query p/key/last_time/last_area 等
    // AES/RSA 加密契约未留样（本仓库无 playlistAesDecrypt/rsaEncrypt2）；
    // listid/total_ver/type 明文兜底发送，写操作不重试，失败留痕。
    Log.w(_tag, 'deletePlaylist encrypted p/key contract unmeasured, '
        'plain fallback (no retry)');
    final res = await client.request(EndpointRegistry.playlistDelete,
        <String, Object?>{
      'last_area': 'gztx',
      'last_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, body: <String, Object?>{
      'listid': id,
      'total_ver': 0,
      'type': 1,
      'userid': client.session.userid,
      'token': client.session.token,
    });
    final ok = _ok(res);
    Log.d(_tag, 'deletePlaylist id=$id ok=$ok');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'deletePlaylist failed listid=$listid', e, st);
    return false;
  }
}

/// 歌单删歌（POST /v4/delete_songs，ENDPOINT_TRUTH.md §4
/// playlist_tracks_del.js）。写操作：不重试。
Future<bool> removeSongsFromPlaylist(
  KugouClient client,
  String listid,
  List<String> hashes,
) async {
  try {
    final id = listid.trim();
    final hs = hashes
        .map((h) => h.trim())
        .where((h) => h.isNotEmpty)
        .toList(growable: false);
    if (id.isEmpty || hs.isEmpty) {
      Log.w(_tag, 'removeSongsFromPlaylist empty listid or hashes');
      return false;
    }
    final res = await client.request(EndpointRegistry.playlistDelSongs,
        <String, Object?>{}, body: <String, Object?>{
      'resource': [
        for (final h in hs)
          <String, Object?>{'hash': h, 'number': 1},
      ],
      'listid': id,
      'userid': client.session.userid,
      'token': client.session.token,
      'list_ver': 0,
    });
    final ok = _ok(res);
    Log.d(_tag, 'removeSongsFromPlaylist id=$id n=${hs.length} ok=$ok');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'removeSongsFromPlaylist failed listid=$listid', e, st);
    return false;
  }
}

/// 歌单分类 tags（POST /pubsongs/v1/get_tags_by_type，docs §3.3 留样：
/// body {tag_type:"collection", tag_id:0, source:3}）。读操作，字段容错。
Future<List<String>> getPlaylistTags(KugouClient client) async {
  try {
    final res = await client.request(EndpointRegistry.playlistTags,
        <String, Object?>{}, body: <String, Object?>{
      'tag_type': 'collection',
      'tag_id': 0,
      'source': 3,
    });
    // 响应字段容错：data.tags[]/data.info[]（tagname/name/title 别名）。
    final data = dataOf(res);
    final raw = listOf(data['tags'] ?? data['data'] ?? data['info'] ??
        res['tags'] ?? res['data']);
    final tags = <String>[];
    for (final t in raw) {
      if (t is Map) {
        tags.add(safeStr(t['tagname'] ?? t['name'] ?? t['title'] ?? ''));
      } else {
        tags.add(safeStr(t));
      }
    }
    final clean = tags.where((t) => t.isNotEmpty).toList(growable: false);
    Log.d(_tag, 'getPlaylistTags got=${clean.length}');
    return clean;
  } catch (e, st) {
    Log.e(_tag, 'getPlaylistTags failed', e, st);
    return const <String>[];
  }
}

/// 用户歌单（POST /v7/get_all_list，x-router cloudlist；docs §3.3：
/// query plat=1&userid&token，body userid/token/total_ver/type=2/page/pagesize）。
/// 读操作，字段容错（PlaylistBrief.fromMap 全容错）。
Future<List<PlaylistBrief>> getUserPlaylists(
  KugouClient client, {
  int page = 1,
  int pageSize = 30,
}) async {
  try {
    final uid = client.session.userid;
    if (uid.isEmpty) {
      Log.w(_tag, 'getUserPlaylists not logged in (empty userid)');
      return const <PlaylistBrief>[];
    }
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    final res = await client.request(EndpointRegistry.userPlaylists,
        <String, Object?>{
      // ENDPOINT_TRUTH.md §4 user_playlist.js：query plat/userid/token +
      // 默认参数（多参不缺参）。
      'plat': 1,
      'userid': uid,
      'token': client.session.token,
    }, body: <String, Object?>{
      'userid': uid,
      'token': client.session.token,
      'total_ver': 979,
      'type': 2,
      'page': p,
      'pagesize': ps,
    });
    final data = dataOf(res);
    final raw = listOf(data['list'] ?? data['info'] ?? data['data'] ??
        res['list'] ?? res['data']);
    final items = raw.map(PlaylistBrief.fromMap).toList(growable: false);
    Log.d(_tag, 'getUserPlaylists page=$p got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getUserPlaylists failed page=$page', e, st);
    return const <PlaylistBrief>[];
  }
}
