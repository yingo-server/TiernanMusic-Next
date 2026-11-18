// L7 surface · 应用根（MaterialApp + 语义主题 + 外壳装配）
//
// 契约（docs/UI_REWRITE_PLAN.md §0.0 / docs/DESIGN_LANGUAGE.md §5）：
// - 只用官方 Material 3 控件 + GetWidget 现成能力；不手写控件类。
// - 颜色全部来自语义 token（design/tokens_v2.dart），无裸色值。
// - 明暗双主题：**首帧前**读取持久化主题（防闪烁），切换 200–300ms 过渡。
// - 系统栏（Android 导航栏/状态栏）显式锁暗（真机事故：MIUI 用浅灰
//   windowBackground 画系统导航带，盖住 Flutter 底栏；见 docs/ui_diagnosis.md）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle;

import '../bridges/bridge_core.dart'
    show
        KugouClient,
        SongDao,
        PlaylistDao,
        HistoryDao,
        DownloadStore,
        KeyValueSettings,
        StoragePaths;
import '../bridges/bridge_session.dart'
    show
        ModuleRegistry,
        NavEntry,
        SurfaceModule,
        PlaybackSession,
        ThemeController,
        LocaleController;
import 'design/tokens_v2.dart';
import 'shell.dart';

/// 装配依赖（由 L1 经 bridge_surface 注入）。
class SurfaceDeps {
  const SurfaceDeps({
    required this.client,
    required this.songDao,
    required this.playlistDao,
    required this.historyDao,
    required this.downloadStore,
    required this.settings,
    this.paths,
  });
  final KugouClient client;
  final SongDao songDao;
  final PlaylistDao playlistDao;
  final HistoryDao historyDao;
  final DownloadStore downloadStore;
  final KeyValueSettings settings;
  final StoragePaths? paths;
  StoragePaths get pathsOrI => paths ?? StoragePaths.I;
}

/// 根组件（唯一入口）。监听 L6 ThemeController，按档位给 theme/darkTheme/themeMode。
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  @override
  void initState() {
    super.initState();
    _applySystemBarStyle();
  }

  /// 真机修复（浅灰/米黄底栏带）：App 自身不设置 Android 系统导航栏颜色时，
  /// MIUI 等 ROM 会用浅灰 windowBackground 画系统导航区（截图里那条无色无图标的
  /// 纯色带），它盖住/挤掉 Flutter 的 NavigationBar，造成"底栏不可见"。显式锁暗。
  static void _applySystemBarStyle() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: TnSystemColors.navDark,
      systemNavigationBarDividerColor: TnSystemColors.navDark,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      statusBarColor: TnSystemColors.statusDark,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => ValueListenableBuilder<String>(
        valueListenable: LocaleController.instance,
        builder: (context, localeCode, _) {
          // 语义色板：Light/Dark 成对定义（design/tokens_v2.dart）。
          final light = TnPalette.light.toThemeData();
          final dark = TnPalette.dark.toThemeData();
          return MaterialApp(
            title: 'TiernanMusicNext',
            debugShowCheckedModeBanner: false,
            theme: light,
            darkTheme: dark,
            // 0 跟随系统 / 1 浅色 / 2 深色 / 3 纯黑。
            themeMode: switch (mode) {
              0 => ThemeMode.system,
              1 => ThemeMode.light,
              2 => ThemeMode.dark,
              _ => ThemeMode.dark, // 纯黑：暗色板 + 纯黑画布（下方覆盖）
            },
            // 主题切换 200–300ms 颜色过渡，避免闪白/闪黑。
            themeAnimationDuration: const Duration(milliseconds: 250),
            themeAnimationCurve: Curves.easeInOut,
            // 语言切换实时生效——locale 变化触发本 builder 重建。
            locale: _toLocale(localeCode),
            supportedLocales: const <Locale>[
              Locale('zh'), Locale('zh', 'Hant'), Locale('en'), Locale('ja'),
              Locale('ko'), Locale('es'), Locale('fr'), Locale('de'),
              Locale('pt'), Locale('ru'),
            ],
            home: const AppShell(),
          );
        },
      ),
    );
  }

  /// 'zh_Hant' -> Locale('zh','Hant')；'zh' -> Locale('zh')；'' -> null（跟随系统）。
  static Locale? _toLocale(String code) {
    if (code.isEmpty || code == 'system') return null;
    final parts = code.replaceAll('-', '_').split('_');
    if (parts.length >= 2) return Locale(parts[0], parts[1]);
    return Locale(parts[0]);
  }
}

// ── L1 装配入口（经 bridge_surface 调用；非 UI 控件，符合零手写控件契约）──

/// 页面模块注册（各页面 Module 自注册）。
Future<void> installServices({
  required SurfaceDeps deps,
  Object? engine,
}) async {
  try {
    registerModules();
    assert(deps.settings != null, 'surface deps requires settings');
  } catch (e, st) {
    debugPrint('surface.installServices failed: $e\n$st');
    rethrow;
  }
}

/// runApp 入口（保留既有 bootstrapApp 调用形状）。
void bootstrapApp(dynamic result) {
  runApp(const AppRoot());
}
