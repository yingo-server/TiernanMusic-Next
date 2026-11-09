// L4 core/net/endpoints · 播放/权益端点封装（play_url v5 / privilege_lite）
// FINDINGS.md 实测：
// - /v5/url 成功时响应顶层即数据（url/backupUrl/bitRate/extName/timeLength/status/priv_status），
//   无 data 包层；err 时顶层 status/error/errcode（20028=需验证）。
// - key 签名已由 KugouClient.encryptKey 处理（endpoint encryptKey:true）。
// - 权限判定以 play_url 的 priv_status/status 为准；privilege_lite 的 privilege 是 int 标量。
import '../../../kernel/kernel.dart' show Log;
import '../kugou_client.dart';
import '../signing.dart' show KugouSign;
import 'models.dart';

const String _tag = 'ep.play';

/// 容错解析单条 privilege：privilege 字段是 int 标量（FINDINGS.md §10），
/// 兼容数组形态但不依赖；hash 小写化。
PrivilegeItem parsePrivilegeItem(Map<String, dynamic> item) {
  try {
    var priv = 0;
    final pv = item['privilege'];
    if (pv is int) {
      priv = pv;
    } else if (pv is List && pv.isNotEmpty) {
      priv = safeInt((pv as List).first);
    } else {
      priv = safeInt(pv);
    }
    return PrivilegeItem(
      hash: safeStr(item['hash']).toLowerCase(),
      privilege: priv,
      status: safeInt(item['status']),
    );
  } catch (e, st) {
    Log.e(_tag, 'parsePrivilegeItem failed', e, st);
    return const PrivilegeItem();
  }
}

/// play_url v5：按 hash 单音质取播放地址。
/// quality ∈ 128/320/flac/high 或魔法音质（piano/acappella/subwoofer/ancient/dj/surnay）。
/// isFreePart=true 传 IsFreePart=1（试听；实测 VIP 曲非 VIP 号仍可能回全长，以返回为准）。
Future<PlayResult> getPlayUrlV5(
  KugouClient client,
  String hash,
  String quality, {
  bool isFreePart = false,
}) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'getPlayUrlV5 empty hash');
      return const PlayResult();
    }
    final q = quality.trim().isEmpty ? '128' : quality.trim();
    final magic = const {
      'piano', 'acappella', 'subwoofer', 'ancient', 'dj', 'surnay',
    }.contains(q);
    final res = await client.request(EndpointRegistry.playUrlV5,
        <String, Object?>{
      'hash': h,
      'quality': magic ? '128' : q,
      if (magic) 'magic_$q': 1,
      'album_audio_id': 0,
      'album_id': 0,
      'area_code': 1,
      'behavior': 'play',
      'ssa_flag': 'is_fromtrack',
      'version': 11430,
      'clientver': 11430,
      'page_id': 151369488,
      'ppage_id': '463467626,350369493,788954147',
      'pid': 2,
      'cmd': 26,
      'pidversion': 3001,
      'IsFreePart': isFreePart ? 1 : 0,
      'cdnBackup': 1,
    });
    // 顶层即数据（无 data 包层）；err 时同层有 status/error/errcode。
    final urls = <String>[];
    final rawUrls = res['url'];
    try {
      if (rawUrls is List) {
        urls.addAll(rawUrls.map((u) => safeStr(u)).where((u) => u.isNotEmpty));
      } else if (rawUrls is String && rawUrls.isNotEmpty) {
        urls.add(rawUrls);
      }
    } catch (e, st) {
      Log.e(_tag, 'parse urls failed', e, st);
    }
    final backups = <String>[];
    final rawBackup = res['backupUrl'];
    try {
      if (rawBackup is List) {
        backups.addAll(
            rawBackup.map((u) => safeStr(u)).where((u) => u.isNotEmpty));
      } else if (rawBackup is String && rawBackup.isNotEmpty) {
        backups.add(rawBackup);
      }
    } catch (e, st) {
      Log.e(_tag, 'parse backupUrls failed', e, st);
    }
    // tracker_through.musicpack_advance（顶层嵌套 map）→ VIP 曲判定。
    var vipTrack = false;
    try {
      final tt = res['tracker_through'];
      if (tt is Map) {
        final ttv = tt['musicpack_advance'];
        vipTrack = safeBool(ttv);
      }
    } catch (e, st) {
      Log.e(_tag, 'parse tracker_through failed', e, st);
    }
    final status = safeInt(res['status']);
    final priv = safeInt(res['priv_status']);
    final result = PlayResult(
      status: status,
      privStatus: priv,
      errcode: safeInt(res['errcode']),
      error: safeStr(res['error']),
      urls: urls,
      backupUrls: backups,
      bitrate: safeInt(res['bitRate']),
      extName: safeStr(res['extName']),
      timeLengthSec: safeInt(res['timeLength']),
      isVipTrack: vipTrack,
      isFreePart: isFreePart,
      hash: h,
    );
    Log.d(_tag,
        'getPlayUrlV5 hash=$h q=$q status=$status priv=$priv urls=${urls.length}');
    return result;
  } catch (e, st) {
    Log.e(_tag, 'getPlayUrlV5 failed hash=$hash quality=$quality', e, st);
    return PlayResult(errcode: -1, error: '$e', hash: hash);
  }
}

/// 权益批量（/v2/get_res_privilege/lite）：按 hash 批量查询。
/// 注意 FINDINGS.md §10：body 必须带 appid/clientver；结果 privilege 为 int 标量；
/// 权限判定不要依赖本接口，仅作元数据/离线预取参考。
Future<List<PrivilegeItem>> getPrivilegeLite(
  KugouClient client,
  List<String> hashes,
) async {
  try {
    final clean = hashes
        .map((h) => h.trim().toLowerCase())
        .where((h) => h.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (clean.isEmpty) return const <PrivilegeItem>[];
    final res = await client.request(EndpointRegistry.privilegeLite,
        <String, Object?>{
      'appid': KugouSign.appid,
      'clientver': KugouSign.clientver,
      'area_code': 1,
      'behavior': 'play',
      'need_hash_offset': 1,
      'relate': 1,
      'support_verify': 1,
    }, body: <String, Object?>{
      'resource': [
        for (final h in clean)
          <String, Object?>{
            'type': 'audio',
            'hash': h,
            'album_id': '',
            'page_id': 0,
          },
      ],
      'qualities': const ['128', '320', 'flac', 'high'],
      'appid': KugouSign.appid,
      'clientver': KugouSign.clientver,
      'area_code': 1,
      'behavior': 'play',
    });
    final data = dataOf(res);
    final out = listOf(data['data']).map(parsePrivilegeItem).toList(growable: false);
    Log.d(_tag, 'getPrivilegeLite n=${clean.length} got=${out.length}');
    return out;
  } catch (e, st) {
    Log.e(_tag, 'getPrivilegeLite failed hashes=${hashes.length}', e, st);
    return const <PrivilegeItem>[];
  }
}
