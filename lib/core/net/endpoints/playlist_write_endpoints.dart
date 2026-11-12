// L4 core/net/endpoints · 歌单写操作端点封装（批9-B 真实请求 + 批N3-B 三态实测修正）
// 范围：建歌单 / 删歌单 / 歌单删歌 / 歌单分类 tags / 用户歌单。
// 端点路径与参数据 docs/ENDPOINT_TRUTH.md §4（playlist_add/del/tracks_del/
//   tags/user_playlist），Registry 声明见 kugou_client.dart。
// 质量原则：写操作禁止回退/重试（防重复提交，PARITY_NOTES.md）。
// 字段容错（listid/status/error_code）+ try/catch + Log('ep.playlist.write')。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../crypto_rsa.dart' show playlistAesEncrypt, playlistAesDecrypt, rsaEncrypt2;
import '../kugou_client.dart';
import '../signing.dart' show KugouSign;
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
    // 批N3-B 实测：data.info.listid（int），data.listid 不存在。
    final data = dataOf(res);
    final infoRaw = data['info'];
    String id = '';
    if (infoRaw is Map) {
      id = safeStr(infoRaw['listid'] ?? infoRaw['list_create_listid'] ?? '');
    }
    Log.d(_tag, 'createPlaylist name=$n id=$id');
    return id.isEmpty ? null : id;
  } catch (e, st) {
    Log.e(_tag, 'createPlaylist failed name=$name', e, st);
    return null;
  }
}

/// 删歌单（POST /v2/delete_list + x-router cloudlist.service.kugou.com）。
/// 真实加密契约（出处 KuGouMusicApi util/crypto.js + module/playlist_del.js，
/// 批F1-B 落地；实测 20010 "need param p" 后按上游契约实现）：
///   dataMap = {listid:Number, total_ver:0, type:1}（明文 body 为此 JSON 时
///     网关不识别，body 必须是 AES Base64 密文）；
///   aes = playlistAesEncrypt(dataMap)：key=randomString(6) 小写，
///     encryptKey=md5(key)[0,16)，iv=md5(key)[16,32)，AES-128-CBC PKCS7，
///     body = Base64(ciphertext)；
///   p = rsaEncrypt2(jsonEncode({aes:key, uid:userid, token})).toUpperCase()
///     （RSAES-PKCS1-V1_5，1024 位公钥）；
///   query 含 p + key=signParamsKey(clienttime 秒) + clientver/appid/
///     clienttime/last_time/last_area='gztx'（多参不缺参）。
/// 响应为 AES 密文（Base64），同 key 派生解密。写操作不重试，失败 false + Log。
Future<bool> deletePlaylist(KugouClient client, String listid) async {
  try {
    final id = int.tryParse(listid.trim());
    final uid = int.tryParse(client.session.userid.trim());
    final token = client.session.token;
    if (id == null || uid == null || token.isEmpty) {
      Log.w(_tag, 'deletePlaylist missing listid/userid/token');
      return false;
    }
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dataMap = <String, Object?>{
      'listid': id,
      'total_ver': 0,
      'type': 1,
    };
    final aes = playlistAesEncrypt(dataMap);
    final p = rsaEncrypt2(jsonEncode(<String, Object?>{
      'aes': aes.key,
      'uid': uid,
      'token': token,
    }));
    final res = await client.request(EndpointRegistry.playlistDelete,
        <String, Object?>{
      // module/playlist_del.js paramsMap：clienttime/key/last_area/clientver/
      // appid/last_time/p（key=signParamsKey，多参不缺参）。
      'clienttime': clienttime,
      'key': KugouSign.signParamsKey('$clienttime'),
      'last_area': 'gztx',
      'clientver': KugouSign.clientver,
      'appid': KugouSign.appid,
      'last_time': clienttime,
      'p': p,
    }, rawBody: aes.cipherBase64);
    // 响应为 AES 密文（非 JSON → _raw_text），同 key 派生解密后判 status。
    final rawText = '${res['_raw_text'] ?? ''}';
    if (rawText.isEmpty) {
      // 网关偶发直接回 JSON：按通用 _ok 判定。
      final ok = _ok(res);
      Log.d(_tag, 'deletePlaylist id=$listid plain-json ok=$ok');
      return ok;
    }
    final text = playlistAesDecrypt(rawText, aes.key);
    Map<String, dynamic> body;
    try {
      final dec = jsonDecode(text);
      body = dec is Map<String, dynamic>
          ? dec
          : <String, dynamic>{'_raw': text};
    } catch (_) {
      body = <String, dynamic>{'_raw': text};
    }
    final ok = _ok(body);
    Log.d(_tag, 'deletePlaylist id=$listid decrypted ok=$ok');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'deletePlaylist failed listid=$listid', e, st);
    return false;
  }
}

/// 歌单加歌（POST /cloudlist.service/v6/add_song，批N3-B 三态实测 status=1）。
/// body data:[{number,name,hash(小写),size,sort,timelen,bitrate,album_id,mixsongid}]，
/// query last_time/last_area=gztx/userid/token。成功返回 data.info[] 逐曲回执
/// （fileid/hash/name/cover/audio_id/singerinfo…），失败 null。写操作不重试。
Future<List<Map<String, dynamic>>> addSongsToPlaylist(
  KugouClient client,
  String listid,
  List<Map<String, String>> songs, // {name, hash, albumId, mixsongid, size, timelen, bitrate}
) async {
  try {
    final id = int.tryParse(listid.trim());
    if (id == null || songs.isEmpty) {
      Log.w(_tag, 'addSongsToPlaylist empty listid or songs');
      return const <Map<String, dynamic>>[];
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final res = await client.request(EndpointRegistry.playlistAddSongs,
        <String, Object?>{
      'last_time': now,
      'last_area': 'gztx',
      'userid': client.session.userid,
      'token': client.session.token,
    }, body: <String, Object?>{
      'userid': client.session.userid,
      'token': client.session.token,
      'listid': id,
      'list_ver': 0,
      'type': 0,
      'slow_upload': 1,
      'scene': 'false;null',
      'data': [
        for (var i = 0; i < songs.length; i++)
          <String, Object?>{
            'number': i + 1,
            'name': songs[i]['name'] ?? '',
            'hash': (songs[i]['hash'] ?? '').toLowerCase(),
            'size': int.tryParse(songs[i]['size'] ?? '') ?? 0,
            'sort': 0,
            'timelen': int.tryParse(songs[i]['timelen'] ?? '') ?? 0,
            'bitrate': int.tryParse(songs[i]['bitrate'] ?? '') ?? 0,
            'album_id': int.tryParse(songs[i]['albumId'] ?? '') ?? 0,
            'mixsongid': int.tryParse(songs[i]['mixsongid'] ?? '') ?? 0,
          },
      ],
    });
    if (!_ok(res)) {
      Log.w(_tag, 'addSongsToPlaylist not ok listid=$listid');
      return const <Map<String, dynamic>>[];
    }
    final data = dataOf(res);
    final raw = listOf(data['info']);
    final items = <Map<String, dynamic>>[for (final m in raw) m];
    Log.d(_tag, 'addSongsToPlaylist listid=$listid n=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'addSongsToPlaylist failed listid=$listid', e, st);
    return const <Map<String, dynamic>>[];
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
      // 批N3-B 实测：data:[{fileid}]，fileid=album_audio_id（audio_id），
      // 非 hash；body {listid,userid,data,type:0,token,list_ver}。
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

/// 歌单分类 tags（POST /pubsongs/v1/get_tags_by_type）。读操作。
/// 批N3-B 实测：data[] 直排数组，item {tag_id,tag_name,parent_id,sort,son[]}，
/// son[] 子标签 {tag_id,tag_name,parent_id,sort}（tag_name 非 tagname）。
Future<List<String>> getPlaylistTags(KugouClient client) async {
  try {
    final res = await client.request(EndpointRegistry.playlistTags,
        <String, Object?>{}, body: <String, Object?>{
      'tag_type': 'collection',
      'tag_id': 0,
      'source': 3,
    });
    final data = dataOf(res);
    final raw = listOf(data['info'] ?? data['data'] ?? res['data'] ?? data);
    final tags = <String>[];
    void collect(List<Map<String, dynamic>> items) {
      for (final t in items) {
        final n = safeStr(t['tag_name'] ?? t['tagname'] ?? t['name'] ?? '');
        if (n.isNotEmpty) tags.add(n);
        final sons = listOf(t['son']);
        if (sons.isNotEmpty) {
          collect(<Map<String, dynamic>>[for (final m in sons) m]);
        }
      }
    }

    collect(<Map<String, dynamic>>[for (final m in raw) m]);
    Log.d(_tag, 'getPlaylistTags got=${tags.length}');
    return tags;
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
    // 批N3-B 实测：data.info[]（A6-1），list/data 兜底保留容错。
    final raw = listOf(data['info'] ?? data['list'] ?? data['data'] ??
        res['list'] ?? res['data']);
    final items = raw.map(PlaylistBrief.fromMap).toList(growable: false);
    Log.d(_tag, 'getUserPlaylists page=$p got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getUserPlaylists failed page=$page', e, st);
    return const <PlaylistBrief>[];
  }
}
