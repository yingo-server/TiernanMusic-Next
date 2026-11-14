// L6 surface/widgets · 播放队列弹层（M3）
// 入口：播放页 ⋮ 菜单「播放队列」/ 封面上滑。
// 数据：playerProvider 唯一真源；支持跳转播放与移除。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../player_controller.dart' show playerProvider;
import '../ui/spotify_ui.dart' as sp;

const String _tag = 'surface.queueSheet';

/// 打开播放队列弹层。
Future<void> showQueueSheet(BuildContext context) async {
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _QueueSheet(),
    );
  } catch (e, st) {
    Log.e(_tag, 'showQueueSheet failed', e, st);
  }
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final snap = ref.watch(playerProvider);
      final q = snap.queue;
      final ctl = ref.read(playerProvider.notifier);
      final cs = Theme.of(context).colorScheme;
      final t = Theme.of(context).textTheme;
      final items = q.items;
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scroll) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  sp.Sp.pagePad, 0, sp.Sp.pagePad, sp.Sp.gapM),
              child: Row(
                children: <Widget>[
                  Text('播放队列',
                      style: t.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${items.length} 首',
                      style: t.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const sp.SpStateView(
                      icon: Icons.queue_music,
                      title: '队列为空',
                      subtitle: '去首页或歌单添加歌曲',
                    )
                  : ListView.separated(
                      controller: scroll,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (ctx2, i) {
                        final s = items[i];
                        final current = i == q.index;
                        return ListTile(
                          selected: current,
                          selectedTileColor: cs.primary.withValues(alpha: 0.10),
                          leading: SizedBox(
                            width: 40,
                            child: current
                                ? Icon(Icons.graphic_eq, color: cs.primary)
                                : Text('${i + 1}',
                                    textAlign: TextAlign.center,
                                    style: t.bodyMedium
                                        ?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                          title: Text(s.name.isEmpty ? s.hash : s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.singer,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            try {
                              ctl.playAt(i);
                            } catch (e, st) {
                              Log.e(_tag, 'playAt $i failed', e, st);
                            }
                          },
                          trailing: IconButton(
                            tooltip: '从队列移除',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              try {
                                ctl.removeFromQueue(i);
                              } catch (e, st) {
                                Log.e(_tag, 'remove $i failed', e, st);
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'queue sheet build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
