// L7 surface/pages · 歌词页（官方 M3 控件 + 语义 token）
// 数据经桥：LyricsLogic（bridge_logic）、LyricResult/LyricsDisplayMode（bridge_core）。
// 性能：定时轮询播放位置（200ms）→ 只更新「当前行索引」ValueNotifier，
// 列表项用 ValueListenableBuilder 局部重绘，避免整页每帧 rebuild。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show LyricResult, LyricsDisplayMode;
import '../../bridges/bridge_logic.dart'
    show LyricsLogic, TranslationLogic, DisplayLine, LrcLine;
import '../../bridges/bridge_session.dart'
    show playbackSession, SurfaceModule, NavEntry;
// GAP(跨桥)：逻辑单例随 AppGraph 暴露，bridge_session 暂未导出实例出口。
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens_v2.dart';

/// 一行歌词（原文 + 可选译文）。
class _LyricRow {
  const _LyricRow(this.timeMs, this.main, this.sub);

  final int timeMs;
  final String main;
  final String sub;
}

/// 歌词页。
class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final ValueNotifier<int> _active = ValueNotifier<int>(-1);
  final ScrollController _scroll = ScrollController();

  Timer? _timer;
  String _hash = '';
  bool _loading = true;
  bool _error = false;
  bool _bilingual = false;
  bool _hasTranslation = false;
  List<_LyricRow> _rows = const <_LyricRow>[];
  LyricsLogic? _lyrics;
  TranslationLogic? _translation;

  @override
  void initState() {
    super.initState();
    _lyrics = appGraph.lyrics;
    _translation = appGraph.translation;
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _active.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final song = playbackSession().snapshot.current;
    if (song == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rows = const <_LyricRow>[];
      });
      return;
    }
    if (song.hash == _hash && _rows.isNotEmpty) return;
    _hash = song.hash;
    final logic = _lyrics;
    if (logic == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final LyricResult result = await logic.lyricsFor(song);
      final parsed = logic.parsedFor(result);
      final List<LrcLine> lines = parsed.lines;
      var rows = <_LyricRow>[];
      if (lines.isNotEmpty) {
        final trans = _translation;
        List<DisplayLine> display = const <DisplayLine>[];
        if (trans != null) {
          display = trans.displayFor(
            result,
            LyricsDisplayMode.bilingual,
            songHash: song.hash,
          );
        }
        var has = false;
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          var sub = '';
          if (i < display.length) {
            sub = display[i].sub;
            if (sub.isNotEmpty) has = true;
          }
          rows.add(_LyricRow(l.timeMs, l.text, sub));
        }
        _hasTranslation = has;
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = false;
      });
      _active.value = -1;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// 轮询：只推进「当前行」，变化时才滚动。
  void _tick() {
    final snap = playbackSession().snapshot;
    final song = snap.current;
    if (song == null || _rows.isEmpty) return;
    if (song.hash != _hash) {
      _load();
      return;
    }
    final pos = snap.player.positionMs;
    var idx = -1;
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].timeMs <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx == _active.value) return;
    _active.value = idx;
    _scrollTo(idx);
  }

  void _scrollTo(int idx) {
    if (idx < 0 || !_scroll.hasClients) return;
    // 逐行高度近似 44px，居中偏移半屏。
    final target = (idx * 44.0 - 160.0)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cs.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _topBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          tooltip: '返回',
        ),
        const Spacer(),
        // 无译文数据时只显示原文（翻译开关禁用）。
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text('原文')),
            ButtonSegment<bool>(value: true, label: Text('翻译')),
          ],
          selected: <bool>{_bilingual},
          onSelectionChanged: _hasTranslation
              ? (s) => setState(() => _bilingual = s.first)
              : null,
        ),
      ],
    ),
  );

  Widget _body() {
    if (_loading) {
      return _skeleton();
    }
    if (_error) {
      return _stateView(Icons.lyrics_outlined, '歌词加载失败', '稍后重试或切歌再试');
    }
    if (_rows.isEmpty) {
      return _stateView(Icons.lyrics_outlined, '暂无歌词', '这首歌没有可用的歌词数据');
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: _rows.length,
      itemBuilder: (BuildContext context, int i) {
        final r = _rows[i];
        return ValueListenableBuilder<int>(
          valueListenable: _active,
          builder: (BuildContext context, int active, _) {
            final on = active == i;
            final showSub = _bilingual && r.sub.isNotEmpty;
            final mainColor = on
                ? context.cs.primary
                : context.cs.onSurfaceVariant;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    r.main,
                    style: TextStyle(
                      fontSize: on ? 16 : 14,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                      color: mainColor,
                    ),
                  ),
                  if (showSub) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      r.sub,
                      style: TextStyle(
                        fontSize: on ? 14 : 12,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: mainColor,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 加载骨架（官方 Card + LinearProgressIndicator）。
  Widget _skeleton() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      children: <Widget>[
        for (int i = 0; i < 8; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 44,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: context.cs.primary,
                      backgroundColor: context.cs.surfaceContainerHigh,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  /// 三态（官方 Icon + Text + FilledButton）。
  Widget _stateView(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 40, color: context.cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

/// 歌词模块（不进底部导航）。
class LyricsPageModule extends SurfaceModule {
  @override
  String get id => 'lyrics';

  @override
  String get route => '/lyrics';

  @override
  NavEntry? get navEntry => null;

  @override
  WidgetBuilder? get builder =>
      (_) => const LyricsPage();
}
