// L6 surface/theme · 封面主色提取 + 动态调色板（纯 Dart 自实现，零第三方包）
// GAP #19 封面取色/动态主题：RGBA8888 字节 → 32 级色桶直方图 → 主色 → HSL 调色板。
// 分层：仅本 surface 文件 import package:flutter/material.dart（取 Color 类型）；
//       Log 沿用既有惯例经 bridge_logic（L5⇅L6 桥导出 kernel.Log）取得，
//       不 import core/logic/kernel 内部文件，不新增跨更高层依赖。
import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.color';

/// 主色种子（RGB 各 0..255）；[fallback] 为品牌紫 #7C4DFF。
class ColorSeed {
  const ColorSeed(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  /// 空输入 / 畸形输入 / 异常时的默认紫（对齐 tn_theme.tnPrimary）。
  static const ColorSeed fallback = ColorSeed(0x7C, 0x4D, 0xFF);

  Color toColor() {
    try {
      final int value = 0xFF000000 |
          ((r & 0xFF) << 16) |
          ((g & 0xFF) << 8) |
          (b & 0xFF);
      return Color(value);
    } catch (e, st) {
      Log.e(_tag, 'ColorSeed.toColor failed', e, st);
      return const Color(0xFF7C4DFF);
    }
  }

  @override
  String toString() => 'ColorSeed($r,$g,$b)';
}

/// 由主色推导的四色调色板（供 M3 ThemeData.colorScheme 使用）。
class ThemePalette {
  const ThemePalette({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.surface,
    this.dark = false,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color surface;
  final bool dark;
}

/// 纯 Dart 像素采样主色提取。
/// [rgbaBytes]：RGBA8888，每像素 4 字节，顺序 r,g,b,a；[width]/[height] 为像素数。
/// 采样：每 N 像素取一点，N = max(1, w*h/4096)（整数截断），样本上限约 4096。
/// 过滤：近黑(max<28)、近白(min>236)、低饱和(max-min<24)、近透明(a<96) 跳过。
/// 统计：r/g/b 各按 32 级分桶（>>3）做直方图，取样本数最多桶的通道均值。
/// 空/畸形输入或异常一律返回默认紫 #7C4DFF，且必 Log 留痕（不静默吞）。
ColorSeed extractDominant(List<int> rgbaBytes, int width, int height) {
  try {
    if (rgbaBytes.isEmpty || width <= 0 || height <= 0) {
      Log.w(_tag, 'extractDominant: empty/invalid size, fallback purple');
      return ColorSeed.fallback;
    }
    final int total = width * height;
    if (total <= 0 || rgbaBytes.length < total * 4) {
      Log.w(_tag, 'extractDominant: malformed RGBA length '
          '${rgbaBytes.length} < ${total * 4}, fallback purple');
      return ColorSeed.fallback;
    }
    int step = total ~/ 4096;
    if (step < 1) step = 1;

    final Map<int, _Bucket> buckets = <int, _Bucket>{};
    int sampled = 0;
    for (int p = 0; p < total; p += step) {
      final int o = p * 4;
      if (o + 3 >= rgbaBytes.length) break; // 畸形尾部防御
      final int a = rgbaBytes[o + 3] & 0xFF;
      if (a < 96) continue;
      final int r = rgbaBytes[o] & 0xFF;
      final int g = rgbaBytes[o + 1] & 0xFF;
      final int b = rgbaBytes[o + 2] & 0xFF;
      final int mx = math.max(r, math.max(g, b));
      final int mn = math.min(r, math.min(g, b));
      if (mx < 28 || mn > 236 || mx - mn < 24) continue;
      final int key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      buckets.putIfAbsent(key, () => _Bucket()).add(r, g, b);
      sampled++;
    }
    if (sampled == 0) {
      Log.w(_tag, 'extractDominant: no colorful samples, fallback purple');
      return ColorSeed.fallback;
    }
    _Bucket? best;
    for (final _Bucket bucket in buckets.values) {
      final _Bucket? current = best;
      if (current == null || bucket.count > current.count) best = bucket;
    }
    final _Bucket? winner = best;
    if (winner == null) {
      Log.w(_tag, 'extractDominant: empty histogram, fallback purple');
      return ColorSeed.fallback;
    }
    final ColorSeed seed = ColorSeed(
      winner.sumR ~/ winner.count,
      winner.sumG ~/ winner.count,
      winner.sumB ~/ winner.count,
    );
    Log.d(_tag, 'extractDominant: seed=$seed step=$step '
        'samples=$sampled buckets=${buckets.length}');
    return seed;
  } catch (e, st) {
    Log.e(_tag, 'extractDominant crashed', e, st);
    return ColorSeed.fallback;
  }
}

/// 直方图桶：累计通道和与样本数，用于取均值。
class _Bucket {
  int count = 0;
  int sumR = 0;
  int sumG = 0;
  int sumB = 0;

  void add(int r, int g, int b) {
    count++;
    sumR += r;
    sumG += g;
    sumB += b;
  }
}

/// HSL 明暗推导：primary / onPrimary / primaryContainer / surface 四色。
/// dark=true：主色提亮、容器与底色压暗；dark=false：主色定在中明度、底色近白。
/// [dark] 命名参数默认 false（亮色）；主会话按 themeModeProvider 传入。
ThemePalette fromSeed(ColorSeed seed, {bool dark = false}) {
  try {
    final List<double> hsl =
        _rgbToHsl(seed.r & 0xFF, seed.g & 0xFF, seed.b & 0xFF);
    final double h = hsl[0];
    final double s = math.min(0.92, math.max(0.36, hsl[1]));
    final double primaryL = dark ? 0.62 : 0.46;
    final Color primary = _hslToColor(h, s, primaryL);
    final Color onPrimary =
        _hslToColor(h, s * 0.18, primaryL > 0.55 ? 0.12 : 0.98);
    final Color primaryContainer =
        _hslToColor(h, s * 0.55, dark ? 0.28 : 0.88);
    final Color surface = _hslToColor(h, s * 0.10, dark ? 0.11 : 0.97);
    Log.d(_tag, 'fromSeed: seed=$seed dark=$dark');
    return ThemePalette(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      surface: surface,
      dark: dark,
    );
  } catch (e, st) {
    Log.e(_tag, 'fromSeed failed', e, st);
    return _fallbackPalette(dark);
  }
}

/// 推导失败时的品牌紫常量表（与 tn_theme.dart 亮暗取值一致）。
ThemePalette _fallbackPalette(bool dark) => ThemePalette(
      primary: const Color(0xFF7C4DFF),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer:
          dark ? const Color(0xFF372A5E) : const Color(0xFFEDE7FF),
      surface: dark ? const Color(0xFF14121C) : const Color(0xFFF7F5FC),
      dark: dark,
    );

// ── HSL 工具（纯 Dart，无 dart:ui / 第三方依赖）──

/// 返回 [h(0..1), s(0..1), l(0..1)]；h × 360 即色相角度。
List<double> _rgbToHsl(int r, int g, int b) {
  final double rf = r / 255.0;
  final double gf = g / 255.0;
  final double bf = b / 255.0;
  final double mx = math.max(rf, math.max(gf, bf));
  final double mn = math.min(rf, math.min(gf, bf));
  final double l = (mx + mn) / 2.0;
  final double d = mx - mn;
  if (d == 0) return <double>[0.0, 0.0, l];
  final double s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
  double h;
  if (mx == rf) {
    h = (gf - bf) / d + (gf < bf ? 6.0 : 0.0);
  } else if (mx == gf) {
    h = (bf - rf) / d + 2.0;
  } else {
    h = (rf - gf) / d + 4.0;
  }
  h = (h / 6.0) % 1.0;
  return <double>[h, _clamp01(s), _clamp01(l)];
}

double _clamp01(double v) => v < 0 ? 0.0 : (v > 1.0 ? 1.0 : v);

Color _hslToColor(double h, double s, double l) {
  final double ss = _clamp01(s);
  final double ll = _clamp01(l);
  double r;
  double g;
  double b;
  if (ss == 0) {
    r = ll;
    g = ll;
    b = ll;
  } else {
    final double q = ll < 0.5 ? ll * (1.0 + ss) : ll + ss - ll * ss;
    final double p = 2.0 * ll - q;
    r = _hue(p, q, h + 1.0 / 3.0);
    g = _hue(p, q, h);
    b = _hue(p, q, h - 1.0 / 3.0);
  }
  return ColorSeed(_byte(r), _byte(g), _byte(b)).toColor();
}

int _byte(double v) => (v * 255.0).round().clamp(0, 255).toInt();

double _hue(double p, double q, double t) {
  double x = t % 1.0;
  if (x < 0) x += 1.0;
  if (x < 1.0 / 6.0) return p + (q - p) * 6.0 * x;
  if (x < 0.5) return q;
  if (x < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - x) * 6.0;
  return p;
}
