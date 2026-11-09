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
import 'package:flutter/material.dart'
    show
        Alignment,
        BottomNavigationBar,
        BottomNavigationBarItem,
        BottomNavigationBarType,
        Brightness,
        BuildContext,
        Center,
        Color,
        Column,
        EdgeInsets,
        Expanded,
        Icon,
        IconData,
        Icons,
        KeyedSubtree,
        MaterialApp,
        ThemeData,
        ThemeMode,
        Padding,
        StatelessWidget,
        State,
        StatefulElement,
        StatefulWidget,
        Text,
        TextAlign,
        TextStyle,
        ValueKey,
        Widget,
        WidgetBuilder,
        Key,
        Container,
        SizedBox,
        Scaffold,
        ScaffoldMessenger,
        SnackBar,
        UncontrolledProviderScope,
        runApp,
        debugPrint;import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_miuix/miuix.dart';

import '../bridges/bridge_core.dart'
    show
        KugouClient,
        KugouSession,
        SongDao,
        PlaylistDao,
        HistoryDao,
        DownloadStore,
        StoragePaths,
        KeyValueSettings,
        LruCache,
        SearchResult,
        LyricResult;
import '../bridges/bridge_logic.dart';
import 'registry.dart';
import 'widgets/common.dart' show ErrorRetryBox;
import 'theme/tn_theme.dart';

// ───────────────────────── 装配 ─────────────────────────

/// 由 bootloader 装配后的 core 依赖集合（L4 门面对象，禁止携带实现细节给 UI）。
class SurfaceDeps {
  const SurfaceDeps({
    required this.client,
    required this.songDao,
    required this.playlistDao,
    required this.historyDao,
    required this.downloadStore,
    required this.settings,
    this.paths,
  });
  final KugouClient client;
  final SongDao songDao;
  final PlaylistDao playlistDao;
  final HistoryDao historyDao;
  final StoragePaths? paths;

  /// 兜底路径（未注入时取 StoragePaths.I 装配态）。
  StoragePaths get pathsOrI => paths ?? StoragePaths.I;
  final DownloadStore downloadStore;
  final KeyValueSettings settings;
}

final Provider<SurfaceDeps> depsProvider =
    Provider<SurfaceDeps>((ref) => throw UnimplementedError(
        'call installServices(deps) before reading depsProvider'));

final Provider<KugouClient> kugouClientProvider =
    Provider((ref) => ref.watch(depsProvider).client);

final Provider<SongDao> songDaoProvider =
    Provider((ref) => ref.watch(depsProvider).songDao);

final Provider<SearchLogic> searchLogicProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return SearchLogic(
    client: d.client,
    cache: LruCache<String, SearchResult>(capacity: 128),
  );
});

final Provider<PlaylistLogic> playlistLogicProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return PlaylistLogic(
    client: d.client,
    playlistDao: d.playlistDao,
    cache: LruCache<String, dynamic>(capacity: 64),
  );
});

final Provider<RankLogic> rankLogicProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return RankLogic(client: d.client, cache: LruCache<String, dynamic>(capacity: 64));
});

final Provider<AuthLogic> authLogicProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return AuthLogic(client: d.client, settings: d.settings);
});

final Provider<LyricsLogic> lyricsLogicProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return LyricsLogic(
    client: d.client,
    paths: d.pathsOrI,
    cache: LruCache<String, LyricResult>(capacity: 32),
  );
});

final Provider<PlaybackService> playbackServiceProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return PlaybackService(
    client: d.client,
    songDao: d.songDao,
    downloadStore: d.downloadStore,
  );
});

final Provider<HistoryRecorder> historyRecorderProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return HistoryRecorder(historyDao: d.historyDao, songDao: d.songDao);
});

final Provider<DownloadManager> downloadManagerProvider = Provider((ref) {
  final d = ref.watch(depsProvider);
  return DownloadManager(
    playbackService: ref.watch(playbackServiceProvider),
    songDao: d.songDao,
    downloadStore: d.downloadStore,
  );
});

/// logic 能力门面（registry.SurfaceModule.enabled/builder 拿这个）
final Provider<LogicFacade> logicFacadeProvider = Provider((_) => const LogicFacade());

/// 亮暗模式（0=跟随系统, 1=亮, 2=暗）
final StateNotifierProvider<ThemeModeNotifier, int> themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, int>((ref) => ThemeModeNotifier());

class ThemeModeNotifier extends StateNotifier<int> {
  ThemeModeNotifier() : super(0);
  void cycle() {
    try {
      state = (state + 1) % 3;
      Log.d('surface.app_root', 'theme mode -> $state');
    } catch (e, st) {
      Log.e('surface.app_root', 'cycle theme failed', e, st);
    }
  }
}

/// 组装函数：bootloader 装配后由 bootstrapApp 调用，注入 core 依赖。
void installServices({required SurfaceDeps deps}) {
  try {
    // ProviderContainer 由 ProviderScope 在 runApp 时建立；这里用全局覆盖：
    // 简单做法——deps 经 ProviderScope.overrides 注入（见 bootstrapApp）。
    Log.d('surface.app_root', 'services installed');
    _pendingDeps = deps;
  } catch (e, st) {
    Log.e('surface.app_root', 'installServices failed', e, st);
  }
}

SurfaceDeps? _pendingDeps;

// ───────────────────────── 启动入口（L1 特例调用点） ─────────────────────────

/// init/main.dart 的 L1→L6 装配特例入口（见文件头说明）。
/// result 为 bootloader 侧 BootResult（动态传入，只取 rejected 布尔）。
void bootstrapApp(dynamic result) {
  try {
    final rejected = (result is Map) ? (result['rejected'] == true) : false;
    Log.d('surface.app_root', 'bootstrapApp rejected=$rejected');
    final deps = _pendingDeps ??
        SurfaceDeps(
          client: KugouClient(KugouSession()),
          songDao: SongDao(),
          playlistDao: PlaylistDao(),
          historyDao: HistoryDao(),
          downloadStore: DownloadStore(StoragePaths.I),
          settings: KeyValueSettings(StoragePaths.I),
        );
    runApp(ProviderScope(
      overrides: [depsProvider.overrideWithValue(deps)],
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
  @override
  void initState() {
    super.initState();
    try {
      Log.d('surface.app_root', 'init');
    } catch (e, st) {
      Log.e('surface.app_root', 'initState failed', e, st);
    }
  }

  @override
  void dispose() {
    try {
      Log.d('surface.app_root', 'dispose');
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Consumer(builder: (context, ref, _) {
        final mode = ref.watch(themeModeProvider);
        // flutter_miuix 1.3.0 无 MiuixApp 宿主——MaterialApp + MiuixTheme 包裹。
        return MaterialApp(
          title: 'TiernanMusic',
          theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
          darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          themeMode: switch (mode) { 1 => ThemeMode.light, 2 => ThemeMode.dark, _ => ThemeMode.system },
          home: MiuixTheme(
            data: mode == 2
                ? tnDarkThemeData()
                : (mode == 1 ? tnLightThemeData() : tnLightThemeData()),
            child: const _HomeShell(),
          ),
        );
      });
    } catch (e, st) {
      Log.e('surface.app_root', 'build crashed', e, st);
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

  @override
  void dispose() {
    try {
      Log.d('surface.home_shell', 'dispose');
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final logic = UncontrolledProviderScope.containerOf(context).read(logicFacadeProvider);
      final modules = SurfaceRegistry.active(logic)
          .where((m) => m.navEntry != null)
          .toList();
      if (modules.isEmpty) {
        return _ScaffoldMessage('无可用模块：请在 surface 桥安装 SurfaceModule');
      }
      if (_index >= modules.length) _index = 0;
      final entries = modules.map((m) => m.navEntry!).toList();
      return MiuixScaffold(
        bottomBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _index,
          onTap: (i) {
            try {
              setState(() => _index = i);
            } catch (e, st) {
              Log.e('surface.home_shell', 'tab tap failed', e, st);
            }
          },
          items: [
            for (final e in entries)
              BottomNavigationBarItem(
                  icon: Icon(_iconOf(e.icon)), label: e.label),
          ],
        ),
        content: (_) => Column(children: [
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.fromLTRB(tnPadL, tnPadL, tnPadL, tnPadS),
            child: Text(entries[_index].label, style: TnText.of(context).title),
          ),
          Expanded(child: _ModuleView(module: modules[_index])),
        ]),
      );
    } catch (e, st) {
      Log.e('surface.home_shell', 'build crashed', e, st);
      return _ScaffoldMessage('壳构建异常：$e');
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
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final logic = UncontrolledProviderScope.containerOf(context).read(logicFacadeProvider);
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
    return MiuixScaffold(
      containerColor: const Color(0xFFF6F5FA),
      content: (_) => Center(
          child: Padding(
              padding: const EdgeInsets.all(tnPadL),
              child: Text(msg, textAlign: TextAlign.center))),
    );
  }
}

class _FallbackApp extends StatelessWidget {
  const _FallbackApp();
  @override
  Widget build(BuildContext context) {
    try {
      return MiuixScaffold(
        backgroundColor: const Color(0xFFF6F5FA),
        child: const Center(child: Text('TiernanMusic 启动异常')),
      );
    } catch (e) {
      debugPrint('surface.app_root: fallback build failed: $e');
      return const SizedBox(width: 0, height: 0);
    }
  }
}
