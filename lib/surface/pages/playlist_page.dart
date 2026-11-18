// L7 surface/pages · 歌单页（官方 M3 + 语义 token 森林翡翠）。
//
// 契约：只用官方 Material 3 控件 + get 包现成能力；不手写控件类（页面/弹层容器除外）；
// 颜色只来自 context.cs.*（design/tokens_v2.dart 的 ColorScheme 扩展）；
// 数据只经 bridge_logic/logic 单例取；异步 future 只在 initState / 交互回调持有。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show PlaylistMeta;
import '../../bridges/bridge_logic.dart'
    show Log, SongBrief, PlaylistBrief, PlaylistDetail, TrackPage;
import '../../bridges/bridge_session.dart'
    show NavState, PlaybackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens_v2.dart';

const String _tag = 'surface.playlist';

const double _pad = 16;
const double _gapXS = 4;
const double _gapS = 8;
const double _gapM = 12;
const double _gapXL = 24;
const double _radiusS = 8;

/// 页面模块注册（L7 注入 builder，宿主按 id 覆盖 session 占位模块）。
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

/// 歌单页：官方 NavigationBar 分段（推荐 / 我的）+ 网格 + 详情底部弹层。
///
/// 说明：原 DefaultTabController + 自写 _RecommendTab/_MineTab StatefulWidget
/// 改为页面自身持有两个 future（initState 加载）+ IndexedStack 切换，
/// 既保留原业务逻辑，又消灭手写控件类。
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  int _tab = 0;
  late Future<List<PlaylistBrief>> _recommendF;
  late Future<List<PlaylistMeta>> _mineF;

  @override
  void initState() {
    super.initState();
    _recommendF = _loadRecommend();
    _mineF = _loadMine();
  }

  Future<List<PlaylistBrief>> _loadRecommend() async {
    try {
      final pl = appGraph.playlist;
      if (pl == null) return const <PlaylistBrief>[];
      return pl.recommend(1);
    } catch (e, st) {
      Log.e(_tag, 'recommend failed', e, st);
      return const <PlaylistBrief>[];
    }
  }

  Future<List<PlaylistMeta>> _loadMine() async {
    try {
      final pl = appGraph.playlist;
      if (pl == null) return const <PlaylistMeta>[];
      return pl.listLocal();
    } catch (e, st) {
      Log.e(_tag, 'listLocal failed', e, st);
      return const <PlaylistMeta>[];
    }
  }

  void _reloadRecommend() => setState(() => _recommendF = _loadRecommend());
  void _reloadMine() => setState(() => _mineF = _loadMine());

  void _openBrief(PlaylistBrief brief) {
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
      Log.e(_tag, 'open detail failed', e, st);
    }
  }

  void _openMeta(PlaylistMeta meta) {
    try {
      showModalBottomSheet<void>(
        context: context,
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
    return Scaffold(
      appBar: AppBar(
        title: Text('歌单', style: Theme.of(context).textTheme.headlineSmall),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const <NavigationDestination>[
                NavigationDestination(icon: Icon(Icons.recommend), label: '推荐'),
                NavigationDestination(icon: Icon(Icons.library_music_outlined), label: '我的'),
              ],
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _recommendTab(context),
                  _mineTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 推荐歌单网格：官方 GridView + Card（原 PlaylistGridCard）。
  Widget _recommendTab(BuildContext c) {
    return FutureBuilder<List<PlaylistBrief>>(
      future: _recommendF,
      builder: (BuildContext c, AsyncSnapshot<List<PlaylistBrief>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loading(c);
        }
        if (snap.hasError) {
          return _error(c, '推荐歌单加载失败', _reloadRecommend);
        }
        final List<PlaylistBrief> items = snap.data ?? const <PlaylistBrief>[];
        if (items.isEmpty) return _empty(c, '暂无推荐歌单');
        final columns = MediaQuery.sizeOf(c).width >= 1000
            ? 5
            : MediaQuery.sizeOf(c).width >= 600
            ? 4
            : 3;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(_pad, _gapM, _pad, _gapXL),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.72,
            crossAxisSpacing: _gapM,
            mainAxisSpacing: _gapM,
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext c, int i) =>
              _gridCard(c, items[i], () => _openBrief(items[i])),
        );
      },
    );
  }

  /// 我的歌单：官方 ListView + ListTile（原 _MineRow）。
  Widget _mineTab(BuildContext c) {
    return FutureBuilder<List<PlaylistMeta>>(
      future: _mineF,
      builder: (BuildContext c, AsyncSnapshot<List<PlaylistMeta>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loading(c);
        }
        if (snap.hasError) {
          return _error(c, '我的歌单加载失败', _reloadMine);
        }
        final List<PlaylistMeta> items = snap.data ?? const <PlaylistMeta>[];
        if (items.isEmpty) return _empty(c, '还没有收藏的歌单');
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: _gapXL),
          itemCount: items.length,
          itemBuilder: (BuildContext c, int i) =>
              _mineRow(c, items[i], () => _openMeta(items[i])),
        );
      },
    );
  }

  /// 网格封面卡：官方 Card + InkWell + ClipRRect/Image.network。
  Widget _gridCard(BuildContext c, PlaylistBrief brief, VoidCallback onTap) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: brief.cover.isEmpty
                  ? Container(color: c.cs.surfaceContainerHigh)
                  : Image.network(
                      brief.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: c.cs.surfaceContainerHigh),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(_gapS),
              child: Text(
                brief.name.isEmpty ? '未命名歌单' : brief.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(c).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gapS),
              child: Text(
                brief.trackCount > 0 ? '${brief.trackCount} 首' : '曲目数未知',
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 我的歌单行：官方 ListTile。
  Widget _mineRow(BuildContext c, PlaylistMeta meta, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: _pad),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(_radiusS),
        child: SizedBox(
          width: 48,
          height: 48,
          child: meta.coverUrl.isEmpty
              ? Container(color: c.cs.surfaceContainerHigh)
              : Image.network(
                  meta.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: c.cs.surfaceContainerHigh),
                ),
        ),
      ),
      title: Text(
        meta.name.isEmpty ? '未命名歌单' : meta.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(c).textTheme.bodyMedium,
      ),
      subtitle: Text(
        '${meta.songHashes.length} 首',
        style: Theme.of(c).textTheme.bodySmall,
      ),
      trailing: Icon(Icons.chevron_right, color: c.cs.onSurfaceVariant),
    );
  }

  /// 加载占位：官方 Card + LinearProgressIndicator（原 SpSkeleton）。
  Widget _loading(BuildContext c) {
    return Center(
      child: SizedBox(
        width: 160,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(_gapM),
            child: LinearProgressIndicator(
              minHeight: 3,
              color: c.cs.primary,
              backgroundColor: c.cs.surfaceContainerHigh,
            ),
          ),
        ),
      ),
    );
  }

  /// 空态：官方 Icon + Text（原 PlaylistEmptyBox / SpStateView）。
  Widget _empty(BuildContext c, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.queue_music, color: c.cs.onSurfaceVariant),
            const SizedBox(height: _gapS),
            Text(message, style: Theme.of(c).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  /// 错误 + 重试：官方 Icon + Text + FilledButton.tonal（原 PlaylistErrorRetry）。
  Widget _error(BuildContext c, String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, color: c.cs.error),
            const SizedBox(height: _gapS),
            Text(message, style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: _gapS),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
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

  void _openAlbum(String albumId) {
    try {
      NavState.instance.setAlbum(albumId);
    } catch (e, st) {
      Log.e(_tag, 'setAlbum failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (BuildContext c, ScrollController ctrl) {
        return FutureBuilder<_SheetData>(
          future: _f,
          builder: (BuildContext c, AsyncSnapshot<_SheetData> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
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
                _header(c, title, items),
                Expanded(
                  child: items.isEmpty
                      ? _emptyTracks(c)
                      : ListView.builder(
                          controller: ctrl,
                          itemCount: items.length,
                          itemBuilder: (BuildContext c, int i) => _trackRow(
                            c,
                            items[i],
                            i,
                            () => _play(i),
                            () => _openAlbum(items[i].albumId),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 弹层头部：官方 Row + ClipRRect/Image.network（原内联封面块）。
  Widget _header(BuildContext c, String title, List<SongBrief> items) {
    return Padding(
      padding: const EdgeInsets.all(_pad),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(_radiusS),
            child: SizedBox(
              width: 64,
              height: 64,
              child: widget.cover.isEmpty
                  ? Container(color: c.cs.surfaceContainerHigh)
                  : Image.network(
                      widget.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: c.cs.surfaceContainerHigh),
                    ),
            ),
          ),
          const SizedBox(width: _gapM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.isEmpty ? '歌单详情' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                const SizedBox(height: _gapXS),
                Text(
                  items.isNotEmpty
                      ? '${items.length} 首'
                      : '本地镜像 ${widget.localTrackCount} 首',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 曲目行：官方 ListTile（原 _TrackRow）。
  Widget _trackRow(BuildContext c, SongBrief song, int index,
      VoidCallback onTap, VoidCallback onAlbum) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: _pad),
      leading: SizedBox(
        width: 28,
        child: Text('${index + 1}', style: Theme.of(c).textTheme.bodySmall),
      ),
      title: Text(
        song.name.isEmpty ? '未知歌曲' : song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(c).textTheme.bodyMedium,
      ),
      subtitle: Text(
        song.singer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(c).textTheme.bodySmall,
      ),
      trailing: song.albumId.isEmpty
          ? null
          : IconButton(
              tooltip: '专辑',
              iconSize: 18,
              onPressed: onAlbum,
              icon: const Icon(Icons.album_outlined),
            ),
    );
  }

  /// 空曲目：官方 Icon + Text（原 PlaylistEmptyBox）。
  Widget _emptyTracks(BuildContext c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.music_off, color: c.cs.onSurfaceVariant),
            const SizedBox(height: _gapS),
            Text('该歌单暂无曲目', style: Theme.of(c).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// 弹层数据载体（纯数据，非控件）。
class _SheetData {
  const _SheetData(this.detail, this.tracks);
  final PlaylistDetail? detail;
  final TrackPage tracks;
}
