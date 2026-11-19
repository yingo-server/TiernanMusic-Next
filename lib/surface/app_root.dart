// L7 surface · 应用根（MaterialApp + 语义主题 + 外壳装配）
//
// 契约（docs/UI_REWRITE_PLAN.md §0.0 / docs/DESIGN_LANGUAGE.md §5）：
// - 只用官方 Material 3 控件 + GetWidget 现成能力；不手写控件类。
// - 颜色全部来自语义 token（design/tokens_v2.dart），无裸色值。
// - 明暗双主题：**首帧前**读取持久化主题（防闪烁），切换 200–300ms 过渡。
// - 系统栏（Android 导航栏/状态栏）显式锁暗（真机事故：MIUI 用浅灰
//   windowBackground 画系统导航带，盖住 Flutter 底栏；见 docs/ui_diagnosis.md）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiMode, SystemUiOverlay, SystemUiOverlayStyle;

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
import 'design/desktop_titlebar.dart' show buildDesktopTitleBar;
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
    _enableEdgeToEdge();
  }

  /// Edge-to-edge（计划书 P5）：Flutter 画布延伸到系统栏之下，
  /// Scaffold 经 MediaQuery.padding 自动为 NavigationBar/mini bar 避让
  /// 手势区 —— MIUI 的独立系统导航区域不再存在，悬浮通知横幅也不会
  /// 再把底栏"盖住"（真机 2026-11-20：底栏区域曾被系统面板遮挡）。
  static void _enableEdgeToEdge() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: <SystemUiOverlay>[SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }

  /// 真机修复（浅灰/米黄底栏带）：edge-to-edge 模式下系统导航栏透明，
  /// 由 Flutter 画布绘制底色；MIUI 不再有独立的浅灰 windowBackground 区域。
  /// 注意：legacy 模式的 systemNavigationBarColor 在 edge-to-edge 下无效，
  /// 但保留设置无害（部分 ROM 仍读它做过渡帧）。
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
          // 档位 3 = 纯黑（AMOLED）：画布真黑，其余沿用暗色板。
          // 旧版有该档位，UI 重写时丢失，这里补回。
          final dark = (mode == 3 ? TnPalette.pureBlack : TnPalette.dark)
              .toThemeData();
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
            // 桌面端（Win/Linux）在内容上方挂自绘标题栏（官方 bitsdojo 控件）；
            // 移动/Web 返回 null → 直接用 AppShell。用官方 Builder 取 MaterialApp
            // 生效后的 context（确保 titlebar token 取到正确明暗）。
            home: Builder(
              builder: (appContext) {
                final titleBar = buildDesktopTitleBar(appContext);
                if (titleBar == null) return const AppShell();
                return Column(
                  children: <Widget>[
                    titleBar,
                    const Expanded(child: AppShell()),
                  ],
                );
              },
            ),
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
