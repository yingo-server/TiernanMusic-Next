// L4 core/net · 纯 Dart AES-128-CBC（PKCS7）+ RSA 裸模幂
// 知识来源：docs/KUGOU_API.md §2.1（AES-CBC 固定 key/iv）、§2.2（RSA no padding）
// 原则：SDK 优先（dart:typed_data 自实现，≤500 行，零第三方库）。
// 测试锚点：FIPS-197 Appendix C.1（AES-128）——
//   key=000102030405060708090a0b0c0d0e0f
//   plaintext=00112233445566778899aabbccddeeff
//   ciphertext=69c4e0d86a7b0430d8cdb78070b4c55a
//   单块 ECB 加密结果必须等于该向量（CBC 首块含 IV，需向量级自测）。
// 铁律：禁 surface/flutter；容错优先，失败抛 CryptoException 并由调用方 Log。
import 'dart:convert';
import 'dart:typed_data';

import '../../kernel/kernel.dart' show Log;

const String _tag = 'net.crypto';

class CryptoException implements Exception {
  CryptoException(this.message);
  final String message;
  @override
  String toString() => 'CryptoException($message)';
}

// ─── AES S 盒 / 逆 S 盒（FIPS-197 §5.1.1，常量逐字抄录） ───

const List<int> _sbox = [
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
];

const List<int> _invSbox = [
  0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
  0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
  0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
  0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
  0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
  0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
  0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
  0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
  0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
  0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
  0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
  0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
  0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
  0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
  0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
  0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
];

// GF(2^8) 乘数表（xtime 组合），避免逐位循环。
int _xt(int v) => ((v << 1) ^ ((v & 0x80) != 0 ? 0x1b : 0)) & 0xff;
int _mul2(int v) => _xt(v);
int _mul3(int v) => _xt(v) ^ v;

int _gmul(int a, int b) {
  // 通用 GF(2^8) 乘（解密列混淆用），Russian peasant。
  var r = 0, x = a, y = b;
  for (var i = 0; i < 8; i++) {
    if ((y & 1) != 0) r ^= x;
    x = _xt(x);
    y >>= 1;
  }
  return r;
}

// ─── AES-128 核心（单块 ECB） ───

/// 轮密钥扩展（AES-128 → 11 组 16 字节，共 176 字节）。
Uint8List _expandKey(Uint8List key) {
  if (key.length != 16) throw CryptoException('aes key must be 16 bytes');
  final w = List<int>.filled(176, 0);
  w.setRange(0, 16, key);
  for (var i = 16; i < 176; i += 4) {
    var t0 = w[i - 4], t1 = w[i - 3], t2 = w[i - 2], t3 = w[i - 1];
    if (i % 16 == 0) {
      // RotWord + SubWord + Rcon
      final tmp = t0;
      t0 = _sbox[t1] ^ 0x01;
      t1 = _sbox[t2];
      t2 = _sbox[t3];
      t3 = _sbox[tmp];
    }
    w[i] = w[i - 16] ^ t0;
    w[i + 1] = w[i - 15] ^ t1;
    w[i + 2] = w[i - 14] ^ t2;
    w[i + 3] = w[i - 13] ^ t3;
  }
  return Uint8List.fromList(w);
}

/// 单块 ECB 加密（state 列主序：state[r][c] = in[r + 4c]）。
Uint8List _encryptBlock(Uint8List rk, Uint8List block) {
  final s = Uint8List.fromList(block);
  void addRoundKey(int off) {
    for (var i = 0; i < 16; i++) {
      s[i] ^= rk[off + i];
    }
  }

  void subShift() {
    for (var i = 0; i < 16; i++) {
      s[i] = _sbox[s[i]];
    }
    // ShiftRows：行 r 循环左移 r（state 列主序索引 r + 4c）。
    for (var r = 1; r < 4; r++) {
      final row = [s[r], s[r + 4], s[r + 8], s[r + 12]];
      for (var c = 0; c < 4; c++) {
        s[r + 4 * c] = row[(c + r) % 4];
      }
    }
  }

  void mixColumns() {
    for (var c = 0; c < 4; c++) {
      final a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3];
      s[4 * c] = _mul2(a0) ^ _mul3(a1) ^ a2 ^ a3;
      s[4 * c + 1] = a0 ^ _mul2(a1) ^ _mul3(a2) ^ a3;
      s[4 * c + 2] = a0 ^ a1 ^ _mul2(a2) ^ _mul3(a3);
      s[4 * c + 3] = _mul3(a0) ^ a1 ^ a2 ^ _mul2(a3);
    }
  }

  addRoundKey(0);
  for (var round = 1; round < 10; round++) {
    subShift();
    mixColumns();
    addRoundKey(round * 16);
  }
  subShift();
  addRoundKey(160);
  return s;
}

/// 单块 ECB 解密。
Uint8List _decryptBlock(Uint8List rk, Uint8List block) {
  final s = Uint8List.fromList(block);
  void invShiftSub() {
    // 逆 ShiftRows：行 r 循环右移 r。
    for (var r = 1; r < 4; r++) {
      final row = [s[r], s[r + 4], s[r + 8], s[r + 12]];
      for (var c = 0; c < 4; c++) {
        s[r + 4 * c] = row[(c - r + 4) % 4];
      }
    }
    for (var i = 0; i < 16; i++) {
      s[i] = _invSbox[s[i]];
    }
  }

  void addRoundKey(int off) {
    for (var i = 0; i < 16; i++) {
      s[i] ^= rk[off + i];
    }
  }

  void invMixColumns() {
    for (var c = 0; c < 4; c++) {
      final a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3];
      s[4 * c] = _gmul(a0, 14) ^ _gmul(a1, 11) ^ _gmul(a2, 13) ^ _gmul(a3, 9);
      s[4 * c + 1] = _gmul(a0, 9) ^ _gmul(a1, 14) ^ _gmul(a2, 11) ^ _gmul(a3, 13);
      s[4 * c + 2] = _gmul(a0, 13) ^ _gmul(a1, 9) ^ _gmul(a2, 14) ^ _gmul(a3, 11);
      s[4 * c + 3] = _gmul(a0, 11) ^ _gmul(a1, 13) ^ _gmul(a2, 9) ^ _gmul(a3, 14);
    }
  }

  addRoundKey(160);
  for (var round = 9; round >= 1; round--) {
    invShiftSub();
    invMixColumns();
    addRoundKey(round * 16);
  }
  invShiftSub();
  addRoundKey(0);
  return s;
}

// ─── 对外 API：AES-128-CBC + PKCS7 ───

class AesCbc {
  AesCbc._();

  /// AES-128-CBC 加密（PKCS7），输出 hex（KUGOU_API §2.1）。
  static String encryptHex(String plaintext, String keyHex, String ivHex) {
    final out = encrypt(
        Uint8List.fromList(utf8.encode(plaintext)),
        _bytesFromHex(keyHex, 'key'),
        _bytesFromHex(ivHex, 'iv'));
    return _toHex(out);
  }

  /// AES-128-CBC 解密（PKCS7），输入 hex。
  static String decryptHex(String cipherHex, String keyHex, String ivHex) {
    final out = decrypt(_bytesFromHex(cipherHex, 'cipher'),
        _bytesFromHex(keyHex, 'key'), _bytesFromHex(ivHex, 'iv'));
    return utf8.decode(out, allowMalformed: true);
  }

  static Uint8List encrypt(
      Uint8List plaintext, Uint8List key, Uint8List iv) {
    try {
      if (iv.length != 16) throw CryptoException('iv must be 16 bytes');
      final rk = _expandKey(key);
      final padded = _pkcs7Pad(plaintext);
      final out = Uint8List(padded.length);
      var prev = Uint8List.fromList(iv);
      for (var off = 0; off < padded.length; off += 16) {
        final block = Uint8List(16);
        for (var i = 0; i < 16; i++) {
          block[i] = padded[off + i] ^ prev[i];
        }
        prev = _encryptBlock(rk, block);
        out.setRange(off, off + 16, prev);
      }
      return out;
    } catch (e) {
      Log.e(_tag, 'aes encrypt failed len=${plaintext.length}', e);
      rethrow;
    }
  }

  static Uint8List decrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    try {
      if (iv.length != 16) throw CryptoException('iv must be 16 bytes');
      if (ciphertext.isEmpty || ciphertext.length % 16 != 0) {
        throw CryptoException('ciphertext not block aligned: ${ciphertext.length}');
      }
      final rk = _expandKey(key);
      final out = Uint8List(ciphertext.length);
      var prev = Uint8List.fromList(iv);
      for (var off = 0; off < ciphertext.length; off += 16) {
        final cur = ciphertext.sublist(off, off + 16);
        final dec = _decryptBlock(rk, cur);
        for (var i = 0; i < 16; i++) {
          out[off + i] = dec[i] ^ prev[i];
        }
        prev = cur;
      }
      return _pkcs7Unpad(out);
    } catch (e) {
      Log.e(_tag, 'aes decrypt failed len=${ciphertext.length}', e);
      rethrow;
    }
  }

  static Uint8List _pkcs7Pad(Uint8List data) {
    final pad = 16 - (data.length % 16);
    final out = Uint8List(data.length + pad)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + pad, pad);
    return out;
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    final pad = data[data.length - 1];
    if (pad < 1 || pad > 16) throw CryptoException('bad pkcs7 pad: $pad');
    for (var i = data.length - pad; i < data.length; i++) {
      if (data[i] != pad) throw CryptoException('bad pkcs7 pad bytes');
    }
    return Uint8List.sublistView(data, 0, data.length - pad);
  }
}

// ─── RSA 裸模幂（no padding，KUGOU_API §2.2 cryptoRSAEncrypt） ───

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
class BigIntL {
  BigIntL(List<int> limbs, {bool littleEndian = true})
      : limbs = _normalize(List<int>.from(limbs));

  /// 每元素 0..0xffffffff，低 limb 在前。
  final List<int> limbs;

  static List<int> _normalize(List<int> l) {
    while (l.isNotEmpty && l.last == 0) {
      l.removeLast();
    }
    if (l.isEmpty) l.add(0);
    return l;
  }

  static BigIntL fromHex(String hex) {
    final l = <int>[];
    for (var i = hex.length; i > 0; i -= 8) {
      final start = i - 8 < 0 ? 0 : i - 8;
      l.add(int.parse(hex.substring(start, i), radix: 16));
    }
    return BigIntL(l);
  }

  bool get isZero => limbs.length == 1 && limbs[0] == 0;
  int get bitLength {
    final top = limbs.last;
    var bits = (limbs.length - 1) * 32;
    var t = top;
    while (t > 0) {
      bits++;
      t >>= 1;
    }
    return bits;
  }

  int _cmp(BigIntL o) {
    if (limbs.length != o.limbs.length) {
      return limbs.length > o.limbs.length ? 1 : -1;
    }
    for (var i = limbs.length - 1; i >= 0; i--) {
      if (limbs[i] != o.limbs[i]) {
        return limbs[i] > o.limbs[i] ? 1 : -1;
      }
    }
    return 0;
  }

  BigIntL sub(BigIntL o) {
    final r = List<int>.filled(limbs.length, 0);
    var borrow = 0;
    for (var i = 0; i < limbs.length; i++) {
      var d = limbs[i] - (i < o.limbs.length ? o.limbs[i] : 0) - borrow;
      if (d < 0) {
        d += 0x100000000;
        borrow = 1;
      } else {
        borrow = 0;
      }
      r[i] = d;
    }
    return BigIntL(r);
  }

  BigIntL shl1() {
    final r = List<int>.filled(limbs.length + 1, 0);
    var carry = 0;
    for (var i = 0; i < limbs.length; i++) {
      r[i] = ((limbs[i] << 1) | carry) & 0xffffffff;
      carry = limbs[i] >>> 31;
    }
    r[limbs.length] = carry;
    return BigIntL(r);
  }

  BigIntL mul(BigIntL o) {
    final r = List<int>.filled(limbs.length + o.limbs.length + 1, 0);
    for (var i = 0; i < limbs.length; i++) {
      var carry = 0;
      for (var j = 0; j < o.limbs.length; j++) {
        final t = r[i + j] + limbs[i] * o.limbs[j] + carry;
        // Dart int 64 位：拆高 32。
        r[i + j] = t & 0xffffffff;
        carry = t >>> 32;
      }
      var k = i + o.limbs.length;
      while (carry > 0) {
        final t = r[k] + carry;
        r[k] = t & 0xffffffff;
        carry = t >>> 32;
        k++;
      }
    }
    return BigIntL(r);
  }

  BigIntL mod(BigIntL m) {
    if (m.isZero) throw CryptoException('mod by zero');
    if (_cmp(m) < 0) return this;
    // 二进制长除法（模幂次数低，够用）。
    var rem = BigIntL([0]);
    final bl = bitLength;
    for (var i = bl - 1; i >= 0; i--) {
      rem = rem.shl1();
      if (_bit(i) != 0) {
        rem.limbs[0] |= 1;
      }
      if (rem._cmp(m) >= 0) {
        rem = rem.sub(m);
      }
    }
    return rem;
  }

  int _bit(int i) => (limbs[i >> 5] >>> (i & 31)) & 1;

  BigIntL modPow(BigIntL e, BigIntL m) {
    var base = mod(m);
    var result = BigIntL([1]).mod(m);
    for (var i = 0; i < e.bitLength; i++) {
      if (e._bit(i) != 0) {
        result = result.mul(base).mod(m);
      }
      base = base.mul(base).mod(m);
    }
    return result;
  }

  /// 大端 hex（按 limb 高→低）。
  String toHex({int padBytes = 0}) {
    final top = limbs.last;
    var s = top.toRadixString(16);
    if (s.length.isOdd) s = '0$s';
    for (var i = limbs.length - 2; i >= 0; i--) {
      s += limbs[i].toRadixString(16).padLeft(8, '0');
    }
    if (padBytes > 0 && s.length < padBytes * 2) {
      s = s.padLeft(padBytes * 2, '0');
    }
    return s;
  }
}

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

String _toHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _bytesFromHex(String hex, String what) {
  final h = hex.replaceAll(' ', '').toLowerCase();
  if (h.length.isOdd) throw CryptoException('bad hex $what: odd length');
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
