// L6 surface/ui · Spotify 设计语言设计系统（全量重写 UI 架构的唯一真源）
//
// 设计规格（对标 Spotify Android）：
// - 色彩：黑底 #121212，卡片 #1F1F1F / 高亮层 #2A2A2A，主色绿 #1DB954，
//   文字主 #FFFFFF / 次 #B3B3B3；无渐变（除专辑大卡用 surfaceTint 微调）。
// - 排版：页面标题 28sp w900（Spotify 的「大标题滚动收缩」）；区块标题 20sp w700；
//   条目 15sp w500 / 辅助 13sp regular。
// - 形状：卡片圆角 8dp（Spotify 特征：小圆角、非 M3 大圆角）；按钮胶囊；封面方形无圆角（歌单）。
// - 交互：底部 64dp 导航（5 位）；每个条目 trailing = ⋮ 操作；横滑卡片 120dp。
// - 布局：全列表驱动（无 Tab 嵌套），首页 = 垂直区块流 + 横滑行。
// 纪律：只 import flutter/material + 本目录；所有颜色/字号/间距只在本文件定义。
//
// 批5-F1：theme() 增补可选动态调色板与纯黑模式，app_root 统一走这里，
// 消除 Sp.* 硬编码色与 app_root M3 主题两套混搭（21 页消费 Sp.* 不动）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../theme/color_extract.dart' show ThemePalette;

/// Spotify 设计令牌（唯一真源，禁止页面层硬编码颜色/字号）。
abstract class Sp {
  // ── 色彩 ──
  static const Color bg = Color(0xFF121212);
  static const Color card = Color(0xFF1F1F1F);
  static const Color cardHigh = Color(0xFF2A2A2A);
  static const Color green = Color(0xFF1DB954);
  static const Color text = Color(0xFFFFFFFF);
  static const Color textSub = Color(0xFFB3B3B3);
  static const Color textFaint = Color(0xFF7A7A7A);
  static const Color divider = Color(0xFF2E2E2E);
  static const Color red = Color(0xFFE91429);

  // ── 间距 ──
  static const double pagePad = 16;
  static const double gapS = 8;
  static const double gapM = 12;
  static const double gapL = 16;
  static const double gapXL = 24;

  // ── 尺寸 ──
  static const double navH = 64;
  static const double barH = 60;
  static const double cardCover = 120;
  static const double tileCover = 48;
  static const double rCard = 8;
  static const double rBtn = 24;

  // ── 字号 ──
  static const double fPageTitle = 28;
  static const double fSection = 20;
  static const double fItem = 15;
  static const double fSub = 13;
  static const double fTiny = 11;

  /// 深色主题（Spotify 风格，全 app 唯一主题；Spotify 不提供亮色）。
  ///
  /// [palette]：动态调色板（封面取色），非空时覆盖 primary/onPrimary/primaryContainer。
  /// [pitchBlack]：纯黑模式——surface 家族（surfaceContainer* / scaffold / canvas）
  ///   全覆盖为纯黑，其余令牌不变。
  ///
  /// 主题为 M3（useMaterial3: true），保证消费方 colorScheme.surfaceContainer*
  /// 在各页稳定可用；失败一律 try/catch + Log 兜底为静态深色主题。
  static ThemeData theme({ThemePalette? palette, bool pitchBlack = false}) {
    try {
      final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
      final seed =
          ColorScheme.fromSeed(seedColor: Sp.green, brightness: Brightness.dark);
      final Color surface = pitchBlack ? Colors.black : const Color(0xFF0E0F12);
      final Color low = pitchBlack ? Colors.black : Sp.card;
      final Color high = pitchBlack ? Colors.black : Sp.cardHigh;
      final ColorScheme cs = seed.copyWith(
        surface: surface,
        onSurface: Sp.text,
        surfaceContainerLowest: surface,
        surfaceContainerLow: low,
        surfaceContainer: low,
        surfaceContainerHigh: high,
        surfaceContainerHighest: high,
        primary: Sp.green,
        onPrimary: Colors.black,
        secondary: Sp.textSub,
        onSecondary: Sp.text,
        error: Sp.red,
      );
      final ColorScheme themed = _applyPalette(cs, palette);
      return base.copyWith(
        colorScheme: themed,
        scaffoldBackgroundColor: themed.surface,
        canvasColor: themed.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: themed.surface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
              color: Sp.text, fontSize: fPageTitle, fontWeight: FontWeight.w900),
          iconTheme: const IconThemeData(color: Sp.text),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: pitchBlack ? Colors.black : Colors.black,
          indicatorColor: Colors.transparent,
          height: navH,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? Sp.text : Sp.textSub,
              )),
          labelTextStyle: WidgetStateProperty.resolveWith((states) =>
              TextStyle(
                  fontSize: fTiny,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: states.contains(WidgetState.selected)
                      ? Sp.text
                      : Sp.textSub)),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Sp.textSub,
          titleTextStyle: TextStyle(
              color: Sp.text, fontSize: fItem, fontWeight: FontWeight.w500),
          subtitleTextStyle: TextStyle(color: Sp.textSub, fontSize: fSub),
          contentPadding: EdgeInsets.symmetric(horizontal: pagePad),
          minLeadingWidth: 0,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: low,
          selectedColor: Sp.green,
          labelStyle: const TextStyle(color: Sp.text, fontSize: fSub),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rBtn)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        dividerTheme: const DividerThemeData(color: Sp.divider, thickness: 0.5),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Sp.cardHigh,
          contentTextStyle: TextStyle(color: Sp.text),
          behavior: SnackBarBehavior.floating,
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: Sp.green),
      );
    } catch (e, st) {
      Log.e('surface.sp_tokens', 'theme() failed, fallback static', e, st);
      return _fallbackTheme();
    }
  }

  /// 动态调色板覆盖：仅在 palette 非空时改写 primary 三元组，surface 家族不动。
  static ColorScheme _applyPalette(ColorScheme cs, ThemePalette? palette) {
    try {
      if (palette == null) return cs;
      return cs.copyWith(
        primary: palette.primary,
        onPrimary: palette.onPrimary,
        primaryContainer: palette.primaryContainer,
      );
    } catch (e, st) {
      Log.e('surface.sp_tokens', '_applyPalette failed', e, st);
      return cs;
    }
  }

  /// 兜底静态主题（不依赖任何动态状态）。
  static ThemeData _fallbackTheme() {
    try {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF0E0F12),
          onSurface: Sp.text,
          primary: Sp.green,
          onPrimary: Colors.black,
          secondary: Sp.textSub,
          error: Sp.red,
        ),
      );
    } catch (e, st) {
      Log.e('surface.sp_tokens', '_fallbackTheme failed', e, st);
      return ThemeData(useMaterial3: true, brightness: Brightness.dark);
    }
  }
}
