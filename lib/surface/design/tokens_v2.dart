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
  final Color outline;
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

  /// 浅色主题（森林翡翠）。
  static const TnPalette light = TnPalette(
    brightness: Brightness.light,
    bgCanvas: Color(0xFFF1F8F4),
    bgSurface: Color(0xFFFFFFFF),
    bgContainer: Color(0xFFD8F3DC),
    bgContainerHigh: Color(0xFFB7E4C7),
    primary: Color(0xFF1B5E20),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF52B788),
    onSecondary: Color(0xFF0B1F14),
    textPrimary: Color(0xFF102A18),
    textSecondary: Color(0xFF4A6B55),
    textDisabled: Color(0xFF9BB5A3),
    outline: Color(0xFF6B8F76),
    focus: Color(0xFF2F5D50),
    success: Color(0xFF2F7D4A),
    warning: Color(0xFF9A6700),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    info: Color(0xFF0B6BCB),
    titlebarBg: Color(0xFF1B5E20),
    titlebarFg: Color(0xFFE8F5EC),
    titlebarButtonHover: Color(0xFF52B788),
    titlebarCloseHover: Color(0xFFF2B8B5),
    titlebarInactive: Color(0xFFA8C5B2),
  );

  /// 深色主题（森林翡翠）。深色画布 #0B1F14（非纯黑）。
  static const TnPalette dark = TnPalette(
    brightness: Brightness.dark,
    bgCanvas: Color(0xFF0B1F14),
    bgSurface: Color(0xFF102A18),
    bgContainer: Color(0xFF17332A),
    bgContainerHigh: Color(0xFF1F4432),
    primary: Color(0xFFA7F3D0),
    onPrimary: Color(0xFF0B1F14),
    secondary: Color(0xFF52B788),
    onSecondary: Color(0xFF0B1F14),
    textPrimary: Color(0xFFE8F5EC),
    textSecondary: Color(0xFFA8C5B2),
    textDisabled: Color(0xFF5C7A66),
    outline: Color(0xFF5C7A66),
    focus: Color(0xFFA7F3D0),
    success: Color(0xFF7DD3A0),
    warning: Color(0xFFF5C542),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    info: Color(0xFF8EC5FF),
    titlebarBg: Color(0xFF0B1F14),
    titlebarFg: Color(0xFFA7F3D0),
    titlebarButtonHover: Color(0xFF17332A),
    titlebarCloseHover: Color(0xFFF2B8B5),
    titlebarInactive: Color(0xFF6B8F76),
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
      outlineVariant: outline,
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
      dividerColor: outline,
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
