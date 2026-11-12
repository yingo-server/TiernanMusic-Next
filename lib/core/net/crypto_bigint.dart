// L4 core/net · 大整数（小端 32-bit limb）——由 crypto_extra.dart 拆出（R2-A）。
// BigIntL 类体逐字搬移，零逻辑改动；依赖 CryptoException（来自 crypto_aes.dart）。
import 'crypto_aes.dart' show CryptoException;

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
