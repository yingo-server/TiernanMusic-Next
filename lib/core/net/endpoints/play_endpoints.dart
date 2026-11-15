// L4 core/net/endpoints · 播放/权益端点封装（play_url v5 / privilege_lite）
// FINDINGS.md 实测：
// - /v5/url 成功时响应顶层即数据（url/backupUrl/bitRate/extName/timeLength/status/priv_status），
//   无 data 包层；err 时顶层 status/error/errcode（20028=需验证）。
// - key 签名已由 KugouClient.encryptKey 处理（endpoint encryptKey:true）。
// - 权限判定以 play_url 的 priv_status/status 为准；privilege_lite 的 privilege 是 int 标量。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import '../signing.dart' show KugouSign;
import 'models.dart';

const String _tag = 'ep.play';

/// 批1-F3：hash_offset / end_byte / fail_process 已真正落 PlayResult 公开字段
///（见 play_models.dart）。Expando 侧挂 + PlayResultExtras 扩展整体退役：
/// 公开实例字段天然可被 L5（playback_service，批3范围）直接读取，
/// `result.hashOffset` / endByte / failProcess 读点零改动。

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
      'piano',
      'acappella',
      'subwoofer',
      'ancient',
      'dj',
      'surnay',
    }.contains(q);
    final res = await client.request(
      EndpointRegistry.playUrlV5,
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
      },
    );
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
          rawBackup.map((u) => safeStr(u)).where((u) => u.isNotEmpty),
        );
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
    // ── 批1-F3：22 顶层键补齐（真正落 PlayResult 公开字段，L5 可读）──
    // ① hash_offset / end_byte / fail_process（试听分片 / 断点 / 风控诊断）。
    int? hashOffset;
    int? endByte;
    int? failProcess;
    try {
      if (res['hash_offset'] != null) hashOffset = safeInt(res['hash_offset']);
      if (res['end_byte'] != null) endByte = safeInt(res['end_byte']);
      if (res['fail_process'] != null) {
        failProcess = safeInt(res['fail_process']);
      }
    } catch (e, st) {
      Log.e(_tag, 'parse hash_offset/end_byte/fail_process failed', e, st);
    }
    // ② 响应 q：服务端实际回档。quality 回填优先用响应 q，缺省才用请求档，
    //    避免服务端降档被请求档掩盖（C1 §F3 结论 1）。
    var respQ = '';
    try {
      final qv = res['q'];
      if (qv is num) {
        respQ = '$qv';
      } else if (qv is String && qv.trim().isNotEmpty) {
        respQ = qv.trim();
      }
    } catch (e, st) {
      Log.e(_tag, 'parse q failed', e, st);
    }
    // ③ fileSize / volume / classmap / fileName / fileHead / std_hash /
    //    hash_token / trans_param.qualitymap / auth_through[] 容错读取。
    //    safe* 风格：任何形态异常只落 Log.e，绝不抛到外层丢整包结果。
    var fSize = 0;
    var vol = 0.0;
    final cmap = <String, String>{};
    final transMap = <String, String>{};
    final authList = <String>[];
    var fileName = '';
    var fileHead = '';
    var stdH = '';
    var hTok = '';
    try {
      fSize = safeInt(res['fileSize'] ?? res['filesize']);
    } catch (e, st) {
      Log.e(_tag, 'parse fileSize failed', e, st);
    }
    try {
      final vv = res['volume'];
      if (vv is num) {
        vol = vv.toDouble();
      } else if (vv is String && vv.trim().isNotEmpty) {
        vol = double.tryParse(vv.trim()) ?? 0.0;
      }
    } catch (e, st) {
      Log.e(_tag, 'parse volume failed', e, st);
    }
    try {
      void flat(Object? src, Map<String, String> dst) {
        if (src is! Map) return;
        src.forEach((k, v) {
          final key = safeStr(k);
          if (key.isEmpty) return;
          dst[key] = v is Map || v is List ? '$v' : safeStr(v);
        });
      }

      final cm = res['classmap'];
      if (cm is List) {
        for (final item in cm) {
          flat(item, cmap);
        }
      } else {
        flat(cm, cmap);
      }
      // trans_param 常含 qualitymap 子 map；同样扁平化，避免丢档位映射。
      final tp = res['trans_param'] ?? res['transParam'];
      flat(tp, transMap);
      if (tp is Map && tp['qualitymap'] is Map) {
        flat(tp['qualitymap'], transMap);
      }
    } catch (e, st) {
      Log.e(_tag, 'parse classmap/trans_param failed', e, st);
    }
    try {
      final at = res['auth_through'] ?? res['authThrough'];
      if (at is List) {
        for (final v in at) {
          final sv = v is Map || v is List ? '$v' : safeStr(v);
          if (sv.isNotEmpty) authList.add(sv);
        }
      } else if (at != null) {
        final sv = at is Map ? '$at' : safeStr(at);
        if (sv.isNotEmpty) authList.add(sv);
      }
    } catch (e, st) {
      Log.e(_tag, 'parse auth_through failed', e, st);
    }
    try {
      fileName = safeStr(res['fileName'] ?? res['filename']);
      fileHead = safeStr(res['fileHead'] ?? res['filehead']);
      stdH = safeStr(res['std_hash'] ?? res['stdHash']);
      hTok = safeStr(res['hash_token'] ?? res['hashToken']);
    } catch (e, st) {
      Log.e(_tag, 'parse fileName/fileHead/std_hash/hash_token failed', e, st);
    }
    // ④ 通用顶层键兜底：只留键名（脱敏）+ 已知 camelCase/下划线变体标量，
    //    防止 q/fileSize/volume 等换壳后再次静默丢弃（仍严格 try/catch+Log）。
    final topKeys = <String>[];
    final variants = <String, String>{};
    try {
      for (final k in res.keys) {
        final sk = safeStr(k);
        if (sk.isNotEmpty) topKeys.add(sk);
      }
      for (final alias in const <String>[
        'file_size',
        'vol',
        'volume_gain',
        'q',
        'bit_rate',
        'time_length',
      ]) {
        final vv = res[alias];
        if (vv != null && vv is! Map && vv is! List) {
          variants[alias] = '$vv';
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'parse topLevelKeys/variants failed', e, st);
    }
    // quality 优先按响应 q 回填；响应未带 q 才回退请求档（服务端降档可感知）。
    final effectiveQuality = respQ.isNotEmpty ? respQ : q;
    final result = PlayResult(
      status: status,
      privStatus: priv,
      // docs/API_FIELDS_TRUTH.md §A3-1（批N2-A）：非 VIP 带 key 的失败形态
      // 顶层是 error_code=35104（Hash not found），旧写法只取 errcode → 丢码。
      errcode: safeInt(res['errcode'] ?? res['error_code']),
      error: safeStr(res['error']),
      urls: urls,
      backupUrls: backups,
      bitrate: safeInt(res['bitRate']),
      extName: safeStr(res['extName']),
      timeLengthSec: safeInt(res['timeLength']),
      isVipTrack: vipTrack,
      isFreePart: isFreePart,
      hash: h,
      // priv_status 缺失（匿名/错误响应）不得被 safeInt 折叠成 0 → 误判无权限。
      privKnown: res.containsKey('priv_status') && res['priv_status'] != null,
      // 批1-F3 新增公开字段：全部带默认值，不破坏既有构造调用。
      hashOffset: hashOffset,
      endByte: endByte,
      failProcess: failProcess,
      responseQuality: effectiveQuality,
      fileSizeBytes: fSize,
      volume: vol,
      classMap: Map<String, String>.unmodifiable(cmap),
      transParam: Map<String, String>.unmodifiable(transMap),
      authThrough: List<String>.unmodifiable(authList),
      fileName: fileName,
      fileHead: fileHead,
      stdHash: stdH,
      hashToken: hTok,
      topLevelKeys: List<String>.unmodifiable(topKeys),
      variantFields: Map<String, String>.unmodifiable(variants),
    );
    Log.d(
      _tag,
      'getPlayUrlV5 hash=$h q=$q respQ=$respQ effectiveQ=$effectiveQuality '
      'status=$status priv=$priv urls=${urls.length} '
      'backups=${backups.length} bitRate=${result.bitrate} '
      'ext=${result.extName} len=${result.timeLengthSec} '
      'fileSize=${result.fileSizeBytes} volume=${result.volume} '
      'classmap=${cmap.length} transParam=${transMap.length} '
      'authThrough=${authList.length} '
      'hashOffset=${result.hashOffset} endByte=${result.endByte} '
      'failProcess=${result.failProcess}',
    );
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
    final res = await client.request(
      EndpointRegistry.privilegeLite,
      <String, Object?>{
        'appid': KugouSign.appid,
        'clientver': KugouSign.clientver,
        'area_code': 1,
        'behavior': 'play',
        'need_hash_offset': 1,
        'relate': 1,
        'support_verify': 1,
      },
      body: <String, Object?>{
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
      },
    );
    final data = dataOf(res);
    final out = listOf(data['data'])
        .map(parsePrivilegeItem)
        .toList(growable: false);
    Log.d(_tag, 'getPrivilegeLite n=${clean.length} got=${out.length}');
    return out;
  } catch (e, st) {
    Log.e(_tag, 'getPrivilegeLite failed hashes=${hashes.length}', e, st);
    return const <PrivilegeItem>[];
  }
}
