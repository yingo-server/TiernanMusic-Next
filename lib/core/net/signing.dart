// L4 core/net 级 · 酷狗原生 API 签名引擎
// 知识来源：docs/KUGOU_API.md §1（逐字实现，含测试锚点）
// 原则：SDK 优先（dart:convert md5 自实现，crypto 包不引入）
import 'dart:convert';

class KugouSign {
  KugouSign._();

  // ── 盐常量（docs/KUGOU_API.md §1.1）──
  static const androidSalt = 'OIlwieks28dk2k092lksi2UIkp';
  static const webSalt = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
  static const registerSalt = '1014';
  static const signKeySalt = '57ae12eb6890223e355ccfcb74edf70d';
  static const trackerKeySalt = '185672dd44712f60bb1736df5a377e82';
  static const signParamsSalt = 'R6snCXJgbCaj9WFRJKefTMIFp0ey6Gza';

  // ── 设备常量（config.json）──
  static const appid = '1005';
  static const clientver = '20489';
  static const srcappid = '2919';
  static const defaultUa = 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';

  /// Android 签名（§1.2）：参数名 ASCII 升序 k=v 无分隔拼接，
  /// 对象值 JSON 序列化；GET body 空串 / POST body JSON 原文；md5(salt+s+body+salt)。
  static String android(Map<String, Object?> params,
      {String body = '', String salt = androidSalt}) {
    final keys = params.keys.toList()..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      final v = params[k];
      final vs = (v is Map || v is List) ? jsonEncode(v) : '$v';
      sb.write('$k=$vs');
    }
    return md5Hex(salt + sb.toString() + body + salt);
  }

  /// Web 签名（§1.3）：先拼 "k=v" 串再整体排序后拼接。
  static String web(Map<String, Object?> params) {
    final parts =
        params.entries.map((e) => '${e.key}=${e.value}').toList()..sort();
    return md5Hex(webSalt + parts.join('') + webSalt);
  }

  /// Register 签名（§1.4）：只排序"值"，不含键名。
  static String register(Map<String, Object?> params) {
    final values = params.values.map((v) => '$v').toList()..sort();
    return md5Hex(registerSalt + values.join('') + registerSalt);
  }

  /// play_url key（§1.5）：md5(hash + 盐 + appid + mid + userid)
  static String playKey(String hash, String mid, String userid,
      {bool lite = false}) {
    final salt = lite ? trackerKeySalt : signKeySalt;
    return md5Hex('$hash$salt$appid$mid${userid.isEmpty ? '0' : userid}');
  }

  /// signParamsKey（§1.6）：md5(appid + androidSalt + clientver + clienttimeMs)
  static String signParamsKey(String clienttimeMs) =>
      md5Hex('$appid$androidSalt$clientver$clienttimeMs');
}

/// 纯 Dart MD5（RFC 1321），输出小写 hex。SDK 自实现，≤120 行。
class Md5 {
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

  static String hex(String input) => hexBytes(utf8.encode(input));

  static String hexBytes(List<int> msg) {
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
        a = d;
        d = c;
        c = b;
        b = (b + ((f << _s[i]) | (f >>> (32 - _s[i])))) & 0xffffffff;
      }
      a0 = (a0 + a) & 0xffffffff;
      b0 = (b0 + b) & 0xffffffff;
      c0 = (c0 + c) & 0xffffffff;
      d0 = (d0 + d) & 0xffffffff;
    }
    String le(int v) {
      final out = StringBuffer();
      for (var i = 0; i < 4; i++) {
        out.write(((v >>> (8 * i)) & 0xff).toRadixString(16).padLeft(2, '0'));
      }
      return out.toString();
    }

    return le(a0) + le(b0) + le(c0) + le(d0);
  }
}

String md5Hex(String s) => Md5.hex(s);
