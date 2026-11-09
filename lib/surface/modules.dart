// L6 surface · 模块统一装配出口（defaultModules）
// 三个功能模块页在此以工厂注入依赖并返回列表；
// bootloader / surface 桥逐个 SurfaceRegistry.install，即热插拔接入。
// 模块间零直接 import：共享依赖只经本工厂参数与 riverpod provider。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridges/bridge_logic.dart'
    show SearchLogic, PlaylistLogic, Log;
import 'pages/player_page.dart' show PlayerPageModule, MiniBar;
import 'pages/playlist_page.dart' show PlaylistPageModule;
import 'pages/search_page.dart' show SearchPageModule;
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
  });

  /// 批2-C 装配好的搜索 logic。
  final SearchLogic search;

  /// 批2-C 装配好的歌单 logic。
  final PlaylistLogic playlist;

  /// 播放源解析门面（典型：PlaybackService().resolvePlaySource tear-off）。
  final PlaySourceResolver resolver;

  /// 目标音质（128/320/flac …），传给 resolver。
  final String quality;
}

/// 构建默认模块集 + 装配全局 PlayerController provider override。
/// 用法（boot 处）：
/// ```dart
/// final deps = SurfaceDeps(search: s, playlist: p, resolver: playback.resolvePlaySource);
/// for (final m in defaultModules(deps)) SurfaceRegistry.install(m);
/// ```
List<SurfaceModule> defaultModules(SurfaceDeps deps) {
  try {
    // 播放控制器：唯一实例，经两个 provider 暴露（boot 处 override）。
    final controller = PlayerController(
      resolver: deps.resolver,
      quality: deps.quality,
    );
    final overrides = <Override>[
      playerProvider.overrideWith((ref) => controller),
      playerControllerProvider.overrideWith((ref) => controller),
    ];
    SurfaceRegistry.setOverrides(overrides);

    return <SurfaceModule>[
      SearchPageModule(search: deps.search, player: controller),
      PlaylistPageModule(playlist: deps.playlist, player: controller),
      PlayerPageModule(controller: controller),
    ];
  } catch (e, st) {
    // 不 import kernel（层纪律），异常信息由桥层 Log 兜底留痕。
    Log.e('surface.modules', 'defaultModules failed', e, st);
    return const <SurfaceModule>[];
  }
}

/// MiniBar 从这里 re-export，宿主（主页 Scaffold bottomNavigationBar 上方）直接引用。
// PlaybackService 类型 re-export，供 boot 处书写 resolver tear-off 类型。
