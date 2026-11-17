// L7 surface/pages · 歌单页（Spotify 深色 + M3）。只画控件；数据只经 bridge_logic 的 logic 单例取；颜色/字号/间距只用 Sp.*。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show PlaylistMeta;
import '../../bridges/bridge_logic.dart'
    show Log, SongBrief, PlaylistBrief, PlaylistDetail, TrackPage;
import '../../bridges/bridge_session.dart'
    show NavState, PlaybackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens.dart' show Sp, SpColorSchemeX;

const String _tag = 'surface.playlist';

/// 页面模块注册。
class PlaylistPageModule extends SurfaceModule {
  @override
  String get id => 'playlist';
  @override
  String get route => '/playlist';
  @override
  NavEntry? get navEntry => const NavEntry('歌单', 'playlist', navOrder: 2);
  @override
  bool get enabled => true;
  @override
  WidgetBuilder? get builder =>
      (BuildContext ctx) => const PlaylistPage();
}

/// 歌单页：TabBar（推荐 / 我的）+ 网格 + 详情底部弹层。
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.cs.surface,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              TabBar(
                indicatorColor: context.cs.primary,
                indicatorWeight: 3,
                labelColor: context.cs.onSurface,
                unselectedLabelColor: context.cs.onSurfaceVariant,
                labelStyle: TextStyle(
                  fontSize: Sp.fSection,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: TextStyle(fontSize: Sp.fSection),
                tabs: <Widget>[
                  Tab(text: '推荐'),
                  Tab(text: '我的'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: <Widget>[_RecommendTab(), _MineTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 推荐歌单网格（3 列封面卡 + 名称 + 曲目数）。
class _RecommendTab extends StatefulWidget {
  const _RecommendTab();
  @override
  State<_RecommendTab> createState() => _RecommendTabState();
}

class _RecommendTabState extends State<_RecommendTab> {
  late Future<List<PlaylistBrief>> _f;
  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<List<PlaylistBrief>> _load() async {
    try {
      final pl = appGraph.playlist;
      if (pl == null) return const <PlaylistBrief>[];
      return pl.recommend(1);
    } catch (e, st) {
      Log.e(_tag, 'recommend failed', e, st);
      return const <PlaylistBrief>[];
    }
  }

  void _reload() => setState(() => _f = _load());
  void _open(PlaylistBrief brief) {
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
      Log.e(_tag, 'open detail failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlaylistBrief>>(
      future: _f,
      builder: (BuildContext c, AsyncSnapshot<List<PlaylistBrief>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: context.cs.primary),
          );
        }
        if (snap.hasError) {
          return PlaylistErrorRetry(message: '推荐歌单加载失败', onRetry: _reload);
        }
        final List<PlaylistBrief> items = snap.data ?? const <PlaylistBrief>[];
        if (items.isEmpty) {
          return const PlaylistEmptyBox('暂无推荐歌单');
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            Sp.pagePad,
            Sp.gapM,
            Sp.pagePad,
            Sp.gapXL,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.72,
            crossAxisSpacing: Sp.gapM,
            mainAxisSpacing: Sp.gapM,
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext c, int i) =>
              PlaylistGridCard(brief: items[i], onTap: () => _open(items[i])),
        );
      },
    );
  }
}

/// 我的歌单（本地镜像列表）。
class _MineTab extends StatefulWidget {
  const _MineTab();
  @override
  State<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<_MineTab> {
  late Future<List<PlaylistMeta>> _f;
  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<List<PlaylistMeta>> _load() async {
    try {
      final pl = appGraph.playlist;
      if (pl == null) return const <PlaylistMeta>[];
      return pl.listLocal();
    } catch (e, st) {
      Log.e(_tag, 'listLocal failed', e, st);
      return const <PlaylistMeta>[];
    }
  }

  void _reload() => setState(() => _f = _load());
  void _open(PlaylistMeta meta) {
    try {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.cs.surfaceContainerLow,
        isScrollControlled: true,
        builder: (BuildContext c) => PlaylistDetailSheet(
          playlistId: meta.playlistId,
          title: meta.name,
          cover: meta.coverUrl,
          localTrackCount: meta.songHashes.length,
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'open detail failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlaylistMeta>>(
      future: _f,
      builder: (BuildContext c, AsyncSnapshot<List<PlaylistMeta>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: context.cs.primary),
          );
        }
        if (snap.hasError) {
          return PlaylistErrorRetry(message: '我的歌单加载失败', onRetry: _reload);
        }
        final List<PlaylistMeta> items = snap.data ?? const <PlaylistMeta>[];
        if (items.isEmpty) {
          return const PlaylistEmptyBox('还没有收藏的歌单');
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: Sp.gapXL),
          itemCount: items.length,
          itemBuilder: (BuildContext c, int i) =>
              _MineRow(meta: items[i], onTap: () => _open(items[i])),
        );
      },
    );
  }
}

/// 歌单详情底部弹层（首页与歌单页共用）：在线详情 + 曲目列表，行点击即播放。
class PlaylistDetailSheet extends StatefulWidget {
  const PlaylistDetailSheet({
    super.key,
    required this.playlistId,
    required this.title,
    required this.cover,
    this.localTrackCount = 0,
  });
  final String playlistId;
  final String title;
  final String cover;
  final int localTrackCount;
  @override
  State<PlaylistDetailSheet> createState() => _PlaylistDetailSheetState();
}

class _PlaylistDetailSheetState extends State<PlaylistDetailSheet> {
  late Future<_SheetData> _f;
  _SheetData _data = const _SheetData(null, TrackPage());
  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<_SheetData> _load() async {
    try {
      final pl = appGraph.playlist;
      if (pl == null) return const _SheetData(null, TrackPage());
      final PlaylistDetail d = await pl.detail(widget.playlistId);
      if (d.id.isEmpty && d.name.isEmpty) {
        return const _SheetData(null, TrackPage());
      }
      final String special = d.specialId.isEmpty ? '' : d.specialId;
      final TrackPage tp = await pl.tracks(
        widget.playlistId,
        1,
        specialIdOverride: special.isEmpty ? null : special,
      );
      _data = _SheetData(d, tp);
      return _data;
    } catch (e, st) {
      Log.e(_tag, 'detail load failed id=${widget.playlistId}', e, st);
      return const _SheetData(null, TrackPage());
    }
  }

  void _play(int index) {
    try {
      PlaybackSession.instance.playAll(_data.tracks.items, index);
    } catch (e, st) {
      Log.e(_tag, 'playAll failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (BuildContext c, ScrollController ctrl) {
        return Container(
          color: context.cs.surfaceContainerLow,
          child: FutureBuilder<_SheetData>(
            future: _f,
            builder: (BuildContext c, AsyncSnapshot<_SheetData> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(
                  child: CircularProgressIndicator(color: context.cs.primary),
                );
              }
              final _SheetData data =
                  snap.data ?? const _SheetData(null, TrackPage());
              final String title = data.detail?.name.isNotEmpty == true
                  ? data.detail!.name
                  : widget.title;
              final List<SongBrief> items = data.tracks.items;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(Sp.pagePad),
                    child: Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Sp.rCard),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: widget.cover.isEmpty
                                ? Container(color: context.cs.surfaceContainerHigh)
                                : Image.network(
                                    widget.cover,
                                    fit: BoxFit.cover,
                                    errorBuilder: (
                                      BuildContext c,
                                      Object e,
                                      StackTrace? s,
                                    ) => Container(color: context.cs.surfaceContainerHigh),
                                  ),
                          ),
                        ),
                        const SizedBox(width: Sp.gapM),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title.isEmpty ? '歌单详情' : title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: Sp.fSection,
                                  fontWeight: FontWeight.w700,
                                  color: context.cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: Sp.gapXS),
                              Text(
                                items.isNotEmpty
                                    ? '${items.length} 首'
                                    : '本地镜像 ${widget.localTrackCount} 首',
                                style: TextStyle(
                                  fontSize: Sp.fSub,
                                  color: context.cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? const PlaylistEmptyBox('该歌单暂无曲目')
                        : ListView.builder(
                            controller: ctrl,
                            itemCount: items.length,
                            itemBuilder: (BuildContext c, int i) => _TrackRow(
                              song: items[i],
                              index: i,
                              onTap: () => _play(i),
                              onAlbum: () {
                                try {
                                  NavState.instance.setAlbum(items[i].albumId);
                                } catch (e, st) {
                                  Log.e(_tag, 'setAlbum failed', e, st);
                                }
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// 网格封面卡：封面 + 名称 + 曲目数。
class PlaylistGridCard extends StatelessWidget {
  const PlaylistGridCard({required this.brief, required this.onTap});
  final PlaylistBrief brief;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final Widget cover = ClipRRect(
      borderRadius: BorderRadius.circular(Sp.rCard),
      child: AspectRatio(
        aspectRatio: 1,
        child: brief.cover.isEmpty
            ? Container(color: context.cs.surfaceContainerHigh)
            : Image.network(
                brief.cover,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    Container(color: context.cs.surfaceContainerHigh),
              ),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          cover,
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

/// 我的歌单行。
class _MineRow extends StatelessWidget {
  const _MineRow({required this.meta, required this.onTap});
  final PlaylistMeta meta;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final Widget lead = ClipRRect(
      borderRadius: BorderRadius.circular(Sp.rM),
      child: SizedBox(
        width: Sp.tileCover,
        height: Sp.tileCover,
        child: meta.coverUrl.isEmpty
            ? Container(color: context.cs.surfaceContainerHigh)
            : Image.network(
                meta.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    Container(color: context.cs.surfaceContainerHigh),
              ),
      ),
    );
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
      leading: lead,
      title: Text(
        meta.name.isEmpty ? '未命名歌单' : meta.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: Sp.fItem, color: context.cs.onSurface),
      ),
      subtitle: Text(
        '${meta.songHashes.length} 首',
        style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right, color: context.cs.onSurfaceVariant),
    );
  }
}

/// 曲目行：序号 + 名称/歌手 + 专辑跳转（NavState 传 id）。
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.song,
    required this.index,
    required this.onTap,
    required this.onAlbum,
  });
  final SongBrief song;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onAlbum;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
      leading: SizedBox(
        width: 28,
        child: Text(
          '${index + 1}',
          style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurfaceVariant),
        ),
      ),
      title: Text(
        song.name.isEmpty ? '未知歌曲' : song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: Sp.fItem, color: context.cs.onSurface),
      ),
      subtitle: Text(
        song.singer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurfaceVariant),
      ),
      trailing: song.albumId.isEmpty
          ? null
          : IconButton(
              tooltip: '专辑',
              iconSize: 18,
              color: context.cs.onSurfaceVariant,
              onPressed: onAlbum,
              icon: const Icon(Icons.album_outlined),
            ),
    );
  }
}

/// 弹层数据载体。
class _SheetData {
  const _SheetData(this.detail, this.tracks);
  final PlaylistDetail? detail;
  final TrackPage tracks;
}

/// 空态。
class PlaylistEmptyBox extends StatelessWidget {
  const PlaylistEmptyBox(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Sp.pagePad,
      vertical: Sp.gapXL,
    ),
    child: Text(
      message,
      style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurfaceVariant),
    ),
  );
}

/// 错误 + 重试。
class PlaylistErrorRetry extends StatelessWidget {
  const PlaylistErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Sp.pagePad,
      vertical: Sp.gapXL,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: Sp.fSub, color: context.cs.error),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(
            '重试',
            style: TextStyle(fontSize: Sp.fSub, color: context.cs.primary),
          ),
        ),
      ],
    ),
  );
}
