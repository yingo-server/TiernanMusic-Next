// L7 surface/pages · 首页（官方 M3 卡片流 + 语义 token）
//
// 契约：只用官方 Material 3 控件 + GetWidget；不手写控件类；颜色只来自语义 token。
// 数据只经 bridge_logic 的 logic 单例取；异步 future 只在 initState 持有。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show Log, SongBrief, PlaylistBrief, RankBrief;
import '../../bridges/bridge_session.dart'
    show NavState, PlaybackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens_v2.dart';
import 'login_sheet.dart' show showLoginSheet;
import 'playlist_page.dart' show PlaylistDetailSheet;

const String _tag = 'surface.home';

/// 页面模块注册（L7 注入 builder，宿主按 id 覆盖 session 占位模块）。
class HomePageModule extends SurfaceModule {
  @override
  String get id => 'home';
  @override
  String get route => '/home';
  @override
  NavEntry? get navEntry => const NavEntry('首页', 'home', navOrder: 0);
  @override
  bool get enabled => true;
  @override
  WidgetBuilder? get builder =>
      (BuildContext ctx) => const HomePage();
}

/// 首页：每日推荐 / 推荐歌单 / 排行榜 三区块流。
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<SongBrief>> _dailyF;
  late Future<List<PlaylistBrief>> _playlistF;
  late Future<List<RankBrief>> _rankF;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 异步数据只在 initState 持有 future（禁止在 build 内新建 future）。
  void _load() {
    try {
      final g = appGraph;
      _dailyF = g.recommend?.daily(1) ?? Future.value(const <SongBrief>[]);
      _playlistF =
          g.playlist?.recommend(1) ?? Future.value(const <PlaylistBrief>[]);
      _rankF = g.rank?.rankList() ?? Future.value(const <RankBrief>[]);
    } catch (e, st) {
      Log.e(_tag, 'load failed', e, st);
      _dailyF = Future.value(const <SongBrief>[]);
      _playlistF = Future.value(const <PlaylistBrief>[]);
      _rankF = Future.value(const <RankBrief>[]);
    }
  }

  void _reload() => setState(_load);

  void _play(List<SongBrief> songs, int index) {
    try {
      PlaybackSession.instance.playAll(songs, index);
    } catch (e, st) {
      Log.e(_tag, 'playAll failed', e, st);
    }
  }

  void _openPlaylist(PlaylistBrief brief) {
    try {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext c) => PlaylistDetailSheet(
          playlistId: brief.id,
          title: brief.name,
          cover: brief.cover,
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'openPlaylist failed', e, st);
    }
  }

  /// 榜单卡：直接进入榜单曲目并播放。
  void _openRank(RankBrief rank) {
    try {
      final rk = appGraph.rank;
      if (rk == null) return;
      rk
          .rankInfo(rank.rankId)
          .then((List<SongBrief> songs) {
            if (songs.isEmpty) return;
            PlaybackSession.instance.playAll(songs, 0);
          })
          .catchError((Object e, StackTrace st) {
            Log.e(_tag, 'rankInfo failed id=${rank.rankId}', e, st);
          });
    } catch (e, st) {
      Log.e(_tag, 'openRank failed', e, st);
    }
  }

  void _goSearch() {
    try {
      NavState.instance.requestTab('search');
    } catch (e, st) {
      Log.e(_tag, 'requestTab failed', e, st);
    }
  }

  /// 「每日推荐」空态的登录入口：与设置页同一入口（login_sheet）。
  void _goLogin() {
    try {
      showLoginSheet(context);
    } catch (e, st) {
      Log.e(_tag, 'showLoginSheet failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AppBar(
              title: Text('首页', style: theme.textTheme.headlineSmall),
              actions: <Widget>[
                IconButton(
                  tooltip: '搜索',
                  onPressed: _goSearch,
                  icon: const Icon(Icons.search),
                ),
                const SizedBox(width: 8),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: <Widget>[
                  _dailySection(context),
                  _playlistSection(context),
                  _rankSection(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 区块标题（计划书 §2.3：标题 + 「更多」同行，8dp 体系）。
  Widget _section(BuildContext c, String title, Widget child,
      {VoidCallback? onMore}) {
    final theme = Theme.of(c);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
                if (onMore != null)
                  TextButton(
                    onPressed: onMore,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('更多'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// 加载占位（官方 Card + LinearProgressIndicator）。
  Widget _loading(BuildContext c, double height) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Center(
            child: SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 3,
                color: Theme.of(c).colorScheme.primary,
                backgroundColor: Theme.of(c).colorScheme.surfaceContainerHigh,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 空态（计划书 §2.3.1：图标 + 文案 + 动作，紧凑高度 96，不再大块占位）。
  Widget _empty(BuildContext c, String message, {VoidCallback? onAction, String? actionLabel}) {
    final theme = Theme.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 96,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.music_note, size: 32, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(message, style: theme.textTheme.bodySmall),
                  if (onAction != null && actionLabel != null) ...<Widget>[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 错误态（官方 Icon + Text + FilledButton）。
  Widget _error(BuildContext c, String message, VoidCallback onRetry) {
    final theme = Theme.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(height: 8),
              Text(message, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dailySection(BuildContext c) {
    return FutureBuilder<List<SongBrief>>(
      future: _dailyF,
      builder: (BuildContext c, AsyncSnapshot<List<SongBrief>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _section(c, '每日推荐', _loading(c, 176));
        }
        if (snap.hasError) {
          return _section(c, '每日推荐', _error(c, '每日推荐加载失败', _reload));
        }
        final items = snap.data ?? const <SongBrief>[];
        if (items.isEmpty) {
          return _section(
            c,
            '每日推荐',
            _empty(
              c,
              '登录后可查看每日推荐',
              actionLabel: '去登录',
              onAction: _goLogin,
            ),
          );
        }
        return _section(
          c,
          '每日推荐',
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext c, int i) {
                final s = items[i];
                return SizedBox(
                  width: 124,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _play(items, i),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AspectRatio(
                            aspectRatio: 1,
                            child: s.cover.isEmpty
                                ? Container(color: Theme.of(c).colorScheme.surfaceContainerHigh)
                                : Image.network(
                                    s.cover,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Theme.of(c)
                                          .colorScheme
                                          .surfaceContainerHigh,
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              s.name.isEmpty ? '未知歌曲' : s.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          onMore: _goSearch,
        );
      },
    );
  }

  Widget _playlistSection(BuildContext c) {
    return FutureBuilder<List<PlaylistBrief>>(
      future: _playlistF,
      builder: (BuildContext c, AsyncSnapshot<List<PlaylistBrief>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _section(c, '推荐歌单', _loading(c, 200));
        }
        if (snap.hasError) {
          return _section(c, '推荐歌单', _error(c, '歌单加载失败', _reload));
        }
        final items = snap.data ?? const <PlaylistBrief>[];
        if (items.isEmpty) {
          return _section(c, '推荐歌单', _empty(c, '暂无推荐歌单'));
        }
        final columns = MediaQuery.sizeOf(c).width >= 1000
            ? 5
            : MediaQuery.sizeOf(c).width >= 600
            ? 3
            : 2;
        return _section(
          c,
          '推荐歌单',
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: items.length,
            itemBuilder: (BuildContext c, int i) {
              final p = items[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openPlaylist(p),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AspectRatio(
                        aspectRatio: 1,
                        child: p.cover.isEmpty
                            ? Container(
                                color: Theme.of(c).colorScheme.surfaceContainerHigh,
                              )
                            : Image.network(
                                p.cover,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Theme.of(c)
                                      .colorScheme
                                      .surfaceContainerHigh,
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          p.name.isEmpty ? '未命名歌单' : p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(c).textTheme.titleSmall,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '曲目数未知',
                          style: Theme.of(c).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _rankSection(BuildContext c) {
    return FutureBuilder<List<RankBrief>>(
      future: _rankF,
      builder: (BuildContext c, AsyncSnapshot<List<RankBrief>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _section(c, '排行榜', _loading(c, 140));
        }
        if (snap.hasError) {
          return _section(c, '排行榜', _error(c, '榜单加载失败', _reload));
        }
        final items = snap.data ?? const <RankBrief>[];
        if (items.isEmpty) {
          return _section(c, '排行榜', _empty(c, '暂无榜单数据'));
        }
        return _section(
          c,
          '排行榜',
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext c, int i) {
                final r = items[i];
                return SizedBox(
                  width: 160,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _openRank(r),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              r.name.isEmpty ? '榜单' : r.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            Text(
                              r.updateTime.isEmpty ? '每周更新' : r.updateTime,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
