// L6 surface/pages · 歌手页模块（功能对齐批4-A · GAP_ANALYSIS #22）
// TODO(批10-B): 收敛到 TnDims / TnColors 设计令牌表。
// 装配注入方式（不动 modules.dart / assembly.dart，由主代理接线）：
//   final artistLogic = ArtistLogic(client: ..., cache: ...);      // boot 装配
//   SurfaceRegistry.install(buildArtistModule(
//     logic: artistLogic,
//     currentArtistId: () => navState.currentArtistId,             // 路由参数钩子
//     onPlay: (s) => playerController.playSong(s),                 // 播放回调
//   ));
//   go_router 注册 route '/artist'（模块无 navEntry，非 tab）。
// 依赖纪律：只经 bridge_logic/bridge_core 取 L5/L4 门面与模型；模块间零直接
//   import；同层公共件合法；try/catch + Log('surface.artist_page') 留痕。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show ArtistDetail, AlbumBrief;
import '../../bridges/bridge_logic.dart'
    show ArtistLogic, SongBrief, Log, LogicFacade;
import '../registry.dart';
import '../widgets/common_widgets.dart' show CoverImage, SongTile;
import '../widgets/tn_app_bar.dart' show TnAppBar, TnPagePadding;
import '../theme/tn_theme.dart' show TnDims, tnPadS, tnPadM, tnPadL, tnRadiusM;

const String _tag = 'surface.artist_page';
const int _pageSize = 30;

/// 歌手页模块工厂（deps 注入：ArtistLogic + artistId 提供者 + 播放回调 + 打开专辑回调）。
SurfaceModule buildArtistModule({
  required ArtistLogic logic,
  required String? Function() currentArtistId,
  required void Function(SongBrief) onPlay,
  void Function(AlbumBrief album)? onOpenAlbum,
}) => ArtistPageModule(
      logic: logic,
      currentArtistId: currentArtistId,
      onPlay: onPlay,
      onOpenAlbum: onOpenAlbum);

class ArtistPageModule implements SurfaceModule {
  ArtistPageModule({
    required this.logic,
    required this.currentArtistId,
    required this.onPlay,
    this.onOpenAlbum,
  });
  final ArtistLogic logic;
  final String? Function() currentArtistId;
  final void Function(SongBrief) onPlay;

  /// 打开专辑页回调（由装配层注入；模块间零直接 import）。
  final void Function(AlbumBrief album)? onOpenAlbum;

  @override
  String get id => 'artist';
  @override
  String get route => '/artist';
  @override
  NavEntry? get navEntry => null; // 歌手页由其他页点入，非底部 tab
  @override
  bool enabled(LogicFacade facade) => true;
  @override
  WidgetBuilder builder(LogicFacade facade) => (ctx) => _ArtistPageBody(
        logic: logic,
        artistId: currentArtistId()?.trim() ?? '',
        onPlay: onPlay,
        onOpenAlbum: onOpenAlbum,
      );
}

class _ArtistPageBody extends StatefulWidget {
  const _ArtistPageBody({
    required this.logic,
    required this.artistId,
    required this.onPlay,
    this.onOpenAlbum,
  });
  final ArtistLogic logic;
  final String artistId;
  final void Function(SongBrief) onPlay;

  /// 打开专辑页回调（装配层注入）。
  final void Function(AlbumBrief album)? onOpenAlbum;

  @override
  State<_ArtistPageBody> createState() => _ArtistPageBodyState();
}

class _ArtistPageBodyState extends State<_ArtistPageBody> {
  ArtistDetail _detail = const ArtistDetail();
  List<SongBrief> _audios = const <SongBrief>[];
  List<AlbumBrief> _albums = const <AlbumBrief>[];
  int _audioPage = 1;
  int _albumPage = 1;
  bool _audioMore = true;
  bool _albumMore = true;
  bool _loading = false;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    try {
      Log.d(_tag, 'initState id=${widget.artistId}');
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
    } catch (e, st) {
      Log.e(_tag, 'initState failed', e, st);
    }
  }

  /// 首屏：详情 + 热门歌曲第 1 页 + 专辑第 1 页（并发，世代由 id 固定保证）。
  Future<void> _loadFirst() async {
    try {
      final id = widget.artistId;
      if (id.isEmpty) {
        if (mounted) setState(() => _initialLoading = false);
        Log.w(_tag, 'loadFirst skip: empty artistId');
        return;
      }
      setState(() => _loading = true);
      // 分开 await（不用泛型擦除 + as 强转），三路各自已在 logic 层降级容错。
      final detail = await widget.logic.detail(id);
      final audios = await widget.logic.audios(id, 1, pageSize: _pageSize);
      final albums = await widget.logic.albums(id, 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _audios = audios;
        _albums = albums;
        _audioPage = 1;
        _albumPage = 1;
        _audioMore = audios.length >= _pageSize;
        _albumMore = albums.length >= _pageSize;
        _loading = false;
        _initialLoading = false;
      });
      Log.d(_tag, 'loadFirst id=$id songs=${audios.length} albums=${albums.length}');
    } catch (e, st) {
      Log.e(_tag, 'loadFirst failed id=${widget.artistId}', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _initialLoading = false;
        });
      }
    }
  }

  /// 分页加载：songs=true 取热门歌曲，false 取专辑；列表尾部哨兵自动触发。
  Future<void> _loadMore({required bool songs}) async {
    try {
      if (_loading || widget.artistId.isEmpty) return;
      if (songs ? !_audioMore : !_albumMore) return;
      setState(() => _loading = true);
      final next = (songs ? _audioPage : _albumPage) + 1;
      if (songs) {
        final items = await widget.logic.audios(widget.artistId, next,
            pageSize: _pageSize);
        if (!mounted) return;
        setState(() {
          _audioPage = next;
          _audios = <SongBrief>[..._audios, ...items];
          _audioMore = items.length >= _pageSize;
          _loading = false;
        });
        Log.d(_tag, 'loadMore songs page=$next got=${items.length}');
      } else {
        final items = await widget.logic.albums(widget.artistId, next,
            pageSize: _pageSize);
        if (!mounted) return;
        setState(() {
          _albumPage = next;
          _albums = <AlbumBrief>[..._albums, ...items];
          _albumMore = items.length >= _pageSize;
          _loading = false;
        });
        Log.d(_tag, 'loadMore albums page=$next got=${items.length}');
      }
    } catch (e, st) {
      Log.e(_tag, 'loadMore failed songs=$songs', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _play(SongBrief song) {
    try {
      widget.onPlay(song);
    } catch (e, st) {
      Log.e(_tag, 'onPlay failed hash=${song.hash}', e, st);
    }
  }

  void _openAlbum(AlbumBrief album) {
    try {
      final cb = widget.onOpenAlbum;
      if (cb != null) {
        cb(album);
        return;
      }
      // 未注入回调（装配缺失）时给出可读提示，不静默无响应。
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('专辑 ${album.name.isEmpty ? album.id : album.name}')));
    } catch (e, st) {
      Log.e(_tag, 'openAlbum failed id=${album.id}', e, st);
    }
  }

  Widget _header() {
    try {
      final name = _detail.name.isEmpty ? widget.artistId : _detail.name;
      return TnPagePadding(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: tnPadM),
          child: Row(children: <Widget>[
            CoverImage(url: _detail.avatar, size: const Size(88, 88)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(_detail.intro.isEmpty ? '暂无简介' : _detail.intro,
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'header crashed', e, st);
      return const SizedBox.shrink();
    }
  }

  Widget _songList() {
    try {
      if (_audios.isEmpty && !_initialLoading) {
        return const Center(child: Text('暂无热门歌曲'));
      }
      final count = _audios.length + (_audioMore ? 1 : 0);
      return ListView.builder(
        itemCount: count,
        itemBuilder: (ctx, i) {
          if (i == _audios.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try { _loadMore(songs: true); }
              catch (e, st) { Log.e(_tag, 'song auto load failed', e, st); }
            });
            return const Padding(
              padding: EdgeInsets.all(tnPadL),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return SongTile(song: _audios[i], index: i + 1, onPlay: _play);
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'songList crashed', e, st);
      return const SizedBox.shrink();
    }
  }

  Widget _albumList() {
    try {
      if (_albums.isEmpty && !_initialLoading) {
        return const Center(child: Text('暂无专辑'));
      }
      final count = _albums.length + (_albumMore ? 1 : 0);
      return ListView.builder(
        itemCount: count,
        itemBuilder: (ctx, i) {
          if (i == _albums.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try { _loadMore(songs: false); }
              catch (e, st) { Log.e(_tag, 'album auto load failed', e, st); }
            });
            return const Padding(
              padding: EdgeInsets.all(tnPadL),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final a = _albums[i];
          return ListTile(
            leading: CoverImage(url: a.cover, size: const Size(56, 56)),
            title: Text(a.name.isEmpty ? a.id : a.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${a.publishDate} · ${a.songCount}首',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _openAlbum(a),
          );
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'albumList crashed', e, st);
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: TnAppBar(
            title: _detail.name.isEmpty ? '歌手' : _detail.name,
            actions: <Widget>[
              IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新',
                  onPressed: _initialLoading ? null : () => _loadFirst()),
            ],
            bottom: const TabBar(tabs: <Widget>[
              Tab(text: '热门歌曲'), Tab(text: '专辑'),
            ]),
          ),
          body: widget.artistId.isEmpty
              ? const Center(child: Text('未指定歌手'))
              : Column(children: <Widget>[
                    _header(),
                    if (_initialLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: TabBarView(children: <Widget>[
                        _songList(), _albumList(),
                      ]),
                    ),
                  ]),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}
