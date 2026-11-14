// L6 surface/pages · 专辑页模块（功能对齐批4-B，主会话实现）
// 装配：SurfaceRegistry.install(buildAlbumModule(...))；TnAppBar 统一顶栏。
// 铁律：只 import flutter + ../bridges/ + 本层；每方法 try/catch+Log。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show SongBrief, AlbumDetail, PlaylistBrief;
import '../../bridges/bridge_logic.dart' show AlbumLogic, Log, LogicFacade;
import '../registry.dart';
import '../ui/spotify_ui.dart' as sp;
import '../widgets/common_widgets.dart' show SongTile;
import '../widgets/tn_app_bar.dart' show TnAppBar;
import '../theme/tn_motion.dart' show TnMotionStaggered;

const String _tag = 'surface.album_page';

/// 专辑页模块工厂。
SurfaceModule buildAlbumModule({
  required AlbumLogic logic,
  required String? Function() currentAlbumId,
  required void Function(SongBrief) onPlay,
}) =>
    AlbumPageModule(
        logic: logic, currentAlbumId: currentAlbumId, onPlay: onPlay);

class AlbumPageModule implements SurfaceModule {
  AlbumPageModule({
    required this.logic,
    required this.currentAlbumId,
    required this.onPlay,
  });
  final AlbumLogic logic;
  final String? Function() currentAlbumId;
  final void Function(SongBrief) onPlay;

  @override
  String get id => 'album';
  @override
  String get route => '/album';
  @override
  NavEntry? get navEntry => null;
  @override
  bool enabled(LogicFacade logic) => true;
  @override
  WidgetBuilder builder(LogicFacade _) => (ctx) => AlbumPage(
        logic: logic,
        albumId: currentAlbumId(),
        onPlay: onPlay,
      );
}

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.logic,
    required this.albumId,
    required this.onPlay,
  });
  final AlbumLogic logic;
  final String? albumId;
  final void Function(SongBrief) onPlay;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  AlbumDetail _detail = const AlbumDetail();
  List<SongBrief> _songs = const <SongBrief>[];
  List<PlaylistBrief> _similar = const <PlaylistBrief>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = widget.albumId;
      if (id == null || id.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final d = await widget.logic.detail(id);
      final tp = await widget.logic.songs(id, 1);
      final sim = await widget.logic.similarPlaylists(id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _songs = tp.items;
        _similar = sim;
        _loading = false;
      });
      Log.d(_tag, 'loaded id=$id songs=${_songs.length} similar=${_similar.length}');
    } catch (e, st) {
      Log.e(_tag, 'load failed', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: TnAppBar(title: _detail.name.isEmpty ? '专辑' : _detail.name),
        body: _loading
            // 页面级加载态（R2-B 统一）：Linear（局部加载才用 Circular）。
            ? const LinearProgressIndicator(minHeight: 2)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_detail.cover.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(sp.Sp.pagePad),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(sp.Sp.rCard),
                        child: Image.network(_detail.cover,
                            height: 160, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink()),
                      ),
                    ),
                  if (_detail.intro.isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: sp.Sp.pagePad),
                      child: Text(_detail.intro,
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                  Expanded(
                    child: _songs.isEmpty
                        ? const Center(child: Text('暂无歌曲'))
                        : ListView.builder(
                            itemCount: _songs.length,
                            itemBuilder: (ctx, i) {
                              final s = _songs[i];
                              // 歌曲列表入场交错动画（R2-B 接线）。
                              return TnMotionStaggered(
                                index: i,
                                child: SongTile(
                                  song: s,
                                  onPlay: widget.onPlay,
                                ),
                              );
                            },
                          ),
                  ),
                  if (_similar.isNotEmpty)
                    SizedBox(
                      height: 96,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _similar.length,
                        itemBuilder: (ctx, i) {
                          final p = _similar[i];
                          // 相似歌单横滑区入场交错动画（R2-B 接线）：+4 错开歌曲列表。
                          return TnMotionStaggered(
                            index: i + 4,
                            child: Container(
                            width: 140,
                            padding: const EdgeInsets.all(sp.Sp.gapS),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text('${p.trackCount} 首',
                                    style: const TextStyle(
                                        fontSize: sp.Sp.fTiny)),
                              ],
                            ),
                          ));
                        },
                      ),
                    ),
                ],
              ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return const Scaffold(body: Center(child: Text('页面加载失败')));
    }
  }
}
