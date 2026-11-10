// QR 编码器自洽回归测试（纯 Dart，零第三方依赖；CI 上 flutter test 会跑）。
// 验证方式：encodeQr → 独立解码器（读格式信息取掩码 → 按标准布局读数据位 →
// 反掩码 → 解析 mode/length/UTF-8），还原字符串与输入一致即证明编码自洽可扫。
// 2026-11-10：批1-C 审查时以纯 Python 独立解码器交叉验证通过（酷狗登录 URL 48B / V3-L）。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiernan_music_next/surface/widgets/qr_painter.dart';

void main() {
  const cases = <String>[
    'HELLO',
    'https://h5.kugou.com/queue/index.html?appid=1014',
    'TiernanMusic-Next QR login 26.11.10',
    'https://h5.kugou.com/queue/index.html?appid=1014&t=1234567890&k=abcdef',
  ];

  for (final data in cases) {
    test('QR round-trip: ${data.hashCode}', () {
      final m = encodeQr(data);
      expect(m.size % 4, 1); // size = 17 + 4*version
      expect(m.size >= 21 && m.size <= 33, true); // v1-4
      expect(_decode(m), data);
    });
  }

  test('QR finder / timing / format invariants', () {
    final m = encodeQr('TEST');
    final s = m.size;
    // 三个 finder 的 7x7 边框与中心
    for (final o in <List<int>>[
      <int>[0, 0],
      <int>[s - 7, 0],
      <int>[0, s - 7],
    ]) {
      for (var d = 0; d < 7; d++) {
        expect(m.isDark(o[0] + d, o[1]), true); // 上边
        expect(m.isDark(o[0] + d, o[1] + 6), true); // 下边
        expect(m.isDark(o[0], o[1] + d), true); // 左边
        expect(m.isDark(o[0] + 6, o[1] + d), true); // 右边
      }
      for (var y = 2; y <= 4; y++) {
        for (var x = 2; x <= 4; x++) {
          expect(m.isDark(o[0] + x, o[1] + y), true); // 3x3 黑心
        }
      }
    }
    // timing 交替
    for (var i = 8; i <= s - 9; i++) {
      expect(m.isDark(i, 6), i.isEven);
      expect(m.isDark(6, i), i.isEven);
    }
    // 暗模块恒黑
    expect(m.isDark(s - 8, 8), true);
  });
}

/// 独立解码器：不复用编码器任何内部函数，只按 QR 规范读矩阵。
String _decode(QrMatrix m) {
  final s = m.size;
  int bit(int x, int y) => m.isDark(x, y) ? 1 : 0;

  // 格式信息副本1 → 掩码号（BCH 解码后取 data5 低 3 位）
  var f = 0;
  for (var i = 0; i < 6; i++) {
    f |= bit(8, i) << i;
  }
  f |= bit(8, 7) << 6;
  f |= bit(8, 8) << 7;
  f |= bit(7, 8) << 8;
  for (var i = 9; i < 15; i++) {
    f |= bit(14 - i, 8) << i;
  }
  final mask = ((f ^ 0x5412) >> 10) & 7;
  if (mask != 0) {
    throw StateError('unexpected mask $mask (encoder fixed mask 0)');
  }

  bool isFunc(int x, int y) {
    if (x == 6 || y == 6) return true;
    if (x <= 8 && y <= 8) return true;
    if (x >= s - 8 && y <= 8) return true;
    if (x <= 8 && y >= s - 8) return true;
    final v = (s - 17) ~/ 4;
    const centers = <int, int>{2: 18, 3: 22, 4: 26};
    final c = centers[v];
    if (c != null && (x - c).abs() <= 2 && (y - c).abs() <= 2) return true;
    return false;
  }

  final pairs = <List<int>>[];
  for (var right = s - 2; right >= 8; right -= 2) {
    pairs.add(<int>[right, right - 1]);
  }
  pairs.addAll(<List<int>>[
    <int>[5, 4],
    <int>[3, 2],
    <int>[1, 0],
  ]);
  final bits = <int>[];
  var upward = true;
  for (final pair in pairs) {
    for (var row = 0; row < s; row++) {
      final y = upward ? s - 1 - row : row;
      for (final x in pair) {
        if (isFunc(x, y)) continue;
        bits.add(bit(x, y) ^ ((x + y) % 2 == 0 ? 1 : 0));
      }
    }
    upward = !upward;
  }
  final bs = bits.join();
  final mode = _bin(bs, 0, 4);
  if (mode != 4) throw StateError('expected byte mode, got $mode');
  final len = _bin(bs, 4, 8);
  final payload = bs.substring(12, 12 + len * 8);
  final bytes = <int>[];
  for (var i = 0; i < payload.length; i += 8) {
    bytes.add(_bin(payload, i, 8));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

int _bin(String s, int start, int len) {
  var v = 0;
  for (var i = 0; i < len; i++) {
    v = (v << 1) | (s[start + i] == '1' ? 1 : 0);
  }
  return v;
}
