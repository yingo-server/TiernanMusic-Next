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
import 'package:flutter/material.dart';

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
  static ThemeData theme() {
    final base = ThemeData(useMaterial3: false, brightness: Brightness.dark);
    final cs = ColorScheme.dark(
      surface: bg,
      onSurface: text,
      surfaceContainer: card,
      surfaceContainerHigh: cardHigh,
      primary: green,
      onPrimary: Colors.black,
      secondary: textSub,
      error: red,
    );
    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            color: text, fontSize: fPageTitle, fontWeight: FontWeight.w900),
        iconTheme: IconThemeData(color: text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.black,
        indicatorColor: Colors.transparent,
        height: navH,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? text : textSub,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            TextStyle(
                fontSize: fTiny,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: states.contains(WidgetState.selected)
                    ? text
                    : textSub)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSub,
        titleTextStyle: const TextStyle(
            color: text, fontSize: fItem, fontWeight: FontWeight.w500),
        subtitleTextStyle:
            const TextStyle(color: textSub, fontSize: fSub),
        contentPadding: const EdgeInsets.symmetric(horizontal: pagePad),
        minLeadingWidth: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: green,
        labelStyle: const TextStyle(color: text, fontSize: fSub),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rBtn)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 0.5),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: cardHigh,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: green),
    );
  }
}
