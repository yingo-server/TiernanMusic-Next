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
import 'theme/tn_theme.dart';
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
final Provider<asm.AssemblyResult?> assemblyProvider =
    Provider<asm.AssemblyResult?>((ref) => null);

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
asm.AssemblyResult? _pendingAssembly;

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
            return _buildMaterialApp(mode);
          },
        );
      });
    } catch (e, st) {
      Log.e('surface.app_root', 'build crashed', e, st);
      return const _FallbackApp();
    }
  }

  Widget _buildMaterialApp(int mode) {
    try {
      return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'TiernanMusicNext',
          theme: tnLightThemeData(),
          darkTheme:
              mode == 3 ? tnPitchBlackThemeData() : tnDarkThemeData(),
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
          home: const _HomeShell(),
        );
    } catch (e, st) {
      Log.e('surface.app_root', 'buildMaterialApp crashed', e, st);
      return const _FallbackApp();
    }
  }
}

/// 底部导航壳：按 SurfaceRegistry.active 排 navEntry 模块。
class _HomeShell extends StatefulWidget {
  const _HomeShell();
  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;
  // homeTabRequest 监听：装配层回调（onOpenSearch 等）请求切 tab。
  // 弱引用回调句柄（dispose 时移除），防壳重建后悬挂引用。
  static void Function(String)? _tabRequestHandler;

  @override
  void initState() {
    super.initState();
    _tabRequestHandler = (moduleId) {
      try {
        if (!mounted) return;
        final modules = SurfaceRegistry.active(
            ProviderScope.containerOf(context, listen: false)
                .read(logicFacadeProvider))
            .where((m) => m.navEntry != null)
            .toList();
        final i = modules.indexWhere((m) => m.id == moduleId);
        if (i >= 0 && mounted) setState(() => _index = i);
      } catch (e, st) {
        Log.e('surface.home_shell', 'tab request failed id=$moduleId', e, st);
      }
    };
    homeTabRequest.addListener(_dispatchTabRequest);
  }

  static void _dispatchTabRequest() {
    try {
      final id = homeTabRequest.value;
      if (id != null && id.isNotEmpty) _tabRequestHandler?.call(id);
    } catch (e, st) {
      Log.e('surface.home_shell', 'dispatch tab request failed', e, st);
    }
  }

  @override
  void dispose() {
    try {
      homeTabRequest.removeListener(_dispatchTabRequest);
      Log.d('surface.home_shell', 'dispose');
    } catch (e, st) {
      // ignore: avoid_print
      print('surface.home_shell: dispose failed: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final logic = ProviderScope.containerOf(context).read(logicFacadeProvider);
      final modules = SurfaceRegistry.active(logic)
          .where((m) => m.navEntry != null)
          .toList();
      if (modules.isEmpty) {
        return _ScaffoldMessage('无可用模块：请在 surface 桥安装 SurfaceModule');
      }
      if (_index >= modules.length) _index = 0;
      final entries = modules.map((m) => m.navEntry!).toList();
      return Scaffold(
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            try {
              setState(() => _index = i);
            } catch (e, st) {
              Log.e('surface.home_shell', 'tab tap failed', e, st);
            }
          },
          destinations: [
            for (final e in entries)
              NavigationDestination(
                  icon: Icon(_iconOf(e.icon)),
                  selectedIcon: Icon(_iconOf(e.icon)),
                  label: e.label),
          ],
        ),
        body: Column(children: [
          Container(
            alignment: Alignment.centerLeft,
              padding: const EdgeInsets.fromLTRB(tnPadL, tnPadL, tnPadL, tnPadS),
            child: Text(entries[_index].label, style: TnText.of(context).title),
          ),
          Expanded(child: _ModuleView(module: modules[_index])),
          // 全局迷你播放条：悬浮于底部导航上方（有当前曲才显示）；
          // 点击展开走已装配的播放页模块（id='player'，带收藏/音质/FM/评论回调）。
          MiniBar(onExpand: _expandFullPlayer),
        ]),
      );
    } catch (e, st) {
      Log.e('surface.home_shell', 'build crashed', e, st);
      return _ScaffoldMessage('壳构建异常：$e');
    }
  }

  /// 展开全屏播放页：复用已装配的播放页模块 builder（含收藏/音质/FM/评论接线），
  /// 不使用 MiniBar 内置的裸 PlayerPageBody（那会丢失装配回调）。
  void _expandFullPlayer(BuildContext ctx) {
    try {
      final c = ProviderScope.containerOf(ctx, listen: false);
      final modules = SurfaceRegistry.active(c.read(logicFacadeProvider))
          .where((m) => m.id == 'player')
          .toList();
      if (modules.isEmpty) {
        Log.w('surface.home_shell', 'player module not installed');
        return;
      }
      final builder = modules.first.builder(c.read(logicFacadeProvider));
      Navigator.of(ctx).push(MaterialPageRoute<void>(
          builder: builder, fullscreenDialog: true));
      Log.d('surface.home_shell', 'expand full player');
    } catch (e, st) {
      Log.e('surface.home_shell', 'expandFullPlayer failed', e, st);
    }
  }

  IconData _iconOf(String name) {
    switch (name) {
      case 'search':
        return Icons.search;
      case 'library':
      case 'playlist':
        return Icons.library_music;
      case 'rank':
        return Icons.leaderboard;
      case 'download':
        return Icons.download;
      case 'settings':
      case 'me':
        return Icons.person;
      default:
        return Icons.music_note;
    }
  }
}

/// 模块视图隔离：模块 builder 崩溃不影响壳。
class _ModuleView extends StatefulWidget {
  const _ModuleView({required this.module});
  final SurfaceModule module;
  @override
  State<_ModuleView> createState() => _ModuleViewState();
}

class _ModuleViewState extends State<_ModuleView> {
  @override
  void dispose() {
    try {
      Log.d('surface.module_view', 'dispose ${widget.module.id}');
    } catch (e, st) {
      // ignore: avoid_print
      print('surface.module_view: dispose failed: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final logic = ProviderScope.containerOf(context).read(logicFacadeProvider);
      return KeyedSubtree(
        key: ValueKey(widget.module.id),
        child: widget.module.builder(logic)(context),
      );
    } catch (e, st) {
      Log.e('surface.module_view', 'build ${widget.module.id} crashed', e, st);
      return ErrorRetryBox(message: '模块 ${widget.module.id} 加载失败', onRetry: () {
        try {
          setState(() {});
        } catch (err, s) {
          Log.e('surface.module_view', 'retry failed', err, s);
        }
      });
    }
  }
}

class _ScaffoldMessage extends StatelessWidget {
  const _ScaffoldMessage(this.msg);
  final String msg;
  @override
  Widget build(BuildContext context) {
    debugPrint('surface.app_root: $msg');
    try {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(tnPadL),
                child: Text(msg,
                    textAlign: TextAlign.center,
                    style: TnText.of(context).body))),
      );
    } catch (e) {
      debugPrint('surface.app_root: scaffold message failed: $e');
      return const SizedBox(width: 0, height: 0);
    }
  }
}

class _FallbackApp extends StatelessWidget {
  const _FallbackApp();
  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        body: const Center(child: Text('TiernanMusicNext 启动异常')),
      );
    } catch (e) {
      debugPrint('surface.app_root: fallback build failed: $e');
      return const SizedBox(width: 0, height: 0);
    }
  }
}

