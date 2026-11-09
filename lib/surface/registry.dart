// L6 surface 级 · UI 模块热插拔机制
// 每个页面/组件是一个 SurfaceModule，经 SurfaceRegistry 装配。
// 模块间禁止直接 import，通信只走 riverpod provider / 桥。
import '../bridge_logic.dart'; // 仅取 logic 能力门面（bridge_logic 属 L5/L6 共用）

abstract class SurfaceModule {
  String get id;
  String get route; // go_router 路径
  /// 模块是否可用（如依赖的 logic 能力缺失可声明降级/隐藏）
  bool enabled(LogicFacade logic);
  /// 构建模块根视图（参数由桥层传入，禁止携带 IO 对象）
  WidgetBuilder builder(LogicFacade logic);
  /// 可选：模块贡献的底部导航/抽屉入口
  NavEntry? get navEntry => null;
}

class NavEntry {
  const NavEntry(this.label, this.icon);
  final String label;
  final String icon;
}

class SurfaceRegistry {
  SurfaceRegistry._();
  static final _modules = <String, SurfaceModule>{};

  /// 启动时由 bootloader/surface 桥逐个 install；重复 id 视为替换（热插拔语义）
  static void install(SurfaceModule m) {
    try {
      _modules[m.id] = m;
      Log.d('surface', 'module installed: ${m.id}');
    } catch (e, st) {
      Log.e('surface', 'install ${m.id} failed', e, st);
    }
  }

  static void uninstall(String id) {
    try {
      _modules.remove(id);
      Log.d('surface', 'module uninstalled: $id');
    } catch (e, st) {
      Log.e('surface', 'uninstall $id failed', e, st);
    }
  }

  static List<SurfaceModule> active(LogicFacade logic) {
    try {
      final list = _modules.values.where((m) {
        try {
          return m.enabled(logic);
        } catch (e, st) {
          Log.e('surface', 'enabled(${m.id}) crashed', e, st);
          return false;
        }
      }).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      return list;
    } catch (e, st) {
      Log.e('surface', 'active() crashed', e, st);
      return const [];
    }
  }
}
