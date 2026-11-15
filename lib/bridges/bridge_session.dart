// 六桥 · bridge_session：L5 logic ↔ L6 session 的唯一通道。
// V2（docs/SEVEN_SIX_RULE.md）：session 是 surface 的底层，负责播放编排/装配图/
// 模块注册表/导航状态；surface 只经 bridge_surface + bridge_session 取状态。
// 铁律：每个桥函数 try/catch + Log 留痕，失败不静默吞。
library;

import '../kernel/kernel.dart' show Log;
import '../session/graph.dart' show AppGraph;
import '../session/contracts.dart' show SurfaceModule, NavEntry;
import '../session/module_registry.dart' show ModuleRegistry;
import '../session/nav_state.dart' show NavState;
import '../session/playback_session.dart'
    show PlaybackSession, PlaybackSnapshot;

export '../session/graph.dart' show AppGraph;
export '../session/contracts.dart' show SurfaceModule, NavEntry;
export '../session/module_registry.dart' show ModuleRegistry;
export '../session/nav_state.dart' show NavState;
export '../session/playback_session.dart'
    show PlaybackSession, PlaybackSnapshot;

/// L7 页面统一取装配图（唯一合法跨层入口：session/bootstrap.appGraph）。
/// bootstrapSession 失败时为 null，页面按空态/错误态处理。
export '../session/bootstrap.dart' show appGraph;
// 批1-F1：主题模式控制器（L6 foundation ValueNotifier，持久化经 bridge_core）。
export '../session/theme_controller.dart' show ThemeController;
// 批2-F3：登录态会话（isLoggedIn/userid 快照 + onAuthChanged 订阅）。
export '../session/auth_session.dart' show AuthSession;

/// 创建默认装配图（失败返回空图并留痕，不抛给 L7）。
AppGraph createAppGraph() {
  try {
    return AppGraph.empty();
  } catch (e, st) {
    Log.e('bridge_session', 'createAppGraph failed', e, st);
    return AppGraph.empty();
  }
}

/// 取全局模块注册表（单例；失败留痕返回新建空表）。
ModuleRegistry moduleRegistry() {
  try {
    return ModuleRegistry.instance;
  } catch (e, st) {
    Log.e('bridge_session', 'moduleRegistry failed', e, st);
    return ModuleRegistry.instance;
  }
}

/// 取全局导航状态（单例）。
NavState navState() {
  try {
    return NavState.instance;
  } catch (e, st) {
    Log.e('bridge_session', 'navState failed', e, st);
    return NavState.instance;
  }
}

/// 取全局播放会话（单例；L7 只拿它暴露的快照与意图方法）。
PlaybackSession playbackSession() {
  try {
    return PlaybackSession.instance;
  } catch (e, st) {
    Log.e('bridge_session', 'playbackSession failed', e, st);
    return PlaybackSession.instance;
  }
}
