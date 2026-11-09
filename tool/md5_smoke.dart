// 纯 Dart 冒烟测试（本地无 Flutter test runner，用 dart 直接跑）
// CI 上等价测试在 test/signing_test.dart（flutter test）
import 'dart:convert';

String md5Hex(String s) => _Md5.hex(utf8.encode(s));

void main() {
  void eq(Object a, Object b, String name) {
    final ok = a.toString() == b.toString();
    // ignore: avoid_print
    print('${ok ? "PASS" : "FAIL"} $name: $a${ok ? "" : " != $b"}');
    if (!ok) throw StateError(name);
  }

  // MD5 标准向量
  eq(md5Hex(''), 'd41d8cd98f00b204e9800998ecf8427e', 'md5 empty');
  eq(md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72', 'md5 abc');
  eq(md5Hex('The quick brown fox jumps over the lazy dog'),
      '9e107d9d372bb6826bd81d3542a419d6', 'md5 fox');
  eq(md5Hex('a' * 1000), 'cabe45dcc9ae5b66ba86600cca6b8ba8', 'md5 long');
}

class _Md5 {
  static const _s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  static const _k = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
    0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
    0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
    0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
    0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
    0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  static String hex(List<int> msg) {
    var ml = msg.length;
    final data = List<int>.from(msg)..add(0x80);
    while (data.length % 64 != 56) {
      data.add(0);
    }
    final bl = ml * 8;
    for (var i = 0; i < 8; i++) {
      data.add((bl >>> (8 * i)) & 0xff);
    }
    var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
    for (var chunk = 0; chunk < data.length; chunk += 64) {
      final m = List<int>.filled(16, 0);
      for (var j = 0; j < 16; j++) {
        m[j] = data[chunk + j * 4] |
            (data[chunk + j * 4 + 1] << 8) |
            (data[chunk + j * 4 + 2] << 16) |
            (data[chunk + j * 4 + 3] << 24);
      }
      var a = a0, b = b0, c = c0, d = d0;
      for (var i = 0; i < 64; i++) {
        int f, g;
        if (i < 16) {
          f = (b & c) | (~b & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | (~d & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | ~d);
          g = (7 * i) % 16;
        }
        f = (f + a + _k[i] + m[g]) & 0xffffffff;
        a = d; d = c; c = b;
        b = (b + ((f << _s[i]) | (f >>> (32 - _s[i])))) & 0xffffffff;
      }
      a0 = (a0 + a) & 0xffffffff;
      b0 = (b0 + b) & 0xffffffff;
      c0 = (c0 + c) & 0xffffffff;
      d0 = (d0 + d) & 0xffffffff;
    }
    String le(int v) => List.generate(
        4, (i) => ((v >>> (8 * i)) & 0xff).toRadixString(16).padLeft(2, '0'))
        .join();
    return le(a0) + le(b0) + le(c0) + le(d0);
  }
}
