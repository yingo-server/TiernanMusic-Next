// L5 logic/lyrics · 歌词解析器（纯函数零 IO）
// 支持：LRC（[mm:ss.xx] 多时间标签）、KRC 逐字时间轴、[offset:ms] 偏移、容错跳过。
// 铁律：禁 surface/flutter/IO；每公开函数 try/catch + Log('lyrics.parser')。
import '../../kernel/kernel.dart' show Log;

const String _tag = 'lyrics.parser';

/// LRC/KRC 单行歌词。
class LrcLine {
  const LrcLine({this.timeMs = 0, this.text = ''});
  final int timeMs;
  final String text;

  @override
  String toString() => 'LrcLine(${timeMs}ms, $text)';
}

/// KRC 逐字单词时间轴。
class KrcWord {
  const KrcWord({this.startMs = 0, this.durMs = 0, this.word = ''});
  final int startMs; // 行起始 + 词内偏移（绝对毫秒）
  final int durMs;
  final String word;

  @override
  String toString() => 'KrcWord(${startMs}ms+${durMs}ms $word)';
}

/// 解析结果：行级时间轴 + 逐字时间轴（按行索引分组）+ offset。
class LyricParseResult {
  const LyricParseResult({
    this.lines = const <LrcLine>[],
    this.wordsByLine = const <int, List<KrcWord>>{},
    this.offsetMs = 0,
    this.isKrc = false,
  });
  final List<LrcLine> lines;
  final Map<int, List<KrcWord>> wordsByLine; // key = lines 下标
  final int offsetMs; // [offset:ms]，正值表示整体前移（播放时间需减去）
  final bool isKrc;

  bool get isEmpty => lines.isEmpty;

  @override
  String toString() =>
      'LyricParseResult(lines=${lines.length}, wordsLines=${wordsByLine.length}, '
      'offset=$offsetMs, krc=$isKrc)';
}

final RegExp _timeTagRe =
    RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final RegExp _offsetTagRe = RegExp(r'^\[offset:\s*(-?\d+)\s*\]$', caseSensitive: false);
final RegExp _krcHeaderRe = RegExp(r'^\[(\d+),(\d+)\]');
final RegExp _krcWordRe = RegExp(r'<(\d+),(\d+),\d+>([^<]*)');

int _fracToMs(String? frac) {
  if (frac == null || frac.isEmpty) return 0;
  // 2 位=百分秒；3 位=毫秒；其余按位数补齐。
  final digits = frac.length >= 3 ? frac : frac.padRight(3, '0');
  return int.tryParse(digits) ?? 0;
}

/// 解析 [mm:ss.xx] 多时间标签行 → (timeMs, text) 列表；非规整行返回空。
List<MapEntry<int, String>> _extractTimeTags(String line) {
  final out = <MapEntry<int, String>>[];
  try {
    final matches = _timeTagRe.allMatches(line).toList(growable: false);
    if (matches.isEmpty || matches.first.start != 0) return out;
    int end = 0;
    for (final m in matches) {
      if (m.start != end) break; // 标签必须连续开头
      final ms = int.parse(m.group(1)!) * 60000 +
          int.parse(m.group(2)!) * 1000 +
          _fracToMs(m.group(3));
      out.add(MapEntry(ms, ''));
      end = m.end;
    }
    if (out.isEmpty) return out;
    final text = end >= line.length ? '' : line.substring(end).trim();
    return out.map((e) => MapEntry(e.key, text)).toList(growable: false);
  } catch (e, st) {
    Log.e(_tag, '_extractTimeTags failed: $line', e, st);
    return const <MapEntry<int, String>>[];
  }
}

/// 解析 KRC 逐字时间轴行：[start,dur]<t,d>(word)… → (startMs, words)。
MapEntry<int, List<KrcWord>>? _parseKrcLine(String line) {
  try {
    final head = _krcHeaderRe.firstMatch(line);
    if (head == null) return null;
    final start = int.tryParse(head.group(1)!) ?? 0;
    final dur = int.tryParse(head.group(2)!) ?? 0;
    final words = <KrcWord>[];
    for (final m in _krcWordRe.allMatches(line)) {
      final off = int.tryParse(m.group(1)!) ?? 0;
      final wd = int.tryParse(m.group(2)!) ?? 0;
      final w = m.group(3) ?? '';
      if (w.isEmpty) continue;
      words.add(KrcWord(startMs: start + off, durMs: wd, word: w));
    }
    return MapEntry(start, words);
  } catch (e, st) {
    Log.e(_tag, '_parseKrcLine failed: $line', e, st);
    return null;
  }
}

/// KRC 行转 LRC 行文本（拼接逐字 word）。
String _krcText(List<KrcWord> words) {
  try {
    return words.map((w) => w.word).join();
  } catch (e, st) {
    Log.e(_tag, '_krcText failed', e, st);
    return '';
  }
}

/// 主入口：自动识别 KRC / LRC。纯函数，无 IO。
LyricParseResult parseLyrics(String content) {
  try {
    if (content.trim().isEmpty) return const LyricParseResult();
    var offsetMs = 0;
    final lrcLines = <LrcLine>[];
    final wordsByLine = <int, List<KrcWord>>{};
    var isKrc = false;

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      // offset 标签（独立行）。
      final om = _offsetTagRe.firstMatch(line);
      if (om != null) {
        offsetMs = int.tryParse(om.group(1)!) ?? 0;
        continue;
      }

      // KRC 行。
      final krc = _parseKrcLine(line);
      if (krc != null) {
        isKrc = true;
        final idx = lrcLines.length;
        lrcLines.add(LrcLine(timeMs: krc.key, text: _krcText(krc.value)));
        if (krc.value.isNotEmpty) wordsByLine[idx] = krc.value;
        continue;
      }

      // LRC 行（多时间标签）。
      for (final e in _extractTimeTags(line)) {
        lrcLines.add(LrcLine(timeMs: e.key, text: e.value));
      }
    }
    // 排序（KRC 已序，LRC 多标签展开后需排序）。
    lrcLines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final r = LyricParseResult(
      lines: lrcLines,
      wordsByLine: wordsByLine,
      offsetMs: offsetMs,
      isKrc: isKrc,
    );
    Log.d(_tag, 'parseLyrics lines=${lrcLines.length} krc=$isKrc offset=$offsetMs');
    return r;
  } catch (e, st) {
    Log.e(_tag, 'parseLyrics failed', e, st);
    return const LyricParseResult();
  }
}

/// 应用 offset：返回新结果（offsetMs>0 表示歌词整体提前，播放时间 t 对应行时间 t-offset）。
/// 纯函数；结果行时间统一加 offsetMs（负值同理），offset 归零。
LyricParseResult applyOffset(LyricParseResult r) {
  try {
    if (r.offsetMs == 0) return r;
    final d = -r.offsetMs; // 正 offset → 时间前移
    final lines = r.lines
        .map((l) => LrcLine(timeMs: l.timeMs + d, text: l.text))
        .toList(growable: false);
    final words = <int, List<KrcWord>>{};
    r.wordsByLine.forEach((k, v) {
      words[k] = v
          .map((w) => KrcWord(startMs: w.startMs + d, durMs: w.durMs, word: w.word))
          .toList(growable: false);
    });
    Log.d(_tag, 'applyOffset ${r.offsetMs}ms');
    return LyricParseResult(
      lines: lines, wordsByLine: words, offsetMs: 0, isKrc: r.isKrc);
  } catch (e, st) {
    Log.e(_tag, 'applyOffset failed', e, st);
    return r;
  }
}

/// 二分查找当前播放毫秒对应的行下标（-1 表示未开始）。
int findLineIndex(LyricParseResult r, int positionMs) {
  try {
    var lo = 0, hi = r.lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (r.lines[mid].timeMs <= positionMs) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  } catch (e, st) {
    Log.e(_tag, 'findLineIndex failed pos=$positionMs', e, st);
    return -1;
  }
}
