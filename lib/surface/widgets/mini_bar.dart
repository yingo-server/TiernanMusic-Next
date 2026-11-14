// L6 surface/widgets · 全局悬浮迷你播放条（M3 重构，批UI-1）
// 宿主把本组件叠在底部导航上方；点击展开全屏播放页。
// 视觉基线（截图）：上缘 1px 主色细线、44dp 圆角封面、两行标题、
// 主色圆形播放/暂停 + 次按钮；无当前曲不渲染。
// 铁律：只 import flutter/riverpod/bridge_logic/本层；每函数 try/catch+Log。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart' show PlayerStatus, Log;
import '../player_controller.dart' show playerProvider;
import '../pages/player_page.dart' show PlayerPageBody;
import '../theme/tn_motion.dart' show TnPageRoute;
import '../theme/tn_theme.dart' show TnDims;
import 'common_widgets.dart' show CoverImage;

const String _tag = 'surface.mini_bar';

/// MiniBar：全局悬浮迷你播放条（无当前曲不悬浮）。
class MiniBar extends ConsumerWidget {
  const MiniBar({super.key, this.onExpand});

  final void Function(BuildContext)? onExpand;

  void _defaultExpand(BuildContext ctx) {
    try {
      Navigator.of(ctx).push(TnPageRoute<void>(const PlayerPageBody()));
    } catch (e, st) {
      Log.e(_tag, 'miniBar expand failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final snap = ref.watch(playerProvider);
      if (song == null || p.status == PlayerStatus.idle) {
        return const SizedBox.shrink(); // 无当前曲不悬浮
      }
      final ColorScheme cs = Theme.of(context).colorScheme;
      final TextTheme t = Theme.of(context).textTheme;
      final ctl = ref.read(playerProvider.notifier);
      return Material(
        color: cs.surfaceContainer,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.primary.withValues(alpha: 0.85)),
            ),
          ),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(TnDims.rM),
                  onTap: () {
                    try {
                      (onExpand ?? _defaultExpand)(context);
                    } catch (e, st) {
                      Log.e(_tag, 'miniBar tap crashed', e, st);
                    }
                  },
                  child: Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: CoverImage(
                            url: song.cover.isEmpty ? null : song.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
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
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.singer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  minimumSize: const Size(44, 44),
                ),
                icon: Icon(p.isPlaying ? Icons.pause : Icons.play_arrow),
                tooltip: p.isPlaying ? '暂停' : '播放',
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
                tooltip: '下一首',
                onPressed: () {
                  try {
                    ctl.next();
                  } catch (e, st) {
                    Log.e(_tag, 'miniBar next crashed', e, st);
                  }
                },
              ),
            ],
          ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'miniBar build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}
