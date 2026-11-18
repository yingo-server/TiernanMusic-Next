// L7 surface · 应用根（MaterialApp + 主题 + 外壳装配）
// 76 原则：L7 只画控件；数据与状态全部来自 L6 session（经 bridge_session）。
import 'package:flutter/material.dart';
// 真机修复（浅灰/米黄底栏带）：App 自身不设置 Android 系统导航栏颜色时，
// MIUI 等 ROM 会用浅灰 windowBackground 画系统导航区（截图里那条无色无图标的
// 纯色带），它盖住/挤掉 Flutter 的 NavigationBar，造成"底栏不可见"。显式锁暗。
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
import 'design/tokens.dart';
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

  /// 真机回归根因修复（浅灰/米黄底栏带）：
  /// 本 App 全部视觉基底都是深色，但从未向 Android 声明系统导航栏样式。
  /// MIUI 等 ROM 在深色 App 未声明时会用浅灰 windowBackground 画系统导航栏
  /// （真机截图最底部那条纯色、无图标文字的带，实测 RGB≈(182,182,182)），
  /// 它盖在 Flutter 的 NavigationBar 之上，导致底栏图标文字"完全不可见"。
  /// 只改 Flutter ThemeData 的颜色无法影响这条系统带——必须在此显式锁暗。
  static void _applySystemBarStyle() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF0E0F12),
      systemNavigationBarDividerColor: Color(0xFF0E0F12),
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      statusBarColor: Color(0xFF0E0F12),
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => ValueListenableBuilder<String>(
        valueListenable: LocaleController.instance,
        builder: (context, localeCode, _) {
          // 阶段B B6：动态取色——seed 由 L6 ThemeController 持有（L4 fromSeed
          // 派生），applySeed 会 notify 触发本 builder 重建。
          final seed = Color(ThemeController.instance.seedArgb);
          return MaterialApp(
            title: 'TiernanMusicNext',
            debugShowCheckedModeBanner: false,
            theme: Sp.theme(dark: false, seed: seed),
            darkTheme: Sp.theme(
              dark: true,
              seed: seed,
              pureBlack: mode == 3,
            ),
            // 0 跟随系统(暗色基底) / 1 亮 / 2 暗 / 3 纯黑(AMOLED)。
            // 审查修复（底栏浅色回归）：本 App 视觉基底为深色（Spotify 深色风），
            // "跟随系统"沿用系统浅色会让大量深色假设失效、底栏与内容板分裂；
            // 故 0 档保持暗色基底（与旧行为一致），想用浅色请选"亮"。
            themeMode: switch (mode) {
              1 => ThemeMode.light,
              _ => ThemeMode.dark, // 0 跟随系统(暗色基底) / 2 暗 / 3 纯黑
            },
            // 阶段B B7 P0：语言切换实时生效——locale 变化触发本 builder 重建。
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

/// 装配入口（L1 → L7）。
///
/// L6 session 已由 bridge_surface 在此之前装配完成；L7 只负责注册页面模块。
Future<void> installServices({
  required SurfaceDeps deps,
  Object? engine,
}) async {
  try {
    // 页面模块由各页面的 Module 注册函数自行注册（见 registerModules）。
    registerModules();
    assert(deps.settings != null, 'surface deps requires settings');
  } catch (e, st) {
    debugPrint('surface.installServices failed: $e\n$st');
    rethrow;
  }
}

/// runApp 入口（保留给既有 bootstrapApp 调用形状）。
void bootstrapApp(dynamic result) {
  runApp(const AppRoot());
}
