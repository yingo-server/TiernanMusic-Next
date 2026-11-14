// L6 surface 级 · App 壳：riverpod 装配点 + 底部导航 + 亮暗模式
//
// ── L1→L6 装配特例（架构放行说明）──
// init/main.dart（L1）在 Bootstrap.run 之后需要 runApp 一个根组件。若经
// L2 bootloader 的 bootstrapWidgetHook 注入，则该 hook 变量必须由某人赋值，
// 而 L2/L5 均不得 import L6（层审计强制）。因此约定：
//   main.dart 直接 import surface/app_root.dart 并调用顶层函数
//   bootstrapApp(BootResult) 完成 runApp。
// 这是唯一的 init→surface 直接依赖特例（main 是依赖图的根，无其他出边）。
// tool/layer_audit.py 对 init/main.dart → surface/app_root.dart 加了白名单。
// surface 层内部文件仍铁律不变：只能 import bridge_logic / bridge_core /
// flutter / miuix / riverpod，禁触 core/logic 内部。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridges/bridge_core.dart' show KugouClient, SongDao;
import '../bridges/bridge_logic.dart';
import 'assembly.dart' as asm;
import 'assembly_result.dart' show AssemblyResult;
import 'pages/home_shell.dart' show HomeShell, FallbackApp;
import 'providers.dart'
    show appNavigatorKey, homeTabRequest, localeRevision, logicFacadeProvider;
import 'deps.dart' show SurfaceDeps;
import 'player_controller.dart' show AudioEngine;
import 'audio/keep_alive.dart';
import 'player_controller.dart'
    show playerProvider, playerControllerProvider, PlayerSnapshot;
import 'registry.dart';
import 'widgets/common_m3.dart' show ErrorRetryBox;
import 'widgets/mini_bar.dart' show MiniBar;
import 'l10n/l10n_helper.dart' show TnStrings;
import 'theme/theme_state.dart' show themeModeProvider, settingsProvider;
import 'theme/dynamic_theme.dart' show dynamicThemeProvider, ThemePalette;
import 'theme/cover_palette.dart' show applyCoverPalette;
import 'theme/tn_theme.dart'
    show tnThemeWithPalette, tnPitchBlackThemeData, tnPadL, tnPadS, TnText;
import 'theme/tn_shader_warmup.dart' show TnShaderWarmup;

export 'deps.dart' show SurfaceDeps;

// 批04-A（环B破除）：appNavigatorKey / homeTabRequest / localeRevision /
// logicFacadeProvider 已抽至 providers.dart（assembly 不再 import app_root）。
// 本文件经 providers.dart 引用这些符号，行为不变。

// ───────────────────────── 装配 ─────────────────────────

// SurfaceDeps 抽至 deps.dart（避免与 assembly.dart 循环 import）。

final Provider<SurfaceDeps> depsProvider =
    Provider<SurfaceDeps>((ref) => throw UnimplementedError(
        'call installServices(deps) before reading depsProvider'));

final Provider<KugouClient> kugouClientProvider =
    Provider((ref) => ref.watch(depsProvider).client);

final Provider<SongDao> songDaoProvider =
    Provider((ref) => ref.watch(depsProvider).songDao);

// 批5-B：logic 单例不再在此 new，统一由 assembly.assembleAll 装配（见下）。
final Provider<AssemblyResult?> assemblyProvider =
    Provider<AssemblyResult?>((ref) => null);

/// 批5-B：logic 单例统一读装配结果（未装配时抛错暴露装配顺序问题）。
final Provider<SearchLogic> searchLogicProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.search);

final Provider<PlaylistLogic> playlistLogicProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.playlist);

final Provider<RankLogic> rankLogicProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.rank);

final Provider<AuthLogic> authLogicProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.auth);

final Provider<LyricsLogic> lyricsLogicProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.lyrics);

final Provider<PlaybackService> playbackServiceProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.playback);

final Provider<HistoryRecorder> historyRecorderProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.history);

final Provider<DownloadManager> downloadManagerProvider =
    Provider((ref) => ref.watch(assemblyProvider)!.downloads);

/// logic 能力门面（registry.SurfaceModule.enabled/builder 拿这个）
// 批04-A：logicFacadeProvider 已抽至 providers.dart。

// 主题模式唯一状态源见 theme/theme_state.dart（app_root 与 settings_page 共用；
// 此前两处各自声明同名 themeModeProvider 且互不 import，导致切主题对渲染零影响）。
/// 组装函数：bootloader 装配后由 bootstrapApp 调用，注入 core 依赖。
/// 批5-B：不再自装配兜底——强制走 assembly.assembleAll（失败即暴露，不静默降级）。
Future<void> installServices(
    {required SurfaceDeps deps, AudioEngine? engine}) async {
  try {
    final result = await asm.assembleAll(deps, engine: engine);
    _pendingDeps = deps;
    _pendingAssembly = result;
    Log.d('surface.app_root',
        'services installed modules=${result.moduleIds}');
  } catch (e, st) {
    Log.e('surface.app_root', 'installServices failed', e, st);
    rethrow;
  }
}

SurfaceDeps? _pendingDeps;
AssemblyResult? _pendingAssembly;

// ───────────────────────── 启动入口（L1 特例调用点） ─────────────────────────

/// init/main.dart 的 L1→L6 装配特例入口（见文件头说明）。
/// result 为 bootloader 侧 BootResult（动态传入，只取 rejected 布尔）。
void bootstrapApp(dynamic result) {
  try {
    final rejected = (result is Map) ? (result['rejected'] == true) : false;
    Log.d('surface.app_root', 'bootstrapApp rejected=$rejected');
    // 批5-B：兜底自装配路径已删除——installServices 必须先被调用
    // （bootloader 成功路径内装配 deps 并调 installServices）。
    final deps = _pendingDeps;
    final assembly = _pendingAssembly;
    if (deps == null || assembly == null) {
      throw StateError(
          'installServices(deps) was not called before bootstrapApp — '
          'assembly must run in bootloader success path (批5-B)');
    }
    runApp(ProviderScope(
      overrides: [
        depsProvider.overrideWithValue(deps),
        assemblyProvider.overrideWithValue(assembly),
        // 主题模式持久化存储（theme_state.settingsProvider）。
        settingsProvider.overrideWithValue(deps.settings),
        ...SurfaceRegistry.providerOverrides,
      ],
      child: const AppRoot(),
    ));
  } catch (e, st) {
    Log.e('surface.app_root', 'bootstrapApp failed', e, st);
    rethrow;
  }
}

/// surface 自持 BootResult 镜像类型（L6 禁 import L2，只取 rejected 摘要）。
/// bootstrapApp 实际用 dynamic duck-typing（rejected getter），此类型仅作文档锚。
class BootResultMirror {
  const BootResultMirror({required bool rejected}) : _rejected = rejected;
  final bool _rejected;
  bool get rejected => _rejected;
}

// ───────────────────────── AppRoot ─────────────────────────

class AppRoot extends StatefulWidget {
  const AppRoot({Key? key}) : super(key: key);
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  String _lastCover = '';
  bool _lastDark = false;
  KeepAliveCoordinator? _keepAlive;

  @override
  void initState() {
    super.initState();
    try {
      Log.d('surface.app_root', 'init');
      // 保活编排：播放态感知 + 生命周期监听（后台自动暂停默认关闭）。
      _keepAlive = KeepAliveCoordinator(
        playerStateProvider: () {
          // 经 riverpod 容器读当前 PlayerSnapshot.player（PlayerController.state）。
          final el = WidgetsBinding.instance.rootElement;
          if (el == null) return const PlayerState();
          final c = ProviderScope.containerOf(el, listen: false);
          final snap = c.read(playerProvider);
          return snap.player;
        },
        pauseOnBackground: false,
      )..onBackgroundPause = _pausePlayback;
      _keepAlive!.start();
      // 批11-B：首帧后空闲窗口离屏预编译常用材质着色器
      // （会话内幂等 + 7 天窗口重触发，时间戳经 deps.settings 持久化）。
      TnShaderWarmup.schedule(settings: _pendingDeps?.settings);
    } catch (e, st) {
      Log.e('surface.app_root', 'initState failed', e, st);
    }
  }

  void _pausePlayback() {
    try {
      final el = WidgetsBinding.instance.rootElement;
      if (el == null) return;
      final c = ProviderScope.containerOf(el, listen: false);
      c.read(playerControllerProvider.notifier).pause();
    } catch (e, st) {
      Log.e('surface.app_root', 'onBackgroundPause failed', e, st);
    }
  }

  @override
  void dispose() {
    try {
      _keepAlive?.stop();
      Log.d('surface.app_root', 'dispose');
    } catch (e, st) {
      // ignore: avoid_print
      print('surface.app_root: dispose failed: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Consumer(builder: (context, ref, _) {
        final mode = ref.watch(themeModeProvider);
        // 动态主题：当前曲封面变化 → 取色 → 调色板（失败静默回落默认主题）。
        final palette = ref.watch(dynamicThemeProvider);
        final dark = mode == 2 || mode == 3;
        final cover = ref.watch(playerProvider).player.current?.cover ?? '';
        if (cover.isNotEmpty && cover != _lastCover) {
          _lastCover = cover;
          applyCoverPalette(ref, cover, dark: dark);
        }
        if (dark != _lastDark) {
          _lastDark = dark;
          ref.read(dynamicThemeProvider.notifier).setDark(dark);
        }
        // 语言切换重建信号：设置页 _pickLocale 后 ++，此处 ValueListenableBuilder
        // 重建 MaterialApp 使 locale: TnStrings.appLocale() 立即生效（免重启）。
        return ValueListenableBuilder<int>(
          valueListenable: localeRevision,
          builder: (ctx, _, __) {
            try {
              Log.d('surface.app_root', 'locale rebuild rev=$_');
            } catch (e, st) {
              // ignore: avoid_print
              print('surface.app_root: locale rebuild log failed: $e');
            }
            return _buildMaterialApp(mode, palette);
          },
        );
      });
    } catch (e, st) {
      Log.e('surface.app_root', 'build crashed', e, st);
      return const FallbackApp(message: 'TiernanMusicNext 启动异常');
    }
  }

  Widget _buildMaterialApp(int mode, ThemePalette? palette) {
    try {
      return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'TiernanMusicNext',
          theme: tnThemeWithPalette(palette, dark: false),
          darkTheme: mode == 3
              ? tnPitchBlackThemeData()
              : tnThemeWithPalette(palette, dark: true),
          themeMode: switch (mode) {
            1 => ThemeMode.light,
            2 => ThemeMode.dark,
            3 => ThemeMode.dark,
            _ => ThemeMode.system
          },
          // 10 语偏好（TnStrings 从 KeyValueSettings 读取；null = 跟随系统）。
          locale: TnStrings.appLocale(),
          supportedLocales: const <Locale>[
            Locale('zh'),
            Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
            Locale('en'), Locale('ja'), Locale('ko'), Locale('es'),
            Locale('fr'), Locale('de'), Locale('pt'), Locale('ru'),
          ],
          home: const HomeShell(),
        );
    } catch (e, st) {
      Log.e('surface.app_root', 'buildMaterialApp crashed', e, st);
      return const FallbackApp(message: 'TiernanMusicNext 启动异常');
    }
  }
}

/// 底部导航壳：nav 模块 100% 取自 SurfaceRegistry.active(logic) 的 navEntry，
/// 宿主不持有任何硬编码页面 id 列表；tab 集合完全由 registry.install 的模块决定（批08-A 复核）。
