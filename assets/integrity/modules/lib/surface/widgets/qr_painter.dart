// L6 surface/widgets · 纯 Dart QR Code 编码器 + CustomPainter 渲染（零第三方依赖）。
//
// ── 支持范围（最小可用编码器）──────────────────────────────────────────────
// · 版本：1-4（矩阵尺寸 = 17 + 4*version，即 21/25/29/33）
// · 模式：仅 Byte（8-bit byte mode，UTF-8 编码）
// · 纠错等级：L（默认）/ M（ecLevelM:true）
// · 掩码：固定 mask 0（(x+y)%2==0 → 反转）——不做最优掩码选择
// · 版本信息：版本 ≥7 才需要，1-4 不编码
// · 长度上限（UTF-8 字节）：V1-L 17 / V1-M 14 / V2-L 32 / V2-M 26 /
//   V3-L 53 / V3-M 42 / V4-L 78 / V4-M 62。超出抛 QrException。
//   酷狗扫码 URL（https://h5.kugou.com/queue/index.html?appid=1014 ≈ 45B）
//   落在 V3-L/V3-M 内，满足登录场景。
// · 限制：无自动版本升级、无 Numeric/Alpha 模式压缩、无最优掩码。
//
// ── 自测锚点（编码步骤与可验证不变量，供主会话审查）──────────────────────
// 1. 版本选择：最小 v 使 len ≤ cap[v]；不变量：size == 17 + 4*version。
// 2. bitstream = 0100 + [8bit 长度] + bytes + terminator(≤4 个 0) + 补齐
//    字节边界 + 0xEC/0x11 交替填充至 dataCodewords（L:19/34/55/80；
//    M:16/28/44/64）。
// 3. Reed-Solomon（GF(256)，本原多项式 0x11D）追加纠错码字
//    （L:7/10/15/20；M:10/16/26/36，V4-M 为 2 块×18）。
// 4. 矩阵不变量：
//    · 三个 finder 7x7（黑框-白环-3x3 黑心）+ 各一圈白分隔符；
//    · timing：row 6 / col 6 在 (8..size-9) 区间黑白交替，(6,6) 处由
//      finder 覆盖；
//    · alignment（V2:(18,18) V3:(22,22) V4:(26,26)）：5x5 黑框+白环+
//      黑心；
//    · 暗模块 (size-8, 8) 恒为黑（Nayuki 语义，覆盖第二份格式信息 bit7）；
//    · 格式信息 15bit：data=(ecBits<<3)|mask（L=01 M=00），BCH 除式
//      0x537（x^10+x^8+x^5+x^4+x^2+x+1）求余，XOR 0x5412。
//      副本1（LSB=bit0）：bit0-5→(8,0..5)、bit6→(8,7)、bit7→(8,8)、
//      bit8→(7,8)、bit9-14→(14-i,8)；副本2：bit0-7→(size-1-i,8)、
//      bit8-14→(8,size-15+i)。不变量：副本1 bit0 == ecBits 的 bit0
//      （L→1，M→0），副本1 bit3(即数据位) XOR 掩码相关位后与副本2一致。
// 5. 数据放置：自右下双列向上蛇形（右侧列先），跳过 col 6（该列对取
//    col 5/7），仅写入非功能模块单元。
// 6. 掩码 0：dark != ((x+y)%2==0)。
// 7. 已知参考：'HELLO WORLD'（11 字节）→ V1-Q 超出本实现范围；可对照
//    nayuki/QR-Code-generator（同布局算法）以 V1-L/M 数据交叉验证。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.qr';

/// 编码结果：模块矩阵 + 深色判定函数。
class QrMatrix {
  const QrMatrix(this.size, this.isDark);
  final int size;
  final bool Function(int x, int y) isDark;
}

/// QR 编码异常（数据过长等）。
class QrException implements Exception {
  const QrException(this.msg);
  final String msg;
  @override
  String toString() => 'QrException: $msg';
}

/// QR 编码入口（版本1-4 / Byte / EC L|M / mask 0）。
QrMatrix encodeQr(String data, {bool ecLevelM = false}) {
  try {
    final bytes = Uint8List.fromList(utf8.encode(data));
    final cap = ecLevelM ? _capM : _capL;
    var version = 0;
    for (var v = 1; v <= 4; v++) {
      if (bytes.length <= cap[v]) {
        version = v;
        break;
      }
    }
    if (version == 0) {
      throw QrException('data too long (${bytes.length}B) for QR v1-4');
    }
    final dataCw = _dataCodewords(version, ecLevelM);
    final ecCw = _ecCodewords(version, ecLevelM);
    final blocks = _blocks(version, ecLevelM);
    final codewords = _buildCodewords(bytes, dataCw, ecCw, blocks);
    final modules = _buildMatrix(version, codewords, ecLevelM);
    final size = 17 + 4 * version;
    return QrMatrix(size, (x, y) {
      if (x < 0 || y < 0 || x >= size || y >= size) return false;
      return modules[y * size + x] == 1 ||
          modules[y * size + x] == 3 ||
          modules[y * size + x] == 6; // 数据黑（5=数据白）
    });
  } catch (e, st) {
    Log.e(_tag, 'encodeQr failed len=${data.length}', e, st);
    rethrow;
  }
}

// 字节容量表（索引 = 版本 1..4）。
const List<int> _capL = <int>[0, 17, 32, 53, 78];
const List<int> _capM = <int>[0, 14, 26, 42, 62];

int _dataCodewords(int v, bool m) =>
    m ? const [0, 16, 28, 44, 64][v] : const [0, 19, 34, 55, 80][v];

int _ecCodewords(int v, bool m) =>
    m ? const [0, 10, 16, 26, 36][v] : const [0, 7, 10, 15, 20][v];

int _blocks(int v, bool m) =>
    m ? const [0, 1, 1, 1, 2][v] : const [0, 1, 1, 1, 1][v];

// ── 码字构造 ─────────────────────────────────────────────────────────────

Uint8List _buildCodewords(Uint8List bytes, int dataCw, int ecCw, int blocks) {
  final bitBuf = <bool>[];
  void put(int value, int len) {
    for (var i = len - 1; i >= 0; i--) {
      bitBuf.add(((value >> i) & 1) == 1);
    }
  }

  put(0x4, 4); // byte mode
  put(bytes.length, 8); // v1-9 用 8bit 计数
  for (final b in bytes) {
    put(b, 8);
  }
  for (var i = 0; i < 4 && bitBuf.length < dataCw * 8; i++) {
    bitBuf.add(false); // terminator
  }
  while (bitBuf.length % 8 != 0) {
    bitBuf.add(false);
  }
  final cw = <int>[];
  for (var i = 0; i < bitBuf.length; i += 8) {
    var v = 0;
    for (var j = 0; j < 8; j++) {
      if (bitBuf[i + j]) v |= 1 << (7 - j);
    }
    cw.add(v);
  }
  var pad = 0;
  while (cw.length < dataCw) {
    cw.add(pad++ % 2 == 0 ? 0xEC : 0x11);
  }
  if (cw.length != dataCw) {
    throw const QrException('codeword count mismatch');
  }
  // RS 纠错：数据块在前、纠错块在后（分块交错拼接）。
  final perBlock = dataCw ~/ blocks;
  final ecPer = ecCw ~/ blocks;
  final out = <int>[];
  for (var b = 0; b < blocks; b++) {
    out.addAll(cw.sublist(b * perBlock, (b + 1) * perBlock));
  }
  for (var b = 0; b < blocks; b++) {
    out.addAll(_rsEncode(cw.sublist(b * perBlock, (b + 1) * perBlock), ecPer));
  }
  return Uint8List.fromList(out);
}

// ── Reed-Solomon（GF(256)，本原多项式 0x11D，系数按次数升序）────────────
const int _gfPrim = 0x11D;
final Uint8List _gfExp = _buildGfExp();
final Uint8List _gfLog = _buildGfLog();

Uint8List _buildGfExp() {
  final e = Uint8List(512);
  var x = 1;
  for (var i = 0; i < 255; i++) {
    e[i] = x;
    x <<= 1;
    if (x & 0x100 != 0) x ^= _gfPrim;
  }
  for (var i = 255; i < 512; i++) {
    e[i] = e[i - 255];
  }
  return e;
}

Uint8List _buildGfLog() {
  final l = Uint8List(256);
  for (var i = 0; i < 255; i++) {
    l[_gfExp[i]] = i;
  }
  return l;
}

int _gmul(int a, int b) =>
    (a == 0 || b == 0) ? 0 : _gfExp[_gfLog[a] + _gfLog[b]];

/// 生成多项式 g(x) = Π (x + a^i), i=0..ecLen-1；数组下标 = 次数，
/// gen[ecLen] == 1（首一）。
List<int> _rsGenPoly(int ecLen) {
  var gen = <int>[1];
  for (var i = 0; i < ecLen; i++) {
    final next = List<int>.filled(gen.length + 1, 0);
    for (var k = 0; k < gen.length; k++) {
      next[k + 1] ^= gen[k]; // × x
      next[k] ^= _gmul(gen[k], _gfExp[i]); // × a^i
    }
    gen = next;
  }
  return gen;
}

/// 多项式长除余数：data[0] 为最高次系数，返回 ecLen 个纠错码字。
Uint8List _rsEncode(List<int> data, int ecLen) {
  final gen = _rsGenPoly(ecLen);
  final rem = List<int>.from(data)..addAll(List<int>.filled(ecLen, 0));
  for (var i = 0; i < data.length; i++) {
    final c = rem[i];
    if (c == 0) continue;
    // gen 的 x^ecLen 项对齐消去 rem[i]，其余项下移。
    for (var j = 0; j < ecLen; j++) {
      rem[i + ecLen - j] ^= _gmul(gen[j], c);
    }
  }
  return Uint8List.fromList(rem.sublist(data.length));
}

// ── 矩阵构建 ─────────────────────────────────────────────────────────────
// 值语义：0=未定 1=数据黑(旧) 2=固定白 3=固定黑 4=格式信息待填
// 5=数据白 6=数据黑（与「未定 0」区分，防止已写白模块被重复覆盖）。
Uint8List _buildMatrix(int version, Uint8List codewords, bool ecLevelM) {
  final size = 17 + 4 * version;
  final m = Uint8List(size * size);
  int at(int x, int y) => m[y * size + x];
  void setv(int x, int y, int v) => m[y * size + x] = v;

  // finder + separator
  void finder(int ox, int oy) {
    for (var dy = -1; dy <= 7; dy++) {
      for (var dx = -1; dx <= 7; dx++) {
        final x = ox + dx, y = oy + dy;
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        final inFinder = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6;
        final dark = inFinder &&
            (dx == 0 || dx == 6 || dy == 0 || dy == 6 ||
                (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4));
        setv(x, y, dark ? 3 : 2);
      }
    }
  }

  finder(0, 0);
  finder(size - 7, 0);
  finder(0, size - 7);

  // timing：row 6 / col 6
  for (var i = 8; i <= size - 9; i++) {
    final dark = i % 2 == 0;
    if (at(6, i) == 0) setv(6, i, dark ? 3 : 2);
    if (at(i, 6) == 0) setv(i, 6, dark ? 3 : 2);
  }

  // alignment（V2+ 单中心）
  const alignCenter = <int, int>{2: 18, 3: 22, 4: 26};
  final c = alignCenter[version];
  if (c != null) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final d = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        setv(c + dx, c + dy, d == 1 ? 2 : 3);
      }
    }
  }

  // 格式信息占位（副本1 + 副本2 区域）
  for (var i = 0; i <= 8; i++) {
    if (i != 6) {
      if (at(8, i) == 0) setv(8, i, 4);
      if (at(i, 8) == 0) setv(i, 8, 4);
    }
  }
  for (var i = 0; i <= 7; i++) {
    setv(size - 1 - i, 8, 4); // 副本2 bit0-7
  }
  for (var i = 8; i < 15; i++) {
    setv(8, size - 15 + i, 4); // 副本2 bit8-14
  }
  setv(size - 8, 8, 3); // 暗模块（覆盖副本2 bit7 槽位，Nayuki 语义）

  // 标准列对（右列，左列）：28/27, 26/25 … 8/7, 5/4, 3/2, 1/0。
  // col 6 为 timing 整列跳过，列对在 6 处断开（不是 (7,5)，也不含 (6,5)）。
  final pairs = <List<int>>[];
  for (var right = size - 2; right >= 8; right -= 2) {
    pairs.add(<int>[right, right - 1]);
  }
  pairs.addAll(<List<int>>[
    <int>[5, 4],
    <int>[3, 2],
    <int>[1, 0],
  ]);
  final totalBits = codewords.length * 8;
  var bitIdx = 0;
  var upward = true;
  for (final pair in pairs) {
    for (var row = 0; row < size; row++) {
      final y = upward ? size - 1 - row : row;
      for (final x in pair) {
        if (x < 0 || x >= size) continue;
        if (at(x, y) != 0) continue; // 功能/格式模块跳过
        final dark = bitIdx < totalBits &&
            ((codewords[bitIdx >> 3] >> (7 - (bitIdx & 7))) & 1) == 1;
        bitIdx++;
        setv(x, y, (dark != ((x + y) % 2 == 0)) ? 6 : 5); // mask 0
      }
    }
    upward = !upward;
  }

  // 格式信息：15bit = ((ec<<3)|mask)*x^10 + BCH余 再 XOR 0x5412。
  final ecBits = ecLevelM ? 0x00 : 0x01; // M=00, L=01
  final data5 = ecBits << 3 | 0; // mask 0
  var rem = data5;
  for (var i = 0; i < 10; i++) {
    rem = (rem << 1) ^ ((rem >> 9 & 1) == 1 ? 0x537 : 0);
  }
  final fmt = ((data5 << 10) | (rem & 0x3FF)) ^ 0x5412;
  int bit(int i) => (fmt >> i) & 1;
  // 副本1
  for (var i = 0; i <= 5; i++) {
    setv(8, i, bit(i) == 1 ? 3 : 2);
  }
  setv(8, 7, bit(6) == 1 ? 3 : 2);
  setv(8, 8, bit(7) == 1 ? 3 : 2);
  setv(7, 8, bit(8) == 1 ? 3 : 2);
  for (var i = 9; i < 15; i++) {
    setv(14 - i, 8, bit(i) == 1 ? 3 : 2);
  }
  // 副本2
  for (var i = 0; i <= 7; i++) {
    setv(size - 1 - i, 8, bit(i) == 1 ? 3 : 2);
  }
  for (var i = 8; i < 15; i++) {
    setv(8, size - 15 + i, bit(i) == 1 ? 3 : 2);
  }
  setv(size - 8, 8, 3); // 暗模块恒黑

  // 兜底：任何未定单元（理论上不存在）置白。
  for (var i = 0; i < m.length; i++) {
    if (m[i] == 0) m[i] = 0;
  }
  return m;
}

// ── Painter ──────────────────────────────────────────────────────────────

/// 黑白模块绘制：quiet zone 4 模块，可选圆角模块。
class QrPainter extends CustomPainter {
  QrPainter(this.matrix, {this.rounded = false});

  final QrMatrix matrix;
  final bool rounded;

  static const int _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final total = matrix.size + _quiet * 2;
      final cell = size.width / total;
      final paintDark = Paint()..color = const Color(0xFF000000);
      for (var y = 0; y < matrix.size; y++) {
        for (var x = 0; x < matrix.size; x++) {
          if (!matrix.isDark(x, y)) continue;
          final rect = Rect.fromLTWH(
              (x + _quiet) * cell, (y + _quiet) * cell, cell, cell);
          if (rounded) {
            canvas.drawRRect(
                RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.3)),
                paintDark);
          } else {
            canvas.drawRect(rect, paintDark);
          }
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'QrPainter.paint failed', e, st);
    }
  }

  @override
  bool shouldRepaint(covariant QrPainter old) =>
      old.matrix.size != matrix.size ||
      old.rounded != rounded ||
      !_sameMatrix(old.matrix, matrix);

  bool _sameMatrix(QrMatrix a, QrMatrix b) {
    if (a.size != b.size) return false;
    for (var y = 0; y < a.size; y++) {
      for (var x = 0; x < a.size; x++) {
        if (a.isDark(x, y) != b.isDark(x, y)) return false;
      }
    }
    return true;
  }
}
