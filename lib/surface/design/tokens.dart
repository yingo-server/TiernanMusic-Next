// L7 surface/design · 设计令牌（唯一真源，页面禁止硬编码颜色/字号）
// 风格：Spotify（深色近黑底 + 绿色主色；批1-F1 增加亮色映射）。
// 注意：Sp.bg / Sp.card 等仍为 static const，被 8 个文件 17 处 const 引用；
// 页面 const 色值动态化留批后（亮色页面视觉允许暂不完美，本批不改页面）。
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

  // ── 亮色映射（批1-F1：仅 ThemeData 工厂内部分流，const 令牌仍为深色值） ──
  static const Color _bgLight = Colors.white;
  static const Color _bgElevatedLight = Color(0xFFF7F8FA);
  static const Color _cardLight = Color(0xFFF2F2F2);
  static const Color _cardHighLight = Color(0xFFE8EAEE);
  static const Color _dividerLight = Color(0xFFDCDFE4);
  static const Color _textLight = Color(0xFF111111);
  static const Color _textSubLight = Color(0xFF5F646D);
  static const Color _textFaintLight = Color(0xFF9AA0AA);

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

  /// 主题（唯一工厂；AppRoot 只用它）。dark=false 时用亮色映射。
  static ThemeData theme({bool dark = true}) {
    try {
      final Color bg = dark ? Sp.bg : _bgLight;
      final Color bgElevated = dark ? Sp.bgElevated : _bgElevatedLight;
      final Color card = dark ? Sp.card : _cardLight;
      final Color cardHigh = dark ? Sp.cardHigh : _cardHighLight;
      final Color divider = dark ? Sp.divider : _dividerLight;
      final Color text = dark ? Sp.text : _textLight;
      final Color textSub = dark ? Sp.textSub : _textSubLight;
      final scheme = ColorScheme.fromSeed(
        seedColor: green,
        brightness: dark ? Brightness.dark : Brightness.light,
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
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: scheme,
        scaffoldBackgroundColor: bg,
        dividerColor: divider,
        splashFactory: InkSparkle.splashFactory,
        textTheme: _text(scheme, dark: dark),
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: fPageTitle, fontWeight: FontWeight.w700, color: text),
          iconTheme: IconThemeData(color: text),
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
          titleTextStyle: TextStyle(fontSize: fItem, color: text),
          subtitleTextStyle: TextStyle(fontSize: fSub, color: textSub),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: card,
          side: BorderSide(color: divider),
          labelStyle: TextStyle(fontSize: fSub, color: text),
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
        snackBarTheme: SnackBarThemeData(
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

  static TextTheme _text(ColorScheme s, {bool dark = true}) {
    final base = TextStyle(
        color: dark ? Sp.text : _textLight, fontSize: fItem);
    final sub = dark ? Sp.textSub : _textSubLight;
    return TextTheme(
      headlineSmall: base.copyWith(
          fontSize: fPageTitle, fontWeight: FontWeight.w700),
      titleLarge: base.copyWith(fontSize: fSection, fontWeight: FontWeight.w600),
      titleMedium: base.copyWith(fontSize: fItem, fontWeight: FontWeight.w600),
      bodyMedium: base.copyWith(fontSize: fItem),
      bodySmall: base.copyWith(fontSize: fSub, color: sub),
      labelSmall: base.copyWith(fontSize: fTiny, color: sub),
    );
  }
}
