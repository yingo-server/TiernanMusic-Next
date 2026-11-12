// L6 surface/theme · Material Design 3 主题底座（批M1-A）
// 纪律：surface 层只 import package:flutter/material.dart + 桥 + 本层；
//       禁止 import flutter_miuix；异常一律经 bridge_logic 的 Log 留痕，不静默。
// 兼容契约（调用方不改）：保留 TnDims / TnColors / TnText / TnMotion，以及
//   tnLightThemeData / tnDarkThemeData / tnPitchBlackThemeData /
//   tnLightTheme / tnDarkTheme 全部工厂名；返回值改为 M3 ThemeData，
//   由 M1-B 的 MaterialApp(theme: / darkTheme: / themeMode:) 直接接入。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.tn_theme';

// ── 品牌色（M3 seedColor）──
const Color tnPrimary = Color(0xFF7C4DFF); // 音乐紫
const Color tnPrimaryAlt = Color(0xFF3D5AFE); // 备选主色（蓝）
const Color tnOnPrimary = Color(0xFFFFFFFF);

// ── 圆角常量（M3 4dp 网格）──
const double tnRadiusS = 8;
const double tnRadiusM = 12;
const double tnRadiusL = 16;

// ── 间距常量（M3 spacing 4dp 网格）──
const double tnPadS = 8;
const double tnPadM = 12;
const double tnPadL = 16;

// ── M3 Typography 常量（Material Design 3 type scale）──
/// 五类十五档官方 M3 字号 / 字重 / 字距，全部 const：
/// display / headline / title / body / label。
/// ThemeData 另挂 Typography.material2021()，保证内置组件文本层级同属 M3。
class TnTypography {
  TnTypography._();

  static const TextStyle displayLarge = TextStyle(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      height: 1.12);
  static const TextStyle displayMedium = TextStyle(
      fontSize: 45,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.16);
  static const TextStyle displaySmall = TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.22);

  static const TextStyle headlineLarge = TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.25);
  static const TextStyle headlineMedium = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.29);
  static const TextStyle headlineSmall = TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.33);

  static const TextStyle titleLarge = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.27);
  static const TextStyle titleMedium = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.50);
  static const TextStyle titleSmall = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.10,
      height: 1.43);

  static const TextStyle bodyLarge = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.50,
      height: 1.50);
  static const TextStyle bodyMedium = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 1.43);
  static const TextStyle bodySmall = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.40,
      height: 1.33);

  static const TextStyle labelLarge = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.10,
      height: 1.43);
  static const TextStyle labelMedium = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.50,
      height: 1.33);
  static const TextStyle labelSmall = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.50,
      height: 1.45);
}

// ── 动效常量表：全部取 Google M3 官方 Durations / Easing（禁裸 Duration）──
/// 兼容名保留（tn_motion.dart 与各页面仍按 TnMotion.* 取值）。
/// fast=short3(150) / normal=medium1(250) / slow=medium3(350) /
/// extraLong=long2(500)；curve=standard，进出分别 emphasizedDecelerate/Accelerate。
class TnMotion {
  TnMotion._();

  static const Curve curve = Easing.standard;
  static const Curve standard = Easing.standard;
  static const Curve standardAccelerate = Easing.standardAccelerate;
  static const Curve emphasizedDecelerate = Easing.emphasizedDecelerate;
  static const Curve emphasizedAccelerate = Easing.emphasizedAccelerate;

  static const Duration fast = Durations.short3;
  static const Duration normal = Durations.medium1;
  static const Duration slow = Durations.medium3;
  static const Duration extraLong = Durations.long2;
}

// ── 三态 M3 主题工厂（亮 / 暗 / 纯黑 AMOLED）──

/// M3 亮色主题：ColorScheme.fromSeed(品牌紫) + M3 Typography。
ThemeData tnLightThemeData() => _m3Theme(Brightness.light);

/// M3 暗色主题。
ThemeData tnDarkThemeData() => _m3Theme(Brightness.dark);

/// 兼容旧调用名（app_root / 错误页仍可用）。
ThemeData tnLightTheme() => tnLightThemeData();
ThemeData tnDarkTheme() => tnDarkThemeData();

/// M3 纯黑模式（AMOLED）：surface 家族全黑 + 保留品牌紫 primary。
/// 基于暗色 seed 生成，失败 Log 留痕并回退暗色主题，不静默吞。
ThemeData tnPitchBlackThemeData() {
  try {
    return _m3Theme(Brightness.dark, pitchBlack: true);
  } catch (e, st) {
    Log.e(_tag, 'pitch-black theme build failed, fallback dark', e, st);
    return tnDarkThemeData();
  }
}

/// 三态共用实现：ColorScheme.fromSeed 是唯一色彩真源；
/// ThemeData(useMaterial3:true) + Typography.material2021() + M3 组件主题。
ThemeData _m3Theme(Brightness brightness, {bool pitchBlack = false}) {
  try {
    final ColorScheme seed = ColorScheme.fromSeed(
      seedColor: tnPrimary,
      brightness: brightness,
    );
    final ColorScheme scheme = pitchBlack
        ? seed.copyWith(
            surface: TnColors.pitchBlack,
            onSurface: TnColors.pitchOn,
            onSurfaceVariant: TnColors.pitchOn.withValues(alpha: 0.72),
            surfaceContainerLowest: TnColors.pitchBlack,
            surfaceContainerLow: TnColors.pitchBlack,
            surfaceContainer: TnColors.pitchBlack,
            surfaceContainerHigh: TnColors.pitchBlack,
            surfaceContainerHighest: TnColors.pitchBlack,
          )
        : seed;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      typography: Typography.material2021(),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: scheme.surfaceTint,
        indicatorColor: scheme.secondaryContainer,
        elevation: 3,
        height: 80,
      ),
    );
  } catch (e, st) {
    Log.e(_tag, 'M3 theme build failed, fallback plain ThemeData', e, st);
    return ThemeData(useMaterial3: true, brightness: brightness);
  }
}

/// 文本主题分级：标题 / 正文 / 辅助，取 M3 TextTheme 三档角色。
///   final t = TnText.of(context);
///   Text('标题', style: t.title); Text('正文', style: t.body); ...
class TnText {
  TnText._(this.title, this.body, this.aux);
  final TextStyle title;
  final TextStyle body;
  final TextStyle aux;

  static TnText of(BuildContext context) {
    try {
      final theme = Theme.of(context);
      final tt = theme.textTheme;
      final cs = theme.colorScheme;
      return TnText._(
        (tt.titleMedium ?? TnTypography.titleMedium).copyWith(
            fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
        (tt.bodyMedium ?? TnTypography.bodyMedium)
            .copyWith(color: cs.onSurface),
        (tt.bodySmall ?? TnTypography.bodySmall)
            .copyWith(color: cs.onSurfaceVariant),
      );
    } catch (e, st) {
      Log.e(_tag, 'TnText.of failed, fallback M3 typography constants', e, st);
      return TnText._(TnTypography.titleMedium, TnTypography.bodyMedium,
          TnTypography.bodySmall);
    }
  }
}

// ── 设计令牌表：集中收敛 surface 层硬编码尺寸/颜色（兼容名保留）──
/// 与 tnPad*/tnRadius* 保持一致的别名表；新代码优先用本表。
class TnDims {
  TnDims._();
  // 间距（M3 4dp 网格）
  static const double padXS = 4;
  static const double padS = tnPadS; // 8
  static const double padM = tnPadM; // 12
  static const double padL = tnPadL; // 16
  static const double padXL = 24;
  // 圆角（M3 四档）
  static const double rXS = 4;
  static const double rS = tnRadiusS; // 8
  static const double rM = tnRadiusM; // 12
  static const double rL = tnRadiusL; // 16
  static const double rXL = 28;
  // 图标 / 封面 / 栏高（M3 TopAppBar=64 / NavigationBar=80）
  static const double iconS = 18;
  static const double iconM = 24;
  static const double coverS = 110;
  static const double barH = 56;
  static const double topAppBarH = 64;
  static const double navBarH = 80;

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

/// 占位 / 纯黑色板颜色令牌。
class TnColors {
  TnColors._();
  static const Color pitchBlack = Color(0xFF000000);
  static const Color pitchOn = Color(0xFFEDEDED);
  static const Color placeholder = Color(0xFFBDBDBD);
}
