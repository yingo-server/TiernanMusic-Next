// L7 surface · 应用外壳（官方 M3 导航 + 模块渲染 + Now Playing 条）
//
// 契约（docs/UI_REWRITE_PLAN.md §0.0）：
// - 只用官方 Material 3 控件 + GetWidget 现成能力；**不手写任何控件类**。
// - 颜色只来自语义 token（design/tokens_v2.dart），无裸色值。
// - 桌面（≥1000）用 NavigationRail；移动用 NavigationBar。
// - 平台差异不经 Platform.isXxx（走能力集合，bridge_core 门面）。
// - 导航图标必须被静态引用，否则构建期 tree-shaking 会裁掉（历史事故：
//   --tree-shake-icons 裁掉动态 switch 引用的图标 → 底栏 tab 全消失）。
//   见 tool/bottom_bar_gate.py。
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../bridges/bridge_session.dart'
    show ModuleRegistry, NavEntry, NavState, SurfaceModule;
import 'design/tokens_v2.dart';
import 'design/layout.dart' show TnBreakpoint, TnRadius, TnSize, TnSpace;
import 'pages/home_page.dart' show HomePageModule;
import 'pages/library_page.dart' show LibraryPageModule;
import 'pages/lyrics_page.dart' show LyricsPageModule;
import 'pages/mv_page.dart' show registerMvModule;
import 'pages/player_page.dart' show PlayerPageModule;
import 'pages/playlist_page.dart' show PlaylistPageModule;
import 'pages/search_page.dart' show SearchPageModule;
import 'pages/settings_page.dart' show SettingsPageModule;

/// 注册全部页面模块到 L6 注册表（id 幂等覆盖）。
void registerModules() {
  try {
    final reg = ModuleRegistry.instance;
    reg
      ..install(HomePageModule())
      ..install(SearchPageModule())
      ..install(PlaylistPageModule())
      ..install(LibraryPageModule())
      ..install(SettingsPageModule())
      ..install(PlayerPageModule())
      ..install(LyricsPageModule());
    registerMvModule();
  } catch (e, st) {
    debugPrint('surface.shell: registerModules failed: $e\n$st');
  }
}

/// 导航图标映射（navEntry.icon 字符串 → 官方图标）。
IconData iconFor(String key) {
  switch (key) {
    case 'home':
      return Icons.home_outlined;
    case 'search':
      return Icons.search;
    case 'library':
    case 'library_music':
      return Icons.library_music_outlined;
    case 'music':
    case 'playlist':
      return Icons.queue_music;
    case 'settings':
      return Icons.settings_outlined;
    default:
      return Icons.music_note;
  }
}

/// 应用外壳：导航（底栏/侧栏）+ 当前模块页 + Now Playing 条。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// GetWidget 视图态（仅 L7 视图层；业务状态仍在 L6 session）。
  final RxInt _index = 0.obs;

  @override
  void dispose() {
    _index.close();
    super.dispose();
  }

  List<SurfaceModule> get _modules => ModuleRegistry.instance
      .active()
      .where((m) => m.navEntry != null)
      .toList();

  @override
  Widget build(BuildContext context) {
    final modules = _modules;
    if (modules.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'No modules available',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Obx(() {
      final safeIndex = _index.value.clamp(0, modules.length - 1);
      final current = modules[safeIndex];
      // 页面内容（不含迷你条——迷你条放 Scaffold 官方 bottomNavigationBar 槽位，
      // 与 NavigationBar 同列，inset 由 Scaffold 统一处理：兼容性最强，全平台一致）。
      final content = KeyedSubtree(
        key: ValueKey<String>(current.id),
        child:
            (current.builder as WidgetBuilder?)?.call(context) ??
            Center(
              child: Text(
                'Module has no page',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
      );
      // 桌面（expanded）：迷你条放内容列底部（Rail 下方/内容上方，官方 Column 槽位）。
      // 移动（compact/medium）：迷你条 + NavigationBar 同列进 Scaffold
      // bottomNavigationBar 槽位，系统 inset 由 Scaffold 官方处理
      // （兼容性最强：Flutter 全平台一致的机制，不依赖任何平台新 API）。
      final bool expanded = TnBreakpoint.isExpanded(MediaQuery.sizeOf(context).width);
      final Widget desktopContent = Column(
        children: <Widget>[
          Expanded(child: content),
          _nowPlayingBar(context),
        ],
      );
      final Widget? bottomBar = expanded
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _nowPlayingBar(context),
                _bar(modules, safeIndex),
              ],
            );
      return LayoutBuilder(
        builder: (context, constraints) {
          if (TnBreakpoint.isExpanded(constraints.maxWidth)) {
            return Scaffold(
              body: Row(
                children: <Widget>[
                  _rail(modules, safeIndex),
                  const VerticalDivider(width: 1),
                  Expanded(child: desktopContent),
                ],
              ),
            );
          }
          return Scaffold(
            body: SafeArea(
              child: content,
            ),
            bottomNavigationBar: bottomBar,
          );
        },
      );
    });
  }

  /// 桌面侧栏（官方 NavigationRail）。
  Widget _rail(List<SurfaceModule> modules, int selected) {
    final bool extended = TnBreakpoint.isExpanded(MediaQuery.sizeOf(context).width);
    return NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: (i) => _index.value = i,
      extended: extended,
      labelType: extended ? null : NavigationRailLabelType.all,
      destinations: <NavigationRailDestination>[
        for (final m in modules)
          NavigationRailDestination(
            icon: Icon(iconFor(m.navEntry?.icon ?? '')),
            selectedIcon: Icon(iconFor(m.navEntry?.icon ?? '')),
            label: Text(m.navEntry?.label ?? m.id),
          ),
      ],
    );
  }

  /// 移动底栏（官方 NavigationBar）。
  Widget _bar(List<SurfaceModule> modules, int selected) {
    return NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (i) => _index.value = i,
      destinations: <NavigationDestination>[
        for (final m in modules)
          NavigationDestination(
            icon: Icon(iconFor(m.navEntry?.icon ?? '')),
            selectedIcon: Icon(iconFor(m.navEntry?.icon ?? '')),
            label: m.navEntry?.label ?? m.id,
          ),
      ],
    );
  }

  /// Now Playing 条（官方 Material + InkWell + Row 组合，无自写控件类）。
  Widget _nowPlayingBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: InkWell(
        onTap: () {
          final nav = NavState.instance;
          nav.requestTab('player');
        },
        child: SizedBox(height: TnSize.miniBar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: TnSpace.lg),
            child: Row(
              children: <Widget>[
                Container(
                  width: TnSize.avatarSm,
                  height: TnSize.avatarSm,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(TnRadius.sm),
                  ),
                ),
                const SizedBox(width: TnSpace.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Not playing',
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Idle',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Play',
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
