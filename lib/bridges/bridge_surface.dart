// 六桥 · bridge_surface：L6 session ↔ L7 surface / L1 装配入口。
// V2（docs/SEVEN_SIX_RULE.md）：surface 只画控件；播放编排/装配图全在 session。
// 铁律：每个桥函数 try/catch + Log 留痕，失败原样上抛（必须暴露，不静默吞）。
library;

import '../kernel/kernel.dart' show Log;
import '../surface/app_root.dart'
    as root
    show SurfaceDeps, bootstrapApp, installServices;
import '../surface/theme/tn_theme.dart' show spErrorThemeData;
import '../session/bootstrap.dart' as session;

export '../surface/app_root.dart' show SurfaceDeps, AppRoot;
export '../bridges/bridge_core.dart'
    show platformCapabilities, windowService;
export '../surface/theme/tn_theme.dart' show spErrorThemeData;
// V2：L1/独立 UI 模型可直接经桥取 session 门面。
export '../session/graph.dart' show AppGraph, SessionDeps;
export '../session/contracts.dart' show NavEntry, SurfaceModule;
export '../session/module_registry.dart' show ModuleRegistry;
export '../session/nav_state.dart' show NavState;
export '../session/playback_session.dart'
    show PlaybackSession, PlaybackSnapshot;

/// L1 → L7 装配入口：先装配 L6 session，再由独立 UI 模型装配 L7。
Future<void> installServices({required dynamic deps, dynamic engine}) async {
  try {
    // ① session（非 UI 逻辑）先就位；失败即暴露。
    final d = deps as root.SurfaceDeps;
    await session.bootstrapSession(
      client: d.client,
      songDao: d.songDao,
      playlistDao: d.playlistDao,
      historyDao: d.historyDao,
      downloadStore: d.downloadStore,
      settings: d.settings,
      paths: d.paths,
      engine: engine,
    );
    // ② L7 控件装配（独立模型实现；当前占位会抛 StateError）。
    await root.installServices(deps: d, engine: engine);
    Log.d('bridge_surface', 'installServices ok');
  } catch (e, st) {
    Log.e('bridge_surface', 'installServices failed', e, st);
    rethrow;
  }
}

/// bootstrapApp 转调。
void bootstrapApp(dynamic bootResult) {
  try {
    root.bootstrapApp(bootResult);
    Log.d('bridge_surface', 'bootstrapApp ok');
  } catch (e, st) {
    Log.e('bridge_surface', 'bootstrapApp failed', e, st);
    rethrow;
  }
}
