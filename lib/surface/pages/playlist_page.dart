// L6 surface/pages · 歌单页模块（SurfaceModule 热插拔）
// recommend 网格（封面+名字）+ 点击进歌单 tracks（Navigator.push 简单页）+ 本地镜像 listLocal tab。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show
        PlaylistLogic,
        PlaylistBrief,
        PlaylistDetail,
        PlaylistMeta,
        TrackPage,
        Log,
        LogicFacade;
import '../../bridges/bridge_core.dart' show SongBrief, PlaylistMeta;
import '../player_controller.dart' show PlayerController;
import '../registry.dart';
import '../widgets/common_widgets.dart' show CoverImage, SongTile;
import '../widgets/tn_app_bar.dart' show TnAppBar;
import '../theme/tn_theme.dart' show TnDims, tnPadS, tnPadM, tnPadL, tnRadiusM;

const String _tag = 'surface.playlist';

/// 歌单页模块。deps 注入 PlaylistLogic + PlayerController。
class PlaylistPageModule implements SurfaceModule {
  PlaylistPageModule({required PlaylistLogic playlist, required PlayerController player})
      : _playlist = playlist,
        _player = player;

  final PlaylistLogic _playlist;
  final PlayerController _player;

  @override
  String get id => 'playlist';

  @override
  String get route => '/playlist';

  @override
  NavEntry? get navEntry => const NavEntry('歌单', 'queue_music');

  @override
  bool enabled(LogicFacade logic) => true;

  @override
  WidgetBuilder builder(LogicFacade logic) => (ctx) => _PlaylistPageBody(
        playlist: _playlist,
        player: _player,
      );
}

class _PlaylistPageBody extends StatefulWidget {
  const _PlaylistPageBody({required this.playlist, required this.player});

  final PlaylistLogic playlist;
  final PlayerController player;

  @override
  State<_PlaylistPageBody> createState() => _PlaylistPageBodyState();
}

class _PlaylistPageBodyState extends State<_PlaylistPageBody> {
  static const int _pageSize = 30;
  List<PlaylistBrief> _recommend = const <PlaylistBrief>[];
  List<PlaylistMeta> _local = const <PlaylistMeta>[];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    try {
      _loadRecommend(reset: true);
      _loadLocal();
      Log.d(_tag, 'initState');
    } catch (e, st) {
      Log.e(_tag, 'initState failed', e, st);
    }
  }

  @override
  void dispose() {
    try {
      Log.d(_tag, 'dispose');
    } catch (e, st) {
      Log.e(_tag, 'dispose failed', e, st);
    }
    super.dispose();
  }

  Future<void> _loadRecommend({bool reset = false}) async {
    try {
      if (_loading) return;
      setState(() => _loading = true);
      final p = reset ? 1 : _page + 1;
      final items = await widget.playlist.recommend(p, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _recommend = reset ? items : <PlaylistBrief>[..._recommend, ...items];
        _page = p;
        _hasMore = items.length >= _pageSize;
        _loading = false;
      });
      Log.d(_tag, 'loadRecommend page=$p got=${items.length}');
    } catch (e, st) {
      Log.e(_tag, 'loadRecommend failed', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLocal() async {
    try {
      final list = await widget.playlist.listLocal();
      if (!mounted) return;
      setState(() => _local = list);
    } catch (e, st) {
      Log.e(_tag, 'loadLocal failed', e, st);
    }
  }

  Future<void> _openDetail(PlaylistBrief brief) async {
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _PlaylistTracksPage(
          playlist: widget.playlist,
          player: widget.player,
          playlistId: brief.id,
          title: brief.name,
        ),
      ));
      _loadLocal(); // 镜像可能已更新
    } catch (e, st) {
      Log.e(_tag, 'openDetail failed id=${brief.id}', e, st);
    }
  }

  void _openLocalMirror(PlaylistMeta meta) {
    try {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _LocalMirrorPage(
          player: widget.player,
          meta: meta,
          playlist: widget.playlist,
        ),
      ));
    } catch (e, st) {
      Log.e(_tag, 'openLocalMirror failed id=${meta.playlistId}', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: TnAppBar(
            title: '歌单',
            bottom: const TabBar(tabs: <Widget>[
              Tab(text: '推荐'),
              Tab(text: '本地'),
            ]),
          ),
          body: TabBarView(children: <Widget>[
            _buildRecommendGrid(),
            _buildLocalList(),
          ]),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build crashed', e, st);
      return const SizedBox.shrink();
    }
  }

  Widget _buildRecommendGrid() {
    try {
      final count = _recommend.length + (_hasMore ? 1 : 0);
      return RefreshIndicator(
        onRefresh: () => _loadRecommend(reset: true),
        child: GridView.builder(
          padding: const EdgeInsets.all(tnPadS),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.78,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: count,
          itemBuilder: (ctx, i) {
            if (i == _recommend.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  _loadRecommend();
                } catch (e, st) {
                  Log.e(_tag, 'grid auto load failed', e, st);
                }
              });
              return const Center(child: CircularProgressIndicator());
            }
            final b = _recommend[i];
            return InkWell(
              onTap: () => _openDetail(b),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                Expanded(
                  child: CoverImage(url: b.cover, size: const Size(200, 200)),
                ),
                const SizedBox(height: 4),
                Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                Text('${b.trackCount}首 · ${b.playCount}次',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(ctx).hintColor)),
              ]),
            );
          },
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'buildRecommendGrid crashed', e, st);
      return const SizedBox.shrink();
    }
  }

  Widget _buildLocalList() {
    try {
      if (_local.isEmpty) {
        return const Center(child: Text('暂无本地歌单镜像'));
      }
      return ListView.builder(
        itemCount: _local.length,
        itemBuilder: (ctx, i) {
          final m = _local[i];
          return ListTile(
            leading: CoverImage(url: m.coverUrl),
            title: Text(m.name.isEmpty ? m.playlistId : m.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${m.songHashes.length}首 · ${m.source}'),
            onTap: () => _openLocalMirror(m),
          );
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'buildLocalList crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}

/// 在线歌单 tracks 分页列表（Navigator.push 简单页，不引入 go_router）。
class _PlaylistTracksPage extends StatefulWidget {
  const _PlaylistTracksPage({
    required this.playlist,
    required this.player,
    required this.playlistId,
    required this.title,
  });

  final PlaylistLogic playlist;
  final PlayerController player;
  final String playlistId;
  final String title;

  @override
  State<_PlaylistTracksPage> createState() => _PlaylistTracksPageState();
}

class _PlaylistTracksPageState extends State<_PlaylistTracksPage> {
  static const int _pageSize = 30;
  final ScrollController _scrollCtrl = ScrollController();
  PlaylistDetail _detail = const PlaylistDetail();
  List<SongBrief> _tracks = const <SongBrief>[];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    try {
      _scrollCtrl.addListener(_onScroll);
      _loadFirst();
      Log.d(_tag, 'tracksPage init id=${widget.playlistId}');
    } catch (e, st) {
      Log.e(_tag, 'tracksPage initState failed', e, st);
    }
  }

  @override
  void dispose() {
    try {
      _scrollCtrl.dispose();
      Log.d(_tag, 'tracksPage dispose');
    } catch (e, st) {
      Log.e(_tag, 'tracksPage dispose failed', e, st);
    }
    super.dispose();
  }

  Future<void> _loadFirst() async {
    try {
      setState(() => _loading = true);
      final d = await widget.playlist.detail(widget.playlistId);
      final tp = await widget.playlist.tracks(widget.playlistId, 1,
          pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _tracks = tp.items;
        _page = 1;
        _hasMore = tp.hasMore;
        _loading = false;
      });
      Log.d(_tag, 'loadFirst id=${widget.playlistId} got=${tp.items.length}');
    } catch (e, st) {
      Log.e(_tag, 'loadFirst failed id=${widget.playlistId}', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    try {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (pos.pixels < pos.maxScrollExtent - 200 || _loading || !_hasMore) return;
      _loadMore();
    } catch (e, st) {
      Log.e(_tag, 'tracks onScroll failed', e, st);
    }
  }

  Future<void> _loadMore() async {
    try {
      if (_loading || !_hasMore) return;
      setState(() => _loading = true);
      final tp = await widget.playlist.tracks(widget.playlistId, _page + 1,
          pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _tracks = <SongBrief>[..._tracks, ...tp.items];
        _hasMore = tp.hasMore;
        _loading = false;
      });
    } catch (e, st) {
      Log.e(_tag, 'loadMore failed id=${widget.playlistId}', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playAll() async {
    try {
      if (_tracks.isEmpty) return;
      await widget.player.playAll(_tracks, 0);
      Log.d(_tag, 'playAll ${widget.playlistId} n=${_tracks.length}');
    } catch (e, st) {
      Log.e(_tag, 'playAll failed', e, st);
    }
  }

  Future<void> _saveMirror() async {
    try {
      final ok = await widget.playlist.saveLocalMirror(_detail, _tracks);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? '已保存本地镜像' : '保存镜像失败')));
    } catch (e, st) {
      Log.e(_tag, 'saveMirror failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final count = _tracks.length + (_hasMore ? 1 : 0);
      return Scaffold(
        appBar: TnAppBar(
          title: _detail.name.isEmpty ? widget.title : _detail.name,
          actions: <Widget>[
            IconButton(icon: const Icon(Icons.save_alt), onPressed: _saveMirror),
            IconButton(icon: const Icon(Icons.play_arrow), onPressed: _playAll),
          ],
        ),
        body: ListView.builder(
          controller: _scrollCtrl,
          itemCount: count,
          itemBuilder: (ctx, i) {
            if (i == _tracks.length) {
              return const Padding(
                padding: EdgeInsets.all(tnPadL),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return SongTile(
              song: _tracks[i],
              onPlay: (s) {
                try {
                  widget.player.playAll(_tracks, i);
                } catch (e, st) {
                  Log.e(_tag, 'tile play failed', e, st);
                }
              },
              index: i + 1,
            );
          },
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'tracksPage build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}

/// 本地镜像歌单页：PlaylistMeta 仅含 hash 列表，展示 hash 索引 + 单曲起播。
class _LocalMirrorPage extends StatelessWidget {
  const _LocalMirrorPage({
    required this.meta,
    required this.playlist,
    required this.player,
  });

  final PlaylistMeta meta;
  final PlaylistLogic playlist;
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: TnAppBar(
            title: meta.name.isEmpty ? meta.playlistId : meta.name),
        body: meta.songHashes.isEmpty
            ? const Center(child: Text('镜像歌单为空'))
            : ListView.builder(
                itemCount: meta.songHashes.length,
                itemBuilder: (ctx, i) => SongTile(
                  song: SongBrief(hash: meta.songHashes[i]),
                  index: i + 1,
                  onPlay: (s) {
                    try {
                      player.playSong(s);
                    } catch (e, st) {
                      Log.e(_tag, 'mirror play failed', e, st);
                    }
                  },
                ),
              ),
      );
    } catch (e, st) {
      Log.e(_tag, 'mirrorPage build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}
