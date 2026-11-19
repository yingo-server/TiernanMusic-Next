// L1 init 级 · 启动入口
// TiernanMusicNext: 六层五桥架构。init 层职责：
// 1. 经 path_provider 拿存储根目录（L1 特例，注入 runBoot(rootDir:)）
// 2. 显式 registerBootloader() 后经 bridge_boot.runBoot() 触发 L2 bootloader
//    （kernel + core 依赖装配；无运行期完整性校验）
// 3. 经 bridge_surface.installServices → bootstrapApp 完成装配与 runApp
// 失败处理：任何启动期异常都渲染可见错误页（不再静默退出，避免"闪退"观感）。
import 'dart:io';

import 'package:flutter/material.dart';
// Clipboard：启动失败页"复制诊断信息"（把原因+日志一键带给开发者）。
import 'package:flutter/services.dart';
// L1 特例（架构放行）：仅 main 允许 path_provider——L2 bootloader 禁 flutter，
// 存储根目录必须由依赖图根（main）拿好后注入 runBoot(rootDir:)。
import 'package:path_provider/path_provider.dart';

// Log 经 bridge_boot 再导出（L1→kernel 跨层 import 被层审计拒绝，只走桥）。
import '../bridges/bridge_boot.dart' show BootOutcome, Log, runBoot;
// L1 装配根触发 L2 显式注册（bootloader.dart 的 installBootBridge() 需被调用
// 才完成注册；见 lib/bootloader/register.dart 头注释）。这是 L1→L2 的最小装配例外，
// 业务调用仍全部经 bridge_boot。
import '../bootloader/register.dart' show registerBootloader;
import '../bridges/bridge_surface.dart'
    show
        SurfaceDeps,
        bootstrapApp,
        installServices,
        spErrorThemeData,
        platformCapabilities,
        windowService;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final debugBypass =
      args.contains('--bypass-integrity') ||
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
  // ① 存储根目录（L1 特例）。
  //
  // 关键修复：**不再静默回落到相对根 '.'**。
  // 旧行为：path_provider 失败 → rootDir=null → bootloader 用 '.' →
  //   Android 进程 CWD 是 '/' → StoragePaths 的 createSync 抛 PathAccessException
  //   → boot rejected（真机启动失败，且原因被固定文案掩盖）。
  // 旧代码的 fallback 只写在注释里（"仅 debug 可跑通"），release 真机照样走这条路。
  // 现在：拿不到存储根 = 明确的启动失败，错误页直接显示真实原因。
  String rootDir;
  try {
    rootDir = (await getApplicationSupportDirectory()).path;
  } catch (e, st) {
    debugPrint('main: path_provider failed: $e\n$st');
    runApp(_BootErrorApp(
      message: '无法获取应用存储目录（storage root unavailable）\n'
          '$e\n\n应用无法在无存储目录的情况下启动。',
    ));
    return;
  }
  // ①b 日志落盘 sink：release 真机 stdout 不可见，boot 日志必须写文件，
  //     否则"see boot log"无从查证。L3 只暴露 sink 钩子，写盘由 L1 实施。
  _installLogSink(rootDir);

  // ③ runBoot（kernel + core 装配，无运行期完整性校验）。返回类型化的
  //    BootOutcome（见 bridge_boot）：init 层只认 BootOutcome 形状 + deps
  //    具名键，不再对 dynamic 做 .client 探测。
  registerBootloader();
  final Object? raw = runBoot(bypassIntegrity: debugBypass, rootDir: rootDir);
  final BootOutcome outcome = raw is BootOutcome
      ? raw
      : BootOutcome.fromAny(raw);

  if (outcome.rejected) {
    // 启动失败（桥归一化形状）：显示真实原因，不静默退出。
    final reason =
        '${outcome.error.isEmpty ? 'boot failed' : outcome.error}'
                '\n${outcome.detail}'
            .trim();
    debugPrint('main: boot failure: $reason');
    runApp(_BootErrorApp(message: '启动失败：$reason'));
    return;
  }

  // ④ surface 装配（L6 经桥）：仅按 deps 具名键取值（Map 形状），零 duck typing。
  final deps = outcome.deps;
  // 审查修复：全 dep 判空（旧代码只查 client/songDao，其余 5 个可为 null
  // 却被下游按非 null 用 → NPE）。缺任一走错误页，不静默降级。
  const requiredDeps = <String>[
    'client',
    'songDao',
    'playlistDao',
    'historyDao',
    'downloadStore',
    'settings',
    'paths',
  ];
  final missing = <String>[
    for (final k in requiredDeps)
      if (deps[k] == null) k,
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

  // ⑤ 桌面窗口服务初始化（隐藏原生标题栏 + 监听窗口事件 + 最小尺寸）。
  //    必须在 runApp 前 await，否则自绘标题栏叠在原生标题栏上、事件不注册。
  if (platformCapabilities.supportsCustomTitleBar) {
    try {
      await windowService.ensureInitialized(
        minWidth: 640,
        minHeight: 480,
        customTitleBar: true,
      );
    } catch (e, st) {
      debugPrint('main: window init failed (non-fatal): $e\n$st');
    }
  }

  // ⑥ runApp（bridge_surface 内部完成）。把归一化前的原始 L2 结果原样交回
  //    既有 bootstrapApp，保持其桥业务逻辑不变（不在本次改动范围）。
  bootstrapApp(outcome.dep('__raw'));
}

/// 把 L3 日志写到存储根的 logs/boot.log（L1 实施写盘，L3 只提供 sink 钩子）。
///
/// 失败静默：落盘不可用不得阻断启动。
void _installLogSink(String? rootDir) {
  try {
    final base = rootDir ?? '.';
    final dir = Directory('${base.endsWith('/') ? base : '$base/'}logs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/boot.log');
    // 启动即截断：只保留本次启动的日志，便于真机取证。
    if (file.existsSync()) file.deleteSync();
    Log.sink = (line) {
      try {
        file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      } catch (_) {
        // ignore
      }
    };
  } catch (e) {
    debugPrint('main: log sink install failed: $e');
  }
}

/// 启动失败可见页（M3 全屏报错，替代静默退出/闪退观感）。
///
/// 关键修复：显示**真实失败原因**与 boot 日志尾部。
/// 旧版只显示固定文案 "core assembly failed (see boot log)"，而 boot log
/// 只 print 不落盘 —— release 真机上用户与开发者都拿不到任何线索，
/// 导致"CI 全绿但真机启动失败"长期无法定位。
class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    // 关键修复：主题必须**先建好再传给 MaterialApp**，不能用 Theme.of(context)。
    // 旧版在 build 里取 Theme.of(context) 拿到的是 MaterialApp 尚未应用主题时
    // 的外层上下文（默认亮色），导致错误页出现"深底 + 亮色文字/图标"的割裂配色。
    final theme = spErrorThemeData();
    final scheme = theme.colorScheme;
    // boot 日志尾部：取最后 40 行，让真机一屏可见根因。
    final logTail = Log.recent.reversed.take(40).toList().reversed.join('\n');
    final detail = message.trim();
    final hasLog = logTail.trim().isNotEmpty;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        appBar: AppBar(title: const Text('TiernanMusicNext 无法启动')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: scheme.error,
                semanticLabel: '启动失败',
              ),
              const SizedBox(height: 16),
              Text(
                'TiernanMusicNext 无法启动',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (hasLog) ...[
                const SizedBox(height: 24),
                Text('启动日志（末尾 40 行）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    logTail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 一键复制完整诊断（原因 + 日志），用户直接粘给开发者即可，
                // 无需截图、不依赖外部工具。
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await Clipboard.setData(
                          ClipboardData(text: '$detail\n\n$logTail'),
                        );
                        messenger.showSnackBar(
                          const SnackBar(content: Text('诊断信息已复制')),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('复制失败：$e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('复制诊断信息'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'TiernanMusicNext LTS',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
