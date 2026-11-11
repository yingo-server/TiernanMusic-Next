// 五桥 · bridge_surface：L6 surface 暴露给 L1 init 的装配入口门面。
// 铁律：每个桥函数 try/catch + Log 留痕（print 兜底防递归）；装配/runApp
// 失败留痕后原样上抛（必须暴露），其余失败返回语义默认值。
// init 禁再直接 import surface/app_root.dart（白名单已删）。
library;

import '../surface/app_root.dart' as root
    show SurfaceDeps, bootstrapApp, installServices;
import '../kernel/kernel.dart' show Log;

// 保留装配入口可见：SurfaceDeps（构造参数类型）与 AppRoot（根组件）。
export '../surface/app_root.dart' show SurfaceDeps, AppRoot;

/// installServices 转调：surface 全量装配（assembly.assembleAll）。
Future<void> installServices(
    {required dynamic deps, dynamic engine}) async {
  try {
    await root.installServices(
        deps: deps as root.SurfaceDeps,
        engine: engine == null ? null : engine as dynamic);
    Log.d('bridge_surface', 'installServices ok');
  } catch (e, st) {
    Log.e('bridge_surface', 'installServices failed', e, st);
    rethrow;
  }
}

/// bootstrapApp 转调：消费 installServices 装配结果并 runApp。
void bootstrapApp(dynamic bootResult) {
  try {
    root.bootstrapApp(bootResult);
    Log.d('bridge_surface', 'bootstrapApp ok');
  } catch (e, st) {
    Log.e('bridge_surface', 'bootstrapApp failed', e, st);
    rethrow;
  }
}
