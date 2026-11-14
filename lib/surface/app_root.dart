// L7 surface · 应用根（MaterialApp + 主题 + 外壳装配）
// 76 原则：L7 只画控件；数据与状态全部来自 L6 session（经 bridge_session）。
import 'package:flutter/material.dart';

import '../bridges/bridge_core.dart'
    show KugouClient, SongDao, PlaylistDao, HistoryDao, DownloadStore,
        KeyValueSettings, StoragePaths;
import '../bridges/bridge_session.dart'
    show ModuleRegistry, NavEntry, SurfaceModule, PlaybackSession;
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

/// 根组件（唯一入口）。
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TiernanMusicNext',
        debugShowCheckedModeBanner: false,
        theme: Sp.theme(),
        home: const AppShell(),
      );
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
