// L7 surface/pages · 音乐库页（Spotify 深色 + M3）
// 数据只经桥取：AppGraph 内的 logic 单例（user/collect/downloads）。
// 说明：本地曲库与最近播放需要 SongDao/HistoryDao 实例，
// 目前它们只存在于 session 装配参数（SessionDeps），未随 AppGraph 暴露，
// 因此这两页签显示空态而非假数据（待 DAOs 经桥暴露后接入）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show UserProfile;
import '../../bridges/bridge_logic.dart' show DownloadTask;
import '../../bridges/bridge_session.dart' show SurfaceModule, NavEntry;
// GAP(跨桥)：bridge_session 只导出 AppGraph 类型，未导出装配图实例，
// 暂直接取 session 层的 appGraph 实例；后续由主会话在 bridge_session 补出口。
import '../../bridges/bridge_session.dart' show appGraph;
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadDownloads();
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
                  fontSize: Sp.fItem, fontWeight: FontWeight.w600),
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
                              fontSize: Sp.fSub, color: Sp.textSub),
                        ),
                        const SizedBox(width: Sp.gapM),
                        FutureBuilder<int>(
                          future: _favCount,
                          builder: (context, c) => Text(
                            '我喜欢 ${c.data ?? 0}',
                            style: const TextStyle(
                                fontSize: Sp.fSub, color: Sp.textSub),
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

  /// 本地曲库：DAO 未经桥暴露 → 空态（不造假数据）。
  Widget _localLibrary() => const SpStateView(
        icon: Icons.library_music_outlined,
        title: '本地曲库暂不可用',
        subtitle: '本地歌曲数据库能力尚未接入本页',
      );

  /// 最近播放：播放历史 DAO 未经桥暴露 → 空态。
  Widget _recentPlays() => const SpStateView(
        icon: Icons.history,
        title: '暂无最近播放',
        subtitle: '播放历史能力尚未接入本页',
      );

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
          title: Text(t.displayName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${t.quality} · ${t.status.name}',
              style: const TextStyle(fontSize: Sp.fSub, color: Sp.textSub)),
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
  NavEntry? get navEntry => const NavEntry('音乐库', 'library_music');

  @override
  WidgetBuilder? get builder => (_) => const LibraryPage();
}
