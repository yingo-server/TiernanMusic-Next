// L7 surface/pages · 播放页（Spotify 深色 + M3）
// 铁律：只画控件；数据只来自 PlaybackSession 快照；样式一律 Sp.*。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show AudioQuality, qualityParam, vipQualities;
import '../../bridges/bridge_logic.dart' show PlayMode, SongBrief;
import '../../bridges/bridge_session.dart'
    show
        appGraph,
        playbackSession,
        navState,
        PlaybackSession,
        SurfaceModule,
        NavEntry;
import '../design/tokens.dart';
import '../design/components.dart';
import '../l10n/s.dart' show S;
import 'mv_page.dart' show MvPage, registerMvModule;

/// 进度条：拖动只改本地预览，松手才 seek（严禁 onChanged 里直接 seek）。
class _SeekSlider extends StatefulWidget {
  const _SeekSlider({required this.positionMs, required this.durationMs});

  final int positionMs;
  final int durationMs;

  @override
  State<_SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<_SeekSlider> {
  double? _preview;

  @override
  void didUpdateWidget(covariant _SeekSlider old) {
    super.didUpdateWidget(old);
    if (_preview == null) return;
    // 外部位置已追上预览值 → 交还真实进度。
    if ((widget.positionMs - (_preview ?? 0).round()).abs() < 900) {
      _preview = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.durationMs;
    final max = dur <= 0 ? 1.0 : dur.toDouble();
    final pos =
        _preview ?? widget.positionMs.toDouble().clamp(0, max).toDouble();
    return Slider(
      value: pos.clamp(0.0, max).toDouble(),
      max: max,
      activeColor: Sp.green,
      inactiveColor: Sp.divider,
      onChanged: dur <= 0 ? null : (v) => setState(() => _preview = v),
      onChangeEnd: dur <= 0
          ? null
          : (v) {
              setState(() => _preview = null);
              playbackSession().seek(v.round());
            },
    );
  }
}

/// 收藏按钮：审查修复（阶段A A1/A3/A5/A7 P0）——旧实现是纯本地
/// setState 假按钮，重启即丢、不落库、不请求。改为经 appGraph.collect
/// 读真实镜像态 + 调真 toggle，失败给可见反馈。
class FavoriteButton extends StatefulWidget {
  const FavoriteButton({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cur = PlaybackSession.instance.snapshot.player.current;
    final hash = cur?.hash ?? '';
    final collected =
        hash.isEmpty ? false : (appGraph.collect?.isCollected(hash) ?? false);
    return IconButton(
      onPressed: _busy ? null : () => _toggle(cur),
      icon: Icon(collected ? Icons.favorite : Icons.favorite_border),
      color: collected ? Sp.green : Sp.textSub,
      tooltip: collected ? '取消收藏' : '收藏',
    );
  }

  Future<void> _toggle(SongBrief? cur) async {
    final logic = appGraph.collect;
    if (logic == null || cur == null) {
      _msg(S.of(context).t('favoriteUnavailable'));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await logic.toggle(cur.hash, cur.mixSongId, song: cur);
      if (!mounted) return;
      if (r.needsLogin) {
        _msg(S.of(context).t('favoriteNeedLogin'));
      } else if (!r.ok) {
        _msg(S.of(context).t('favoriteFailed'));
      }
      setState(() {}); // 刷新 isCollected 真实态
      widget.onChanged?.call();
    } catch (e) {
      _msg('收藏失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

/// 播放页。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const List<double> _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  void _openSpeedSheet(double current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Sp.bgElevated,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const SpSectionHeader(title: '播放速度'),
            for (final s in _speeds)
              ListTile(
                title: Text(
                  '${s.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x',
                ),
                trailing: (s - current).abs() < 0.001
                    ? const Icon(Icons.check, color: Sp.green)
                    : null,
                onTap: () {
                  playbackSession().setSpeed(s);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openQualitySheet(String current) {
    final list = vipQualities();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Sp.bgElevated,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const SpSectionHeader(title: '音质'),
            for (final AudioQuality q in list)
              ListTile(
                title: Text(qualityParam(q)),
                trailing: qualityParam(q) == current
                    ? const Icon(Icons.check, color: Sp.green)
                    : null,
                onTap: () {
                  playbackSession().setQuality(qualityParam(q));
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Sp.bgElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.lyrics_outlined, color: Sp.textSub),
              title: const Text('歌词'),
              onTap: () {
                navState().requestTab('lyrics');
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.mode_comment_outlined,
                color: Sp.textSub,
              ),
              title: const Text('评论'),
              onTap: () {
                navState().requestTab('comment');
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.video_library_outlined,
                color: Sp.textSub,
              ),
              title: const Text('查看 MV'),
              onTap: () {
                Navigator.of(ctx).pop();
                registerMvModule();
                final current =
                    PlaybackSession.instance.snapshot.player.current;
                final aid = current?.albumAudioId ?? 0;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MvPage(albumAudioId: aid),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined, color: Sp.textSub),
              title: const Text('下载当前歌曲'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final cur = PlaybackSession.instance.snapshot.player.current;
                final mgr = appGraph.downloads;
                if (cur == null || mgr == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(S.of(context).t('downloadUnavailable'))),
                    );
                  }
                  return;
                }
                try {
                  final task = await mgr.enqueue(cur, '128');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          task == null
                              ? S.of(context).t('errorGeneric')
                              : S.of(context).t('downloadQueued'),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('下载失败：$e')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.radio_outlined, color: Sp.textSub),
              title: const Text('个人 FM'),
              onTap: () async {
                Navigator.of(ctx).pop();
                try {
                  final songs = await appGraph.fm?.start();
                  if (songs != null && songs.isNotEmpty) {
                    await PlaybackSession.instance.playAll(songs, 0);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('FM 暂无可用曲目（端点待实测）')),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('FM 启动失败：$e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = playbackSession();
    return Scaffold(
      backgroundColor: Sp.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: session,
          builder: (context, _) {
            final snap = session.snapshot;
            final song = snap.current;
            if (song == null) {
              return const SpStateView(
                icon: Icons.music_note,
                title: '暂无播放',
                subtitle: '播放队列为空',
              );
            }
            final art = Sp.artHero;
            final errText = snap.player.lastError.trim();
            return Column(
              children: <Widget>[
                _topBar(),
                if (errText.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                      horizontal: Sp.pagePad,
                      vertical: Sp.gapS,
                    ),
                    padding: const EdgeInsets.all(Sp.gapM),
                    decoration: BoxDecoration(
                      color: Sp.cardHigh,
                      borderRadius: BorderRadius.circular(Sp.rCard),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.error_outline, color: Sp.red, size: 20),
                        const SizedBox(width: Sp.gapS),
                        Expanded(
                          child: Text(
                            errText,
                            style: const TextStyle(
                              fontSize: Sp.fSub,
                              color: Sp.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Sp.pagePad,
                      vertical: Sp.gapM,
                    ),
                    children: <Widget>[
                      Center(
                        child: SpCover(
                          url: song.cover,
                          size: art,
                          radius: Sp.rXL,
                        ),
                      ),
                      const SizedBox(height: Sp.gapXL),
                      Text(
                        song.name.isEmpty ? song.hash : song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: Sp.fPageTitle,
                          fontWeight: FontWeight.w700,
                          color: Sp.text,
                        ),
                      ),
                      const SizedBox(height: Sp.gapS),
                      Text(
                        song.singer.isEmpty ? '未知歌手' : song.singer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: Sp.fItem,
                          color: Sp.textSub,
                        ),
                      ),
                      if (snap.player.sourceKind == 'mv-audio') ...<Widget>[
                        const SizedBox(height: Sp.gapS),
                        const Text(
                          '试听音源',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: Sp.fTiny,
                            color: Sp.textFaint,
                          ),
                        ),
                      ],
                      const SizedBox(height: Sp.gapXL),
                      _SeekSlider(
                        positionMs: snap.player.positionMs,
                        durationMs: snap.player.durationMs,
                      ),
                      _timeRow(snap.player.positionMs, snap.player.durationMs),
                      const SizedBox(height: Sp.gapM),
                      _controls(snap.mode),
                      const SizedBox(height: Sp.gapL),
                      _badges(snap.speed),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Sp.gapM, vertical: Sp.gapS),
    child: Row(
      children: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.keyboard_arrow_down, size: 28),
          color: Sp.text,
          tooltip: '收起',
        ),
        const Spacer(),
        const FavoriteButton(),
        IconButton(
          onPressed: _openMenu,
          icon: const Icon(Icons.more_vert),
          color: Sp.text,
          tooltip: '更多',
        ),
      ],
    ),
  );

  Widget _timeRow(int posMs, int durMs) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      Text(_fmt(posMs), style: _timeStyle),
      Text(_fmt(durMs), style: _timeStyle),
    ],
  );

  static final TextStyle _timeStyle = const TextStyle(
    fontSize: Sp.fTiny,
    color: Sp.textFaint,
  );

  Widget _controls(PlayMode mode) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      SpRoundButton(
        icon: Icons.shuffle,
        active: mode == PlayMode.shuffle,
        tooltip: '随机',
        onTap: () {
          final s = playbackSession();
          s.setMode(
            mode == PlayMode.shuffle ? PlayMode.sequence : PlayMode.shuffle,
          );
        },
      ),
      SpRoundButton(
        icon: Icons.skip_previous,
        tooltip: '上一首',
        onTap: () => playbackSession().prev(),
      ),
      SpPlayButton(
        playing: playbackSession().snapshot.player.isPlaying,
        onTap: () => playbackSession().toggle(),
      ),
      SpRoundButton(
        icon: Icons.skip_next,
        tooltip: '下一首',
        onTap: () => playbackSession().next(),
      ),
      SpRoundButton(
        icon: Icons.repeat,
        active: mode == PlayMode.loopOne,
        tooltip: '循环',
        onTap: () {
          final s = playbackSession();
          s.setMode(
            mode == PlayMode.loopOne ? PlayMode.sequence : PlayMode.loopOne,
          );
        },
      ),
    ],
  );

  Widget _badges(double speed) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      ActionChip(
        avatar: const Icon(Icons.speed, size: 16, color: Sp.textSub),
        label: Text('${speed.toStringAsFixed(2)}x'),
        onPressed: () => _openSpeedSheet(speed),
      ),
      const SizedBox(width: Sp.gapM),
      ActionChip(
        avatar: const Icon(Icons.graphic_eq, size: 16, color: Sp.textSub),
        label: const Text('音质'),
        onPressed: () => _openQualitySheet('128'),
      ),
    ],
  );

  static String _fmt(int ms) {
    if (ms <= 0) return '00:00';
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// 播放页模块（不进底部导航）。
class PlayerPageModule extends SurfaceModule {
  @override
  String get id => 'player';

  @override
  String get route => '/player';

  @override
  NavEntry? get navEntry => null;

  @override
  WidgetBuilder? get builder =>
      (_) => const PlayerPage();
}
