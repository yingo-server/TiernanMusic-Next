// L1 init 级 · 启动入口
// TiernanMusic-Next: 六层五桥架构。init 层只做两件事：
// 1. 运行 Bootstrap.run()（L2 bootloader 编排模块签名校验与依赖装配）
// 2. 校验失败且非 debug 构建时拒绝启动
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bootloader/bootloader.dart';
import '../surface/app_root.dart' show bootstrapApp;

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final debugBypass = args.contains('--bypass-integrity') ||
      const bool.fromEnvironment('NEXT_DEBUG_BYPASS');
  // debugBypass 仅允许在 debug 构建生效（bootloader 内有 assert 双保险）
  final exit = Bootstrap.run(bypassIntegrity: debugBypass);
  if (exit.rejected) {
    // 完整性校验失败：debug 下打显著标记继续，release 直接拒绝
    if (!debugBypass) {
      SystemNavigator.pop();
      return;
    }
    debugPrint('⚠️ NEXT_DEBUG: integrity bypass active — build is UNVERIFIED');
  }
  // L1→L6 装配特例：bootstrapApp 内部会调用 installServices 前置的 deps
  // 或按 StoragePaths.I 自装配（见 surface/app_root.dart 文件头注释）。
  bootstrapApp(exit);
}
