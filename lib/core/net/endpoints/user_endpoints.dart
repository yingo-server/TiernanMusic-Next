// L4 core/net/endpoints · 用户域/上报端点封装（批6-A）
// 端点路径据 docs/ENDPOINT_TRUTH.md 修正（真实 URL/x-router 见 kugou_client.dart 声明）。
// 实测状态（API_FIELDS_TRUTH.md §R1-A，2026-11-13 三态复测；批07-B 成功语义复核）：
//   getUserDetail §R1-A-1：p=cryptoRSAEncrypt({token,clienttime}) 裸 RSA 右补零 →
//     匿名 error_code=20018 / 登录态顶层 status=1 error_code=0；
//     **data 顶层即档案字段、无 {data:{…}} 包裹**（nickname/pic/vip_type/…）。
//   uploadPlayHistory §R1-A-2：body {songs:[{mxid,op:1,ot,pc:1}],token,userid} →
//     匿名 20010 / 登录态 status=1 error_code=0，data.songs[].code=1；
//     顶层 status==1 判定经实测正确（成功码在顶层，非 data.status）。
//   reportListen §R1-A-3（listenservice/v2/get_list）：p 裸 RSA 右补零 →
//     匿名 20010 / 登录态顶层 status=1；data 仅 lists[]/data_date/…，
//     **data 内无 status 字段**，成功码在顶层（非 data.status 层级）。
//   getSongClimax / getUserCloud：§R1-A 明示完整契约仍待实测、API_FIELDS_TRUTH
//     无对应实测章节，按「不猜成功码/参数」容错返回空值。
// 铁律：字段容错 safe* + try/catch + Log('ep.user')；dfid/mid/uuid 由
//    KugouClient.request 默认参数恒显式携带并参与签名。
import 'dart:convert';
import 'dart:typed_data';

import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import '../crypto_extra.dart'
    show BigIntL, CryptoException, RsaRaw, kKugouRsaPemBase64;
import 'models.dart';

/// cryptoRSAEncrypt 等价（批R1-A 实测 2026-11-13）：上游 util/crypto.js
/// cryptoRSAEncrypt 是 **裸 RSA（no padding）+ 明文置于 128 字节缓冲区头部，
/// 尾部补零**（padded.set(buffer)），非 PKCS1 v1.5、非左侧补零。
/// RsaRaw.encryptHex 是左侧补零，实测 20006；必须右侧补零。
/// 公钥/密文同 RsaRaw（1024 位，e=65537），输出大写 hex。
String rsaCryptoEncrypt(String plaintext) {
  try {
    final modHex = RsaRaw.modulusHexFromPem(kKugouRsaPemBase64);
    final n = BigIntL.fromHex(modHex);
    final plain = utf8.encode(plaintext);
    if (plain.length > 128) throw CryptoException('rsa plaintext too long');
    // 明文在前、零在后（cryptoRSAEncrypt：padded.set(buffer)）。
    final mBytes = Uint8List(128);
    mBytes.setRange(0, plain.length, plain);
    final l = <int>[];
    for (var i = 128; i > 0; i -= 4) {
      l.add((mBytes[i - 4] << 24) |
          (mBytes[i - 3] << 16) |
          (mBytes[i - 2] << 8) |
          mBytes[i - 1]);
    }
    final c = BigIntL(l).modPow(BigIntL([65537]), n);
    return c.toHex(padBytes: 128).toUpperCase();
  } catch (e, st) {
    Log.e(_tag, 'rsaCryptoEncrypt failed (plaintext not logged)', e, st);
    rethrow;
  }
}

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
        // API_FIELDS_TRUTH.md §R1-A-1：实测主键为 pic（次选 k_pic/fx_pic），
        // avatar/user_pic 仅作历史别名兜底；与「data 平铺」层级一致。
        avatar: safeStr(
            m['pic'] ?? m['k_pic'] ?? m['fx_pic'] ?? m['avatar'] ?? m['user_pic'] ?? ''),
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
/// 批07-B 成功语义/层级复核（API_FIELDS_TRUTH.md §R1-A-1 三态实测）：成功码在
/// **响应顶层** status=1 / error_code=0（匿名 error_code=20018）；
/// `data` 平铺档案字段（nickname/pic/vip_type/…），无 {data:{…}} 再包一层；
/// 响应内无 userid/level 字段（userid 客户端自持、level 取 0 安全）。
Future<UserProfile> getUserDetail(KugouClient client) async {
  try {
    if (client.session.token.isEmpty) {
      Log.w(_tag, 'getUserDetail no token, skip');
      return const UserProfile();
    }
    final ct = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 批R1-A 实测（2026-11-13）：p = cryptoRSAEncrypt({token,clienttime}) 大写
    // ——裸 RSA + 明文头部右补零（rsaCryptoEncrypt）；PKCS1/左补零均 20006。
    final pk = rsaCryptoEncrypt(
        '{"token":"${client.session.token}","clienttime":$ct}');
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
    // API_FIELDS_TRUTH.md §R1-A-1 实测：成功码在「响应顶层」
    // status=1 / error_code=0（匿名 error_code=20018）；profile 字段
    // 与响应根平铺（探针「顶层即 data，无包裹」），dataOf 作为
    // {data:{…}} 包层容错，二者按实测层级合并，不互相误判。
    if (safeInt(res['status'], -1) != 1 ||
        safeInt(res['error_code'], 0) != 0) {
      Log.w(_tag, 'getUserDetail not ok status=${res['status']} '
          'error_code=${res['error_code']}');
      return const UserProfile();
    }
    final d = dataOf(res);
    // 平铺为主（§R1-A-1），包层仅容错；显式 dynamic 泛型避免层级合并歧义。
    final Map<String, dynamic> profile =
        d.isEmpty ? res : <String, dynamic>{...res, ...d};
    final p = UserProfile.fromMap(profile);
    Log.d(_tag, 'getUserDetail uid=${p.userid} nick=${p.nickname}');
    return p;
  } catch (e, st) {
    Log.e(_tag, 'getUserDetail failed', e, st);
    return const UserProfile();
  }
}

/// 听歌历史上报（POST /playhistory/v1/upload_songs，query plat=3）。
/// 契约据 module/playhistory_upload.js：body {songs:[{mxid,op:1,ot:秒,pc:1}],token,userid}。
/// 批07-B 成功语义/层级复核（API_FIELDS_TRUTH.md §R1-A-2 三态实测）：成功码在
/// **响应顶层** status=1 / error_code=0（匿名 error_code=20010）；
/// `data.songs[].code=1` 只是逐曲回执，**data 内无 status 字段**，
/// 仅固化层级结论，成功判定式按实测显式拆开（语义不变）。
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
    // API_FIELDS_TRUTH.md §R1-A-2：成功码在「响应顶层」
    // (status==1 || error_code==0)；data.songs[].code=1 仅逐曲回执，
    // data 内无 status，绝不读 data.status。旧写法把 error_code 值
    // 作为 status 的 safeInt 缺省值，status 缺失时可能伪成功，此处
    // 按实测判定式显式拆开，语义不变、层级更清晰。
    final status = safeInt(res['status'], -1);
    final err = safeInt(res['error_code'], -1);
    final ok = status == 1 || err == 0;
    Log.d(_tag, 'uploadPlayHistory n=${mixSongIds.length} '
        'status=$status error_code=$err ok=$ok');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'uploadPlayHistory failed', e, st);
    return false;
  }
}

/// 高潮片段（GET /v1/audio_climax/audio，expendablekmrcdn.kugou.com）
/// → 片段 URL 或「起始-结束秒」描述串。
/// 据 ENDPOINT_TRUTH.md §1：响应 `body.data[*]`（顶层 data 为数组）。
/// 批07-B 语义复核：API_FIELDS_TRUTH.md **无本端点实测章节**（§R1-A 明示
/// 「完整契约仍待实测」），故不臆造 status=1 / data.status 成功码门槛，
/// 仅按实测文档记载的「顶层 data 数组」层级容错取首项，空 data 返回 null。
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
/// 批07-B 语义复核：API_FIELDS_TRUTH.md **无本端点实测章节**（§R1-A
/// 明示「完整契约仍待实测」），不臆造 status=1 / data.status 成功码门槛；
/// 现有 20010 + 空/字符串 data 短路保留（匿名失败形态的通用容错），
/// data 为 List 时直接当顶层列表，为 Map 时取 list/info 两形态。
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

/// 单曲收听列表获取（POST /v2/get_list，直连 listenservice.kugou.com）。
/// 批R1-A 三态实测（2026-11-13）：匿名 20010；登录态 status=1，data.lists[]/
/// data_date/servertime/total_history/total_week。body p 为裸 RSA
/// cryptoRSAEncrypt({clienttime,token}) 大写；t_userid/userid 字符串。
Future<bool> reportListen(KugouClient client, String hash) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'reportListen empty hash, skip');
      return false;
    }
    // 真实契约（ENDPOINT_TRUTH.md §1 + 批R1-A 实测）：listenservice /v2/get_list
    // body 含 p = cryptoRSAEncrypt({clienttime,token}) 大写（裸 RSA 右补零）；
    // t_userid/userid 为字符串；非 gateway，直连 listenservice.kugou.com。
    // hash 仅作留痕，不臆造上报字段。
    final ct = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pk = rsaCryptoEncrypt(
        '{"clienttime":$ct,"token":"${client.session.token}"}');
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
