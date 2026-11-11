// L1 init 级 · 启动入口
// TiernanMusicNext: 六层五桥架构。init 层职责：
// 1. 从 rootBundle 预加载完整性清单与模块字节（Android APK 内无 lib/ 文件系统路径）
// 2. 经 bridge_boot.runBoot() 触发 L2 bootloader（完整性校验 + 依赖装配）
// 3. 经 bridge_surface.installServices → bootstrapApp 完成装配与 runApp
// 失败处理：任何启动期异常都渲染可见错误页（不再静默退出，避免"闪退"观感）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_miuix/miuix.dart';
// L1 特例（架构放行）：仅 main 允许 path_provider——L2 bootloader 禁 flutter，
// 存储根目录必须由依赖图根（main）拿好后注入 runBoot(rootDir:)。
import 'package:path_provider/path_provider.dart';

import '../bridges/bridge_boot.dart' show runBoot;
import '../bridges/bridge_surface.dart'
    show SurfaceDeps, bootstrapApp, installServices;

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

  // ② 完整性清单 + 模块字节（Android APK 内无 lib/ 路径，必须随包携带）。
  var manifest = <String, dynamic>{};
  var moduleBytes = <String, List<int>>{};
  try {
    final raw = await rootBundle.loadString('assets/integrity/manifest.json');
    manifest = jsonDecode(raw) as Map<String, dynamic>;
    final mods = (manifest['modules'] as Map).cast<String, dynamic>();
    for (final path in mods.keys) {
      final data = await rootBundle.load('assets/integrity/modules/$path');
      moduleBytes[path] = data.buffer.asUint8List(
          data.offsetInBytes, data.lengthInBytes);
    }
    debugPrint('main: manifest loaded, ${moduleBytes.length} module blobs');
  } catch (e, st) {
    debugPrint('main: integrity assets unavailable: $e/$st');
  }

  // ③ runBoot（完整性校验 + core 装配）。
  final exit = runBoot(
      bypassIntegrity: debugBypass,
      rootDir: rootDir,
      manifest: manifest,
      moduleBytes: moduleBytes);
  if (exit.rejected && !debugBypass) {
    // 校验未通过：显示明确原因（不是静默退出）。
    runApp(const _BootErrorApp(
      message: '完整性校验未通过，应用已停止启动。\n'
          '请从官方渠道重新安装最新版本。',
    ));
    return;
  }
  if (exit.rejected) {
    debugPrint('⚠️ NEXT_DEBUG: integrity bypass active — build is UNVERIFIED');
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
/// 与 app_root 相同的宿主方式：MaterialApp + MiuixTheme + MiuixScaffold。
class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MiuixTheme(
        data: MiuixThemeData(brightness: Brightness.light),
        child: MiuixScaffold(
          backgroundColor: const Color(0xFFF7F5FC),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Color(0xFF7C4DFF)),
                    const SizedBox(height: 16),
                    const Text('TiernanMusicNext 无法启动',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    const Text('v26.11.12.01 LTS',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
