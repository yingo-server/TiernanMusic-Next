// L4 core/net/endpoints · 用户域/上报端点封装（批6-A）
// 范围：userDetail / uploadPlayHistory / getSongClimax / getUserCloud / reportListen。
// ⚠️ 五端点全部「需三态实测，未实测不猜参数」：docs/PARITY_NOTES.md §4 未留样，
//    故所有封装在探针确认前 **不发请求**，返回语义空值 + Log.w('needs probe')。
//    实测后：只改本文件与 kugou_client.dart 声明，不动 request 实现。
// 铁律：字段容错 safe* + try/catch + Log('ep.user')；dfid/mid/uuid 由
//    KugouClient.request 默认参数恒显式携带并参与签名。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
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

/// 用户详情（POST /v3/get_my_info）→ UserProfile。
/// ⚠️ needs probe：未实测不发请求，返回语义空值。
Future<UserProfile> getUserDetail(KugouClient client) async {
  try {
    Log.w(_tag, 'getUserDetail needs probe (user_detail)'); // needs probe
    if (client.session.token.isEmpty) {
      Log.w(_tag, 'getUserDetail no token, skip');
      return const UserProfile();
    }
    // 探针确认参数契约前不发请求（未实测不猜参数）。
    return const UserProfile();
  } catch (e, st) {
    Log.e(_tag, 'getUserDetail failed', e, st);
    return const UserProfile();
  }
}

/// 听歌历史上报批量（POST /playhistory/v1/upload_songs）。
/// ⚠️ needs probe：未实测不发请求，恒返回 false（语义空值）。
Future<bool> uploadPlayHistory(
    KugouClient client, List<int> mixSongIds) async {
  try {
    if (mixSongIds.isEmpty) {
      Log.w(_tag, 'uploadPlayHistory empty ids, skip');
      return false;
    }
    Log.w(_tag,
        'uploadPlayHistory needs probe (play_history_upload) n=${mixSongIds.length}'); // needs probe
    // 探针确认 body 形态（songs 数组结构/时间戳字段）前不发请求。
    return false;
  } catch (e, st) {
    Log.e(_tag, 'uploadPlayHistory failed', e, st);
    return false;
  }
}

/// 高潮片段（GET /v1/song_climax）→ 片段 URL 或「起始-结束秒」描述串。
/// ⚠️ needs probe：未实测不发请求，返回 null（语义空值）。
Future<String?> getSongClimax(KugouClient client, String hash) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'getSongClimax empty hash, skip');
      return null;
    }
    Log.w(_tag, 'getSongClimax needs probe (song_climax) hash=$h'); // needs probe
    // 探针确认响应字段（url / starttime-endtime）前不发请求。
    return null;
  } catch (e, st) {
    Log.e(_tag, 'getSongClimax failed hash=$hash', e, st);
    return null;
  }
}

/// 用户云盘歌曲列表（POST /v1/user_cloud）→ List<SongBrief>。
/// ⚠️ needs probe：未实测不发请求，返回空列表（语义空值）。
Future<List<SongBrief>> getUserCloud(KugouClient client) async {
  try {
    Log.w(_tag, 'getUserCloud needs probe (user_cloud)'); // needs probe
    if (client.session.token.isEmpty) {
      Log.w(_tag, 'getUserCloud no token, skip');
      return const <SongBrief>[];
    }
    // 探针确认分页/响应字段（data.info[] 形态）前不发请求。
    return const <SongBrief>[];
  } catch (e, st) {
    Log.e(_tag, 'getUserCloud failed', e, st);
    return const <SongBrief>[];
  }
}

/// 单曲试听上报（POST /v1/user_listen_report）。
/// ⚠️ needs probe：未实测不发请求，恒返回 false（语义空值）。
Future<bool> reportListen(KugouClient client, String hash) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'reportListen empty hash, skip');
      return false;
    }
    Log.w(_tag, 'reportListen needs probe (user_listen_report) hash=$h'); // needs probe
    // 探针确认 body 参数（hash/mixsongid/时长）前不发请求。
    return false;
  } catch (e, st) {
    Log.e(_tag, 'reportListen failed hash=$hash', e, st);
    return false;
  }
}
