// L7 surface/design · 语义色彩 Token v2（森林翡翠设计语言）
//
// 契约（docs/UI_REWRITE_PLAN.md §0.0 / docs/DESIGN_LANGUAGE.md）：
// - UI 层**零手写控件**：只用官方 Material 3 + GetWidget；我们只写色彩。
// - 组件**只引用语义 token**，不引用任何裸色值。
// - 每个语义 token **Light/Dark 成对**定义（成对性由 tool/ui_contrast_gate.py 校验）。
// - 深色不用纯黑、浅色不用纯白。
// - 桌面标题栏用独立 titlebar.* token，不挂到 ColorScheme。
//
// 使用方式：
//   final cs = context.cs;            // 扩展 getter（见文件末尾）
//   cs.primary / cs.onPrimary / cs.textPrimary / cs.bgCanvas ...
//   Theme.of(context).colorScheme.*  // 官方 ColorScheme 角色（已按本 token 装配）
library;

import 'package:flutter/material.dart';

/// 系统 UI 覆盖层颜色（SystemChrome 用；属 platform token，可脱离 context）。
abstract final class TnSystemColors {
  // 与暗色画布一致（中性灰）。旧值 0xFF0B1F14（深绿）会让 MIUI 用浅色
  // windowBackground 画系统导航带时与 Flutter 画布割裂。
  static const Color navDark = Color(0xFF0E0F12);
  static const Color statusDark = Color(0xFF0E0F12);
}

/// 语义色彩表：Light / Dark 成对。
class TnPalette {
  const TnPalette({
    required this.brightness,
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgContainer,
    required this.bgContainerHigh,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.outline,
    required this.divider,
    required this.focus,
    required this.success,
    required this.warning,
    required this.error,
    required this.onError,
    required this.info,
    required this.titlebarBg,
    required this.titlebarFg,
    required this.titlebarButtonHover,
    required this.titlebarCloseHover,
    required this.titlebarInactive,
  });

  final Brightness brightness;

  // 背景层
  final Color bgCanvas;
  final Color bgSurface;
  final Color bgContainer;
  final Color bgContainerHigh;

  // 主/次强调
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;

  // 文本层
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  // 边界与焦点
  /// 可见边框（控件边界）：对卡片/画布需 3:1（门禁硬要求）。
  final Color outline;

  /// 纯装饰分割线：低对比（无信息量，按 WCAG 无对比度要求）。
  /// 与 outline 分档，避免把"分割线"也做成 3:1 的重线而弄脏界面。
  final Color divider;
  final Color focus;

  // 状态（不只靠颜色表达，须配图标/文案）
  final Color success;
  final Color warning;
  final Color error;
  final Color onError;
  final Color info;

  // 桌面标题栏（独立于 ColorScheme）
  final Color titlebarBg;
  final Color titlebarFg;
  final Color titlebarButtonHover;
  final Color titlebarCloseHover;
  final Color titlebarInactive;

  bool get isDark => brightness == Brightness.dark;

  /// 浅色主题（中性灰底 + 翡翠强调）。
  ///
  /// 配色修订（真机反馈"颜色不对"）：上一版把**整屏底色铺成浅绿**
  /// （bgCanvas #F1F8F4 / container #D8F3DC），页面失去中性基调、
  /// 卡片与背景同色系导致没有层次。现在底色回到中性灰阶，
  /// 翡翠绿只保留在强调位（primary / focus / 状态色）。
  static const TnPalette light = TnPalette(
    brightness: Brightness.light,
    bgCanvas: Color(0xFFF7F8FA),
    bgSurface: Color(0xFFFFFFFF),
    bgContainer: Color(0xFFE4E7EB),
    bgContainerHigh: Color(0xFFC2C8D0),
    // 深翡翠：在浅底上 4.56:1（AA 正文达标）；亮翡翠 #1DB954 在白底只有
    // 2.43:1，不可作正文色。
    primary: Color(0xFF12833C),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF1DB954),
    onSecondary: Color(0xFF0E0F12),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF5F646D),
    textDisabled: Color(0xFF9AA0AA),
    outline: Color(0xFF7F9186),
    divider: Color(0xFFDCDFE4),
    focus: Color(0xFF12833C),
    success: Color(0xFF157347),
    warning: Color(0xFF8A5A00),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    info: Color(0xFF0B6BCB),
    titlebarBg: Color(0xFF141519),
    titlebarFg: Color(0xFFEDEFF2),
    titlebarButtonHover: Color(0xFF25272C),
    titlebarCloseHover: Color(0xFFE05B5B),
    titlebarInactive: Color(0xFF6C737D),
  );

  /// 深色主题（中性灰底 + 翡翠强调）。深色画布 #0E0F12（非纯黑）。
  ///
  /// 配色修订（真机反馈"颜色不对"）：上一版把**整屏底色铺成深绿**
  /// （bgCanvas #0B1F14 / container #17332A / containerHigh #1F4432），
  /// 深绿铺满 + 卡片与背景色差过小 → 视觉上"一整块绿糊住、没有层次"。
  /// 现在底色回到中性灰阶（与旧版一致），翡翠绿只做强调色：
  /// primary #1DB954 在深底上 7.41:1（AA 达标）。
  static const TnPalette dark = TnPalette(
    brightness: Brightness.dark,
    bgCanvas: Color(0xFF0E0F12),
    bgSurface: Color(0xFF181A1F),
    bgContainer: Color(0xFF2B3038),
    bgContainerHigh: Color(0xFF3A4049),
    primary: Color(0xFF1DB954),
    onPrimary: Color(0xFF06120A),
    secondary: Color(0xFF2ECC71),
    onSecondary: Color(0xFF06120A),
    textPrimary: Color(0xFFEDEFF2),
    textSecondary: Color(0xFFA9AFB8),
    textDisabled: Color(0xFF6C737D),
    outline: Color(0xFF5A6B60),
    divider: Color(0xFF2E3137),
    focus: Color(0xFF1DB954),
    success: Color(0xFF2ECC71),
    warning: Color(0xFFF2A25C),
    error: Color(0xFFE05B5B),
    onError: Color(0xFF1A0505),
    info: Color(0xFF8EC5FF),
    titlebarBg: Color(0xFF141519),
    titlebarFg: Color(0xFFEDEFF2),
    titlebarButtonHover: Color(0xFF25272C),
    titlebarCloseHover: Color(0xFFE05B5B),
    titlebarInactive: Color(0xFF6C737D),
  );

  /// 纯黑（AMOLED）调色板：画布真黑，其余沿用暗色板。
  ///
  /// 旧版有该档位（mode==3），UI 重写时丢失了 —— 现补回，
  /// 让"档位 3 纯黑"在设置页不再名存实亡。
  static TnPalette get pureBlack => TnPalette(
    brightness: Brightness.dark,
    bgCanvas: const Color(0xFF000000),
    bgSurface: const Color(0xFF000000),
    bgContainer: const Color(0xFF0E0F12),
    bgContainerHigh: const Color(0xFF141519),
    primary: dark.primary,
    onPrimary: dark.onPrimary,
    secondary: dark.secondary,
    onSecondary: dark.onSecondary,
    textPrimary: dark.textPrimary,
    textSecondary: dark.textSecondary,
    textDisabled: dark.textDisabled,
    outline: dark.outline,
    divider: dark.divider,
    focus: dark.focus,
    success: dark.success,
    warning: dark.warning,
    error: dark.error,
    onError: dark.onError,
    info: dark.info,
    titlebarBg: dark.titlebarBg,
    titlebarFg: dark.titlebarFg,
    titlebarButtonHover: dark.titlebarButtonHover,
    titlebarCloseHover: dark.titlebarCloseHover,
    titlebarInactive: dark.titlebarInactive,
  );

  /// 依亮度取色板。
  static TnPalette of(Brightness b) =>
      b == Brightness.dark ? dark : light;

  /// 装配为官方 ColorScheme（页面用 `Theme.of(context).colorScheme` 即可拿到语义角色）。
  ColorScheme toColorScheme() {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      surface: bgCanvas,
      onSurface: textPrimary,
      surfaceContainerLowest: bgCanvas,
      surfaceContainerLow: bgSurface,
      surfaceContainer: bgContainer,
      surfaceContainerHigh: bgContainerHigh,
      surfaceContainerHighest: bgContainerHigh,
      onSurfaceVariant: textSecondary,
      outline: outline,
      // outlineVariant = 纯装饰分割线（低对比）；outline = 可见控件边框（3:1）。
      outlineVariant: divider,
      error: error,
      onError: onError,
      surfaceTint: Colors.transparent,
    );
  }

  /// 装配为官方 ThemeData（组件主题一律用 scheme 角色，杜绝局部常量）。
  ThemeData toThemeData() {
    final scheme = toColorScheme();
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgCanvas,
      canvasColor: bgCanvas,
      dividerColor: divider,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: bgCanvas,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: bgContainerHigh,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            color: s.contains(WidgetState.selected)
                ? textPrimary
                : textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected)
                ? textPrimary
                : textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bgSurface,
        indicatorColor: bgContainerHigh,
        selectedIconTheme: IconThemeData(color: textPrimary, size: 24),
        unselectedIconTheme: IconThemeData(color: textSecondary, size: 24),
        selectedLabelTextStyle: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: textSecondary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        titleTextStyle: TextStyle(fontSize: 15, color: textPrimary),
        subtitleTextStyle: TextStyle(fontSize: 13, color: textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgContainer,
        side: BorderSide(color: outline),
        labelStyle: TextStyle(fontSize: 13, color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        hintStyle: TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: outline),
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textPrimary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
      ),
      cardTheme: CardThemeData(
        color: bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outline.withValues(alpha: 0.10)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgContainer,
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearMinHeight: 2,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: bgContainerHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: textPrimary, fontSize: 12),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = TextStyle(color: scheme.onSurface, fontSize: 14);
    final sub = scheme.onSurfaceVariant;
    return TextTheme(
      displaySmall: base.copyWith(fontSize: 32, fontWeight: FontWeight.w700),
      headlineMedium: base.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
      headlineSmall: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      titleLarge: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: base.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: base.copyWith(fontSize: 15),
      bodyMedium: base.copyWith(fontSize: 14),
      bodySmall: base.copyWith(fontSize: 12, color: sub),
      labelLarge: base.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: base.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: base.copyWith(fontSize: 11, color: sub),
    );
  }
}

/// 语义色彩便捷访问（页面统一用 `context.cs.*`，不引用裸色值）。
extension TnPaletteX on BuildContext {
  /// 当前亮度下的语义色板。
  TnPalette get palette =>
      TnPalette.of(Theme.of(this).brightness);

  /// 官方 ColorScheme（已按语义 token 装配）。
  ColorScheme get cs => Theme.of(this).colorScheme;

  // —— 便捷别名（与 DESIGN_LANGUAGE.md 语义 token 同名，便于对照）——
  Color get bgCanvas => palette.bgCanvas;
  Color get bgSurface => palette.bgSurface;
  Color get bgContainer => palette.bgContainer;
  Color get bgContainerHigh => palette.bgContainerHigh;
  Color get textPrimary => palette.textPrimary;
  Color get textSecondary => palette.textSecondary;
  Color get textDisabled => palette.textDisabled;
  Color get success => palette.success;
  Color get warning => palette.warning;
  Color get errorColor => palette.error;
  Color get info => palette.info;
  Color get focusColor => palette.focus;

  // 标题栏（独立于 ColorScheme）
  Color get titlebarBg => palette.titlebarBg;
  Color get titlebarFg => palette.titlebarFg;
  Color get titlebarButtonHover => palette.titlebarButtonHover;
  Color get titlebarCloseHover => palette.titlebarCloseHover;
  Color get titlebarInactive => palette.titlebarInactive;
}
