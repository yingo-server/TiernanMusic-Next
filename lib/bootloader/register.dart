// L2 bootloader 级 · 启动注册入口（仅供 L1 装配根触发一次安装）。
//
// 存在原因：bootloader 的桥注册函数需被显式调用（Dart 顶层变量惰性初始化，
// 顶层 final 无人读取时永不执行）；按六五原则 L1 只经桥触达 L2，
// 故这里提供 L1 → L2 的最小装配入口，业务调用仍全部经 bridge_boot。
import 'bootloader.dart' show installBootBridge;

/// 由 L1（init）调用一次：把启动实现安装进 bridge_boot。
void registerBootloader() {
  installBootBridge();
}
