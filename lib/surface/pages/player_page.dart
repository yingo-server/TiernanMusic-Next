// L6 surface/pages · 播放页模块（SurfaceModule 热插拔，无 navEntry——非 tab）
// MiniBar 全局悬浮于底部导航上方；点击展开全屏播放页（大封面/Slider seek/上一首/下一首/
// 播放模式/音量）。状态消费 riverpod PlayerSnapshot provider。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart'
    show SearchLogic, PlayerState, PlayerStatus, PlayMode, Log, LogicFacade,
        CollectLogic;
import '../player_controller.dart'
    show PlayerController, playerProvider;
import '../../bridges/bridge_core.dart'
    show AudioQuality, toPref, fromPref;
import '../registry.dart';
import '../widgets/common_widgets.dart' show CoverImage;
import '../widgets/favorite_button.dart' show FavoriteButton;
import '../widgets/quality_sheet.dart' show QualitySheet;
import '../widgets/tn_app_bar.dart' show TnAppBar;

const String _tag = 'surface.player_page';

/// 播放页模块。deps 注入 PlayerController（或经 provider 覆盖取回）。
class PlayerPageModule implements SurfaceModule {
  PlayerPageModule({
    required this.controller,
    this.collect,
    this.onQualitySelected,
    this.onOpenComments,
    this.onStartFm,
  });

  final PlayerController controller;

  /// 收藏门面（可选；为空时不显示收藏按钮）。
  final CollectLogic? collect;

  /// 音质选择回调（可选；为空时不显示音质按钮）。
  final void Function(AudioQuality quality)? onQualitySelected;

  /// 评论入口（可选）。
  final VoidCallback? onOpenComments;

  /// 个人 FM 入口（可选；为空时不显示 FM 按钮）。
  final VoidCallback? onStartFm;

  @override
  String get id => 'player';

  @override
  String get route => '/player';

  @override
  NavEntry? get navEntry => null; // 播放页不是 tab

  @override
  bool enabled(LogicFacade logic) => true;

  @override
  WidgetBuilder builder(LogicFacade logic) => (ctx) => _PlayerPageBody(
        collect: collect,
        onQualitySelected: onQualitySelected,
        onOpenComments: onOpenComments,
        onStartFm: onStartFm,
      );
}

// ── MiniBar：全局悬浮迷你播放条（宿主把本组件叠在底部导航上方） ──

class MiniBar extends ConsumerWidget {
  const MiniBar({super.key, this.onExpand});

  final void Function(BuildContext)? onExpand;

  void _defaultExpand(BuildContext ctx) {
    try {
      Navigator.of(ctx).push(MaterialPageRoute<void>(
          builder: (_) => const _PlayerPageBody(), fullscreenDialog: true));
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
          height: 56,
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
                    padding: const EdgeInsets.all(8),
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

// ── 全屏播放页 ──

class _PlayerPageBody extends ConsumerWidget {
  const _PlayerPageBody({
    this.collect,
    this.onQualitySelected,
    this.onOpenComments,
    this.onStartFm,
  });

  final CollectLogic? collect;
  final void Function(AudioQuality quality)? onQualitySelected;
  final VoidCallback? onOpenComments;
  final VoidCallback? onStartFm;

  String _fmt(int ms) {
    try {
      final s = (ms / 1000).floor();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    } catch (e, st) {
      Log.e(_tag, 'fmt failed', e, st);
      return '0:00';
    }
  }

  /// 弹出音质选择（15 档，批3-C QualitySheet）。
  void _showQualitySheet(BuildContext context) {
    try {
      final cb = onQualitySelected;
      if (cb == null) return;
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => QualitySheet(
          selected: AudioQuality.q128,
          onSelected: (q) {
            try {
              cb(q);
            } catch (e, st) {
              Log.e(_tag, 'quality select failed', e, st);
            }
            Navigator.of(ctx).pop();
          },
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'showQualitySheet failed', e, st);
    }
  }

  IconData _modeIcon(PlayMode m) {    try {
      switch (m) {
        case PlayMode.sequence:
          return Icons.repeat;
        case PlayMode.loopOne:
          return Icons.repeat_one;
        case PlayMode.shuffle:
          return Icons.shuffle;
      }
    } catch (e, st) {
      Log.e(_tag, 'modeIcon failed', e, st);
      return Icons.repeat;
    }
  }

  PlayMode _nextMode(PlayMode m) {
    switch (m) {
      case PlayMode.sequence:
        return PlayMode.loopOne;
      case PlayMode.loopOne:
        return PlayMode.shuffle;
      case PlayMode.shuffle:
        return PlayMode.sequence;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final snap = ref.watch(playerProvider);
      final p = snap.player;
      final ctl = ref.read(playerProvider.notifier);
      final song = p.current;
      return Scaffold(
        appBar: TnAppBar(
          title: '正在播放',
          actions: <Widget>[
            if (onStartFm != null)
              IconButton(
                icon: const Icon(Icons.radio),
                tooltip: '个人 FM',
                onPressed: () {
                  try {
                    onStartFm!();
                  } catch (e, st) {
                    Log.e(_tag, 'start fm failed', e, st);
                  }
                },
              ),
            if (onOpenComments != null)
              IconButton(
                icon: const Icon(Icons.comment_outlined),
                tooltip: '评论',
                onPressed: onOpenComments,
              ),
            if (onQualitySelected != null)
              IconButton(
                icon: const Icon(Icons.high_quality_outlined),
                tooltip: '音质',
                onPressed: () => _showQualitySheet(context),
              ),
            if (collect != null)
              FavoriteButton(
                isCollected: collect!.isCollected(song?.hash ?? ''),
                onToggle: () async {
                  final h = song?.hash ?? '';
                  if (h.isEmpty) return;
                  final r = await collect!.toggle(h, song?.mixSongId ?? 0);
                  if (r.needsLogin && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先登录后再收藏')));
                  }
                },
              ),
            IconButton(
              icon: Icon(_modeIcon(snap.queue.mode)),
              tooltip: '播放模式：${snap.queue.mode.name}',
              onPressed: () {
                try {
                  ctl.setMode(_nextMode(snap.queue.mode));
                } catch (e, st) {
                  Log.e(_tag, 'setMode crashed', e, st);
                }
              },
            ),
          ],
        ),
        body: song == null
            ? const Center(child: Text('队列为空，去搜索或歌单页挑一首吧'))
            : SafeArea(
                child: Column(children: <Widget>[
                  const Spacer(),
                  Center(
                    child: CoverImage(
                        url: null, size: const Size(240, 240)), // SongBrief 无封面 url
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(children: <Widget>[
                      Text(song.name.isEmpty ? song.hash : song.name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(song.singer,
                          style: TextStyle(color: Theme.of(context).hintColor)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  // 进度条 Slider seek
                  Slider(
                    value: p.progress,
                    onChanged: p.durationMs > 0
                        ? (v) {
                            try {
                              ctl.seek((v * p.durationMs).round());
                            } catch (e, st) {
                              Log.e(_tag, 'slider seek crashed', e, st);
                            }
                          }
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(_fmt(p.positionMs)),
                        Text(_fmt(p.durationMs)),
                      ],
                    ),
                  ),
                  // 控制区：上一首 / 播放暂停 / 下一首
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () {
                          try {
                            ctl.prev();
                          } catch (e, st) {
                            Log.e(_tag, 'prev crashed', e, st);
                          }
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        iconSize: 64,
                        icon: Icon(p.status == PlayerStatus.loading
                            ? Icons.hourglass_top
                            : p.isPlaying
                                ? Icons.pause_circle
                                : Icons.play_circle),
                        onPressed: () {
                          try {
                            ctl.toggle();
                          } catch (e, st) {
                            Log.e(_tag, 'toggle crashed', e, st);
                          }
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(Icons.skip_next),
                        onPressed: () {
                          try {
                            ctl.next();
                          } catch (e, st) {
                            Log.e(_tag, 'next crashed', e, st);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 音量条
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(children: <Widget>[
                      const Icon(Icons.volume_down, size: 20),
                      Expanded(
                        child: Slider(
                          value: p.volume.clamp(0.0, 1.0),
                          onChanged: (v) {
                            try {
                              ctl.setVolume(v);
                            } catch (e, st) {
                              Log.e(_tag, 'setVolume crashed', e, st);
                            }
                          },
                        ),
                      ),
                      const Icon(Icons.volume_up, size: 20),
                    ]),
                  ),
                  // 倍速控件暂未提供：PlayerController / AudioEngine 均无
                  // setSpeed 方法（契约见 player_controller.dart），按「不伪造
                  // 能力」原则跳过；待引擎扩展 setSpeed 后在此补 0.5/1.0/1.5/2.0
                  // 四档 chip，调 ctl.setSpeed(v)。
                  if (p.lastError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(p.lastError,
                          style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                ]),
              ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}
