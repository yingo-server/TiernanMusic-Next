// L7 surface/pages · 播放页（官方 M3 控件 + 语义 token）
//
// 契约：只用官方 Material 3 控件；不手写控件类（页面容器除外）；
// 颜色只来自 design/tokens_v2.dart 语义 token；数据只经 PlaybackSession 快照。
// 进度条：官方 Slider + 本地预览值，拖动只改预览，松手才 seek。
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
import '../design/tokens_v2.dart';
import '../design/layout.dart' show TnBreakpoint, TnRadius, TnSize, TnSpace;
import '../l10n/s.dart' show S;
import 'mv_page.dart' show MvPage, registerMvModule;

/// 播放页。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const List<double> _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// 拖动进度条时的本地预览值（ms）；非 null 期间 Slider 只显示预览，松手才 seek。
  double? _seekPreview;

  /// 收藏请求在途，防重复点击。
  bool _favBusy = false;

  // ── 底部弹层（官方 showModalBottomSheet + ListTile）────────────────

  void _openSpeedSheet(double current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cs.surfaceContainerLow,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(TnSpace.lg),
              child: Text('倍速', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final s in _speeds)
              ListTile(
                title: Text(
                  '${s.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x',
                ),
                trailing: (s - current).abs() < 0.001
                    ? Icon(Icons.check, color: ctx.cs.primary)
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
      backgroundColor: context.cs.surfaceContainerLow,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(TnSpace.lg),
              child: Text('音质', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final AudioQuality q in list)
              ListTile(
                title: Text(qualityParam(q)),
                trailing: qualityParam(q) == current
                    ? Icon(Icons.check, color: ctx.cs.primary)
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
      backgroundColor: context.cs.surfaceContainerLow,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.lyrics_outlined),
              title: const Text('歌词'),
              onTap: () {
                navState().requestTab('lyrics');
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.mode_comment_outlined),
              title: const Text('评论'),
              onTap: () {
                navState().requestTab('comment');
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
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
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载当前歌曲'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final cur = PlaybackSession.instance.snapshot.player.current;
                final mgr = appGraph.downloads;
                if (cur == null || mgr == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(S.of(context).t('downloadUnavailable')),
                      ),
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
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('下载失败，请稍后重试')));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.radio_outlined),
              title: const Text('个人 FM'),
              onTap: () async {
                Navigator.of(ctx).pop();
                try {
                  final songs = await appGraph.fm?.start();
                  if (songs != null && songs.isNotEmpty) {
                    await PlaybackSession.instance.playAll(songs, 0);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('FM 暂无可用曲目')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('FM 启动失败，请重试')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── 收藏（内联官方 IconButton，逻辑经 appGraph.collect 读写真实镜像）──

  Widget _favoriteButton(SongBrief? cur) {
    final hash = cur?.hash ?? '';
    final collected =
        hash.isNotEmpty && (appGraph.collect?.isCollected(hash) ?? false);
    return IconButton(
      onPressed: _favBusy ? null : () => _toggleFavorite(cur),
      icon: Icon(collected ? Icons.favorite : Icons.favorite_border),
      color: collected ? context.cs.primary : context.cs.onSurfaceVariant,
      tooltip: collected ? '取消收藏' : '收藏',
    );
  }

  Future<void> _toggleFavorite(SongBrief? cur) async {
    final logic = appGraph.collect;
    if (logic == null || cur == null) {
      _msg(S.of(context).t('favoriteUnavailable'));
      return;
    }
    setState(() => _favBusy = true);
    try {
      final r = await logic.toggle(cur.hash, cur.mixSongId, song: cur);
      if (!mounted) return;
      if (r.needsLogin) {
        _msg(S.of(context).t('favoriteNeedLogin'));
      } else if (!r.ok) {
        _msg(S.of(context).t('favoriteFailed'));
      }
      setState(() {}); // 刷新 isCollected 真实态
    } catch (e) {
      _msg('收藏失败，请重试');
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  // ── build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = playbackSession();
    return Scaffold(
      backgroundColor: context.cs.surface,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: session,
          builder: (BuildContext context, _) {
            final snap = session.snapshot;
            final song = snap.current;
            if (song == null) {
              return _stateView(Icons.music_note, '暂无播放', '播放队列为空');
            }
            final errText = snap.player.lastError.trim();
            final errCode = snap.player.lastErrorCode;
            final s = S.of(context);
            // 按结构化码取 i18n 文案（跨语言正确），无码时用 L6 兜底文案。
            final shownErr = switch (errCode) {
              'needsVerification' => s.t('needVerifyBody'),
              'noPrivilege' => s.t('needVip'),
              'notFound' => s.t('noPlayable'),
              'network' => s.t('errorNetwork'),
              _ => errText,
            };
            final canRetry =
                errCode == 'needsVerification' || errCode == 'network';
            return Column(
              children: <Widget>[
                _topBar(song),
                if (errText.isNotEmpty)
                  _errorBar(
                    shownErr,
                    canRetry
                        ? () {
                            final cur = snap.current;
                            if (cur != null) {
                              playbackSession().playAll(<SongBrief>[cur], 0);
                            }
                          }
                        : null,
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TnSpace.lg,
                      vertical: TnSpace.md,
                    ),
                    children: <Widget>[
                      Center(child: _cover(song.cover)),
                      const SizedBox(height: TnSpace.xl),
                      Text(
                        song.name.isEmpty ? song.hash : song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: TnSpace.sm),
                      Text(
                        song.singer.isEmpty ? '未知歌手' : song.singer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (snap.player.sourceKind == 'mv-audio') ...<Widget>[
                        const SizedBox(height: TnSpace.sm),
                        Text(
                          '试听音源',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                      const SizedBox(height: TnSpace.xl),
                      _seekSlider(
                        snap.player.positionMs,
                        snap.player.durationMs,
                      ),
                      _timeRow(snap.player.positionMs, snap.player.durationMs),
                      const SizedBox(height: TnSpace.md),
                      _controls(snap.mode),
                      const SizedBox(height: TnSpace.lg),
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

  /// 封面（ClipRRect + Image.network，占位取 surfaceContainerHigh）。
  Widget _cover(String url) {
    const double size = 280;
    final placeholder = Container(
      width: size,
      height: size,
      color: context.cs.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.music_note, size: size * 0.4),
    );
    final u = url.trim();
    if (u.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(TnRadius.lg),
        child: placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(TnRadius.lg),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, Widget child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }

  /// 空态（官方 Icon + Text）。
  Widget _stateView(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(TnSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 40, color: context.cs.onSurfaceVariant),
          const SizedBox(height: TnSpace.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: TnSpace.sm),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  /// 错误条（官方 Card + ListTile；验证/网络错误给"重试"出口）。
  Widget _errorBar(String message, VoidCallback? onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TnSpace.lg, vertical: TnSpace.sm),
      child: Card(
        color: context.cs.surfaceContainerHigh,
        child: ListTile(
          leading: Icon(Icons.error_outline, color: context.cs.error, size: 20),
          title: Text(
            message,
            style: TextStyle(fontSize: 12, color: context.cs.onSurface),
          ),
          trailing: onRetry != null
              ? TextButton(
                  onPressed: onRetry,
                  child: Text(S.of(context).t('retryPlay')),
                )
              : null,
        ),
      ),
    );
  }

  Widget _topBar(SongBrief? cur) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: TnSpace.md, vertical: TnSpace.sm),
    child: Row(
      children: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.keyboard_arrow_down, size: 28),
          tooltip: '收起',
        ),
        const Spacer(),
        _favoriteButton(cur),
        IconButton(
          onPressed: _openMenu,
          icon: const Icon(Icons.more_vert),
          tooltip: '更多',
        ),
      ],
    ),
  );

  /// 官方 Slider：拖动只改本地预览，松手才 seek。
  Widget _seekSlider(int positionMs, int durationMs) {
    // 外部位置已追上预览值（误差 < 900ms）→ 交还真实进度（对齐旧 _SeekSlider）。
    if (_seekPreview != null &&
        (positionMs - _seekPreview!.round()).abs() < 900) {
      _seekPreview = null;
    }
    final max = durationMs <= 0 ? 1.0 : durationMs.toDouble();
    final pos = _seekPreview ?? positionMs.toDouble().clamp(0.0, max);
    return Slider(
      value: pos.clamp(0.0, max),
      max: max,
      onChanged: durationMs <= 0
          ? null
          : (v) => setState(() => _seekPreview = v),
      onChangeEnd: durationMs <= 0
          ? null
          : (v) {
              setState(() => _seekPreview = null);
              playbackSession().seek(v.round());
            },
    );
  }

  Widget _timeRow(int posMs, int durMs) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      Text(_fmt(posMs), style: Theme.of(context).textTheme.labelSmall),
      Text(_fmt(durMs), style: Theme.of(context).textTheme.labelSmall),
    ],
  );

  Widget _controls(PlayMode mode) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      IconButton(
        onPressed: () {
          final s = playbackSession();
          s.setMode(
            mode == PlayMode.shuffle ? PlayMode.sequence : PlayMode.shuffle,
          );
        },
        icon: const Icon(Icons.shuffle),
        color: mode == PlayMode.shuffle ? context.cs.primary : null,
        tooltip: '随机',
      ),
      IconButton(
        onPressed: () => playbackSession().prev(),
        icon: const Icon(Icons.skip_previous),
        tooltip: '上一首',
      ),
      IconButton.filled(
        onPressed: () => playbackSession().toggle(),
        icon: Icon(
          playbackSession().snapshot.player.isPlaying
              ? Icons.pause
              : Icons.play_arrow,
        ),
        tooltip: '播放/暂停',
      ),
      IconButton(
        onPressed: () => playbackSession().next(),
        icon: const Icon(Icons.skip_next),
        tooltip: '下一首',
      ),
      IconButton(
        onPressed: () {
          final s = playbackSession();
          s.setMode(
            mode == PlayMode.loopOne ? PlayMode.sequence : PlayMode.loopOne,
          );
        },
        icon: const Icon(Icons.repeat),
        color: mode == PlayMode.loopOne ? context.cs.primary : null,
        tooltip: '循环',
      ),
    ],
  );

  Widget _badges(double speed) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      ActionChip(
        avatar: const Icon(Icons.speed, size: 16),
        label: Text('${speed.toStringAsFixed(2)}x'),
        onPressed: () => _openSpeedSheet(speed),
      ),
      const SizedBox(width: TnSpace.md),
      ActionChip(
        avatar: const Icon(Icons.graphic_eq, size: 16),
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
