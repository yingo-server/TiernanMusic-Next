// L7 surface/design · 设计令牌（唯一真源，页面禁止硬编码颜色/字号）
// 风格：Spotify 深色（近黑底 + 绿色主色），M3 组件规范。
import 'package:flutter/material.dart';

/// 设计令牌（命名短、语义单一）。
class Sp {
  Sp._();

  // ── 色彩 ──
  static const Color bg = Color(0xFF0E0F12);
  static const Color bgElevated = Color(0xFF141519);
  static const Color card = Color(0xFF1C1D21);
  static const Color cardHigh = Color(0xFF25272C);
  static const Color divider = Color(0xFF2E3137);
  static const Color text = Color(0xFFEDEFF2);
  static const Color textSub = Color(0xFFA9AFB8);
  static const Color textFaint = Color(0xFF6C737D);
  static const Color green = Color(0xFF1DB954);
  static const Color greenDim = Color(0xFF14833C);
  static const Color red = Color(0xFFE05B5B);
  static const Color orange = Color(0xFFF2A25C);

  // ── 间距 ──
  static const double gapXS = 4;
  static const double gapS = 8;
  static const double gapM = 12;
  static const double gapL = 16;
  static const double gapXL = 24;
  static const double pagePad = 16;

  // ── 圆角 ──
  static const double rS = 4;
  static const double rM = 8;
  static const double rCard = 12;
  static const double rXL = 20;
  static const double rFull = 999;

  // ── 字号 ──
  static const double fTiny = 11;
  static const double fSub = 12;
  static const double fItem = 14;
  static const double fSection = 16;
  static const double fPageTitle = 22;
  static const double fHero = 28;

  // ── 尺寸 ──
  static const double tileCover = 48;
  static const double barH = 60;
  static const double navH = 64;
  static const double artHero = 280;

  // ── 动效 ──
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;

  /// 主题（唯一工厂；AppRoot 只用它）。
  static ThemeData theme() {
    try {
      final scheme = ColorScheme.fromSeed(
        seedColor: green,
        brightness: Brightness.dark,
      ).copyWith(
        surface: bg,
        onSurface: text,
        onSurfaceVariant: textSub,
        surfaceContainerLowest: bgElevated,
        surfaceContainerLow: bgElevated,
        surfaceContainer: card,
        surfaceContainerHigh: cardHigh,
        surfaceContainerHighest: divider,
        primary: green,
        onPrimary: Colors.black,
        error: red,
      );
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: bg,
        dividerColor: divider,
        splashFactory: InkSparkle.splashFactory,
        textTheme: _text(scheme),
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
            fontSize: fPageTitle,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          iconTheme: const IconThemeData(color: text),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: bgElevated,
          surfaceTintColor: Colors.transparent,
          indicatorColor: greenDim,
          height: navH,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontSize: fTiny,
              color: s.contains(WidgetState.selected) ? text : textSub,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? text : textSub,
            ),
          ),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: textSub,
          textColor: text,
          titleTextStyle: const TextStyle(fontSize: fItem, color: text),
          subtitleTextStyle: const TextStyle(fontSize: fSub, color: textSub),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: card,
          side: const BorderSide(color: divider),
          labelStyle: const TextStyle(fontSize: fSub, color: text),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rFull),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontSize: fItem, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rFull),
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: cardHigh,
          contentTextStyle: TextStyle(color: text, fontSize: fSub),
          behavior: SnackBarBehavior.floating,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: green,
          linearMinHeight: 2,
        ),
      );
    } catch (e, st) {
      debugPrint('surface.design: theme build failed: $e');
      return ThemeData(useMaterial3: true, brightness: Brightness.dark);
    }
  }

  static TextTheme _text(ColorScheme s) {
    const base = TextStyle(color: text, fontSize: fItem);
    return TextTheme(
      headlineSmall: base.copyWith(
          fontSize: fPageTitle, fontWeight: FontWeight.w700),
      titleLarge: base.copyWith(fontSize: fSection, fontWeight: FontWeight.w600),
      titleMedium: base.copyWith(fontSize: fItem, fontWeight: FontWeight.w600),
      bodyMedium: base.copyWith(fontSize: fItem),
      bodySmall: base.copyWith(fontSize: fSub, color: textSub),
      labelSmall: base.copyWith(fontSize: fTiny, color: textSub),
    );
  }
}
