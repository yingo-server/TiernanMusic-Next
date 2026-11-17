// L7 surface/pages · 音乐库页（Spotify 深色 + M3）
// 数据只经桥取：AppGraph 内的 logic 单例与 songDao / historyDao。
// 本地曲库与最近播放在 initState 持有 Future，由 FutureBuilder 渲染，
// 播放意图统一走 PlaybackSession.playAll，build 内不新建 Future。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart';
import '../../bridges/bridge_logic.dart';
import '../../bridges/bridge_session.dart';
import '../design/tokens.dart';
import '../design/components.dart';

/// 音乐库页：账号卡 + 三页签。
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

  @override
  void initState() {
    super.initState();
    _localSongs = appGraph.songDao?.list();
    _recentSongs = appGraph.historyDao?.recent();
    _loadProfile();
    _loadDownloads();
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

  @override
  void dispose() {
    // 阶段B B5：释放下载订阅，避免 Widget 销毁后回调野指针。
    appGraph.downloads?.onTask = null;
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sp.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _accountCard(),
            TabBar(
              controller: _tabs,
              labelColor: Sp.text,
              unselectedLabelColor: Sp.textSub,
              indicatorColor: Sp.green,
              labelStyle: const TextStyle(
                fontSize: Sp.fItem,
                fontWeight: FontWeight.w600,
              ),
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
                  _localLibrary(),
                  _recentPlays(),
                  _downloadsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 账号卡：无数据（未登录 / 档案端点未实测）时整块隐藏。
  Widget _accountCard() {
    return FutureBuilder<UserProfile>(
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(Sp.pagePad),
            child: Row(
              children: <Widget>[
                SpSkeleton(width: 48, height: 48, radius: Sp.rFull),
                SizedBox(width: Sp.gapM),
                Expanded(child: SpSkeleton(height: 16)),
              ],
            ),
          );
        }
        final p = snap.data ?? const UserProfile();
        if (p.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.all(Sp.pagePad),
          child: Row(
            children: <Widget>[
              _avatar(p.avatar),
              const SizedBox(width: Sp.gapM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      p.nickname.isEmpty ? '未命名用户' : p.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: Sp.fSection,
                        fontWeight: FontWeight.w700,
                        color: Sp.text,
                      ),
                    ),
                    const SizedBox(height: Sp.gapXS),
                    Row(
                      children: <Widget>[
                        Text(
                          'ID ${p.userid}',
                          style: const TextStyle(
                            fontSize: Sp.fSub,
                            color: Sp.textSub,
                          ),
                        ),
                        const SizedBox(width: Sp.gapM),
                        FutureBuilder<int>(
                          future: _favCount,
                          builder: (context, c) => Text(
                            '我喜欢 ${c.data ?? 0}',
                            style: const TextStyle(
                              fontSize: Sp.fSub,
                              color: Sp.textSub,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatar(String url) {
    final u = url.trim();
    final fallback = Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: Sp.cardHigh,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Sp.textFaint),
    );
    if (u.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        u,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }

  /// 本地曲库：SongDao.list() 真数据（Future 在 initState 持有）。
  Widget _localLibrary() => _list<SongRecord>(
    future: _localSongs,
    emptyTitle: '曲库还是空的',
    emptySubtitle: '下载或导入歌曲后会显示在这里',
    icon: Icons.library_music_outlined,
    titleOf: (r) => r.fileName,
    subtitleOf: (r) => r.singerName,
  );

  /// 最近播放：HistoryDao.recent() 真数据。
  Widget _recentPlays() => _list<PlayHistoryEntry>(
    future: _recentSongs,
    emptyTitle: '还没有播放记录',
    emptySubtitle: '播放歌曲后会显示在这里',
    icon: Icons.history,
    titleOf: (r) => r.fileName.isEmpty ? r.hash : r.fileName,
    subtitleOf: (r) => r.singerName,
  );

  /// 三态列表：加载 / 错误 / 空 / 数据（纯展示实体，不伪造 SongBrief）。
  Widget _list<T>({
    required Future<List<T>>? future,
    required String emptyTitle,
    required String emptySubtitle,
    required IconData icon,
    required String Function(T) titleOf,
    required String Function(T) subtitleOf,
  }) {
    if (future == null) {
      return SpStateView(icon: icon, title: '数据能力未装配', subtitle: emptySubtitle);
    }
    return FutureBuilder<List<T>>(
      future: future,
      builder: (BuildContext c, AsyncSnapshot<List<T>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: LinearProgressIndicator());
        }
        if (snap.hasError) {
          return SpStateView(
            icon: Icons.error_outline,
            title: '加载失败',
            subtitle: '${snap.error}',
            actionLabel: '重试',
            onAction: _reloadLists,
          );
        }
        final items = snap.data ?? <T>[];
        if (items.isEmpty) {
          return SpStateView(
            icon: icon,
            title: emptyTitle,
            subtitle: emptySubtitle,
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (BuildContext ctx, int i) => ListTile(
            leading: const Icon(Icons.music_note, color: Sp.textFaint),
            title: Text(
              titleOf(items[i]),
              style: const TextStyle(fontSize: Sp.fItem, color: Sp.text),
            ),
            subtitle: Text(
              subtitleOf(items[i]),
              style: const TextStyle(fontSize: Sp.fSub, color: Sp.textSub),
            ),
          ),
        );
      },
    );
  }

  void _reloadLists() {
    try {
      setState(() {
        _localSongs = appGraph.songDao?.list();
        _recentSongs = appGraph.historyDao?.recent();
      });
    } catch (e, st) {
      debugPrint('library: reload failed: $e\n$st');
    }
  }

  /// 下载管理：走 DownloadManager.listTasks()（经桥暴露的 logic）。
  Widget _downloadsTab() {
    if (appGraph.downloads == null) {
      return const SpStateView(
        icon: Icons.download_outlined,
        title: '下载管理不可用',
        subtitle: '下载能力未装配',
      );
    }
    if (_downloads.isEmpty) {
      return const SpStateView(
        icon: Icons.download_outlined,
        title: '暂无下载任务',
        subtitle: '在歌曲菜单里选择下载',
      );
    }
    return ListView.builder(
      itemCount: _downloads.length,
      itemBuilder: (context, i) {
        final t = _downloads[i];
        return ListTile(
          leading: SpCover(url: t.song.cover, size: Sp.tileCover),
          title: Text(
            t.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${t.quality} · ${t.status.name}',
            style: const TextStyle(fontSize: Sp.fSub, color: Sp.textSub),
          ),
          trailing: t.progress >= 0
              ? SizedBox(
                  width: 48,
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
  NavEntry? get navEntry => const NavEntry('音乐库', 'library_music', navOrder: 3);

  @override
  WidgetBuilder? get builder =>
      (_) => const LibraryPage();
}
