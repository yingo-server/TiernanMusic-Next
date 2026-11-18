// L7 surface · 应用外壳（底部导航 + 模块渲染 + 迷你条）
// 数据源：L6 session 的 ModuleRegistry（模块表）与 PlaybackSession（播放态）。
import 'package:flutter/material.dart';

import '../bridges/bridge_session.dart'
    show ModuleRegistry, NavEntry, NavState, SurfaceModule;
import 'design/mini_bar.dart' show SpMiniBar;
import 'design/tokens.dart';
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

/// 底部导航图标映射（navEntry.icon 字符串 → 图标）。
IconData iconFor(String key) {
  switch (key) {
    case 'home':
      return Icons.home_outlined;
    case 'search':
      return Icons.search;
    case 'library':
      return Icons.library_music_outlined;
    case 'music':
      return Icons.queue_music;
    case 'settings':
      return Icons.settings_outlined;
    default:
      return Icons.music_note;
  }
}

/// 应用外壳：底栏 + 当前模块页 + 迷你播放条。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  late final void Function() _navListener = _onNavState;

  @override
  void initState() {
    super.initState();
    NavState.instance.addListener(_navListener);
  }

  @override
  void dispose() {
    NavState.instance.removeListener(_navListener);
    super.dispose();
  }

  void _onNavState() {
    try {
      final req = NavState.instance.tabRequest;
      if (req.isEmpty) return;
      final modules = _modules;
      final i = modules.indexWhere((m) => m.id == req);
      if (i >= 0 && mounted) setState(() => _index = i);
      NavState.instance.clearTabRequest();
    } catch (e, st) {
      debugPrint('surface.shell: nav request failed: $e\n$st');
    }
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
          child: Text('无可用模块', style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }
    final safeIndex = _index.clamp(0, modules.length - 1);
    final current = modules[safeIndex];
    return Scaffold(
      // 审查修复（底栏浅色块回归）：外壳背景与页面同源，
      // 否则底部导航栏周围会露出外层 Scaffold 的默认底色。
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: KeyedSubtree(
                key: ValueKey<String>(current.id),
                child:
                    (current.builder as WidgetBuilder?)?.call(context) ??
                    const Center(child: Text('模块未提供页面')),
              ),
            ),
            SpMiniBar(onExpand: _openPlayer),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: <Widget>[
          for (final m in modules)
            NavigationDestination(
              icon: Icon(iconFor(m.navEntry?.icon ?? '')),
              selectedIcon: Icon(iconFor(m.navEntry?.icon ?? '')),
              label: m.navEntry?.label ?? m.id,
            ),
        ],
      ),
    );
  }

  void _openPlayer() {
    try {
      final player = ModuleRegistry.instance.byId('player');
      final WidgetBuilder? builder = player?.builder as WidgetBuilder?;
      if (builder == null) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => builder(ctx),
        ),
      );
    } catch (e, st) {
      debugPrint('surface.shell: open player failed: $e\n$st');
    }
  }
}
