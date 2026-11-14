// L6 surface/pages · 应用壳（底部导航 + 模块视图 + 启动错误页）
// 从 app_root.dart 拆出（控制文件 ≤500 行）；app_root 只负责 MaterialApp/主题/装配。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;

import '../../bridges/bridge_logic.dart' show Log;
import '../providers.dart' show homeTabRequest, logicFacadeProvider;
import '../registry.dart' show NavEntry, SurfaceModule, SurfaceRegistry;
import '../theme/tn_theme.dart' show TnText;
import '../widgets/common_m3.dart' show ErrorRetryBox;
import '../widgets/mini_bar.dart' show MiniBar;

const String _tag = 'surface.homeShell';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
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
              padding: EdgeInsets.fromLTRB(tnPadL, tnPadL, tnPadL, tnPadS),
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

  /// navEntry.icon 字符串 → Material 图标（与各模块 navEntry 的 icon 字面量对齐：
  /// search / home / library_music / queue_music / settings …）。
  IconData _iconOf(String name) {
    switch (name) {
      case 'search':
        return Icons.search;
      case 'home':
        return Icons.home;
      case 'library':
      case 'library_music':
      case 'playlist':
        return Icons.library_music;
      case 'queue_music':
        return Icons.queue_music;
      case 'rank':
        return Icons.leaderboard;
      case 'download':
        return Icons.download;
      case 'settings':
        return Icons.settings;
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

class FallbackApp extends StatelessWidget {
  const FallbackApp({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      );
    } catch (e) {
      debugPrint('surface.app_root: fallback build failed: $e');
      return const SizedBox(width: 0, height: 0);
    }
  }
}

