// L4 core/net/endpoints · 匿名播放域（批3-F1：设备注册 + 匿名试听 URL）。
// 从 mv_endpoints.dart 拆出（≤500 行门禁）；证据见 batch3_c3.md。
// - anonymousSongUrl（⚠️ 待实测）：GET /v5/url @ trackercdn，notSign
//   （signType none）、encryptKey、匿名随机 dfid、IsFreePart 试听
//   （song_url.js L32/49-52，batch3_c3.md §1）——见 anonymousPlayUrl。
// - registerDevice（⚠️ 待实测）：POST /risk/v2/r_register_dev 取真实 dfid
//   （register_dev.js，batch3_c3.md §4）——见 registerDevice。
// 铁律：全字段容错，每函数 try/catch + Log('ep.mv.anon')。
// - anonymousSongUrl（批3-F1 新增，⚠️ 待实测）：GET /v5/url @ trackercdn，
//   notSign（signType none）、encryptKey、匿名随机 dfid、IsFreePart 试听
//   （song_url.js L32/49-52，batch3_c3.md §1）——见 anonymousPlayUrl。
// - registerDevice（批3-F1 新增，⚠️ 待实测）：POST /risk/v2/r_register_dev
//   取真实 dfid（register_dev.js，batch3_c3.md §4）——见 registerDevice。
// - videoDetail: POST /v1/video，x-router kmr.service.kugou.com；响应
//   data[0] 平铺清晰度档位（ld/sd/hd/fhd/qhd 各配 hash/filesize/bitrate/
//   width/height + *_265 + mkv_*）。⚠️ 实测签名形态：clearDefaultParams +
//   body 全参数（含 key=signParamsKey）——见 getVideoQualities 注释与
//   EndpointRegistry.videoDetail 声明。备用 /kmr/v2/videos 已弃用（三态
//   实测 404，批3-F1 删除 fallback）。
// - videoUrl: GET /v2/interface/index，x-router trackermv.kugou.com，
//   参数 backupdomain=1/cmd=123/ext=mp4/ismp3=0/hash/pid=1/type=1，
//   ⚠️ 必带 key=md5(hash+57ae12eb…+appid+mid+userid||0)（signKey），否则
//   errcode 40003 "Empty key"（批N2-B 实测）；返回 data[hash].downurl(字符串)
//   + backupdownurl(数组)。
import 'dart:convert';

import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import '../crypto_rsa.dart'
    show rsaEncrypt2, playlistAesEncrypt, playlistAesDecrypt;
import '../signing.dart' show KugouSign, md5Hex;
import 'models.dart' show safeInt, safeStr, dataOf, listOf;
import 'cover_url.dart' show normalizeCoverUrl;

const String _tag = 'ep.mv.anon';

List<String> _collectUrls(Object? v) {
  try {
    if (v is List) {
      return v.map((u) => safeStr(u)).where((u) => u.isNotEmpty).toList();
    }
    final s = v is String ? v : '';
    if (s.contains(',')) {
      return s
          .split(',')
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
    }
    return s.isEmpty ? const <String>[] : <String>[s];
  } catch (e, st) {
    Log.e(_tag, '_collectUrls failed', e, st);
    return const <String>[];
  }
}

Future<String> registerDevice(KugouClient client) async {
  try {
    // dataMap 默认值对齐 register_dev.js L13-96（节选，完整 30+ 字段待实测；
    // imei/uuid/serialnum/suuid=cookie KUGOU_API_GUID，以匿名随机 dfid 兼作）。
    final guid = client.session.dfid;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dataMap = <String, Object?>{
      'brand': 'Redmi',
      'device': 'marble',
      'model': 'marble',
      'device_manufacturer': 'Xiaomi',
      'manufacturer': 'Xiaomi',
      'osversion': '13',
      'pkg': 'com.kugou.android',
      'version': 11430,
      'mobiletype': 1,
      'networktype': 1,
      'wifi': 1,
      'fversion': 2200,
      'language': 'zh-CN',
      'country': 'CN',
      'countrycode': 'CN',
      'canonicalcountrycode': 'CN',
      'carrier': 'China Mobile',
      'screenheight': 2400,
      'screenwidth': 1080,
      'sdkver': '30',
      'totalmemory': 7858096128,
      'useablememory': 2684354560,
      'voltagemv': 4300,
      'rtime': now,
      'userid': 0,
      'isjailbroken': 0,
      'imei': guid,
      'uuid': guid,
      'suuid': guid,
      'serialnum': guid,
      'oaid': '',
    };
    final aes = playlistAesEncrypt(dataMap);
    final p = rsaEncrypt2(
      jsonEncode(<String, Object?>{'aes': aes.key, 'uid': '0', 'token': ''}),
    );
    final res = await client.request(
      EndpointRegistry.registerDevice,
      <String, Object?>{
        'part': 1,
        'platid': 2, // ⚠️ platid 2 vs 上游明示 1 —— 待实测定稿
        'p': p,
      },
      rawBody: aes.cipherBase64,
    );
    // 响应：arraybuffer AES 密文（_raw_text 回退）或网关直接回 JSON。
    Map<String, dynamic> body;
    final rawText = '${res['_raw_text'] ?? ''}';
    if (rawText.isNotEmpty) {
      final text = playlistAesDecrypt(rawText, aes.key);
      final dec = jsonDecode(text);
      body = dec is Map<String, dynamic> ? dec : <String, dynamic>{};
    } else {
      body = res;
    }
    final status = safeInt(body['status']);
    final data = dataOf(body);
    final dfid = safeStr(data['dfid'] ?? body['dfid']);
    if (status == 1 && dfid.isNotEmpty) {
      // 上游 L119-122：data.dfid 写 cookie；此处等价回写 session.dfid。
      client.session.dfid = dfid;
      Log.d(_tag, 'registerDevice ok dfid=<$dfid>');
      return dfid;
    }
    Log.w(_tag, 'registerDevice not ok status=$status (待实测)');
    return '';
  } catch (e, st) {
    Log.e(_tag, 'registerDevice failed (待实测)', e, st);
    return '';
  }
}

/// anonymousPlayUrl（批3-F1 新增封装，⚠️ 待实测）：匿名歌曲试听地址
/// （GET /v5/url @ trackercdn，batch3_c3.md §1 song_url.js）。L51 notSign
/// （endpoint signType=none）；L50 encryptKey → key 照注入；L52 匿名
/// dfid=randomString(24)（session.dfid 首访即随机 24 位，直接复用）；
/// L32 IsFreePart=1 恒传（试听语义，匿名可拿 128 试听）；quality 默认 128。
/// 匿名风险：field_truth_test L403-408 实测匿名 20028 fail_process:['pkg']
/// ——失败时 status!=1 且 urls 空，调用方按试听不可用降级。
/// 返回 ParsedPlayUrlShim（L4 侧同构镜像，不 import L5；跨层只经六桥）。
Future<ParsedPlayUrlShim> anonymousPlayUrl(
  KugouClient client,
  String hash, {
  String quality = '128',
}) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'anonymousPlayUrl empty hash');
      return const ParsedPlayUrlShim();
    }
    final res = await client.request(
      EndpointRegistry.anonymousSongUrl,
      <String, Object?>{
        'hash': h,
        'quality': quality,
        'album_audio_id': 0,
        'album_id': 0,
        'area_code': 1,
        'behavior': 'play',
        'cmd': 26,
        'pid': 2,
        'pidversion': 3001,
        'IsFreePart': 1, // song_url.js L32：试听片段开关（待实测）
        'cdnBackup': 1,
      },
    );
    // 顶层即数据（song_url.js 匿名路径与登录态同契约，§A3-1；待实测）。
    final urls = _collectUrls(res['url']);
    final backups = _collectUrls(res['backupUrl']);
    var mp = 0;
    final tt = res['tracker_through'];
    if (tt is Map) mp = safeInt(tt['musicpack_advance']);
    final fp = res['IsFreePart'];
    final parsed = ParsedPlayUrlShim(
      status: safeInt(res['status']),
      privStatus: safeInt(res['priv_status']),
      urls: urls,
      backupUrls: backups,
      bitRate: safeInt(res['bitRate']),
      extName: res['extName'] is String ? res['extName'] as String : '',
      musicpackAdvance: mp,
      isFreePart: safeInt(fp) == 1 || '$fp'.toLowerCase() == 'true',
      endByte: safeInt(res['end_byte']),
      timeLengthSec: safeInt(res['timeLength']),
      traceId: res['traceId'] is String ? res['traceId'] as String : '',
    );
    Log.d(
      _tag,
      'anonymousPlayUrl hash=$h status=${parsed.status} '
      'urls=${parsed.urls.length} freePart=${parsed.isFreePart} (待实测)',
    );
    return parsed;
  } catch (e, st) {
    Log.e(_tag, 'anonymousPlayUrl failed hash=$hash (待实测)', e, st);
    return const ParsedPlayUrlShim();
  }
}

/// ParsedPlayUrl 同构镜像（L4 侧，与 logic/player/play_source_parser
/// .ParsedPlayUrl 字段一一对应）。⚠️ 待实测。
class ParsedPlayUrlShim {
  final int status, privStatus, bitRate, musicpackAdvance;
  final int endByte, timeLengthSec;
  final List<String> urls, backupUrls;
  final String extName, traceId;
  final bool isFreePart;

  const ParsedPlayUrlShim({
    this.status = 0,
    this.privStatus = 0,
    this.urls = const <String>[],
    this.backupUrls = const <String>[],
    this.bitRate = 0,
    this.extName = '',
    this.musicpackAdvance = 0,
    this.isFreePart = false,
    this.endByte = 0,
    this.timeLengthSec = 0,
    this.traceId = '',
  });

  bool get isPlayable => status == 1 && urls.isNotEmpty;
}
