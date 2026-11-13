// L6 surface/pages · 音乐库「我的歌单」横向卡片区
// 数据经 LibraryDeps.myPlaylists 注入（登录态才有）；点开显示曲目（通用弹层）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show PlaylistBrief;
import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show TnDims;
import '../widgets/playlist_tracks_sheet.dart' show showPlaylistTracksSheet;
import 'library_page.dart' show LibraryDeps;

const String _tag = 'surface.library';

/// 「我的歌单」横向卡片区（登录态才有数据；点开显示曲目）。
class LibraryMyPlaylists extends StatelessWidget {
  const LibraryMyPlaylists({required this.deps});

  final LibraryDeps deps;

  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      return FutureBuilder<List<PlaylistBrief>>(
        future: deps.myPlaylists!(),
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
                  onTap: () {
                    try {
                      final loader = deps.playlistTracks;
                      if (loader == null) return;
                      showPlaylistTracksSheet(
                        ctx,
                        p,
                        load: () => loader(p.id),
                        onPlay: deps.onPlay,
                        onSongAction: deps.onSongAction,
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
