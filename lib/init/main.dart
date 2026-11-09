// L1 init 级 · 启动入口
// TiernanMusic-Next: 六层五桥架构。init 层职责：
// 1. 运行 Bootstrap.run()（L2 bootloader 编排模块签名校验与依赖装配）
// 2. 校验失败且非 debug 构建时拒绝启动
// 3. 批5-B：成功路径拿 BootResult 的 core 单例 → 构造 SurfaceDeps →
//    surface.installServices（assembly.assembleAll 真正装配点）→ bootstrapApp。
//    main 是依赖图根（唯一允许 import bootloader+surface 的特例，审计白名单）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// L1 特例（架构放行）：仅 main 允许 path_provider——L2 bootloader 禁 flutter，
// 存储根目录必须由依赖图根（main）拿好后注入 Bootstrap.run(rootDir:)。
// 时序：path_provider 目录 → Bootstrap.run(rootDir:) → installServices → runApp。
import 'package:path_provider/path_provider.dart';

import '../bootloader/bootloader.dart';
import '../surface/app_root.dart'
    show SurfaceDeps, installServices, bootstrapApp;

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

  final exit = Bootstrap.run(bypassIntegrity: debugBypass, rootDir: rootDir);
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
    installServices(
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
