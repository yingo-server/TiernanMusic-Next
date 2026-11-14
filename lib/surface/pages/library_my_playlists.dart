// L6 surface/pages · 音乐库「我的歌单」横向卡片区
// 数据经 LibraryDeps.myPlaylists 注入（登录态才有）；点开显示曲目（通用弹层）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show PlaylistBrief, SongBrief;
import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show TnDims;
import '../widgets/playlist_tracks_sheet.dart' show showPlaylistTracksSheet;
import 'library_page.dart' show LibraryDeps;

const String _tag = 'surface.library';

/// 「我的歌单」横向卡片区（登录态才有数据；点开显示曲目）。
/// 审查修复：Future 在 initState 一次生成（旧实现 build 内 deps.myPlaylists!()
/// 每次 rebuild 重发接口，下载事件 setState 会放大成接口风暴）。
class LibraryMyPlaylists extends StatefulWidget {
  const LibraryMyPlaylists({required this.deps});

  final LibraryDeps deps;

  @override
  State<LibraryMyPlaylists> createState() => _LibraryMyPlaylistsState();
}

class _LibraryMyPlaylistsState extends State<LibraryMyPlaylists> {
  Future<List<PlaylistBrief>>? _future;

  @override
  void initState() {
    super.initState();
    try {
      _future = widget.deps.myPlaylists?.call();
    } catch (e, st) {
      Log.e(_tag, 'myPlaylists call failed', e, st);
      _future = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _future;
    if (f == null) return const SizedBox.shrink();
    try {
      final cs = Theme.of(context).colorScheme;
      return FutureBuilder<List<PlaylistBrief>>(
        future: f,
        builder: (ctx, snap) {
          final items = snap.data ?? const <PlaylistBrief>[];
          if (snap.connectionState != ConnectionState.done || items.isEmpty) {
            return const SizedBox.shrink();
          }
          return SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final p = items[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    try {
                      final loader = widget.deps.playlistTracks;
                      final detailOf = widget.deps.playlistDetail;
                      if (loader == null || detailOf == null) return;
                      // gc_id 先 detail 换数字 specialId；空则 Log.w + 空曲目。
                      final sid = (await detailOf(p.id)).specialId.trim();
                      if (!ctx.mounted) return;
                      if (sid.isEmpty) {
                        Log.w(_tag, 'empty specialId id=${p.id} → empty tracks');
                      }
                      await showPlaylistTracksSheet(
                        ctx,
                        p,
                        load: () => sid.isEmpty
                            ? Future<List<SongBrief>>.value(const <SongBrief>[])
                            : loader(sid),
                        onPlay: widget.deps.onPlay,
                        onSongAction: widget.deps.onSongAction,
                      );
                    } catch (e, st) {
                      Log.e(_tag, 'open my playlist failed', e, st);
                    }
                  },
                  child: SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 120,
                            height: 120,
                            child: p.cover.isEmpty
                                ? ColoredBox(
                                    color: cs.surfaceContainerHigh,
                                    child: Icon(Icons.queue_music,
                                        color: cs.onSurfaceVariant),
                                  )
                                : Image.network(p.cover,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => ColoredBox(
                                          color: cs.surfaceContainerHigh,
                                          child: Icon(Icons.queue_music,
                                              color: cs.onSurfaceVariant),
                                        )),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(p.name.isEmpty ? '歌单' : p.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.bodyMedium),
                        Text('${p.trackCount} 首',
                            style: Theme.of(ctx).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'my playlists row failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
