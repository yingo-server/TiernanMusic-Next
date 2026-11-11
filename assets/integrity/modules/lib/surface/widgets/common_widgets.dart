// L6 surface/widgets · 跨页面共享小组件：SongTile / CoverImage
// 模块间禁止 import，本文件是被各页面模块 import 的本层公共件。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SongBrief;
import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show TnDims;

const String _tag = 'surface.widgets';

/// 歌曲行：序号/封面占位 + 歌名 + 歌手 | 时长，点击回调 playSong。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onPlay,
    this.index,
    this.playing = false,
  });

  final SongBrief song;
  final void Function(SongBrief) onPlay;
  final int? index; // 序号（队列/歌单内），null 不显示
  final bool playing; // 当前正在播高亮

  void _tap() {
    try {
      onPlay(song);
    } catch (e, st) {
      Log.e(_tag, 'SongTile onPlay crashed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final dur = song.durationSec > 0
          ? '${song.durationSec ~/ 60}:${(song.durationSec % 60).toString().padLeft(2, '0')}'
          : '--:--';
      return ListTile(
        onTap: _tap,
        leading: SizedBox(
          width: 40,
          child: Center(
            child: index != null
                ? Text('$index',
                    style: TextStyle(
                        color: playing
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).hintColor))
                : const Icon(Icons.music_note),
          ),
        ),
        title: Text(
          song.name.isEmpty ? song.hash : song.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: playing
              ? TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold)
              : null,
        ),
        subtitle: Text(
          '${song.singer}${song.albumName.isEmpty ? '' : ' · ${song.albumName}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(dur, style: TextStyle(color: Theme.of(context).hintColor)),
      );
    } catch (e, st) {
      Log.e(_tag, 'SongTile.build crashed', e, st);
      return const SizedBox(height: TnDims.barH);
    }
  }
}

/// 封面图：url 空或加载失败回退占位图标（无第三方库）。
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, this.url, this.size = const Size(56, 56)});

  final String? url;
  final Size size;

  @override
  Widget build(BuildContext context) {
    try {
      final u = (url ?? '').trim();
      if (u.isEmpty) return _placeholder(context);
      return ClipRRect(
        borderRadius: BorderRadius.circular(TnDims.rS),
        child: Image.network(
          u,
          width: size.width,
          height: size.height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _placeholder(context),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'CoverImage.build crashed', e, st);
      return _placeholder(context);
    }
  }

  Widget _placeholder(BuildContext context) => Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(TnDims.rS),
        ),
        child: Icon(Icons.album, size: size.shortestSide * 0.6,
            color: Theme.of(context).hintColor),
      );
}
