// 五桥 · 每桥只暴露其下层的门面；桥函数统一 try/catch + Log 留痕。
// L2 可用：bridge_boot.dart（暴露 kernel 门面）
library;

import '../kernel/kernel.dart' as k;

export '../kernel/kernel.dart' show IntegrityVerifier, Kernel, KernelContext, Log;

class BootBridge {
  BootBridge._();

  /// bootloader 暴露给 init 的唯一入口。
  static k.KernelContext assemble() {
    try {
      return k.Kernel.assemble();
    } catch (e, st) {
      k.Log.e('bridge_boot', 'assemble failed', e, st);
      rethrow;
    }
  }

  static bool verifyIntegrity(dynamic manifest, {bool bypass = false}) {
    try {
      return k.IntegrityVerifier.verify(manifest, bypass: bypass);
    } catch (e, st) {
      k.Log.e('bridge_boot', 'verify failed', e, st);
      return false;
    }
  }
}

class BootResult {
  const BootResult({required this.rejected, required this.kernel});
  final bool rejected;
  final k.KernelContext? kernel;
}
