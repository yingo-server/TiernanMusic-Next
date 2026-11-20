// L7 surface/pages · 音乐库页（官方 M3 卡片流 + 语义 token）
//
// 契约：只用官方 Material 3 控件；不手写控件类；颜色只来自语义 token
//（Theme.of(context).colorScheme / context.cs）。
// 数据只经 bridge_logic 的 logic 单例与 bridge_core 的 DAO 取；
// 异步 future 只在 initState 持有；下载任务变更经 onTask 订阅实时刷新。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show SongRecord, PlayHistoryEntry, UserProfile;
import '../../bridges/bridge_logic.dart' show Log, DownloadTask, DownloadEvent;
import '../../bridges/bridge_session.dart'
    show appGraph, SurfaceModule, NavEntry;
import '../design/tokens_v2.dart';
import '../design/layout.dart' show TnBreakpoint, TnRadius, TnSize, TnSpace;
import '../l10n/s.dart' show S;

/// 音乐库页：账号卡 + 三页签（本地曲库 / 最近播放 / 下载管理）。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  Future<UserProfile>? _profile;
  Future<int>? _favCount;
  List<DownloadTask> _downloads = const <DownloadTask>[];
  Future<List<SongRecord>>? _localSongs;
  Future<List<PlayHistoryEntry>>? _recentSongs;

  /// 本地收藏镜像（hash 小写）；用于收藏按钮选中态。
  final Set<String> _collected = <String>{};

  @override
  void initState() {
    super.initState();
    _localSongs = appGraph.songDao?.list();
    _recentSongs = appGraph.historyDao?.recent();
    _loadProfile();
    _loadDownloads();
    _loadCollected();
    // 阶段B B5 P0：订阅下载任务变更，进度/完成/失败实时刷新 UI。
    final dm = appGraph.downloads;
    dm?.onTask = (DownloadEvent e) {
      if (!mounted) return;
      setState(() => _downloads = e.tasks);
    };
  }

  void _loadProfile() {
    final user = appGraph.user;
    final collect = appGraph.collect;
    if (user == null && collect == null) {
      _profile = Future<UserProfile>.value(const UserProfile());
      _favCount = Future<int>.value(0);
      return;
    }
    _profile = user?.profile();
    if (collect == null) {
      _favCount = Future<int>.value(0);
    } else {
      final c = collect;
      _favCount = c.refreshCount().then((_) => c.count);
    }
  }

  void _loadDownloads() {
    final dm = appGraph.downloads;
    if (dm == null) return;
    _downloads = dm.listTasks();
  }

  /// 读取收藏镜像（同步，不打网络）。
  void _loadCollected() {
    try {
      final list = appGraph.collect?.listFavorites() ?? const <String>[];
      _collected
        ..clear()
        ..addAll(list);
    } catch (e, st) {
      Log.e('surface.library', 'load favorites failed', e, st);
    }
  }

  @override
  void dispose() {
    // 阶段B B5：释放下载订阅，避免 Widget 销毁后回调野指针。
    appGraph.downloads?.onTask = null;
    _tabs.dispose();
    super.dispose();
  }

  void _reloadLists() {
    try {
      setState(() {
        _localSongs = appGraph.songDao?.list();
        _recentSongs = appGraph.historyDao?.recent();
      });
    } catch (e, st) {
      Log.e('surface.library', 'reload failed', e, st);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 收藏切换（官方 IconButton 触发）：写端点成功才改本地镜像。
  Future<void> _toggleFavorite(SongRecord record) async {
    final s = S.of(context);
    final collect = appGraph.collect;
    if (collect == null) {
      _toast(s.t('favoriteUnavailable'));
      return;
    }
    final hash = record.hash.trim().toLowerCase();
    if (hash.isEmpty) return;
    try {
      final res = await collect.toggle(
        hash,
        int.tryParse(record.mixSongId.trim()) ?? 0,
      );
      if (!mounted) return;
      if (res.needsLogin) {
        _toast(s.t('favoriteNeedLogin'));
        return;
      }
      if (!res.ok) {
        _toast(s.t('favoriteFailed'));
        return;
      }
      setState(() {
        if (collect.isCollected(hash)) {
          _collected.add(hash);
        } else {
          _collected.remove(hash);
        }
      });
    } catch (e, st) {
      Log.e('surface.library', 'toggle favorite failed', e, st);
      if (mounted) _toast(s.t('favoriteFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AppBar(title: Text('曲库', style: theme.textTheme.headlineSmall)),
            _accountCard(context),
            TabBar(
              controller: _tabs,
              labelColor: theme.colorScheme.onSurface,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              tabs: const <Widget>[
                Tab(text: '本地曲库'),
                Tab(text: '最近播放'),
                Tab(text: '下载管理'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: <Widget>[
                  _localLibrary(context),
                  _recentPlays(context),
                  _downloadsTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 账号卡（官方 Card + ClipOval 头像）；未登录时整块隐藏。
  Widget _accountCard(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<UserProfile>(
      future: _profile,
      builder: (BuildContext c, AsyncSnapshot<UserProfile> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: TnSpace.lg, vertical: TnSpace.md),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(TnSpace.lg),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: TnSpace.xxxl,
                      height: TnSize.avatarLg,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: TnSpace.lg),
                    Expanded(
                      child: LinearProgressIndicator(
                        color: theme.colorScheme.primary,
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final p = snap.data ?? const UserProfile();
        if (p.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(TnSpace.lg, TnSpace.sm, TnSpace.lg, TnSpace.md),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(TnSpace.lg),
              child: Row(
                children: <Widget>[
                  _avatar(context, p.avatar),
                  const SizedBox(width: TnSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          p.nickname.isEmpty ? '未命名用户' : p.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: TnSpace.xs),
                        Text(
                          'ID ${p.userid}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: TnSpace.xs),
                        FutureBuilder<int>(
                          future: _favCount,
                          builder: (BuildContext c, AsyncSnapshot<int> f) =>
                              Text(
                                '我喜欢 ${f.data ?? 0}',
                                style: theme.textTheme.bodySmall,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 头像：官方 ClipOval + Image.network（失败回退官方 Icon）。
  Widget _avatar(BuildContext context, String url) {
    final theme = Theme.of(context);
    final u = url.trim();
    final fallback = SizedBox(width: TnSpace.xxxl,
      height: TnSize.avatarLg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
    if (u.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        u,
        width: TnSize.avatarLg,
        height: TnSize.avatarLg,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }

  /// 本地曲库：SongDao.list() 真数据（Future 在 initState 持有）。
  Widget _localLibrary(BuildContext context) {
    final s = S.of(context);
    return _list<SongRecord>(
      context: context,
      future: _localSongs,
      emptyTitle: '曲库还是空的',
      emptySubtitle: '下载或导入歌曲后会显示在这里',
      icon: Icons.library_music_outlined,
      titleOf: (SongRecord r) => r.fileName,
      subtitleOf: (SongRecord r) => r.singerName,
      trailingOf: (SongRecord r) => IconButton(
        tooltip: s.t('favorite'),
        onPressed: () => _toggleFavorite(r),
        icon: Icon(
          _collected.contains(r.hash.trim().toLowerCase())
              ? Icons.favorite
              : Icons.favorite_border,
          color: _collected.contains(r.hash.trim().toLowerCase())
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 最近播放：HistoryDao.recent() 真数据。
  Widget _recentPlays(BuildContext context) {
    return _list<PlayHistoryEntry>(
      context: context,
      future: _recentSongs,
      emptyTitle: '还没有播放记录',
      emptySubtitle: '播放歌曲后会显示在这里',
      icon: Icons.history,
      titleOf: (PlayHistoryEntry r) => r.fileName.isEmpty ? r.hash : r.fileName,
      subtitleOf: (PlayHistoryEntry r) => r.singerName,
    );
  }

  /// 三态列表：加载 / 错误 / 空 / 数据（纯官方控件组合）。
  Widget _list<T>({
    required BuildContext context,
    required Future<List<T>>? future,
    required String emptyTitle,
    required String emptySubtitle,
    required IconData icon,
    required String Function(T) titleOf,
    required String Function(T) subtitleOf,
    Widget Function(T)? trailingOf,
  }) {
    final theme = Theme.of(context);
    if (future == null) {
      return _stateView(
        context: context,
        icon: icon,
        title: '数据加载暂不可用',
        subtitle: emptySubtitle,
      );
    }
    return FutureBuilder<List<T>>(
      future: future,
      builder: (BuildContext c, AsyncSnapshot<List<T>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _stateView(
            context: context,
            icon: Icons.error_outline,
            title: '加载失败',
            subtitle: '${snap.error}',
            actionLabel: '重试',
            onAction: _reloadLists,
          );
        }
        final items = snap.data ?? <T>[];
        if (items.isEmpty) {
          return _stateView(
            context: context,
            icon: icon,
            title: emptyTitle,
            subtitle: emptySubtitle,
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (BuildContext ctx, int i) => ListTile(
            leading: Icon(
              Icons.music_note,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              titleOf(items[i]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(
              subtitleOf(items[i]),
              style: theme.textTheme.bodySmall,
            ),
            trailing: trailingOf?.call(items[i]),
          ),
        );
      },
    );
  }

  /// 状态视图（官方 Icon + Text + FilledButton）。
  Widget _stateView({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TnSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: context.cs.onSurfaceVariant),
            const SizedBox(height: TnSpace.sm),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: TnSpace.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: TnSpace.md),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  /// 下载管理：走 DownloadManager.listTasks()（经桥暴露的 logic）。
  Widget _downloadsTab(BuildContext context) {
    final theme = Theme.of(context);
    if (appGraph.downloads == null) {
      return _stateView(
        context: context,
        icon: Icons.download_outlined,
        title: '下载管理暂不可用',
        subtitle: '下载功能暂未开放',
      );
    }
    if (_downloads.isEmpty) {
      return _stateView(
        context: context,
        icon: Icons.download_outlined,
        title: '暂无下载任务',
        subtitle: '在歌曲菜单中选择下载',
      );
    }
    return ListView.builder(
      itemCount: _downloads.length,
      itemBuilder: (BuildContext c, int i) {
        final t = _downloads[i];
        return ListTile(
          leading: t.song.cover.isEmpty
              ? Icon(Icons.album, color: theme.colorScheme.onSurfaceVariant)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(TnRadius.sm),
                  child: Image.network(
                    t.song.cover,
                    width: TnSize.avatarSm,
                    height: TnSize.avatarSm,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.album,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
          title: Text(
            t.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(
            '${t.quality} · ${t.status.name}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: t.progress >= 0
              ? SizedBox(width: TnSpace.xxxl,
                  child: LinearProgressIndicator(value: t.progress),
                )
              : null,
        );
      },
    );
  }
}

/// 音乐库模块（进底部导航）。
class LibraryPageModule extends SurfaceModule {
  @override
  String get id => 'library';

  @override
  String get route => '/library';

  @override
  NavEntry? get navEntry => const NavEntry('曲库', 'library_music', navOrder: 3);

  @override
  WidgetBuilder? get builder =>
      (_) => const LibraryPage();
}
