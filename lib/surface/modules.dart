// L6 surface · 模块统一装配出口（defaultModules）
// 三个功能模块页在此以工厂注入依赖，并统一经 SurfaceRegistry.install 装配；
// 重复 id 覆盖替换（幂等），宿主不硬编码页面列表，即热插拔接入。
// 模块间零直接 import：共享依赖只经本工厂参数与 riverpod provider。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridges/bridge_core.dart' show AudioQuality, KeyValueSettings;
import '../bridges/bridge_logic.dart'
    show SearchLogic, PlaylistLogic, Log, CollectLogic, SearchTypedLogic,
        PrefetchEngine;
import 'pages/player_page.dart' show PlayerPageModule;
import 'widgets/mini_bar.dart' show MiniBar;
import 'pages/playlist_page.dart' show PlaylistPageModule;
import 'pages/search_page.dart' show SearchPageModule;
import 'audio/audio_service_bridge.dart'
    show initAudioService, MinimalAudioHandler;
import 'audio/just_audio_engine.dart' show JustAudioEngine;
import 'player_controller.dart'
    show
        PlayerController,
        PlaySourceResolver,
        AudioEngine,
        playerProvider,
        playerControllerProvider;
import 'registry.dart' show SurfaceModule, SurfaceRegistry;

export 'widgets/mini_bar.dart' show MiniBar;
export '../bridges/bridge_logic.dart' show PlaybackService;

/// Surface 层装配依赖（由 bootloader 注入，surface 不 import logic 内部/装配代码）。
class ModuleDeps {
  ModuleDeps({
    required this.search,
    required this.playlist,
    required this.resolver,
    this.quality = '128',
    this.engine,
    this.settings,
    this.collect,
    this.onQualitySelected,
    this.onOpenComments,
    this.searchTyped,
    this.onStartFm,
  });

  /// 批2-C 装配好的搜索 logic。
  final SearchLogic search;

  /// 批2-C 装配好的歌单 logic。
  final PlaylistLogic playlist;

  /// 播放源解析门面（典型：PlaybackService().resolvePlaySource tear-off）。
  final PlaySourceResolver resolver;

  /// 目标音质（128/320/flac …），传给 resolver。
  final String quality;

  /// 键值设置（可选注入；搜索历史/播放偏好持久化用）。
  final KeyValueSettings? settings;

  /// 音频引擎（可选注入）。为 null 时本层自建 JustAudioEngine（正常出声）；
  /// 注入 NullAudioEngine 等替身时用于无音频环境（此时不初始化通知栏）。
  final AudioEngine? engine;

  /// 收藏门面（可选）。
  final CollectLogic? collect;

  /// 音质选择回调（可选）。
  final void Function(AudioQuality quality)? onQualitySelected;

  /// 评论入口（可选）。
  final void Function()? onOpenComments;

  /// 个人 FM 入口（可选；播放页 AppBar FM 按钮）。
  final void Function()? onStartFm;

  /// 六类分类搜索门面（可选；批6-B 的 Tab 依赖此注入）。
  final SearchTypedLogic? searchTyped;
}

/// 已装配的唯一播放控制器实例（assembly 复用，禁止再建第二个）。
PlayerController? _installedController;

/// 本层装配出的播放控制器（未装配时为 null）。
PlayerController? get installedPlayerController => _installedController;

/// 构建默认模块集 + 装配全局 PlayerController provider override（异步：
/// audio_service 初始化为可选能力，await 失败不阻断）。
/// 用法（boot 处）：本函数内部已把全部默认模块逐个
/// SurfaceRegistry.install（重复 id 覆盖替换，幂等），返回的列表仅供宿主
/// 检查/构建路由；宿主不得把页面类硬编码进 app_root，统一取 registry 的
/// active() / navEntries() / providerOverrides。
/// ```dart
/// final deps = ModuleDeps(search: s, playlist: p, resolver: playback.resolvePlaySource);
/// final modules = await defaultModules(deps); // 已装配完毕
/// // ProviderScope 的 overrides 取 SurfaceRegistry.providerOverrides
/// ```
Future<List<SurfaceModule>> defaultModules(ModuleDeps deps) async {
  try {
    // 播放控制器：**全局唯一实例**（批08 修复：此前 assembly 与本层各建一个，
    // 导致列表播放走静音 NullAudioEngine、播放页走另一实例 → 状态分裂且无声）。
    // 引擎回调需引用尚未构造完的 controller，用可空引用间接接通。
    PlayerController? controllerRef;
    final injected = deps.engine;
    final AudioEngine engine = injected ??
        JustAudioEngine(onAction: (a) => controllerRef?.handleEngineAction(a));
    // 通知栏桥（可选能力）：仅 JustAudioEngine 有底层 player；失败不阻断装配。
    // 先初始化再构造 PlayerController，才能把返回的 handler 注入控制器推 metadata。
    MinimalAudioHandler? audioHandler;
    if (engine is JustAudioEngine) {
      try {
        audioHandler = await initAudioService(engine.rawPlayer);
      } catch (e, st) {
        Log.w('surface.modules', 'audioService init skipped: $e $st');
      }
    }
    // 预读引擎：队列变化时预热后续曲目播放源（网络层缓存命中即秒开）。
    final prefetch = PrefetchEngine();
    final controller = PlayerController(
      resolver: deps.resolver,
      engine: engine,
      quality: deps.quality,
      prefetch: prefetch,
      audioHandler: audioHandler,
      // historyRecorder 待 assembly 注入（本层无 HistoryRecorder 实例，不强行造）。
    );
    controllerRef = controller;
    _installedController = controller;
    // 通知栏 next/prev 接线（批5-F2）：handler 早于 controller 创建，故在
    // controller 就绪后 bind 回调；bridge 不反向依赖 controller。
    try {
      audioHandler?.bind(
        onNext: () {
          controller.next();
        },
        onPrev: () {
          controller.prev();
        },
      );
    } catch (e, st) {
      Log.w('surface.modules', 'audioHandler bind next/prev failed: $e $st');
    }
    final overrides = <Override>[
      playerProvider.overrideWith((ref) => controller),
      playerControllerProvider.overrideWith((ref) => controller),
    ];
    SurfaceRegistry.setOverrides(overrides);

    // 三个页面模块全部经 SurfaceRegistry 装配：重复 id 覆盖替换（幂等）。
    // 返回列表仅供宿主检查/构建路由，宿主不得把页面类硬编码到 app_root。
    final modules = <SurfaceModule>[
      SearchPageModule(
          search: deps.search,
          player: controller,
          typed: deps.searchTyped,
          settings: deps.settings),
      PlaylistPageModule(playlist: deps.playlist, player: controller),
      PlayerPageModule(
        controller: controller,
        collect: deps.collect,
        onQualitySelected: deps.onQualitySelected,
        onOpenComments: deps.onOpenComments,
        onStartFm: deps.onStartFm,
      ),
    ];
    for (final module in modules) {
      try {
        SurfaceRegistry.install(module);
      } catch (e, st) {
        // 单个模块装配失败不影响其余模块；install 自身亦带兜底。
        Log.e('surface.modules', 'install ${module.id} failed', e, st);
      }
    }
    return List<SurfaceModule>.unmodifiable(modules);
  } catch (e, st) {
    // 不 import kernel（层纪律），异常信息由桥层 Log 兜底留痕。
    Log.e('surface.modules', 'defaultModules failed', e, st);
    return const <SurfaceModule>[];
  }
}

/// MiniBar 从这里 re-export，宿主（主页 Scaffold bottomNavigationBar 上方）直接引用。
// PlaybackService 类型 re-export，供 boot 处书写 resolver tear-off 类型。
