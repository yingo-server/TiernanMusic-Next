// L6 surface/pages · 歌词页模块（buildLyricsPageModule）
// 由 modules.dart（批4-B）汇总注册：SurfaceRegistry.install(buildLyricsPageModule(...))。
// 嵌入播放页第二页签或独立路由；行级高亮 + 居中滚动（TnMotion.normal）+ KRC 逐字高亮。
// positionMs 来源：注入 positionMsProvider（批4-B PlayerController 提供，本文件只定义接口）。
// 铁律：只 import flutter/miuix/riverpod/bridge_logic/bridge_core/本层；try/catch + Log('surface.lyrics')。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show LyricsLogic, parseLyrics, applyOffset, findLineIndex, LyricParseResult, LrcLine, KrcWord, Log, TranslationLogic, DisplayLine, LogicFacade;
import '../../bridges/bridge_core.dart' show SongBrief, LyricsDisplayMode;
import '../registry.dart';
import '../theme/tn_theme.dart';

const String _tag = 'surface.lyrics';

/// 歌词页依赖：全部经工厂注入。
class LyricsDeps {
  const LyricsDeps({
    required this.lyrics,
    required this.currentSong,
    required this.positionMsProvider,
    this.translation,
  });

  /// 歌词域逻辑（三级缓存加载 + 解析）。
  final LyricsLogic lyrics;

  /// 翻译显示门面（可选；为空时只显示原文，不臆造译文）。
  final TranslationLogic? translation;

  /// 当前歌曲提供者（null = 无播放）。返回 SongBrief 供 lyricsFor 拉歌词。
  final SongBrief? Function() currentSong;

  /// 当前播放进度毫秒（批4-B PlayerController 提供；可高频轮询/流式）。
  final int Function() positionMsProvider;
}

/// 歌词页模块：id='lyrics'，无 navEntry（嵌入播放页）。
class LyricsPageModule extends SurfaceModule {
  LyricsPageModule({required this.deps});

  final LyricsDeps deps;

  @override
  String get id => 'lyrics';

  @override
  String get route => '/lyrics';

  @override
  bool enabled(LogicFacade logic) => true;

  @override
  WidgetBuilder builder(LogicFacade logic) => (_) => LyricsPage(deps: deps);
}

class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key, required this.deps});

  final LyricsDeps deps;

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  LyricParseResult _parsed = const LyricParseResult();
  LyricsDisplayMode _displayMode = LyricsDisplayMode.original;
  List<DisplayLine> _displayLines = const <DisplayLine>[];
  bool _loading = false;
  String _loadedHash = '';
  int _lastLine = -2;
  Timer? _ticker;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLyrics();
    // 200ms 轮询 positionMs：够顺滑且不重负载；PlayerController 流可用后可换订阅。
    // 自定义时长说明：轮询频率非动效时长，不属 TnMotion 三档，保留裸值。
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      try {
        final pos = widget.deps.positionMsProvider();
        _syncScroll(pos);
      } catch (e, st) {
        Log.e(_tag, 'tick positionMsProvider failed', e, st);
      }
    });
  }

  @override
  void didUpdateWidget(covariant LyricsPage old) {
    super.didUpdateWidget(old);
    final s = widget.deps.currentSong();
    if (s != null && s.hash.trim().toLowerCase() != _loadedHash) {
      _loadLyrics();
    }
  }

  Future<void> _loadLyrics() async {
    final song = widget.deps.currentSong();
    if (song == null) return;
    final hash = song.hash.trim().toLowerCase();
    if (hash == _loadedHash || _loading) return;
    _loading = true;
    try {
      final r = await widget.deps.lyrics.lyricsFor(song);
      if (!mounted) return;
      setState(() {
        _parsed = widget.deps.lyrics.parsedFor(r);
        _displayLines = widget.deps.translation
                ?.displayFor(r, _displayMode) ??
            const <DisplayLine>[];
        _loadedHash = hash;
        _lastLine = -2;
      });
      Log.d(_tag, 'lyrics loaded hash=$hash lines=${_parsed.lines.length}');
    } catch (e, st) {
      Log.e(_tag, 'loadLyrics failed hash=$hash', e, st);
      if (mounted) {
        setState(() {
          _parsed = const LyricParseResult();
          _loadedHash = hash;
        });
      }
    } finally {
      _loading = false;
    }
  }

  /// positionMs → 高亮行 + 居中滚动动画（仅换行时触发，TnMotion.normal）。
  void _syncScroll(int positionMs) {
    try {
      if (_parsed.isEmpty) return;
      final idx = findLineIndex(_parsed, positionMs);
      if (idx == _lastLine) return;
      _lastLine = idx;
      setState(() {}); // 触发高亮重建
      if (idx < 0 || !_scroll.hasClients) return;
      const itemH = 48.0;
      final vp = _scroll.position.viewportDimension;
      final target = (idx * itemH - vp / 2 + itemH / 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target,
          duration: TnMotion.normal, curve: TnMotion.curve);
    } catch (e, st) {
      Log.e(_tag, 'syncScroll failed pos=$positionMs', e, st);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_parsed.isEmpty) {
      return Center(
        child: Text(
          _loading ? '歌词加载中…' : (_loadedHash.isEmpty ? '未在播放' : '暂无歌词'),
          style: TnText.of(context).aux,
        ),
      );
    }
    final pos = _currentPos();
    final cur = findLineIndex(_parsed, pos);
    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final m in LyricsDisplayMode.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(switch (m) {
                  LyricsDisplayMode.original => '原文',
                  LyricsDisplayMode.bilingual => '双语',
                  LyricsDisplayMode.translation => '译文',
                }),
                selected: _displayMode == m,
                onSelected: (_) => _setMode(m),
              ),
            ),
        ],
      ),
    );
    return Column(children: [
      chips,
      Expanded(
        child: ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 24),
      itemCount: _parsed.lines.length,
      itemBuilder: (context, i) {
        final line = _parsed.lines[i];
        final display = i < _displayLines.length
            ? _displayLines[i]
            : const DisplayLine(main: '');
        final main = display.main.isNotEmpty ? display.main : line.text;
        final sub = display.sub;
        final active = i == cur;
        final words = _parsed.wordsByLine[i];
        return SizedBox(
          height: 48,
          child: Center(
            child: DefaultTextStyle(
              style: TnText.of(context).body.copyWith(
                    fontSize: active ? 18 : 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                  ),
              child: (active && words != null && words.isNotEmpty)
                  ? _KrcLine(words: words, positionMs: pos)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(main,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (sub.isNotEmpty)
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TnText.of(context).aux),
                      ],
                    ),
            ),
          ),
        );
      },
        ),
      ),
    ]);
  }

  void _setMode(LyricsDisplayMode m) {
    try {
      if (_displayMode == m) return;
      setState(() => _displayMode = m);
      // 用缓存的 LyricResult 重算显示行（无需重新拉网络）。
      final song = widget.deps.currentSong();
      if (song != null) {
        widget.deps.lyrics.lyricsFor(song).then((r) {
          if (!mounted) return;
          setState(() => _displayLines =
              widget.deps.translation?.displayFor(r, m) ??
                  const <DisplayLine>[]);
        }).catchError((Object e) {
          Log.w(_tag, 'displayFor failed: $e');
        });
      }
    } catch (e, st) {
      Log.e(_tag, 'setMode failed', e, st);
    }
  }

  int _currentPos() {
    try {
      return widget.deps.positionMsProvider();
    } catch (e, st) {
      Log.e(_tag, 'positionMsProvider failed', e, st);
      return 0;
    }
  }
}

/// KRC 逐字高亮行：按 positionMs 判定每词进度（进行中词按比例填充）。
class _KrcLine extends StatelessWidget {
  const _KrcLine({required this.words, required this.positionMs});

  final List<KrcWord> words;
  final int positionMs;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final done = base.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700);
    final undone =
        base.copyWith(color: base.color?.withValues(alpha: 0.85));
    final spans = <TextSpan>[];
    for (final w in words) {
      try {
        final end = w.startMs + w.durMs;
        if (positionMs >= end) {
          spans.add(TextSpan(text: w.word, style: done));
        } else if (positionMs <= w.startMs) {
          spans.add(TextSpan(text: w.word, style: undone));
        } else {
          // 进行中：本帧按词内比例混色（简化为半程切换，避免 ShaderMask 开销）。
          final ratio = (positionMs - w.startMs) / (w.durMs == 0 ? 1 : w.durMs);
          spans.add(TextSpan(
              text: w.word, style: ratio >= 0.5 ? done : undone));
        }
      } catch (e, st) {
        Log.e(_tag, 'krc word render failed', e, st);
        spans.add(TextSpan(text: w.word, style: undone));
      }
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(children: spans),
    );
  }
}
