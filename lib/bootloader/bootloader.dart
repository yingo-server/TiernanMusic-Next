// L2 bootloader 级 · 启动序列与完整性校验触发点
// 职责：按序装配 L3 kernel 模块 → 校验模块清单（加盐 SHA-512 + Ed25519 签名）
// → 输出 BootResult。init 层是唯一调用方（经 bridge_boot）。
import 'dart:convert';
import 'dart:io';

import '../bridges/bridge_boot.dart' as bb;
import '../bridges/bridge_boot.dart' show KernelContext, Log;

/// init 层拿到的启动结果。
class BootResult {
  const BootResult({required this.rejected, required this.kernel});
  final bool rejected;
  final KernelContext? kernel;
}

class Bootstrap {
  Bootstrap._();

  /// 启动序列：签名清单校验 → kernel 装配。
  static BootResult run({bool bypassIntegrity = false}) {
    Log.d('boot', 'bootstrap run (bypass=$bypassIntegrity)');
    final manifest = _loadManifest();
    final ok = bb.BootBridge.verifyIntegrity(manifest, bypass: bypassIntegrity);
    if (!ok) {
      // debug bypass 时 rejected=true 但 init 决定继续；release 直接拒绝
      return BootResult(rejected: true, kernel: null);
    }
    return BootResult(rejected: false, kernel: bb.BootBridge.assemble());
  }

  static dynamic _loadManifest() {
    // 构建期由 tool/gen_manifest.dart 生成 assets/integrity/manifest.json
    try {
      return jsonDecode(
          File('assets/integrity/manifest.json').readAsStringSync());
    } catch (e, st) {
      Log.e('boot', 'manifest load failed', e, st);
      return null;
    }
  }
}

/// 由 surface 桥注入根组件构建器；L2 不得直接 import L6。
typedef WidgetBuilderHook = Object Function(BootResult result);
WidgetBuilderHook bootstrapWidgetHook = (r) =>
    throw UnimplementedError('surface bridge not installed');
