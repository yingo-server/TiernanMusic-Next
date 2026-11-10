// L4 core/net/endpoints · 认证域端点封装（功能对齐批5-A · GAP #31）
// 出处：docs/KUGOU_API.md §3.8（login_cellphone.js 短信验证码登录）+ §2.1/§2.2
//   （AES 固定 key/iv + RSA 包 AES key）。
// ⚠️ 端点实测状态：
//   - smsLogin（/v7/login_by_verifycode）：路径/UA/docs 留样齐全，但**未三态实测**
//     （anon/nonvip/vip 或验证码链路无 FINDINGS 留样），参数结构不猜——
//     探针确认前 [sendSmsCode]/[smsLogin] 一律返回语义失败并 Log.w 标注 needs probe。
//   - sendSmsCode（发送验证码端点）：docs **无任何留样**（任务口径 /v1/send_verifycode
//     仅任务文本提及），路径/参数/签名/响应字段全部未知 → 恒 needs probe。
// 铁律：字段容错；每函数 try/catch + Log('ep.auth')；
//   dfid/mid/uuid 恒显式携带并参与签名；只连酷狗官方域名（loginserviceretry.kugou.com
//   为酷狗官方子域，出处 module/login_cellphone.js baseURL）。
import '../../../kernel/kernel.dart' show Log;
import 'dart:convert';
import '../kugou_client.dart';
import '../crypto_extra.dart';
import '../signing.dart' show KugouSign, Md5;

const String _tag = 'ep.auth';

/// 探针开关：三态实测通过后置 true 才放行真实网络调用。
/// 位置：本文件唯一开关，实测后翻转即可，不动 KugouClient.request。
const bool kAuthEndpointsProbed = false;

/// 短信登录结果（经 bridge_core 转出给 logic/surface）。
class SmsLoginResult {
  const SmsLoginResult({required this.ok, this.token = '', this.userid = '',
      this.error = '', this.needsProbe = false});
  final bool ok;
  final String token;
  final String userid;
  final String error;
  /// true 表示因端点未实测而语义失败（非网络/凭据错误）。
  final bool needsProbe;

  Map<String, Object?> toMap() => <String, Object?>{
        'ok': ok, 'token': token, 'userid': userid,
        'error': error, 'needsProbe': needsProbe,
      };

  @override
  String toString() {
    try {
      // token 不进日志：只打存在性与长度。
      return 'SmsLoginResult(ok=$ok uid=$userid tokenLen=${token.length} '
          'error=$error needsProbe=$needsProbe)';
    } catch (e, st) {
      Log.e(_tag, 'SmsLoginResult.toString failed', e, st);
      return 'SmsLoginResult(<unavailable>)';
    }
  }
}

/// AES 固定 key/iv（docs/KUGOU_API.md §2.1 login_token.js 普通版对；
/// 任务口径：短信登录沿用该对，实测后如有差异只改这里）。
const String kSmsAesKey = '90b8382a1bb4ccdcf063102053fd75b8';
const String kSmsAesIv = 'f063102053fd75b8';

/// 发送短信验证码。⚠️ 端点未实测（docs 零留样，任务口径 /v1/send_verifycode
/// 待探针）：不猜参数结构，恒返回 false 并 Log.w 标注 needs probe。
Future<bool> sendSmsCode(KugouClient client, String mobile) async {
  try {
    if (mobile.trim().isEmpty) {
      Log.w(_tag, 'sendSmsCode empty mobile');
      return false;
    }
    if (!kAuthEndpointsProbed) {
      Log.w(_tag,
          'sendSmsCode needs probe: send_verifycode 端点 docs 零留样'
          '（路径/参数/签名均未知），返回语义失败，不发网络请求');
      return false;
    }
    // 探针确认后在此接 EndpointRegistry.sendSmsCode 真实调用；
    // 当前不实现猜测分支（铁律：不猜参数结构）。
    Log.w(_tag, 'sendSmsCode probe branch not implemented');
    return false;
  } catch (e, st) {
    Log.e(_tag, 'sendSmsCode failed', e, st);
    return false;
  }
}

/// 短信验证码登录（login_by_verifycode，docs §3.8 login_cellphone.js）。
/// docs 留样：body `params` = AES(固定key) 加密 {mobile, code} hex、
/// `pk` = RSA({clienttime_ms, key}) 大写 hex、UA Android16-1070-11440-130-0-LOGIN-wifi。
/// ⚠️ 未三态实测：kAuthEndpointsProbed=false 时返回语义失败（needsProbe=true），
/// 不发网络请求、不猜参数结构。
Future<SmsLoginResult> smsLogin(
    KugouClient client, String mobile, String code) async {
  try {
    if (mobile.trim().isEmpty || code.trim().isEmpty) {
      Log.w(_tag, 'smsLogin empty mobile/code mobileLen=${mobile.length}');
      return const SmsLoginResult(ok: false, error: 'empty mobile or code');
    }
    if (!kAuthEndpointsProbed) {
      Log.w(_tag,
          'smsLogin needs probe: login_by_verifycode 未三态实测，'
          '返回语义失败（参数结构已按 docs 构造但不外发）');
      return const SmsLoginResult(
          ok: false,
          error: 'endpoint needs probe (login_by_verifycode)',
          needsProbe: true);
    }
    // 以下为实测后分支（当前不可达）：构造 docs §3.8 载荷并外发。
    final ms = DateTime.now().millisecondsSinceEpoch;
    // 按 docs §3.8 构造载荷（构造不外发，探针后才启用网络分支）。
    final payload = <String, Object?>{
      'mobile': mobile.trim(),
      'code': code.trim(),
      'dfid': client.session.dfid,
      'mid': client.session.mid,
      'uuid': '-',
    };
    final paramsCipher =
        AesCbc.encryptHex(_jsonOf(payload), kSmsAesKey, kSmsAesIv);
    final pkPlain = _jsonOf(<String, Object?>{
      'clienttime_ms': ms,
      'key': kSmsAesKey,
    });
    // docs §2.2：login_cellphone 的 pk 输出 .toUpperCase()。
    final pk = RsaRaw.encryptHex(pkPlain).toUpperCase();
    final body = <String, Object?>{'params': paramsCipher, 'pk': pk};
    Log.d(_tag,
        'smsLogin built paramsLen=${paramsCipher.length} pkLen=${pk.length}');
    final res = await client.request(EndpointRegistry.smsLogin,
        <String, Object?>{
          'dfid': client.session.dfid, 'mid': client.session.mid,
          'uuid': '-', 'clienttime_ms': ms,
        },
        body: body);
    final data = res['data'];
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    final token = '${map['token'] ?? res['token'] ?? ''}';
    final userid = '${map['userid'] ?? res['userid'] ?? ''}';
    final err = '${res['error'] ?? res['errcode'] ?? res['status'] ?? ''}';
    if (token.isEmpty) {
      Log.w(_tag, 'smsLogin rejected err=$err tokenEmpty');
      return SmsLoginResult(ok: false, error: 'status=$err');
    }
    Log.d(_tag, 'smsLogin ok uid=$userid tokenLen=${token.length}');
    return SmsLoginResult(ok: true, token: token, userid: userid);
  } catch (e, st) {
    Log.e(_tag, 'smsLogin failed', e, st);
    return SmsLoginResult(ok: false, error: '$e');
  }
}

String _jsonOf(Map<String, Object?> m) {
  try {
    return jsonEncode(m);
  } catch (e, st) {
    Log.e(_tag, '_jsonOf failed', e, st);
    return '{}';
  }
}

/// signParamsKey（docs §1.6）：md5(appid + Android盐 + clientver + clienttimeMs)。
/// 备用于探针实测阶段（login_cellphone.js 的 key 字段语义）。
String smsSignParamsKey(int clienttimeMs) {
  try {
    return Md5.hex('${KugouSign.appid}'
        'OIlwieks28dk2k092lksi2UIkp'
        '${KugouSign.clientver}'
        '$clienttimeMs');
  } catch (e, st) {
    Log.e(_tag, 'smsSignParamsKey failed', e, st);
    return '';
  }
}
