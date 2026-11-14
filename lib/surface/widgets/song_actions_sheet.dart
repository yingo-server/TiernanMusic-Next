// L6 surface/widgets · 歌曲操作弹层（下一首播放 / 收藏 / 下载 / 信息）
// 入口：列表条目 ⋮ 菜单（首页新歌推荐、歌单曲目、收藏列表）。
// 动作全部经注入回调，弹层自身不持有业务状态。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SongBrief;
import '../../bridges/bridge_logic.dart' show Log;
import '../ui/spotify_ui.dart' show Sp;

const String _tag = 'surface.songActions';

/// 歌曲操作弹层。
Future<void> showSongActionsSheet(
  BuildContext context,
  SongBrief song, {
  VoidCallback? onPlayNext,
  VoidCallback? onCollect,
  bool collected = false,
  VoidCallback? onDownload,
}) async {
  try {
    if (song.hash.isEmpty) {
      Log.w(_tag, 'showSongActionsSheet: empty hash');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Sp.pagePad, 0, Sp.pagePad, Sp.gapS),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(song.name.isEmpty ? song.hash : song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall),
                    const SizedBox(height: 2),
                    Text(song.singer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall
                            ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (onPlayNext != null)
                ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: const Text('下一首播放'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    try {
                      onPlayNext();
                    } catch (e, st) {
                      Log.e(_tag, 'playNext failed', e, st);
                    }
                  },
                ),
              if (onCollect != null)
                ListTile(
                  leading: Icon(collected
                      ? Icons.favorite
                      : Icons.favorite_border),
                  title: Text(collected ? '取消收藏' : '收藏'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    try {
                      onCollect();
                    } catch (e, st) {
                      Log.e(_tag, 'collect failed', e, st);
                    }
                  },
                ),
              if (onDownload != null)
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('下载'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    try {
                      onDownload();
                    } catch (e, st) {
                      Log.e(_tag, 'download failed', e, st);
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('歌曲信息'),
                subtitle: Text(
                  'hash ${song.hash}\n'
                  'mixsongid ${song.mixSongId} · '
                  'album_audio_id ${song.albumAudioId}\n'
                  '时长 ${song.durationSec}s · bitrate ${song.bitrate}',
                ),
                isThreeLine: true,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  } catch (e, st) {
    Log.e(_tag, 'showSongActionsSheet failed', e, st);
  }
}
