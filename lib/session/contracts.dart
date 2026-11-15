// L6 session · 纯契约（零 import → 本地可单测，CI 亦可）
// 只定义形状：导航入口、模块契约。实现与依赖全在 graph.dart / module_registry.dart。

/// 导航入口（纯数据；L7 自己画 NavigationDestination）。
class NavEntry {
  const NavEntry(this.label, this.icon, {this.navOrder = 0});
  final String label;
  final String icon;

  /// 导航栏排序权重：小者靠前；无 navEntry 的模块排最后。
  final int navOrder;
}

/// 模块契约：L7 控件按 id/route 注册，session 只约定形状，不画控件。
/// builder 由 L7 提供（L7 侧以 `as WidgetBuilder?` 收窄），session 零 flutter 依赖。
/// 注意：L7 侧请用 `extends SurfaceModule`（`implements` 不继承默认实现）。
abstract class SurfaceModule {
  String get id;
  String get route;
  NavEntry? get navEntry => null;
  bool get enabled => true;

  /// 页面构造器（L7 注入）。session 只持有不渲染。
  Object? get builder => null;
}
