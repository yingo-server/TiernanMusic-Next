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

  static bool verifyIntegrity(dynamic manifest,
      {bool bypass = false, Map<String, List<int>>? moduleBytes}) {
    try {
      return k.IntegrityVerifier.verify(manifest,
          bypass: bypass, moduleBytes: moduleBytes);
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

/// init 层唯一启动入口包装：转调 bootloader.Bootstrap.run（L1 禁直连 L2）。
/// try/catch + Log 留痕；失败返回 rejected=true 的 BootResult 形状
/// （dynamic 返回，避免 init 与 BootResult 类型耦合）。
/// [manifest] 与 [moduleBytes] 由 L1 从 rootBundle 预加载（Android APK 内无
/// lib/ 文件系统路径，必须随包携带模块字节才能校验）。
dynamic runBoot(
  {bool bypassIntegrity = false,
  String? rootDir,
  dynamic manifest,
  Map<String, List<int>>? moduleBytes}) {
  try {
    // 延迟 import 由 bootloader 侧 Bootstrap 提供实现；此处经 kernel 出口取。
    return runBootImpl(
        bypassIntegrity: bypassIntegrity,
        rootDir: rootDir,
        manifest: manifest,
        moduleBytes: moduleBytes);
  } catch (e, st) {
    k.Log.e('bridge_boot', 'runBoot failed', e, st);
    return const BootResult(rejected: true, kernel: null);
  }
}

/// 由 bootloader 在装配时经桥注册的实现（避免桥反向 import L2）。
dynamic Function({
  bool bypassIntegrity,
  String? rootDir,
  dynamic manifest,
  Map<String, List<int>>? moduleBytes
})? _runBootImpl;
void setRunBootImpl(
    dynamic Function({
      bool bypassIntegrity,
      String? rootDir,
      dynamic manifest,
      Map<String, List<int>>? moduleBytes
    }) impl) {
  try {
    _runBootImpl = impl;
    k.Log.d('bridge_boot', 'runBoot impl installed');
  } catch (e, st) {
    k.Log.e('bridge_boot', 'setRunBootImpl failed', e, st);
  }
}

dynamic runBootImpl(
    {bool bypassIntegrity = false,
    String? rootDir,
    dynamic manifest,
    Map<String, List<int>>? moduleBytes}) {
  try {
    final impl = _runBootImpl;
    if (impl == null) {
      throw StateError('runBoot impl not installed (bootloader must register)');
    }
    return impl(
        bypassIntegrity: bypassIntegrity,
        rootDir: rootDir,
        manifest: manifest,
        moduleBytes: moduleBytes);
  } catch (e, st) {
    k.Log.e('bridge_boot', 'runBootImpl failed', e, st);
    return const BootResult(rejected: true, kernel: null);
  }
}
