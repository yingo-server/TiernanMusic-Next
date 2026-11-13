// L6 surface/widgets · 歌单曲目弹层（通用版，首页与音乐库共用）
// 数据源由调用方注入（首页用 PlaylistLogic、音乐库用装配层回调），
// 弹层只负责渲染与交互，不持有业务状态。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SongBrief, PlaylistBrief;
import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show TnDims;
import 'm3/m3_skeleton.dart' show M3ListSkeleton;
import 'm3/m3_state_views.dart' show M3EmptyState, M3ErrorRetry;

const String _tag = 'surface.playlistSheet';

/// 打开歌单曲目弹层。
Future<void> showPlaylistTracksSheet(
  BuildContext context,
  PlaylistBrief brief, {
  required Future<List<SongBrief>> Function() load,
  required void Function(SongBrief) onPlay,
  void Function(SongBrief)? onSongAction,
  String emptyHint = '暂无曲目',
}) async {
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final t = Theme.of(ctx).textTheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx2, scroll) => Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    TnDims.padL, 0, TnDims.padL, TnDims.padM),
                child: Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: brief.cover.isEmpty
                            ? ColoredBox(
                                color: cs.surfaceContainerHigh,
                                child: Icon(Icons.queue_music,
                                    color: cs.onSurfaceVariant),
                              )
                            : Image.network(brief.cover,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                      color: cs.surfaceContainerHigh,
                                      child: Icon(Icons.queue_music,
                                          color: cs.onSurfaceVariant),
                                    )),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(brief.name.isEmpty ? '歌单' : brief.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleMedium?.copyWith(color: cs.onSurface)),
                          const SizedBox(height: 2),
                          Text('${brief.trackCount} 首',
                              style:
                                  t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<SongBrief>>(
                  future: load(),
                  builder: (ctx3, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const M3ListSkeleton(rows: 6);
                    }
                    if (snap.hasError) {
                      return M3ErrorRetry(
                        title: '歌单加载失败',
                        detail: '${snap.error}',
                        onRetry: () => Navigator.of(ctx3).pop(),
                      );
                    }
                    final songs = snap.data ?? const <SongBrief>[];
                    if (songs.isEmpty) {
                      return M3EmptyState(
                        icon: Icons.queue_music,
                        title: emptyHint,
                        subtitle: '该歌单没有可播放的歌曲',
                      );
                    }
                    return ListView.separated(
                      controller: scroll,
                      itemCount: songs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final s = songs[i];
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: s.cover.isEmpty
                                  ? ColoredBox(
                                      color: cs.surfaceContainerHigh,
                                      child: Icon(Icons.music_note,
                                          color: cs.onSurfaceVariant),
                                    )
                                  : Image.network(s.cover,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => ColoredBox(
                                            color: cs.surfaceContainerHigh,
                                            child: Icon(Icons.music_note,
                                                color: cs.onSurfaceVariant),
                                          )),
                            ),
                          ),
                          title: Text(s.name.isEmpty ? s.hash : s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.singer,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            try {
                              onPlay(s);
                            } catch (e, st) {
                              Log.e(_tag, 'play failed', e, st);
                            }
                          },
                          trailing: onSongAction == null
                              ? null
                              : IconButton(
                                  tooltip: '更多',
                                  icon: const Icon(Icons.more_vert),
                                  onPressed: () {
                                    try {
                                      onSongAction!(s);
                                    } catch (e, st) {
                                      Log.e(_tag, 'song action failed', e, st);
                                    }
                                  },
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  } catch (e, st) {
    Log.e(_tag, 'showPlaylistTracksSheet failed', e, st);
  }
}
