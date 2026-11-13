// L2 bootloader 级 · 启动注册入口（L1 装配根触发一次安装）。
// 存在原因：bootloader 的桥注册函数需被显式调用（Dart 顶层变量惰性初始化，
// 顶层 final 无人读取时永不执行）。业务调用仍全部经 bridge_boot。
// 批07-A：安装 + 零副作用自检（bridge_boot.bootBridgeReady 只读 getter）。
import 'bootloader.dart' show installBootBridge;
import '../bridges/bridge_boot.dart' show bootBridgeReady;

class _BootBridgeInstallState {
  _BootBridgeInstallState._();
  static bool installed = false;
}

bool get bootBridgeInstalled =>
    _BootBridgeInstallState.installed && bootBridgeReady;

void registerBootloader() {
  if (_BootBridgeInstallState.installed) return;
  try {
    installBootBridge();
  } catch (e, st) {
    throw StateError('boot bridge install failed: $e\n$st');
  }
  if (!bootBridgeReady) {
    throw StateError('boot bridge install failed: impl not registered');
  }
  _BootBridgeInstallState.installed = true;
}
