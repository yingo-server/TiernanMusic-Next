// L1 init 级 · 启动入口
// TiernanMusic-Next: 六层五桥架构。init 层职责：
// 1. 经 bridge_boot.runBoot() 触发 L2 bootloader（完整性校验 + 依赖装配）
// 2. 校验失败且非 debug 构建时拒绝启动
// 3. 批5-B：成功路径拿 BootResult 的 core 单例 → 构造 SurfaceDeps →
//    经 bridge_surface.installServices（assembly.assembleAll 真正装配点）→
//    bridge_surface.bootstrapApp。批7-A：init 不再直连 L2/L6，只经桥。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// L1 特例（架构放行）：仅 main 允许 path_provider——L2 bootloader 禁 flutter，
// 存储根目录必须由依赖图根（main）拿好后注入 runBoot(rootDir:)。
// 时序：path_provider 目录 → runBoot(rootDir:) → installServices → runApp。
import 'package:path_provider/path_provider.dart';

import '../bridges/bridge_boot.dart' show runBoot;
import '../bridges/bridge_surface.dart'
    show SurfaceDeps, bootstrapApp, installServices;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final debugBypass = args.contains('--bypass-integrity') ||
      const bool.fromEnvironment('NEXT_DEBUG_BYPASS');

  // 拿存储根目录（L1 特例）。失败退 null：bootloader 内相对根兜底（仅 debug）。
  String? rootDir;
  try {
    rootDir = (await getApplicationSupportDirectory()).path;
  } catch (e, st) {
    debugPrint('main: path_provider failed, fallback relative root: $e/$st');
  }

  // runBoot 返回 dynamic（BootResult 形状），动态取值 rejected/client 等。
  final exit = runBoot(bypassIntegrity: debugBypass, rootDir: rootDir);
  if (exit.rejected) {
    // 完整性校验失败：debug 下打显著标记继续，release 直接拒绝
    if (!debugBypass) {
      SystemNavigator.pop();
      return;
    }
    debugPrint('⚠️ NEXT_DEBUG: integrity bypass active — build is UNVERIFIED');
  }

  // 批5-B：bootloader 成功路径已装配 core 单例并恢复会话（BootResult.auth）。
  // 这里构造 SurfaceDeps 并触发 surface 全量装配（assembly.assembleAll）。
  // TODO(批5-A)：JustAudioEngine 完成后经 installServices(engine: ...) 传入；
  // 当前缺省 NullAudioEngine（PlayerController 可跑通但无声）。
  if (exit.client != null && exit.songDao != null) {
    await installServices(
      deps: SurfaceDeps(
        client: exit.client!,
        songDao: exit.songDao!,
        playlistDao: exit.playlistDao!,
        historyDao: exit.historyDao!,
        downloadStore: exit.downloadStore!,
        settings: exit.settings!,
        paths: exit.paths,
      ),
    );
  } else {
    debugPrint('⚠️ main: core assembly failed (rejected=true), surface not installed');
  }

  // L1→L6 装配特例：bootstrapApp 消费 installServices 装配结果并 runApp。
  bootstrapApp(exit);
}
