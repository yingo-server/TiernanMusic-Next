// L6 session · 模块注册表（纯 Dart 单例，无 Widget）
// 取代原 surface/registry.dart；L7 只按 id/route/navEntry 决定渲染哪个页面。
import '../bridges/bridge_kernel.dart' show Log;
import 'contracts.dart' show NavEntry, SurfaceModule;

const String _tag = 'session.registry';

class ModuleRegistry {
  ModuleRegistry._();
  static final ModuleRegistry instance = ModuleRegistry._();

  final Map<String, SurfaceModule> _modules = <String, SurfaceModule>{};

  /// 安装/替换（重复 id 覆盖，幂等）。
  void install(SurfaceModule module) {
    try {
      final id = module.id;
      _modules[id] = module;
      Log.d(_tag, 'install $id');
    } catch (e, st) {
      Log.e(_tag, 'install failed', e, st);
    }
  }

  void uninstall(String id) {
    try {
      _modules.remove(id);
      Log.d(_tag, 'uninstall $id');
    } catch (e, st) {
      Log.e(_tag, 'uninstall failed', e, st);
    }
  }

  /// 启用模块（按 id 稳定排序，供 L7 生成导航）。
  List<SurfaceModule> active() {
    try {
      final list = _modules.values.where((m) => m.enabled).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      return List<SurfaceModule>.unmodifiable(list);
    } catch (e, st) {
      Log.e(_tag, 'active failed', e, st);
      return const <SurfaceModule>[];
    }
  }

  List<NavEntry> navEntries() {
    try {
      return List<NavEntry>.unmodifiable(
          active().map((m) => m.navEntry).whereType<NavEntry>());
    } catch (e, st) {
      Log.e(_tag, 'navEntries failed', e, st);
      return const <NavEntry>[];
    }
  }

  SurfaceModule? byId(String id) {
    try {
      return _modules[id];
    } catch (e, st) {
      Log.e(_tag, 'byId failed', e, st);
      return null;
    }
  }

  void clear() {
    try {
      _modules.clear();
      Log.d(_tag, 'cleared');
    } catch (e, st) {
      Log.e(_tag, 'clear failed', e, st);
    }
  }
}
