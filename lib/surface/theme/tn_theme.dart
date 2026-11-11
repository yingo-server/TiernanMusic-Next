// L6 surface 级 · miuix 主题封装（亮/暗两套）+ 设计常量
// 仅 surface 层允许 import flutter_miuix；上层不得引用本文件里的 miuix 类型。
// API 对齐 flutter_miuix 1.3.0 实际导出：MiuixThemeData/MiuixTheme/MiuixColors/MiuixTextStyles。
import 'package:flutter/material.dart' show Brightness, BuildContext, Color, Curve, Curves,
    Duration, FontWeight, TextStyle, EdgeInsets, BorderRadius, VoidCallback;
import 'package:flutter_miuix/miuix.dart';

// ── 品牌色 ──
const Color tnPrimary = Color(0xFF7C4DFF); // 音乐紫
const Color tnPrimaryAlt = Color(0xFF3D5AFE); // 备选主色（蓝色）
const Color tnOnPrimary = Color(0xFFFFFFFF);

// ── 圆角常量 ──
const double tnRadiusS = 8;
const double tnRadiusM = 12;
const double tnRadiusL = 16;

// ── 间距常量 ──
const double tnPadS = 8;
const double tnPadM = 12;
const double tnPadL = 16;

// ── 动效常量表：统一曲线 easeOutCubic ──
class TnMotion {
  TnMotion._();
  static const Curve curve = Curves.easeOutCubic;
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
}

/// miuix 亮色主题数据（MiuixThemeData，供 MiuixTheme 包裹）。
MiuixThemeData tnLightThemeData() => _miuixTheme(Brightness.light);

/// miuix 暗色主题数据。
MiuixThemeData tnDarkThemeData() => _miuixTheme(Brightness.dark);

/// 兼容旧调用名（app_root 用）。
MiuixThemeData tnLightTheme() => tnLightThemeData();
MiuixThemeData tnDarkTheme() => tnDarkThemeData();

/// 纯黑模式（AMOLED）：surface 全黑 + 保留品牌紫 primary。
/// 复用暗色基底并把背景色压到纯黑；失败兜底回暗色主题，不静默。
MiuixThemeData tnPitchBlackThemeData() {
  try {
    final base = tnDarkThemeData();
    final colors = base.colors.copy(
      background: const Color(0xFF000000),
      surface: const Color(0xFF000000),
      surfaceContainer: const Color(0xFF000000),
      onBackground: const Color(0xFFEDEDED),
      primary: tnPrimary,
      onPrimary: tnOnPrimary,
    );
    return base.copyWith(colors: colors);
  } catch (e) {
    assert(() {
      // ignore: avoid_print
      print('surface.tn_theme: pitch-black theme build failed, '
          'fallback to dark: $e');
      return true;
    }());
    return tnDarkThemeData();
  }
}

MiuixThemeData _miuixTheme(Brightness b) {
  try {
    final base = b == Brightness.dark
        ? MiuixThemeData.dark()
        : MiuixThemeData.light();
    final colors = base.colors.copy(
      primary: tnPrimary,
      onPrimary: tnOnPrimary,
      primaryContainer: b == Brightness.light
          ? const Color(0xFFEDE7FF)
          : const Color(0xFF372A5E),
    );
    return base.copyWith(colors: colors);
  } catch (e) {
    assert(() {
      // ignore: avoid_print
      print('surface.tn_theme: theme build failed, fallback: $e');
      return true;
    }());
    return b == Brightness.dark
        ? MiuixThemeData.dark()
        : MiuixThemeData.light();
  }
}

/// 文本主题分级：标题 / 正文 / 辅助。
///   final t = TnText.of(context);
///   Text('标题', style: t.title); Text('正文', style: t.body); ...
class TnText {
  TnText._(this.title, this.body, this.aux);
  final TextStyle title;
  final TextStyle body;
  final TextStyle aux;

  static TnText of(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final onSurface = theme.colors.onBackground;
    final ts = theme.textStyles;
    return TnText._(
      ts.title3.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      ts.body1.copyWith(fontSize: 15),
      ts.body2.copyWith(
          fontSize: 12,
          color: onSurface is Color
              ? onSurface.withValues(alpha: 0.55)
              : null),
    );
  }
}

// ── 设计令牌表（批10-B）：集中收敛 surface 层硬编码尺寸/颜色 ──
/// 与 tnPad*/tnRadius* 保持一致的别名表；新代码优先用本表。
class TnDims {
  TnDims._();
  // 间距
  static const double padXS = 4;
  static const double padS = tnPadS; // 8
  static const double padM = tnPadM; // 12
  static const double padL = tnPadL; // 16
  static const double padXL = 24;
  // 圆角
  static const double rS = tnRadiusS; // 8
  static const double rM = tnRadiusM; // 12
  static const double rL = tnRadiusL; // 16
  // 图标 / 封面 / 栏高
  static const double iconS = 18;
  static const double iconM = 24;
  static const double coverS = 110;
  static const double barH = 56;

  // 常用组合 getter（可选糖）。
  static EdgeInsets get padAllS => const EdgeInsets.all(tnPadS);
  static EdgeInsets get padAllM => const EdgeInsets.all(tnPadM);
  static EdgeInsets get padAllL => const EdgeInsets.all(tnPadL);
  static EdgeInsets get padHL => const EdgeInsets.symmetric(horizontal: tnPadL);
  static EdgeInsets get padHXL => const EdgeInsets.symmetric(horizontal: padXL);
  static BorderRadius get rSBorder => BorderRadius.circular(tnRadiusS);
  static BorderRadius get rMBorder => BorderRadius.circular(tnRadiusM);
  static BorderRadius get rLBorder => BorderRadius.circular(tnRadiusL);
}

/// 占位/纯黑色板颜色令牌。
class TnColors {
  TnColors._();
  static const Color pitchBlack = Color(0xFF000000);
  static const Color pitchOn = Color(0xFFEDEDED);
  static const Color placeholder = Color(0xFFBDBDBD);
}
