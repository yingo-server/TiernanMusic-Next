// L7 surface/pages · 首页（Spotify 深色 + M3）
// 只画控件；数据只经 bridge_logic 的 logic 单例取；颜色/字号/间距只用 Sp.*。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show Log, SongBrief, PlaylistBrief, RankBrief;
import '../../bridges/bridge_session.dart'
    show NavState, PlaybackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens.dart' show Sp;
import 'home_state_views.dart'
    show HomeSkeletonBox, HomeEmptyBox, HomeErrorRetry;
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
        backgroundColor: context.cs.surfaceContainerLow,
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

  /// 榜单卡：直接进入榜单曲目并播放（榜单详情走 rankInfo）。
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cs.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AppBar(
              backgroundColor: context.cs.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                '首页',
                style: TextStyle(
                  fontSize: Sp.fHero,
                  fontWeight: FontWeight.w700,
                  color: context.cs.onSurface,
                ),
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: '搜索',
                  onPressed: _goSearch,
                  icon: Icon(Icons.search, color: context.cs.onSurface),
                ),
                const SizedBox(width: Sp.gapS),
              ],
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: Sp.gapXL),
                itemCount: 3,
                itemBuilder: (BuildContext c, int i) {
                  if (i == 0) return _dailySection(c);
                  if (i == 1) return _playlistSection(c);
                  return _rankSection(c);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext c, String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.gapXL, bottom: Sp.gapM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
            child: Text(
              title,
              style: TextStyle(
                fontSize: Sp.fSection,
                fontWeight: FontWeight.w700,
                color: context.cs.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Sp.gapM),
          child,
        ],
      ),
    );
  }

  Widget _dailySection(BuildContext c) {
    return FutureBuilder<List<SongBrief>>(
      future: _dailyF,
      builder: (BuildContext c, AsyncSnapshot<List<SongBrief>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _section(c, '每日推荐', const HomeSkeletonBox(height: 176));
        }
        if (snap.hasError) {
          return _section(
            c,
            '每日推荐',
            HomeErrorRetry(message: '每日推荐加载失败', onRetry: _reload),
          );
        }
        final List<SongBrief> items = snap.data ?? const <SongBrief>[];
        if (items.isEmpty) {
          return _section(c, '每日推荐', const HomeEmptyBox('暂无每日推荐（登录后可能可见）'));
        }
        return _section(
          c,
          '每日推荐',
          SizedBox(
            height: 176,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
              itemCount: items.length,
              itemBuilder: (BuildContext c, int i) =>
                  _SongCard(song: items[i], onTap: () => _play(items, i)),
            ),
          ),
        );
      },
    );
  }

  Widget _playlistSection(BuildContext c) {
    return FutureBuilder<List<PlaylistBrief>>(
      future: _playlistF,
      builder: (BuildContext c, AsyncSnapshot<List<PlaylistBrief>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _section(c, '推荐歌单', const HomeSkeletonBox(height: 220));
        }
        if (snap.hasError) {
          return _section(
            c,
            '推荐歌单',
            HomeErrorRetry(message: '歌单加载失败', onRetry: _reload),
          );
        }
        final List<PlaylistBrief> items = snap.data ?? const <PlaylistBrief>[];
        if (items.isEmpty) {
          return _section(c, '推荐歌单', const HomeEmptyBox('暂无推荐歌单'));
        }
        return _section(
          c,
          '推荐歌单',
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
              itemCount: items.length,
              itemBuilder: (BuildContext c, int i) => SizedBox(
                width: 150,
                child: HomePlaylistCard(
                  brief: items[i],
                  onTap: () => _openPlaylist(items[i]),
                ),
              ),
            ),
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
          return _section(c, '排行榜', const HomeSkeletonBox(height: 110));
        }
        if (snap.hasError) {
          return _section(
            c,
            '排行榜',
            HomeErrorRetry(message: '榜单加载失败', onRetry: _reload),
          );
        }
        final List<RankBrief> items = snap.data ?? const <RankBrief>[];
        if (items.isEmpty) {
          return _section(c, '排行榜', const HomeEmptyBox('暂无榜单数据'));
        }
        return _section(
          c,
          '排行榜',
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
              itemCount: items.length,
              itemBuilder: (BuildContext c, int i) =>
                  _RankCard(rank: items[i], onTap: () => _openRank(items[i])),
            ),
          ),
        );
      },
    );
  }
}

/// 封面图（无图时占位，不伪造封面）。
class _Cover extends StatelessWidget {
  const _Cover({required this.url, this.size, this.radius = Sp.rM});
  final String url;
  final double? size;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final Widget box = url.isEmpty
        ? Container(color: context.cs.surfaceContainerHigh)
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                Container(color: context.cs.surfaceContainerHigh),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: box),
    );
  }
}

/// 每日推荐横滑卡。
class _SongCard extends StatelessWidget {
  const _SongCard({required this.song, required this.onTap});
  final SongBrief song;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Cover(url: song.cover, size: 124, radius: Sp.rCard),
            const SizedBox(height: Sp.gapS),
            Text(
              song.name.isEmpty ? '未知歌曲' : song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurface),
            ),
            Text(
              song.singer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Sp.fTiny, color: context.cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 推荐歌单三列卡。
class HomePlaylistCard extends StatelessWidget {
  const HomePlaylistCard({required this.brief, required this.onTap});
  final PlaylistBrief brief;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Cover(url: brief.cover, radius: Sp.rCard),
          const SizedBox(height: Sp.gapS),
          Text(
            brief.name.isEmpty ? '未命名歌单' : brief.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurface),
          ),
          Text(
            brief.trackCount > 0 ? '${brief.trackCount} 首' : '曲目数未知',
            style: TextStyle(fontSize: Sp.fTiny, color: context.cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 排行榜渐变卡。
class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank, required this.onTap});
  final RankBrief rank;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(Sp.gapS),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Sp.rCard),
          gradient: const LinearGradient(
            colors: <Color>[context.cs.primary, context.cs.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              rank.name.isEmpty ? '榜单' : rank.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: Sp.fSection,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            Text(
              rank.updateTime.isEmpty ? '每周更新' : rank.updateTime,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: Sp.fTiny, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}
