// L6 surface 级 · UI 模块热插拔机制
// 每个页面/组件是一个 SurfaceModule，经 SurfaceRegistry 装配。
// 模块间禁止直接 import，通信只走 riverpod provider / 桥。
import 'package:flutter/material.dart' show WidgetBuilder;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;

import '../bridges/bridge_logic.dart' show LogicFacade, Log;

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

/// 全局共享 override 桶的 key。PlayerController 等跨模块唯一实例归属此桶：
/// 它不属于任何单个模块，uninstall 单个模块时不得清理，否则其它模块会降级。
const String _globalOverrideOwner = '';

class SurfaceRegistry {
  SurfaceRegistry._();

  /// 取 id 的容错包装：模块 getter 崩溃时日志链路不得二次抛异常逃逸。
  static String _safeId(SurfaceModule m) {
    try {
      return m.id;
    } catch (_) {
      return '<unknown>';
    }
  }

  /// 已安装模块表，key = module id；重复 id 写入即覆盖替换（幂等，不累积实例）。
  static final _modules = <String, SurfaceModule>{};

  /// provider overrides 按 owner（module id 或全局桶）分组保存，
  /// 以便 uninstall(id) 精确清除该模块的 overrides，避免热插拔后残留/泄漏。
  static final _overridesByOwner = <String, List<Override>>{};

  /// 安装/替换模块。重复 id 视为覆盖替换（热插拔语义），幂等。
  static void install(SurfaceModule m) {
    final id = _safeId(m);
    try {
      final replaced = _modules.containsKey(id);
      if (replaced) {
        // 覆盖替换时旧实例注入的私有 overrides 视为过期，防止陈旧 provider
        // 继续被 providerOverrides 输出（模块私有 overrides 请在 install 后设置）。
        _overridesByOwner.remove(id);
      }
      _modules[id] = m;
      Log.d('surface', 'module installed: $id, replaced=$replaced');
    } catch (e, st) {
      Log.e('surface', 'install $id failed', e, st);
    }
  }

  /// 卸载模块并清除其私有 provider overrides（不泄漏）。
  /// 全局共享 override（PlayerController）保留，避免误伤其它仍启用的模块。
  static void uninstall(String id) {
    try {
      _modules.remove(id);
      _overridesByOwner.remove(id);
      Log.d('surface', 'module uninstalled: $id');
    } catch (e, st) {
      Log.e('surface', 'uninstall $id failed', e, st);
    }
  }

  /// 只返回 enabled 模块，按 id 稳定排序；enabled 崩溃的模块按不可用处理。
  static List<SurfaceModule> active(LogicFacade logic) {
    try {
      final list = _modules.values.where((m) {
        try {
          return m.enabled(logic);
        } catch (e, st) {
          Log.e('surface', 'enabled(${_safeId(m)}) crashed', e, st);
          return false;
        }
      }).toList()
        ..sort((a, b) => _safeId(a).compareTo(_safeId(b)));
      return list;
    } catch (e, st) {
      Log.e('surface', 'active() crashed', e, st);
      return const <SurfaceModule>[];
    }
  }

  /// 已启用模块贡献的导航入口列表：顺序与 active() 一致（按模块 id 稳定排序），
  /// 跳过未贡献 / 取值崩溃的模块，返回不可变列表。
  static List<NavEntry> navEntries(LogicFacade logic) {
    try {
      final entries = <NavEntry>[];
      for (final m in active(logic)) {
        NavEntry? entry;
        try {
          entry = m.navEntry;
        } catch (e, st) {
          Log.e('surface', 'navEntry(${_safeId(m)}) crashed', e, st);
        }
        if (entry != null) entries.add(entry);
      }
      return List<NavEntry>.unmodifiable(entries);
    } catch (e, st) {
      Log.e('surface', 'navEntries() crashed', e, st);
      return const <NavEntry>[];
    }
  }

  /// 设置全局共享 overrides（modules.defaultModules 注入的 PlayerController
  /// 唯一实例），boot 处把 providerOverrides 传给 ProviderScope。
  /// 归属全局桶，不随单模块 uninstall 清理；重复调用覆盖（幂等）。
  static void setOverrides(List<Override> overrides) {
    try {
      _overridesByOwner[_globalOverrideOwner] =
          List<Override>.unmodifiable(overrides);
      Log.d('surface', 'global overrides set n=${overrides.length}');
    } catch (e, st) {
      Log.e('surface', 'setOverrides failed', e, st);
    }
  }

  /// 为单个模块注册私有 overrides；重复调用覆盖（幂等）。
  /// uninstall(id) 会清除该桶；providerOverrides 只输出仍已安装模块的桶。
  static void setModuleOverrides(String id, List<Override> overrides) {
    try {
      if (id == _globalOverrideOwner) {
        // 空 id 保留给全局桶，避免模块误占 / 覆盖共享 override。
        Log.d('surface', 'setModuleOverrides ignored: reserved empty id');
        return;
      }
      _overridesByOwner[id] = List<Override>.unmodifiable(overrides);
      Log.d('surface', 'module $id overrides set n=${overrides.length}');
    } catch (e, st) {
      Log.e('surface', 'setModuleOverrides $id failed', e, st);
    }
  }

  /// ProviderScope 使用的 override 列表：全局桶 + 仍已安装模块的私有桶
  /// （按 owner key 排序，保证稳定）。已卸载模块的桶不再输出，
  /// 从而热插拔后不会残留陈旧 override（不泄漏）。
  static List<Override> get providerOverrides {
    try {
      final all = <Override>[...?_overridesByOwner[_globalOverrideOwner]];
      final owners = _overridesByOwner.keys
          .where((k) => k != _globalOverrideOwner && _modules.containsKey(k))
          .toList()
        ..sort();
      for (final id in owners) {
        all.addAll(_overridesByOwner[id]!);
      }
      return List<Override>.unmodifiable(all);
    } catch (e, st) {
      Log.e('surface', 'providerOverrides crashed', e, st);
      return const <Override>[];
    }
  }
}
