// L7 surface/design · 迷你播放条（悬浮于底部导航之上）
// 数据源：L6 session 的 PlaybackSnapshot（ChangeNotifier）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SongBrief;
import '../../bridges/bridge_session.dart'
    show PlaybackSession, PlaybackSnapshot;
import 'components.dart' show SpCover;
import 'tokens.dart';

/// 迷你条：封面 + 歌名/歌手 + 播放/暂停 + 下一首；点击展开播放页。
class SpMiniBar extends StatelessWidget {
  const SpMiniBar({super.key, this.onExpand});

  /// 展开播放页（由外壳注入）。
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final session = PlaybackSession.instance;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final snap = session.snapshot;
        final song = snap.current;
        if (song == null) return const SizedBox.shrink();
        return _bar(context, session, snap, song);
      },
    );
  }

  Widget _bar(
    BuildContext context,
    PlaybackSession session,
    PlaybackSnapshot snap,
    SongBrief song,
  ) {
    final t = Theme.of(context).textTheme;
    final playing = snap.player.isPlaying;
    return Material(
      color: context.cs.surfaceContainerLow,
      child: InkWell(
        onTap: onExpand,
        child: Container(
          height: Sp.barH,
          padding: const EdgeInsets.symmetric(horizontal: Sp.gapM),
          child: Row(
            children: <Widget>[
              SpCover(url: song.cover, size: 40, radius: Sp.rS),
              const SizedBox(width: Sp.gapM),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      song.name.isEmpty ? song.hash : song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (song.singer.isNotEmpty)
                      Text(
                        song.singer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: session.toggle,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                color: context.cs.onSurface,
                tooltip: playing ? '暂停' : '播放',
              ),
              IconButton(
                onPressed: session.next,
                icon: const Icon(Icons.skip_next),
                color: context.cs.onSurface,
                tooltip: '下一首',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
