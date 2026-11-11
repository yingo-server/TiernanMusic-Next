// L6 surface · 模块统一装配出口（defaultModules）
// 三个功能模块页在此以工厂注入依赖并返回列表；
// bootloader / surface 桥逐个 SurfaceRegistry.install，即热插拔接入。
// 模块间零直接 import：共享依赖只经本工厂参数与 riverpod provider。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridges/bridge_core.dart' show AudioQuality;
import '../bridges/bridge_logic.dart'
    show SearchLogic, PlaylistLogic, Log, CollectLogic, SearchTypedLogic;
import 'pages/player_page.dart' show PlayerPageModule, MiniBar;
import 'pages/playlist_page.dart' show PlaylistPageModule;
import 'pages/search_page.dart' show SearchPageModule;
import 'audio/audio_service_bridge.dart' show initAudioService;
import 'audio/just_audio_engine.dart' show JustAudioEngine;
import 'player_controller.dart'
    show PlayerController, PlaySourceResolver, playerProvider,
        playerControllerProvider;
import 'registry.dart' show SurfaceModule, SurfaceRegistry;

export 'pages/player_page.dart' show MiniBar;
export '../bridges/bridge_logic.dart' show PlaybackService;

/// Surface 层装配依赖（由 bootloader 注入，surface 不 import logic 内部/装配代码）。
class SurfaceDeps {
  SurfaceDeps({
    required this.search,
    required this.playlist,
    required this.resolver,
    this.quality = '128',
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

/// 构建默认模块集 + 装配全局 PlayerController provider override（异步：
/// audio_service 初始化为可选能力，await 失败不阻断）。
/// 用法（boot 处）：
/// ```dart
/// final deps = SurfaceDeps(search: s, playlist: p, resolver: playback.resolvePlaySource);
/// for (final m in defaultModules(deps)) SurfaceRegistry.install(m);
/// ```
Future<List<SurfaceModule>> defaultModules(SurfaceDeps deps) async {
  try {
    // 播放控制器：唯一实例，经两个 provider 暴露（boot 处 override）。
    // 引擎回调需引用尚未构造完的 controller，用可空引用间接接通。
    PlayerController? controllerRef;
    final engine = JustAudioEngine(
        onAction: (a) => controllerRef?.handleEngineAction(a));
    final controller = PlayerController(
      resolver: deps.resolver,
      engine: engine,
      quality: deps.quality,
    );
    controllerRef = controller;

    // 通知栏桥（可选能力）：失败不阻断模块装配。
    try {
      await initAudioService(engine.rawPlayer);
    } catch (e, st) {
      Log.w('surface.modules', 'audioService init skipped: $e $st');
    }
    final overrides = <Override>[
      playerProvider.overrideWith((ref) => controller),
      playerControllerProvider.overrideWith((ref) => controller),
    ];
    SurfaceRegistry.setOverrides(overrides);

    return <SurfaceModule>[
      SearchPageModule(
          search: deps.search,
          player: controller,
          typed: deps.searchTyped),
      PlaylistPageModule(playlist: deps.playlist, player: controller),
      PlayerPageModule(
        controller: controller,
        collect: deps.collect,
        onQualitySelected: deps.onQualitySelected,
        onOpenComments: deps.onOpenComments,
        onStartFm: deps.onStartFm,
      ),
    ];
  } catch (e, st) {
    // 不 import kernel（层纪律），异常信息由桥层 Log 兜底留痕。
    Log.e('surface.modules', 'defaultModules failed', e, st);
    return const <SurfaceModule>[];
  }
}

/// MiniBar 从这里 re-export，宿主（主页 Scaffold bottomNavigationBar 上方）直接引用。
// PlaybackService 类型 re-export，供 boot 处书写 resolver tear-off 类型。
