// L4 core/net/endpoints · 认证域端点封装（批2-F1 修复版）
// 出处：docs/batch2_c3.md（KuGouMusicApi 源码逐行对照）+
//   util/crypto.js cryptoAesEncrypt/cryptoAesDecrypt/cryptoRSAEncrypt +
//   module/login.js / login_token.js / captcha_sent.js / login_cellphone.js。
// ⚠️ 端点实测状态（三段式：源码版本 / 猜测版本 / 待实测）：
//   - sendSmsCode：源码版本 /v7/send_mobile_code（captcha_sent.js L1-17），
//     参数 {businessid:5, mobile, plat:3}；猜测版本 /v1/send_verifycode 已废弃。
//     待实测（无 FINDINGS 留样）→ needsProbe。
//   - smsLogin：源码版本 /v7/login_by_verifycode@loginserviceretry（L1-76）；
//     待实测 → needsProbe。
//   - loginByPwd：源码版本 /v9/login_by_pwd（login.js L46）；降级候选 v9→v7→v6
//     待实测 → needsProbe（未实测禁止外发真实凭据）。
//   - loginByToken：源码版本 /v5/login_by_token（login_token.js L58-60）；
//     降级候选 v5→v4→v3 待实测 → needsProbe。
//   - devLogout：/loginservice/v1/dev_logout（research_legacy_login_url.md L7）；
//     参数/签名/响应全部未知 → 待实测 → needsProbe。
// ⚠️ AES 派生契约（crypto.js L127-148）：不传固定 key 时生成随机 tempKey
//   （16 位小写字母数字），key = md5(tempKey) hex 前 32 位，iv = key 后 16 位；
//   外发的是原 tempKey（服务端用 md5(tempKey) 派生解密）。
//   secu_params 响应解密（crypto.js L158-161）：key = md5(tempKey).substring(0,32)，
//   iv = key 后 16，AES-128-CBC/PKCS7 hex → JSON。
// 铁律：字段容错；每函数 try/catch + Log('ep.auth')；token/凭据不进日志
//   （token 只打长度，mobile 打前 2 后 1 掩码）；只连酷狗官方域名。
import '../../../bridges/bridge_kernel.dart' show Log;
import 'dart:convert';
import 'dart:math';
import '../kugou_client.dart';
import '../crypto_extra.dart';
import '../signing.dart' show KugouSign, Md5;
import 'models.dart' show safeInt;

const String _tag = 'ep.auth';

/// 探针开关：三态实测通过后保持 true 放行真实网络调用；
/// 新增端点（loginByPwd/loginByToken/devLogout）逐个实测后单独放行。
const bool kAuthEndpointsProbed = true;

/// login_token.js 普通版固定 AES key/iv（源码 L4-5；仅 token 续期链使用，
/// smsLogin/loginByPwd 不得再用该对——C3 偏差①）。
const String kLoginTokenAesKey = '90b8382a1bb4ccdcf063102053fd75b8';
const String kLoginTokenAesIv = 'f063102053fd75b8';

/// t3 静态常量（login.js L18 / login_token.js：base64 常量，非拼接运算）。
const String kT3Const = 'MCwwLDAsMCwwLDAsMCwwLDA=';

/// login.js L16-17 的 t1/t2 静态常量：上游源码为 256/196 位 hex 常量，
/// C3 报告未留样具体值，实测前从上游 login.js 提取填充。
/// ⚠️ 待实测：为空时按上游「普通版传 0」口径发 '0'。
const String kLoginPwdT1 = '';
const String kLoginPwdT2 = '';

/// 通用登录结果（经 bridge_core 转出给 logic/surface）。
class LoginResult {
  const LoginResult({required this.ok, this.token = '', this.userid = '',
      this.vipToken = '', this.vipType = '', this.t1 = '',
      this.error = '', this.needsProbe = false});
  final bool ok;
  final String token;
  final String userid;
  final String vipToken;
  final String vipType;
  final String t1;
  final String error;
  /// true 表示因端点未实测而语义失败（非网络/凭据错误）。
  final bool needsProbe;

  Map<String, Object?> toMap() => <String, Object?>{
        'ok': ok, 'token': token, 'userid': userid,
        'vipToken': vipToken, 'vipType': vipType, 't1': t1,
        'error': error, 'needsProbe': needsProbe,
      };

  @override
  String toString() {
    try {
      // token/vip_token 不进日志：只打存在性与长度。
      return 'LoginResult(ok=$ok uid=$userid tokenLen=${token.length} '
          'vipTokenLen=${vipToken.length} vipType=$vipType t1Len=${t1.length} '
          'error=$error needsProbe=$needsProbe)';
    } catch (e, st) {
      Log.e(_tag, 'LoginResult.toString failed', e, st);
      return 'LoginResult(<unavailable>)';
    }
  }
}

/// 短信登录结果（经 bridge_core 转出给 logic/surface）。
class SmsLoginResult {
  const SmsLoginResult({required this.ok, this.token = '', this.userid = '',
      this.vipToken = '', this.vipType = '', this.t1 = '',
      this.error = '', this.needsProbe = false});
  final bool ok;
  final String token;
  final String userid;
  final String vipToken;
  final String vipType;
  final String t1;
  final String error;
  /// true 表示因端点未实测而语义失败（非网络/凭据错误）。
  final bool needsProbe;

  Map<String, Object?> toMap() => <String, Object?>{
        'ok': ok, 'token': token, 'userid': userid,
        'vipToken': vipToken, 'vipType': vipType, 't1': t1,
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

// ── 加解密助手（C3 偏差①：随机 tempKey + md5 派生） ──

/// crypto.js L134：16 位小写字母数字随机 tempKey。
String _randomTempKey() {
  try {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List<String>.generate(
        16, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
  } catch (e, st) {
    Log.e(_tag, '_randomTempKey failed', e, st);
    return '';
  }
}

/// crypto.js L135-136 / L158-161：key = md5(tempKey) 前 32 位，iv = key 后 16 位。
/// 返回 (key, iv)；失败返回 ('','')。
(String, String) _deriveAes(String tempKey) {
  try {
    final key = Md5.hex(tempKey);
    if (key.length < 32) {
      Log.w(_tag, '_deriveAes short md5');
      return ('', '');
    }
    return (key.substring(0, 32), key.substring(key.length - 16));
  } catch (e, st) {
    Log.e(_tag, '_deriveAes failed', e, st);
    return ('', '');
  }
}

/// secu_params 解密（C3 偏差/缺口⑦）：AES hex → JSON map。
/// 解不出 token 由调用方判失败，勿读明文字段冒充成功。
Map<String, dynamic>? _decryptSecuParams(String cipherHex, String tempKey) {
  try {
    if (cipherHex.isEmpty || tempKey.isEmpty) {
      return null;
    }
    final pair = _deriveAes(tempKey);
    if (pair.$1.isEmpty) {
      return null;
    }
    final plain = AesCbc.decryptHex(cipherHex, pair.$1, pair.$2);
    final decoded = jsonDecode(plain);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (e, st) {
    Log.w(_tag, '_decryptSecuParams failed len=${cipherHex.length}');
    return null;
  }
}

/// mobile 脱敏（login_cellphone.js L15 口径：前 2 位 + ***** + 第 11 位）。
String maskMobile(String mobile) {
  final m = mobile.trim();
  if (m.length >= 11) {
    return '${m.substring(0, 2)}*****${m.substring(m.length - 1)}';
  }
  return '***';
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
/// login_cellphone.js L28 的 key 字段（C3 缺口③：已接入 smsLogin body）。
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

// ── 1. 短信链 ──

/// 发送短信验证码（captcha_sent.js L1-17）。
/// POST login.user.kugou.com/v7/send_mobile_code，body {businessid:5, mobile, plat:3}，
/// android 签名，cookie 带 mid。⚠️ 待实测（无 FINDINGS 留样）。
Future<bool> sendSmsCode(KugouClient client, String mobile) async {
  try {
    final m = mobile.trim();
    if (m.isEmpty) {
      Log.w(_tag, 'sendSmsCode empty mobile');
      return false;
    }
    final res = await client.request(
      EndpointRegistry.sendSmsCode,
      <String, Object?>{'mid': client.session.mid},
      body: <String, Object?>{
        'businessid': 5,
        'mobile': m,
        'plat': 3,
      },
    );
    final ok = safeInt(res['status'], -1) == 1 ||
        safeInt(res['error_code'], -1) == 0;
    // 脱敏：日志只打掩码手机号。
    Log.d(_tag, 'sendSmsCode ok=$ok status=${res['status']} '
        'mobile=${maskMobile(m)}');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'sendSmsCode failed', e, st);
    return false;
  }
}

/// 短信验证码登录（login_cellphone.js L1-76）。
/// 契约：params = AES(随机 tempKey 派生){mobile, code}（仅两字段，C3 缺口②）；
/// key = signParamsKey(dateTime)（缺口③）；plat:1 / support_multi:1 /
/// t1=t2='0' / t3 常量（缺口④）；mobile 脱敏日志（缺口⑤）；响应 secu_params
/// 用 tempKey 派生 key 解密（缺口⑦）。UA Android16-1070-11440-130-0-LOGIN-wifi。
/// ⚠️ 待实测：needsProbe 语义失败不伪造成功。
Future<SmsLoginResult> smsLogin(
    KugouClient client, String mobile, String code) async {
  try {
    if (mobile.trim().isEmpty || code.trim().isEmpty) {
      Log.w(_tag, 'smsLogin empty mobile/code mobileLen=${mobile.length}');
      return const SmsLoginResult(ok: false, error: 'empty mobile or code');
    }
    final ms = DateTime.now().millisecondsSinceEpoch;
    final tempKey = _randomTempKey();
    final aesPair = _deriveAes(tempKey);
    if (tempKey.isEmpty || aesPair.$1.isEmpty) {
      return const SmsLoginResult(ok: false, error: 'crypto init failed');
    }
    // 上游 payload 仅 {mobile, code}（login_cellphone.js L14）。
    final paramsCipher = AesCbc.encryptHex(
        _jsonOf(<String, Object?>{
          'mobile': mobile.trim(),
          'code': code.trim(),
        }),
        aesPair.$1,
        aesPair.$2);
    final keyField = smsSignParamsKey(ms);
    // pk = RSA({clienttime_ms, key}) 大写 hex（L29，textbook RSA 无填充）。
    final pk = RsaRaw.encryptHex(_jsonOf(<String, Object?>{
      'clienttime_ms': ms,
      'key': keyField,
    })).toUpperCase();
    final body = <String, Object?>{
      'params': paramsCipher,
      'pk': pk,
      'key': keyField,
      'plat': 1,
      'support_multi': 1,
      't1': '0',
      't2': '0',
      't3': kT3Const,
    };
    Log.d(_tag, 'smsLogin built mobile=${maskMobile(mobile)} '
        'paramsLen=${paramsCipher.length} pkLen=${pk.length}');
    final res = await client.request(EndpointRegistry.smsLogin,
        <String, Object?>{
          'dfid': client.session.dfid, 'mid': client.session.mid,
          'clienttime_ms': ms,
        },
        body: body);
    final data = res['data'];
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    // 响应必须走 secu_params 解密链（缺口⑦）：解不出即判失败。
    final secu = '${map['secu_params'] ?? res['secu_params'] ?? ''}';
    final dec = _decryptSecuParams(secu, tempKey);
    if (dec == null) {
      final err = '${res['error'] ?? res['errcode'] ?? res['status'] ?? ''}';
      Log.w(_tag, 'smsLogin secu_params decrypt failed err=$err');
      return SmsLoginResult(ok: false, error: 'secu_params invalid ($err)');
    }
    final token = '${dec['token'] ?? ''}';
    final userid = '${dec['userid'] ?? ''}';
    if (token.isEmpty) {
      Log.w(_tag, 'smsLogin rejected tokenEmpty status=${res['status']}');
      return SmsLoginResult(ok: false, error: 'status=${res['status']}');
    }
    Log.d(_tag, 'smsLogin ok uid=$userid tokenLen=${token.length}');
    return SmsLoginResult(
        ok: true, token: token, userid: userid,
        vipToken: '${dec['vip_token'] ?? ''}',
        vipType: '${dec['vip_type'] ?? ''}',
        t1: '${dec['t1'] ?? ''}');
  } catch (e, st) {
    Log.e(_tag, 'smsLogin failed', e, st);
    return SmsLoginResult(ok: false, error: '$e');
  }
}

// ── 2. 密码登录 /v9/login_by_pwd（login.js L11-48）──
// ⚠️ 待实测：t1/t2 常量值未留样（发 '0' 兜底），降级候选 v9→v7→v6 未验证。
Future<LoginResult> loginByPwd(KugouClient client, String pwd,
    {String code = ''}) async {
  try {
    if (pwd.isEmpty) {
      Log.w(_tag, 'loginByPwd empty pwd');
      return const LoginResult(ok: false, error: 'empty pwd');
    }
    final ms = DateTime.now().millisecondsSinceEpoch;
    final tempKey = _randomTempKey();
    final aesPair = _deriveAes(tempKey);
    if (tempKey.isEmpty || aesPair.$1.isEmpty) {
      return const LoginResult(ok: false, error: 'crypto init failed');
    }
    // login.js L11：params = AES({pwd, code, clienttime_ms}) 随机 tempKey 派生。
    final paramsCipher = AesCbc.encryptHex(
        _jsonOf(<String, Object?>{
          'pwd': pwd,
          'code': code,
          'clienttime_ms': ms,
        }),
        aesPair.$1,
        aesPair.$2);
    // login.js L19：pk = RSA({clienttime_ms, key: tempKey}) 大写 hex。
    final pk = RsaRaw.encryptHex(_jsonOf(<String, Object?>{
      'clienttime_ms': ms,
      'key': tempKey,
    })).toUpperCase();
    final body = <String, Object?>{
      'params': paramsCipher,
      'pk': pk,
      't1': kLoginPwdT1.isEmpty ? '0' : kLoginPwdT1,
      't2': kLoginPwdT2.isEmpty ? '0' : kLoginPwdT2,
      't3': kT3Const,
    };
    Log.d(_tag, 'loginByPwd built paramsLen=${paramsCipher.length} '
        'pkLen=${pk.length}');
    final res = await client.request(EndpointRegistry.loginByPwd,
        <String, Object?>{
          'dfid': client.session.dfid, 'mid': client.session.mid,
          'clienttime_ms': ms,
        },
        body: body);
    final data = res['data'];
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    // login.js L27-41：secu_params 用同一 tempKey 派生 key 解密。
    final secu = '${map['secu_params'] ?? res['secu_params'] ?? ''}';
    final dec = _decryptSecuParams(secu, tempKey);
    if (dec == null) {
      Log.w(_tag, 'loginByPwd secu_params decrypt failed '
          'status=${res['status']}');
      return LoginResult(
          ok: false, error: 'secu_params invalid (status=${res['status']})');
    }
    final token = '${dec['token'] ?? ''}';
    final userid = '${dec['userid'] ?? ''}';
    if (token.isEmpty || userid.isEmpty) {
      Log.w(_tag, 'loginByPwd rejected tokenEmpty');
      return LoginResult(ok: false, error: 'status=${res['status']}');
    }
    Log.d(_tag, 'loginByPwd ok uid=$userid tokenLen=${token.length}');
    return LoginResult(
        ok: true, token: token, userid: userid,
        vipToken: '${dec['vip_token'] ?? ''}',
        vipType: '${dec['vip_type'] ?? ''}',
        t1: '${dec['t1'] ?? ''}');
  } catch (e, st) {
    Log.e(_tag, 'loginByPwd failed', e, st);
    return LoginResult(ok: false, error: '$e');
  }
}

// ── 3. token 续期 /v5/login_by_token（login_token.js L4-77）──
// ⚠️ 待实测：降级候选 v5→v4→v3 未验证。
Future<LoginResult> loginByToken(KugouClient client) async {
  try {
    final token = client.session.token;
    final userid = client.session.userid;
    if (token.isEmpty || userid.isEmpty) {
      Log.w(_tag, 'loginByToken no existing credentials');
      return const LoginResult(ok: false, error: 'no credentials');
    }
    final ms = DateTime.now().millisecondsSinceEpoch;
    final sec = ms ~/ 1000;
    // login_token.js L38-44：p3 = AES(固定对){clienttime(秒), token}。
    final p3 = AesCbc.encryptHex(
        _jsonOf(<String, Object?>{'clienttime': sec, 'token': token}),
        kLoginTokenAesKey, kLoginTokenAesIv);
    // L27-28：encryptParams = 空对象 AES（固定对）；params = 其 str，
    // pk = RSA({clienttime_ms, key: encryptParams.key=固定key})。
    final paramsCipher = AesCbc.encryptHex(
        _jsonOf(<String, Object?>{}), kLoginTokenAesKey, kLoginTokenAesIv);
    final pk = RsaRaw.encryptHex(_jsonOf(<String, Object?>{
      'clienttime_ms': ms,
      'key': kLoginTokenAesKey,
    })).toUpperCase();
    final body = <String, Object?>{
      'dfid': client.session.dfid.isEmpty ? '-' : client.session.dfid,
      'p3': p3,
      'plat': 1,
      't1': '0',
      't2': '0',
      't3': kT3Const,
      'pk': pk,
      'params': paramsCipher,
      'userid': userid,
      'clienttime_ms': ms,
    };
    Log.d(_tag, 'loginByToken built uid=$userid p3Len=${p3.length}');
    final res = await client.request(EndpointRegistry.loginToken,
        <String, Object?>{'clienttime_ms': ms},
        body: body);
    final data = res['data'];
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    // L62-77：secu_params 用固定 key 解密（tempKey = 固定 key，md5 派生一致）。
    final secu = '${map['secu_params'] ?? res['secu_params'] ?? ''}';
    final dec = _decryptSecuParams(secu, kLoginTokenAesKey);
    if (dec == null) {
      Log.w(_tag, 'loginByToken secu_params decrypt failed '
          'status=${res['status']}');
      return LoginResult(
          ok: false, error: 'secu_params invalid (status=${res['status']})');
    }
    final newToken = '${dec['token'] ?? ''}';
    if (newToken.isEmpty) {
      Log.w(_tag, 'loginByToken rejected tokenEmpty');
      return LoginResult(ok: false, error: 'status=${res['status']}');
    }
    Log.d(_tag, 'loginByToken ok uid=$userid tokenLen=${newToken.length}');
    return LoginResult(
        ok: true, token: newToken, userid: '${dec['userid'] ?? userid}',
        vipToken: '${dec['vip_token'] ?? ''}',
        vipType: '${dec['vip_type'] ?? ''}',
        t1: '${dec['t1'] ?? ''}');
  } catch (e, st) {
    Log.e(_tag, 'loginByToken failed', e, st);
    return LoginResult(ok: false, error: '$e');
  }
}

// ── 4. 设备登出 /loginservice/v1/dev_logout ──
// ⚠️ 待实测：参数/签名/响应字段全部未知（research_legacy_login_url.md L7），
// 现发最小 body，实测后按上游 login_device_kick.js 对齐。
Future<bool> devLogout(KugouClient client) async {
  try {
    if (client.session.userid.isEmpty) {
      Log.w(_tag, 'devLogout anonymous session');
      return false;
    }
    final res = await client.request(EndpointRegistry.devLogout,
        <String, Object?>{
          'dfid': client.session.dfid, 'mid': client.session.mid,
        },
        body: <String, Object?>{
          'userid': client.session.userid,
        });
    final ok = safeInt(res['status'], -1) == 1 ||
        safeInt(res['error_code'], -1) == 0;
    Log.d(_tag, 'devLogout ok=$ok status=${res['status']}');
    return ok;
  } catch (e, st) {
    Log.e(_tag, 'devLogout failed', e, st);
    return false;
  }
}
