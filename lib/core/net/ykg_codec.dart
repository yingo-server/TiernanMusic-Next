// L4 core/net · YKG 浏览器链接登录 · 密码学封装
//
// 设计权威：docs/YKG_LINK_CRYPTO_DESIGN.md
// 纪律（用户 2026-11-16）：**算法一律调用成熟库**（cryptography 2.7：
// PBKDF2-HMAC-SHA256 / AES-256-GCM / SHA-256 / HMAC），本项目自研的只有
// 「封装方式」——报文结构、字段语义、aad/nonce 约定、导入导出流程、层落位。
//
// 报文：ykg://import/<base64Url(UTF8(JSON payload))>（无填充）
// payload 字段：v 版本 / u userid / s salt(b64url) / n nonce(b64url) /
//   c ciphertext(b64url) / t tag(b64url) / m 兼容摘要 / ts 导出时间 /
//   exp 过期时间 / d 明文 cookie 摘要指纹。
// 密文明文是 canonical JSON：{cookie,token,userid,vip_token,vip_type,dfid,mid}
//
// 安全要点：
//  - dk = PBKDF2-HMAC-SHA256(password, salt, 120000, 32)
//  - AES-256-GCM(dk, nonce, plaintext, aad='ykg-v1')；tag 校验即密码门，
//    错误密码/篡改密文统一拒绝（不区分，避免 oracle）。
//  - m = md5(salt + ':' + password) 仅作兼容快筛字段，不作放行判据。
library;

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List;

import 'package:cryptography/cryptography.dart';

import '../../bridges/bridge_kernel.dart' show Log;
import 'signing.dart' show md5Hex;

const String _tag = 'core.ykg';
const String kYkgScheme = 'ykg://import/';
const String kYkgAad = 'ykg-v1';
const int kYkgVersion = 1;
const int kYkgIterations = 120000;
const int kYkgDefaultTtlSec = 7 * 24 * 3600;

/// 解析/加解密结果（不抛，带明确错误态）。
class YkgLinkResult {
  const YkgLinkResult.ok(this.credentials)
    : error = null,
      ok = true;
  const YkgLinkResult.fail(this.error)
    : credentials = null,
      ok = false;
  final bool ok;
  final String? error;
  final Map<String, String>? credentials;
}

/// 导出：把凭据 + 口令封装成 ykg 链接。
/// [credentials] 至少含 cookie/token/userid；其余键原样透传。
/// 返回链接字符串；失败抛 [YkgException]。
Future<String> encodeYkgLink({
  required Map<String, String> credentials,
  required String password,
  int ttlSec = kYkgDefaultTtlSec,
  int? nowSec,
  Random? rng,
}) async {
  try {
    if (password.isEmpty) throw YkgException('empty password');
    final r = rng ?? Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => r.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => r.nextInt(256)),
    );
    final now = nowSec ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final plain = _canonical(credentials);
    final dk = await _derive(password, salt);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(dk),
      nonce: nonce,
      aad: utf8.encode(kYkgAad),
    );
    final payload = <String, Object?>{
      'v': kYkgVersion,
      'u': credentials['userid'] ?? '',
      's': _b64Url(salt),
      'n': _b64Url(Uint8List.fromList(box.nonce)),
      'c': _b64Url(Uint8List.fromList(box.cipherText)),
      't': _b64Url(Uint8List.fromList(box.mac.bytes)),
      // 兼容字段：md5 加盐口令摘要（仅快筛/兼容，不作放行判据）。
      'm': md5Hex('${_b64Url(salt)}:$password'),
      'ts': now,
      'exp': now + ttlSec,
      // 明文 cookie 指纹，导入后比对完整性（不泄露内容）。
      'd': _b64Url(utf8.encode(md5Hex(plain))),
    };
    return kYkgScheme + _b64Url(utf8.encode(jsonEncode(payload)));
  } catch (e, st) {
    Log.e(_tag, 'encodeYkgLink failed', e, st);
    throw YkgException('encode failed: $e');
  }
}

/// 导入：必须先验密码再解密；任何失败统一返回 YkgLinkResult.fail。
Future<YkgLinkResult> decodeYkgLink(
  String link, {
  required String password,
  int? nowSec,
}) async {
  try {
    if (!link.startsWith(kYkgScheme)) {
      return const YkgLinkResult.fail('invalid link');
    }
    final raw = link.substring(kYkgScheme.length);
    final decoded = utf8.decode(_b64UrlDecode(raw));
    final obj = jsonDecode(decoded);
    if (obj is! Map) return const YkgLinkResult.fail('invalid payload');
    final p = Map<String, Object?>.from(obj);
    if (p['v'] != kYkgVersion) return const YkgLinkResult.fail('unsupported version');
    final exp = p['exp'];
    final now = nowSec ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    if (exp is int && exp < now) return const YkgLinkResult.fail('link expired');
    final s = p['s'];
    final n = p['n'];
    final c = p['c'];
    final t = p['t'];
    if (s is! String || n is! String || c is! String || t is! String) {
      return const YkgLinkResult.fail('invalid payload');
    }
    if (password.isEmpty) return const YkgLinkResult.fail('password required');
    final salt = _b64UrlDecode(s);
    final dk = await _derive(password, salt);
    final plainBytes = await AesGcm.with256bits().decrypt(
      SecretBox(
        _b64UrlDecode(c),
        mac: Mac(_b64UrlDecode(t)),
        nonce: _b64UrlDecode(n),
      ),
      secretKey: SecretKey(dk),
      aad: utf8.encode(kYkgAad),
    );
    final plain = utf8.decode(plainBytes);
    // 完整性指纹：防止密文被替换为其它合法密文（同口令下）。
    final expectD = p['d'];
    if (expectD is String && expectD.isNotEmpty) {
      final actual = _b64Url(utf8.encode(md5Hex(plain)));
      if (actual != expectD) return const YkgLinkResult.fail('integrity mismatch');
    }
    final cred = _parseCanonical(plain);
    if (cred == null) return const YkgLinkResult.fail('invalid credentials');
    return YkgLinkResult.ok(cred);
  } catch (e, st) {
    // 密码错误/密文篡改/解析失败一律统一错误（不区分，避免 oracle）。
    Log.d(_tag, 'decodeYkgLink rejected: ${e.runtimeType}');
    return const YkgLinkResult.fail('wrong password or damaged link');
  }
}

/// 导出密码的本地校验值（不存明文；重新导出时验证用，独立 salt）。
Future<String> passwordVerifier(String password, String saltB64Url) async {
  final dk = await _derive(password, _b64UrlDecode(saltB64Url));
  return _b64Url(Uint8List.fromList(dk));
}

/// 生成新的 (salt, verifier) 对（salt 由 CSPRNG 产生）。
/// 供 L5 持久化：不存明文口令，只存 salt + verifier。
Future<(String, String)> newYkgVerifier(String password, {Random? rng}) async {
  final r = rng ?? Random.secure();
  final salt = Uint8List.fromList(
    List<int>.generate(16, (_) => r.nextInt(256)),
  );
  final saltB64 = _b64Url(salt);
  final verifier = await passwordVerifier(password, saltB64);
  return (saltB64, verifier);
}

Future<List<int>> _derive(String password, List<int> salt) async {
  final pbkdf2 = Pbkdf2.hmacSha256(
    iterations: kYkgIterations,
    bits: 256,
  );
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
  return await key.extractBytes();
}

/// canonical JSON：键固定顺序，避免不同实现序列化差异影响指纹。
String _canonical(Map<String, String> c) {
  const keys = <String>[
    'cookie', 'token', 'userid', 'vip_token', 'vip_type', 'dfid', 'mid',
  ];
  final buf = <String, Object?>{};
  for (final k in keys) {
    buf[k] = c[k] ?? '';
  }
  return jsonEncode(buf);
}

Map<String, String>? _parseCanonical(String plain) {
  try {
    final obj = jsonDecode(plain);
    if (obj is! Map) return null;
    final out = <String, String>{};
    obj.forEach((k, v) {
      if (k is String && v != null) out[k] = '$v';
    });
    return out.isEmpty ? null : out;
  } catch (e) {
    return null;
  }
}

String _b64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

List<int> _b64UrlDecode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64UrlDecode(s + '=' * pad);
}

class YkgException implements Exception {
  const YkgException(this.message);
  final String message;
  @override
  String toString() => 'YkgException($message)';
}
