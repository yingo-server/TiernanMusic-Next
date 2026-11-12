// L1 init 级 · 启动入口
// TiernanMusicNext: 六层五桥架构。init 层职责：
// 1. 从 rootBundle 预加载完整性清单与模块字节（Android APK 内无 lib/ 文件系统路径）
// 2. 经 bridge_boot.runBoot() 触发 L2 bootloader（完整性校验 + 依赖装配）
// 3. 经 bridge_surface.installServices → bootstrapApp 完成装配与 runApp
// 失败处理：任何启动期异常都渲染可见错误页（不再静默退出，避免"闪退"观感）。
import 'dart:convert';

import 'package:flutter/material.dart';
// L1 特例（架构放行）：仅 main 允许 path_provider——L2 bootloader 禁 flutter，
// 存储根目录必须由依赖图根（main）拿好后注入 runBoot(rootDir:)。
import 'package:path_provider/path_provider.dart';

import '../bridges/bridge_boot.dart' show runBoot;
// L1 装配根触发 L2 自注册（bootloader.dart 的注册语句需文件被加载才执行；
// 见 lib/bootloader/register.dart 头注释）。这是 L1→L2 的最小装配例外，
// 业务调用仍全部经 bridge_boot。
import '../bootloader/register.dart' show registerBootloader;
import '../bridges/bridge_surface.dart'
    show SurfaceDeps, bootstrapApp, installServices, tnLightThemeData;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final debugBypass = args.contains('--bypass-integrity') ||
      const bool.fromEnvironment('NEXT_DEBUG_BYPASS');

  try {
    await _boot(debugBypass: debugBypass);
  } catch (e, st) {
    // 兜底：启动期任何异常都给出可见错误页（不静默退出）。
    debugPrint('main: boot failed: $e\n$st');
    runApp(_BootErrorApp(message: '$e'));
  }
}

Future<void> _boot({required bool debugBypass}) async {
  // ① 存储根目录（L1 特例）。失败退 null：bootloader 内相对根兜底（仅 debug）。
  String? rootDir;
  try {
    rootDir = (await getApplicationSupportDirectory()).path;
  } catch (e, st) {
    debugPrint('main: path_provider failed, fallback relative root: $e/$st');
  }

  // ② 完整性校验已移除（Flutter 对深层子目录 asset 不可靠，逐版失败）。
  //    改为 CI 构建时生成 verification.json（加盐 md5/sha512 + RSA-4096 签名）
  //    随同版本 release 发布；本地无法验证时仅警报不阻塞（用户原则）。

  // ③ runBoot（core 装配）。失败时返回 Map{rejected,error,detail}（见 bridge_boot）。
  registerBootloader();
  final exit = runBoot(
      bypassIntegrity: debugBypass,
      rootDir: rootDir);

  if (exit is Map) {
    // 启动失败（桥兜底形状）：显示真实原因，不静默退出。
    final reason = '${exit['error'] ?? 'boot failed'}'
        '\n${exit['detail'] ?? ''}'.trim();
    debugPrint('main: boot failure: $reason');
    runApp(_BootErrorApp(message: '启动失败：$reason'));
    return;
  }

  // ④ surface 装配（L6 经桥）。
  if (exit.client != null && exit.songDao != null) {
    try {
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
    } catch (e, st) {
      debugPrint('main: installServices failed: $e\n$st');
      runApp(_BootErrorApp(message: '装配失败：$e'));
      return;
    }
  } else {
    debugPrint('⚠️ main: core assembly failed, surface not installed');
    runApp(const _BootErrorApp(message: '核心模块装配失败。'));
    return;
  }

  // ⑤ runApp（bridge_surface 内部完成）。
  bootstrapApp(exit);
}

/// 启动失败可见页（miuix 风格全屏报错，替代静默退出/闪退观感）。
/// M3 全屏报错（替代静默退出/闪退观感）。
class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: tnLightThemeData(),
      home: Scaffold(
        appBar: AppBar(title: const Text('TiernanMusicNext 无法启动')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('TiernanMusicNext 无法启动',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Text('TiernanMusicNext LTS',
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
