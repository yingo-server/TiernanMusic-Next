// L1 init 级 · 启动入口
// TiernanMusicNext: 六层五桥架构。init 层职责：
// 1. 经 path_provider 拿存储根目录（L1 特例，注入 runBoot(rootDir:)）
// 2. 显式 registerBootloader() 后经 bridge_boot.runBoot() 触发 L2 bootloader
//    （kernel + core 依赖装配；无运行期完整性校验）
// 3. 经 bridge_surface.installServices → bootstrapApp 完成装配与 runApp
// 失败处理：任何启动期异常都渲染可见错误页（不再静默退出，避免"闪退"观感）。
import 'package:flutter/material.dart';
// L1 特例（架构放行）：仅 main 允许 path_provider——L2 bootloader 禁 flutter，
// 存储根目录必须由依赖图根（main）拿好后注入 runBoot(rootDir:)。
import 'package:path_provider/path_provider.dart';

import '../bridges/bridge_boot.dart' show BootOutcome, runBoot;
// L1 装配根触发 L2 显式注册（bootloader.dart 的 installBootBridge() 需被调用
// 才完成注册；见 lib/bootloader/register.dart 头注释）。这是 L1→L2 的最小装配例外，
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

  // ③ runBoot（kernel + core 装配，无运行期完整性校验）。返回类型化的
  //    BootOutcome（见 bridge_boot）：init 层只认 BootOutcome 形状 + deps
  //    具名键，不再对 dynamic 做 .client 探测。
  registerBootloader();
  final Object? raw = runBoot(
      bypassIntegrity: debugBypass,
      rootDir: rootDir);
  final BootOutcome outcome =
      raw is BootOutcome ? raw : BootOutcome.fromAny(raw);

  if (outcome.rejected) {
    // 启动失败（桥归一化形状）：显示真实原因，不静默退出。
    final reason = '${outcome.error.isEmpty ? 'boot failed' : outcome.error}'
        '\n${outcome.detail}'.trim();
    debugPrint('main: boot failure: $reason');
    runApp(_BootErrorApp(message: '启动失败：$reason'));
    return;
  }

  // ④ surface 装配（L6 经桥）：仅按 deps 具名键取值（Map 形状），零 duck typing。
  final deps = outcome.deps;
  // 审查修复：全 dep 判空（旧代码只查 client/songDao，其余 5 个可为 null
  // 却被下游按非 null 用 → NPE）。缺任一走错误页，不静默降级。
  const requiredDeps = <String>[
    'client', 'songDao', 'playlistDao', 'historyDao',
    'downloadStore', 'settings', 'paths',
  ];
  final missing = <String>[
    for (final k in requiredDeps)
      if (deps[k] == null) k
  ];
  if (missing.isNotEmpty) {
    debugPrint('main: core assembly incomplete, missing: $missing');
    runApp(_BootErrorApp(message: '核心模块缺失：${missing.join(', ')}'));
    return;
  }
  try {
    // 审查修复：先 await DB 打开（bootloader 不再 unawaited），
    // DAO 首访绝不禁于未打开的 Isar。
    final dbFuture = deps['dbOpenFuture'];
    if (dbFuture is Future<bool>) {
      await dbFuture;
      debugPrint('main: db ready');
    }
    await installServices(
      deps: SurfaceDeps(
        client: outcome.dep('client'),
        songDao: outcome.dep('songDao'),
        playlistDao: outcome.dep('playlistDao'),
        historyDao: outcome.dep('historyDao'),
        downloadStore: outcome.dep('downloadStore'),
        settings: outcome.dep('settings'),
        paths: outcome.dep('paths'),
      ),
    );
  } catch (e, st) {
    debugPrint('main: installServices failed: $e\n$st');
    runApp(_BootErrorApp(message: '装配失败：$e'));
    return;
  }

  // ⑤ runApp（bridge_surface 内部完成）。把归一化前的原始 L2 结果原样交回
  //    既有 bootstrapApp，保持其桥业务逻辑不变（不在本次改动范围）。
  bootstrapApp(outcome.dep('__raw'));
}

/// 启动失败可见页（M3 全屏报错，替代静默退出/闪退观感）。
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
