// L6 surface/widgets · 全局悬浮迷你播放条（批R1-B 从 player_page.dart 拆出）
// 宿主把本组件叠在底部导航上方；点击展开全屏播放页。业务/文案零改动。
// 铁律：只 import flutter/riverpod/bridge_logic/本层；每函数 try/catch+Log。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart'
    show PlayerStatus, Log;
import '../player_controller.dart' show playerProvider;
import '../pages/player_page.dart' show PlayerPageBody;
import '../theme/tn_theme.dart' show TnDims, tnPadS;
import 'common_widgets.dart' show CoverImage;

const String _tag = 'surface.mini_bar';

/// MiniBar：全局悬浮迷你播放条（无当前曲不悬浮）。
class MiniBar extends ConsumerWidget {
  const MiniBar({super.key, this.onExpand});

  final void Function(BuildContext)? onExpand;

  void _defaultExpand(BuildContext ctx) {
    try {
      Navigator.of(ctx).push(MaterialPageRoute<void>(
          builder: (_) => const PlayerPageBody(), fullscreenDialog: true));
    } catch (e, st) {
      Log.e(_tag, 'miniBar expand failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final snap = ref.watch(playerProvider);
      final p = snap.player;
      final song = p.current;
      if (song == null || p.status == PlayerStatus.idle) {
        return const SizedBox.shrink(); // 无当前曲不悬浮
      }
      final ctl = ref.read(playerProvider.notifier);
      return Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SizedBox(
          height: TnDims.barH,
          child: Row(children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: () {
                  try {
                    (onExpand ?? _defaultExpand)(context);
                  } catch (e, st) {
                    Log.e(_tag, 'miniBar tap crashed', e, st);
                  }
                },
                child: Row(children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(tnPadS),
                    child: CoverImage(url: song.albumName.isEmpty ? null : null),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(song.name.isEmpty ? song.hash : song.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(song.singer,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).hintColor)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            IconButton(
              icon: Icon(p.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                try {
                  ctl.toggle();
                } catch (e, st) {
                  Log.e(_tag, 'miniBar toggle crashed', e, st);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed: () {
                try {
                  ctl.next();
                } catch (e, st) {
                  Log.e(_tag, 'miniBar next crashed', e, st);
                }
              },
            ),
          ]),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'miniBar build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}
