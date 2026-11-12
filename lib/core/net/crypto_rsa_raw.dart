// L4 core/net · RSA 裸模幂（no padding）——由 crypto_extra.dart 拆出（R2-A）。
// RsaRaw/kKugouRsaPemBase64 类体逐字搬移，零逻辑改动。
import 'dart:convert';
import 'dart:typed_data';

import '../../bridges/bridge_kernel.dart' show Log;
import 'crypto_aes.dart' show CryptoException;
import 'crypto_bigint.dart' show BigIntL;

const String _tag = 'net.crypto';

/// RSA 公钥常量：出处 KuGouMusicApi `util/crypto.js` publicRasKey（1024 位，
/// 经 docs/KUGOU_API.md §2.2 标注，PEM 去头尾 base64 后由 SPKI 提取 modulus）。
/// PEM 原文（逐字抄录 util/crypto.js）：
/// -----BEGIN PUBLIC KEY-----
/// MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDIAG7QOELSYoIJvTFJhMpe1s/gbjDJX51HBNnEl5HXqTW6lQ7LC8jr9fWZTwusknp+sVGzwd40MwP6U5yDE27M/X1+UR4tvOGOqp94TJtQ1EPnWGWXngpeIW5GxoQGao1rmYWAu6oi1z9XkChrsUdC6DJE5E221wf/4WLFxwAtRQIDAQAB
/// -----END PUBLIC KEY-----
/// DER SPKI 中 modulus 偏移：SEQUENCE(30 81 9f) → BIT STRING 包裹 → SEQUENCE(30 0d) 后
/// BIT STRING(03) 起始 00 → INTEGER(02 81 81) 129 字节（首字节 00），即 modulus = 以下 128 字节。
/// modulus 统一从 [kKugouRsaPemBase64]（SPKI DER）运行期解析，
/// 不预置 hex 常量，避免抄录错误。

/// PEM body（util/crypto.js publicRasKey，逐字抄录）。
const String kKugouRsaPemBase64 =
    'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDIAG7QOELSYoIJvTFJhMpe1s/gbjDJX51HBNnEl5HXqTW6lQ7LC8jr9fWZTwusknp+sVGzwd40MwP6U5yDE27M/X1+UR4tvOGOqp94TJtQ1EPnWGWXngpeIW5GxoQGao1rmYWAu6oi1z9XkChrsUdC6DJE5E221wf/4WLFxwAtRQIDAQAB';

/// 大整数：小端 32-bit limb 列表。
class RsaRaw {
  RsaRaw._();

  /// 从 SPKI PEM base64 提取 modulus（大端 hex）。解析失败抛 CryptoException。
  static String modulusHexFromPem(String pemBase64) {
    try {
      final der = base64Decode(pemBase64);
      // 简易 DER 走读：找 02 81 81（INTEGER 129 字节）后取 128 字节（跳过前导 00）。
      for (var i = 0; i < der.length - 130; i++) {
        if (der[i] == 0x02 && der[i + 1] == 0x81 && der[i + 2] == 0x81) {
          final start = i + 3;
          final off = start + (der[start] == 0x00 ? 1 : 0); // 跳过前导 00
          return _toHex(der.sublist(off, off + 128));
        }
      }
      throw CryptoException('rsa modulus not found in SPKI');
    } catch (e) {
      Log.e(_tag, 'rsa modulus parse failed', e);
      rethrow;
    }
  }

  /// RSA no-padding 加密：明文左侧补零到 128 字节，modPow(e=65537, n)，输出 hex。
  static String encryptHex(String plaintext, {String? modulusHex}) {
    try {
      final modHex =
          modulusHex ?? modulusHexFromPem(kKugouRsaPemBase64);
      final n = BigIntL.fromHex(modHex);
      final mBytes = Uint8List(128);
      final plain = Uint8List.fromList(utf8.encode(plaintext));
      if (plain.length > 128) throw CryptoException('rsa plaintext too long');
      mBytes.setRange(128 - plain.length, 128, plain);
      // 大端 → limb（低 limb 在前）。
      final l = <int>[];
      for (var i = 128; i > 0; i -= 4) {
        l.add((mBytes[i - 4] << 24) |
            (mBytes[i - 3] << 16) |
            (mBytes[i - 2] << 8) |
            mBytes[i - 1]);
      }
      final c = BigIntL(l).modPow(BigIntL([65537]), n);
      return c.toHex(padBytes: 128);
    } catch (e) {
      Log.e(_tag, 'rsa encrypt failed (plaintext not logged)', e);
      rethrow;
    }
  }
}

// 注意：_toHex 与 crypto_aes.dart 的同名私有函数逐字相同（Dart 私有标识符
// 不可跨库 import，故按逐字副本放置；纯复制，零逻辑改动）。
String _toHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
