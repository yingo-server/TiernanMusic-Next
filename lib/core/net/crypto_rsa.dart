// L4 core/net 级 · 歌单域加密契约（playlist AES + rsaEncrypt2 PKCS1 v1.5）
// 知识来源：KuGouMusicApi/util/crypto.js（API 参考项目，非归档 Flutter 项目）：
//   - rsaEncrypt2(data)：forge RSAES-PKCS1-V1_5 加密，forge.util.bytesToHex 输出。
//     上游调用（module/playlist_del.js）结果 .toUpperCase()。
//   - playlistAesEncrypt(data)：key=randomString(6).toLowerCase()（小写字母数字 6 位）；
//     encryptKey=md5(key)[0..16)，iv=md5(key)[16..32)；AES-128-CBC PKCS7；
//     输出 Base64(ciphertext)。
//   - playlistAesDecrypt({str,key})：同 key/iv 派生，Base64 输入。
// 原则：纯 Dart，零第三方库；复用 crypto_extra.dart 的 AesCbc/BigIntL/RsaRaw。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../bridges/bridge_kernel.dart' show Log;
import 'crypto_extra.dart' show AesCbc, BigIntL, RsaRaw, CryptoException;
import 'signing.dart' show md5Hex;

const String _tag = 'net.crypto.playlist';

/// RSA 公钥（出处 KuGouMusicApi util/crypto.js publicRasKey，逐字抄录；
/// rsaEncrypt2 非 lite 平台使用此 key，1024 位，e=65537）。
const String kKugouRsaPemBase64Playlist =
    'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDIAG7QOELSYoIJvTFJhMpe1s/gbjDJX51HBNnEl5HXqTW6lQ7LC8jr9fWZTwusknp+sVGzwd40MwP6U5yDE27M/X1+UR4tvOGOqp94TJtQ1EPnWGWXngpeIW5GxoQGao1rmYWAu6oi1z9XkChrsUdC6DJE5E221wf/4WLFxwAtRQIDAQAB';

const String _b64Chars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const String _randLower =
    'abcdefghijklmnopqrstuvwxyz0123456789';

String _base64EncodePadded(List<int> bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    final n = (b0 << 16) | (b1 << 8) | b2;
    sb.write(_b64Chars[(n >> 18) & 63]);
    sb.write(_b64Chars[(n >> 12) & 63]);
    sb.write(i + 1 < bytes.length ? _b64Chars[(n >> 6) & 63] : '=');
    sb.write(i + 2 < bytes.length ? _b64Chars[n & 63] : '=');
  }
  return sb.toString();
}

/// rsaEncrypt2 等价实现：RSAES-PKCS1-V1_5（EME-PKCS1-v1_5 填充）+ 裸模幂。
/// 输出大写 hex（上游 playlist_del.js 对 rsaEncrypt2 结果 .toUpperCase()）。
/// 明文 JSON 序列化（dart:convert jsonEncode，键序由调用方保证）。
String rsaEncrypt2(String plaintext, {String? pemBase64}) {
  try {
    final kLen = 128; // 1024-bit key → 128 字节密文块
    final msg = Uint8List.fromList(utf8.encode(plaintext));
    // PKCS1 v1.5 加密填充：EM = 0x00 || 0x02 || PS(≥8 非零随机) || 0x00 || M
    final psLen = kLen - 3 - msg.length;
    if (psLen < 8) {
      throw CryptoException('pkcs1 plaintext too long: ${msg.length}');
    }
    final rnd = Random.secure();
    final em = Uint8List(kLen);
    em[0] = 0x00;
    em[1] = 0x02;
    for (var i = 0; i < psLen; i++) {
      var b = 0;
      while (b == 0) {
        b = rnd.nextInt(256);
      }
      em[2 + i] = b;
    }
    em[2 + psLen] = 0x00;
    em.setRange(3 + psLen, kLen, msg);
    // 大端字节 → limb（低 limb 在前），模幂 e=65537。
    final l = <int>[];
    for (var i = kLen; i > 0; i -= 4) {
      l.add((em[i - 4] << 24) |
          (em[i - 3] << 16) |
          (em[i - 2] << 8) |
          em[i - 1]);
    }
    final modulusHex =
        RsaRaw.modulusHexFromPem(pemBase64 ?? kKugouRsaPemBase64Playlist);
    final c = BigIntL(l)
        .modPow(BigIntL([65537]), BigIntL.fromHex(modulusHex));
    return c.toHex(padBytes: kLen).toUpperCase();
  } catch (e, st) {
    Log.e(_tag, 'rsaEncrypt2 failed (plaintext not logged)', e, st);
    rethrow;
  }
}

/// playlistAesEncrypt 等价实现结果。
class PlaylistAesResult {
  PlaylistAesResult(this.key, this.cipherBase64);
  /// 随机 6 位小写种子（明文侧参与 rsaEncrypt2 的 aes 字段）。
  final String key;
  /// Base64(AES-128-CBC-PKCS7(JSON))。
  final String cipherBase64;
}

/// playlistAesEncrypt：key=randomString(6) 小写；encryptKey=md5(key)[0,16)、
/// iv=md5(key)[16,32)；AES-128-CBC PKCS7；输出 Base64。
PlaylistAesResult playlistAesEncrypt(Map<String, Object?> data,
    {Random? rng}) {
  try {
    final r = rng ?? Random.secure();
    final key = String.fromCharCodes(
        List<int>.generate(6, (_) => _randLower.codeUnitAt(r.nextInt(_randLower.length))));
    final digest = md5Hex(key);
    final encKey = digest.substring(0, 16);
    final iv = digest.substring(16, 32);
    final plain = utf8.encode(jsonEncode(data));
    // md5 派生的 32 hex 字符即 16 字节 key/iv（hex 直转字节）。
    final cipher = AesCbc.encrypt(Uint8List.fromList(plain),
        _hexToBytes(encKey), _hexToBytes(iv));
    return PlaylistAesResult(key, _base64EncodePadded(cipher));
  } catch (e, st) {
    Log.e(_tag, 'playlistAesEncrypt failed', e, st);
    rethrow;
  }
}

/// playlistAesDecrypt：同 key/iv 派生，Base64 输入，返回解密文本（JSON 由调用方解析）。
String playlistAesDecrypt(String cipherBase64, String key) {
  try {
    final digest = md5Hex(key);
    final encKey = digest.substring(0, 16);
    final iv = digest.substring(16, 32);
    final out = AesCbc.decrypt(_b64ToBytes(cipherBase64),
        _hexToBytes(encKey), _hexToBytes(iv));
    return utf8.decode(out, allowMalformed: true);
  } catch (e, st) {
    Log.e(_tag, 'playlistAesDecrypt failed', e, st);
    rethrow;
  }
}

Uint8List _hexToBytes(String hex) {
  if (hex.length != 32) throw CryptoException('bad key/iv hex len ${hex.length}');
  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _b64ToBytes(String s) {
  final clean = s.replaceAll(RegExp(r'[^A-Za-z0-9+/]'), '');
  var pad = 0;
  while (clean.length % 4 != 0) {
    pad++;
    if (pad > 2) throw CryptoException('bad base64 length');
  }
  final padded = clean + ('=' * pad);
  final out = <int>[];
  for (var i = 0; i < padded.length; i += 4) {
    final c = [for (var j = 0; j < 4; j++) _b64Chars.indexOf(padded[i + j])];
    if (c.contains(-1)) throw CryptoException('bad base64 char');
    final n = (c[0] << 18) | (c[1] << 12) | ((c[2] & 63) << 6) | (c[3] & 63);
    out.add((n >> 16) & 0xff);
    if (padded[i + 2] != '=') out.add((n >> 8) & 0xff);
    if (padded[i + 3] != '=') out.add(n & 0xff);
  }
  return Uint8List.fromList(out);
}
