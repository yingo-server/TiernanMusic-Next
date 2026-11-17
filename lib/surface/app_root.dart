// L7 surface · 应用根（MaterialApp + 主题 + 外壳装配）
// 76 原则：L7 只画控件；数据与状态全部来自 L6 session（经 bridge_session）。
import 'package:flutter/material.dart';

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
            darkTheme: Sp.theme(dark: true, seed: seed),
            // 0 跟随系统 / 1 亮 / 2 暗 / 3 纯黑。
            themeMode: switch (mode) {
              0 => ThemeMode.system,
              1 => ThemeMode.light,
              _ => ThemeMode.dark, // 覆盖 2/3（暗/纯黑）及异常值
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
