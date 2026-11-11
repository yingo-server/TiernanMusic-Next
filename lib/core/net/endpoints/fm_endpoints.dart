// L4 core/net/endpoints · 个人 FM 端点封装（批9-B · 真实请求）
// 端点路径据 docs/ENDPOINT_TRUTH.md §3：
//   personalFm → POST gateway /v2/personal_recommend + x-router
//     persnfm.service.kugou.com（body {action,mode,song_pool_id,m_type,key,...}）。
//   fmSongs → gateway /v1/app_song_list_offset（fmid/fmtype/offset/size）。
// 对应声明：EndpointRegistry.personalFm / EndpointRegistry.fmSongs（kugou_client.dart）。
// 装配方式：L5 logic/catalog/fm_logic.dart 经 bridge_logic 门面消费本文件；
//   L6 surface 只拿 FmLogic，不直接 import 端点文件。
// 铁律：只连酷狗官方 gateway 域名；每函数 try/catch + Log('ep.fm')；字段容错不崩；
//   dfid/mid/uuid 恒显式携带并参与签名；多参不缺参（缺参按 0/空串占位并 Log.w）。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart' show Endpoint, EndpointRegistry, KugouClient;
import '../signing.dart' show KugouSign;
import 'models.dart' show SongBrief, dataOf, listOf, safeInt, safeStr;

const String _tag = 'ep.fm';

/// personalFm / fmSongs 已按 ENDPOINT_TRUTH.md §3 修正为真实请求（批9-B）。
const bool kFmPlayProbed = true;
const bool kFmSongsProbed = true;

/// FM 曲目最小模型（响应字段按既有搜索/歌单字段别名容错，缺失给默认）。
class FmTrack {
  const FmTrack({
    this.hash = '',
    this.name = '',
    this.singer = '',
    this.mixSongId = 0,
  });

  final String hash;
  final String name;
  final String singer;
  final int mixSongId;

  factory FmTrack.fromMap(Map<String, dynamic> m) {
    try {
      return FmTrack(
        hash: safeStr(m['hash'] ?? m['FileHash'] ?? m['file_hash'])
            .toLowerCase(),
        name: safeStr(m['name'] ?? m['FileName'] ?? m['songname']),
        singer: safeStr(m['singer'] ?? m['singername'] ?? m['SingerName']),
        mixSongId: safeInt(m['mixSongId'] ?? m['mixsongid'] ?? m['MixSongID']),
      );
    } catch (e, st) {
      Log.e(_tag, 'FmTrack.fromMap failed', e, st);
      return const FmTrack();
    }
  }

  /// 转成统一播放模型（队列/播放页只认 SongBrief）。
  SongBrief toSongBrief() {
    try {
      return SongBrief(
          hash: hash.toLowerCase(),
          name: name,
          singer: singer,
          mixSongId: mixSongId);
    } catch (e, st) {
      Log.e(_tag, 'FmTrack.toSongBrief failed', e, st);
      return const SongBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'hash': hash,
        'name': name,
        'singer': singer,
        'mixSongId': mixSongId,
      };

  @override
  String toString() {
    try {
      return 'FmTrack(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'FmTrack.toString failed', e, st);
      return 'FmTrack(<unavailable>)';
    }
  }
}

/// 容错解析 FM 歌曲列表。
/// 批N3-A 实测（A5-6）：personal_recommend 列表键是 data.song_list[]；
/// app_song_list_offset 是 data[].songs[]；rcmd_list 是 data[].rcmdlist[]。
List<SongBrief> _parseSongs(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    final raw = data['song_list'] ?? data['songs'] ?? data['list'] ??
        data['info'] ?? data['lists'] ?? res['song_list'] ?? res['songs'] ??
        res['list'] ?? res['data'];
    final items = listOf(raw)
        .map(FmTrack.fromMap)
        .map((t) => t.toSongBrief())
        .where((s) => s.hash.isNotEmpty)
        .toList(growable: false);
    final ec = safeInt(res['errcode'] ?? res['err_code'] ?? data['errcode']);
    if (ec != 0) Log.w(_tag, 'parseSongs server ec=$ec');
    Log.d(_tag, 'parseSongs got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'parseSongs failed', e, st);
    return const <SongBrief>[];
  }
}

/// 唯一请求出口（真实请求）。dfid/mid/uuid 恒显式携带并参与签名（铁律 6）。
Future<List<SongBrief>> _fetch(
  KugouClient client,
  Endpoint ep,
  Map<String, Object?> params, {
  Map<String, Object?> body = const <String, Object?>{},
}) async {
  try {
    final p = <String, Object?>{
      ...params,
      'dfid': client.session.dfid,
      'mid': client.session.mid,
      'uuid': '-',
    };
    final res = await client.request(ep, p, body: body);
    return _parseSongs(res);
  } catch (e, st) {
    Log.e(_tag, 'fetch failed ep=${ep.id}', e, st);
    return const <SongBrief>[];
  }
}

/// 个人 FM 首批（personalFm：POST，ENDPOINT_TRUTH.md §3 personal_fm.js）。
/// body 全参集合（多参不缺参；缺值按 0/空串占位并 Log.w）：
/// { action('play'), mode('normal'), song_pool_id:0, m_type:1, mid, userid/kguid:0,
///   appid, clienttime, clientver, key=signParamsKey(ms), area_code:1, platform,
///   recommend_source_locked:0, callerid:'', remain_songcnt:0, is_overplay:0,
///   fakem:0, token, vip_type:0, hash:'', songid:0, playtime:0 }。
/// 响应 data.songs[] / data.list[] 容错映射；空响应返回空列表。
Future<List<SongBrief>> getFmPlay(
  KugouClient client, {
  String mode = 'normal',
  String action = 'play',
}) async {
  try {
    if (mode.isEmpty) Log.w(_tag, 'getFmPlay empty mode -> placeholder 0');
    final ms = '${DateTime.now().millisecondsSinceEpoch}';
    final uid = client.session.userid;
    if (uid.isEmpty) Log.w(_tag, 'getFmPlay empty userid -> placeholder 0');
    final body = <String, Object?>{
      'appid': KugouSign.appid,
      // 批N3-A 实测（A5-6）：FM 域 clienttime/key 用毫秒，不能除以 1000。
      'clienttime': ms,
      'mid': client.session.mid,
      'action': action.isEmpty ? 'play' : action,
      'mode': mode.isEmpty ? 'normal' : mode,
      'recommend_source_locked': 0,
      'song_pool_id': 0,
      'callerid': '',
      'm_type': 1,
      'platform': 'android',
      'area_code': 1,
      'remain_songcnt': 0,
      'clientver': KugouSign.clientver,
      'is_overplay': 0,
      // 实测固定串（fakem:0 会导致取批失败）；kguid 应等于 userid。
      'fakem': 'ca981cfc583a4c37f28d2d49000013c16a0a',
      'key': KugouSign.signParamsKey(ms),
      'userid': uid,
      'kguid': uid,
      'token': client.session.token,
      'vip_type': 0,
      'hash': '',
      'songid': 0,
      'playtime': 0,
    };
    return await _fetch(client, EndpointRegistry.personalFm,
        const <String, Object?>{}, body: body);
  } catch (e, st) {
    Log.e(_tag, 'getFmPlay failed mode=$mode action=$action', e, st);
    return const <SongBrief>[];
  }
}

/// 电台/FM 批量歌曲（fmSongs：GET，ENDPOINT_TRUTH.md §3 fm_songs.js）。
/// query fmid/fmtype/offset/size 全显式；空参占位 0/空串并 Log.w。
Future<List<SongBrief>> getFmSongs(
  KugouClient client, {
  String fmid = '',
  String fmtype = '',
  int offset = 0,
  int size = 0,
}) async {
  try {
    final ep = EndpointRegistry.fmSongs;
    final off = offset < 0 ? 0 : offset;
    final n = size < 0 ? 0 : size;
    final fid = fmid.trim();
    final fty = fmtype.trim();
    if (fid.isEmpty) Log.w(_tag, 'getFmSongs empty fmid -> placeholder ""');
    if (fty.isEmpty) Log.w(_tag, 'getFmSongs empty fmtype -> placeholder ""');
    if (n == 0) Log.w(_tag, 'getFmSongs size=0 -> placeholder 0');
    final params = <String, Object?>{
      'fmid': fid,
      'fmtype': fty,
      'offset': off,
      'size': n,
    };
    return await _fetch(client, ep, params);
  } catch (e, st) {
    Log.e(_tag, 'getFmSongs failed offset=$offset size=$size', e, st);
    return const <SongBrief>[];
  }
}
