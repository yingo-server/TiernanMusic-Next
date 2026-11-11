// L4 core/net/endpoints · 用户域/上报端点封装（批6-A）
// 端点路径据 docs/ENDPOINT_TRUTH.md 修正（真实 URL/x-router 见 kugou_client.dart 声明）。
// 实测状态：getUserCloud / getSongClimax 已按真实端点发请求（三态探针 status/errcode 已确认）；
//   getUserDetail / uploadPlayHistory / reportListen 的参数契约（RSA p 串、songs 数组、body 形态）
//   仍待三态实测，按「不猜参数」原则返回语义空值 + Log.w，不伪造成功。
// 铁律：字段容错 safe* + try/catch + Log('ep.user')；dfid/mid/uuid 由
//    KugouClient.request 默认参数恒显式携带并参与签名。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import '../crypto_extra.dart' show RsaRaw;
import 'models.dart';

const String _tag = 'ep.user';

/// 用户档案强类型结果（get_my_info 响应容错映射）。
class UserProfile {
  const UserProfile({
    this.userid = '',
    this.nickname = '',
    this.avatar = '',
    this.vipType = 0,
    this.level = 0,
  });

  final String userid;
  final String nickname;
  final String avatar; // 头像 URL
  final int vipType; // 0=非 VIP
  final int level; // 用户等级

  factory UserProfile.fromMap(Map<String, dynamic> m) {
    try {
      return UserProfile(
        userid: safeStr(m['userid'] ?? m['UserId'] ?? ''),
        nickname: safeStr(m['nickname'] ?? m['UserName'] ?? ''),
        avatar: safeStr(m['avatar'] ?? m['user_pic'] ?? ''),
        vipType: safeInt(m['vip_type'] ?? m['vip_type_new']),
        level: safeInt(m['level'] ?? m['user_level']),
      );
    } catch (e, st) {
      Log.e(_tag, 'UserProfile.fromMap failed', e, st);
      return const UserProfile();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'userid': userid, 'nickname': nickname, 'avatar': avatar,
        'vipType': vipType, 'level': level,
      };

  bool get isEmpty => userid.isEmpty && nickname.isEmpty;

  @override
  String toString() {
    try {
      return 'UserProfile(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'UserProfile.toString failed', e, st);
      return 'UserProfile(<unavailable>)';
    }
  }
}

/// 用户详情（POST /v3/get_my_info + x-router usercenter.kugou.com）。
/// 契约据 ENDPOINT_TRUTH.md §1 / module/user_detail.js：body
/// {visit_time(秒), usertype:1, p:RSA({token,clienttime})大写, userid}，query plat=1。
Future<UserProfile> getUserDetail(KugouClient client) async {
  try {
    if (client.session.token.isEmpty) {
      Log.w(_tag, 'getUserDetail no token, skip');
      return const UserProfile();
    }
    final ct = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pk = RsaRaw.encryptHex(
        '{"token":"${client.session.token}","clienttime":$ct}').toUpperCase();
    final res = await client.request(
      EndpointRegistry.userDetail,
      <String, Object?>{'plat': 1},
      body: <String, Object?>{
        'visit_time': ct,
        'usertype': 1,
        'p': pk,
        'userid': client.session.userid,
      },
    );
    final d = dataOf(res);
    final p = UserProfile.fromMap(d.isEmpty ? res : d);
    Log.d(_tag, 'getUserDetail uid=${p.userid} nick=${p.nickname}');
    return p;
  } catch (e, st) {
    Log.e(_tag, 'getUserDetail failed', e, st);
    return const UserProfile();
  }
}

/// 听歌历史上报（POST /playhistory/v1/upload_songs，query plat=3）。
/// 契约据 module/playhistory_upload.js：body {songs:[{mxid,op:1,ot:秒,pc:1}],token,userid}。
/// 写操作：一次提交、失败不重试（防重复上报）。
Future<bool> uploadPlayHistory(
    KugouClient client, List<int> mixSongIds) async {
  try {
    if (mixSongIds.isEmpty) {
      Log.w(_tag, 'uploadPlayHistory empty ids, skip');
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final songs = <Map<String, Object?>>[
      for (final mxid in mixSongIds)
        <String, Object?>{'mxid': mxid, 'op': 1, 'ot': now, 'pc': 1}
    ];
    final res = await client.request(
      EndpointRegistry.playHistoryUpload,
      <String, Object?>{'plat': 3},
      body: <String, Object?>{
        'songs': songs,
        'token': client.session.token,
        'userid': client.session.userid,
      },
    );
    final ok = safeInt(res['status'], safeInt(res['error_code'], -1)) == 1 ||
        safeInt(res['error_code']) == 0;
    Log.d(_tag, 'uploadPlayHistory n=${mixSongIds.length} ok=$ok');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'uploadPlayHistory failed', e, st);
    return false;
  }
}

/// 高潮片段（GET /v1/audio_climax/audio，expendablekmrcdn.kugou.com）
/// → 片段 URL 或「起始-结束秒」描述串。
/// 据ENDPOINT_TRUTH.md 路径已修正，响应 data[] 取首项（start_time/end_time/url
/// 容错），空 data 返回 null；完整参数契约仍待三态实测。
Future<String?> getSongClimax(KugouClient client, String hash) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'getSongClimax empty hash, skip');
      return null;
    }
    final res = await client.request(EndpointRegistry.songClimax,
        <String, Object?>{'hash': h, 'album_audio_id': 0});
    final data = res['data'];
    if (data is! List || data.isEmpty) {
      Log.d(_tag, 'getSongClimax empty data hash=$h');
      return null;
    }
    final first = data.first;
    if (first is! Map<String, dynamic>) {
      Log.w(_tag, 'getSongClimax unexpected item shape hash=$h');
      return null;
    }
    final url = safeStr(first['url'] ?? '');
    if (url.isNotEmpty) return url;
    final start = safeStr(first['start_time'] ?? first['starttime'] ?? '');
    final end = safeStr(first['end_time'] ?? first['endtime'] ?? '');
    if (start.isNotEmpty && end.isNotEmpty) return '$start-$end';
    Log.d(_tag, 'getSongClimax no climax fields hash=$h');
    return null;
  } catch (e, st) {
    Log.e(_tag, 'getSongClimax failed hash=$hash', e, st);
    return null;
  }
}

/// 用户云盘歌曲列表（POST /v1/get_list，mcloudservice.kugou.com）
/// → List<SongBrief>。
/// 据ENDPOINT_TRUTH.md 路径已修正；data.list[]/data.info[] 容错映射
/// SongBrief.fromTrackInfo，data 空串/20010 返回空列表；完整加密参数契约
/// （p/key/AES body）仍待三态实测。
Future<List<SongBrief>> getUserCloud(KugouClient client) async {
  try {
    if (client.session.token.isEmpty) {
      Log.w(_tag, 'getUserCloud no token, skip');
      return const <SongBrief>[];
    }
    final res = await client.request(EndpointRegistry.userCloud,
        <String, Object?>{'page': 1, 'pagesize': 30});
    final code = res['status'];
    final data = res['data'];
    if (data == null || data is String || code == 20010) {
      Log.w(_tag, 'getUserCloud empty/error response status=$code');
      return const <SongBrief>[];
    }
    final list = data is Map<String, dynamic>
        ? (data['list'] ?? data['info'])
        : data;
    if (list is! List) {
      Log.w(_tag, 'getUserCloud unexpected data shape status=$code');
      return const <SongBrief>[];
    }
    final out = <SongBrief>[];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        try {
          out.add(SongBrief.fromTrackInfo(item));
        } catch (e, st) {
          Log.e(_tag, 'getUserCloud item map failed', e, st);
        }
      }
    }
    return out;
  } catch (e, st) {
    Log.e(_tag, 'getUserCloud failed', e, st);
    return const <SongBrief>[];
  }
}

/// 单曲试听上报（POST /v2/get_list listenservice）。
/// ⚠️ 据ENDPOINT_TRUTH.md 路径已修正，body 参数（t_userid/userid/list_type/p）
/// 参数契约待三态实测，暂不发请求，恒返回 false（语义空值）。
Future<bool> reportListen(KugouClient client, String hash) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'reportListen empty hash, skip');
      return false;
    }
    // 真实契约（ENDPOINT_TRUTH.md §1）：listenservice /v2/get_list 是获取收听列表，
    // body 含 RSA p({clienttime,token}) 大写；hash 仅作留痕，不臆造上报字段。
    final ct = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pk = RsaRaw.encryptHex(
        '{"clienttime":$ct,"token":"${client.session.token}"}').toUpperCase();
    final res = await client.request(
      EndpointRegistry.listenReport,
      <String, Object?>{'clienttime': ct, 'plat': 0},
      body: <String, Object?>{
        't_userid': client.session.userid,
        'userid': client.session.userid,
        'list_type': 0,
        'area_code': 1,
        'cover': 2,
        'p': pk,
        'hash': h,
      },
    );
    final ok = safeInt(res['status'], -1) == 1 ||
        safeInt(res['error_code'], -1) == 0;
    Log.d(_tag, 'reportListen hash=$h ok=$ok');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'reportListen failed hash=$hash', e, st);
    return false;
  }
}
