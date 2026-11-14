// L5 logic/lyrics · 翻译歌词显示门面（功能对齐批2 收尾，主会话装配补齐）
// 契约：译文端点未实测（fetchTranslation 恒返回空），displayFor 只按本地
// 对齐契约渲染原文/双语/译文三模式；条数不等绝不臆造译文（alignTranslation
// 已保证）。零 UI、零网络直连；每方法 try/catch+Log('logic.translation')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show LruCache, LyricResult, LyricsDisplayMode, TranslatedLine, alignTranslation, buildKey, extractOriginalLines, extractEmbeddedTranslatedLines;

const String _tag = 'logic.translation';

/// 一行可渲染歌词：主文案 + 可选副文案（双语时的译文）。
class DisplayLine {
  const DisplayLine({required this.main, this.sub = '', this.lineIndex = 0});
  final String main;
  final String sub;
  final int lineIndex;
}

/// 翻译显示门面。
class TranslationLogic {
  TranslationLogic({LruCache<String, List<DisplayLine>>? cache})
      : _cache = cache ??
            LruCache<String, List<DisplayLine>>(capacity: 32);

  final LruCache<String, List<DisplayLine>> _cache;

  /// 按模式生成可渲染行。译文缺失时 bilingual/translation 自动退化为原文
  /// 并 Log.w 留痕（不静默假装已翻译）。
  /// translatedLines 可选：未提供时经 bridge_core 调 fetchTranslationFromContent
  /// 从 LyricResult.content 抽本地 KRC 内嵌翻译轨（不联网、不臆造 API）。
  List<DisplayLine> displayFor(
    LyricResult lyric,
    LyricsDisplayMode mode, {
    List<String>? translatedLines,
    String songHash = '',
  }) {
    try {
      List<String>? local = translatedLines;
      if (local == null) {
        try {
          // 未显式传入译文时，从 LyricResult.content 抽本地 KRC 内嵌翻译轨
          //（不联网；上游无独立翻译端点，见 ENDPOINT_TRUTH.md §6）。
          final trans = extractEmbeddedTranslatedLines(lyric);
          local = trans.isEmpty
              ? null
              : List<String>.unmodifiable(trans);
        } catch (e, st) {
          Log.w(_tag, 'local translation track extract failed: $e');
          local = null;
        }
      }
      // 审查修复：文件缓存路径 lyric.id 恒 0（candidates id 未持久化），
      // 旧键跨歌碰撞（同 mode 同译文行数即返回错歌歌词）。改用 songHash 维度。
      final key = buildKey(
        ns: 'translation',
        path: '/lyrics/display',
        params: <String, Object?>{
          // songHash 缺省时退化为 content 指纹（长度+首行前 24 字符），
          // 仍远优于旧实现的恒 0。
          'song': songHash.isEmpty
              ? '${lyric.content.length}:${lyric.content.trim().length > 24 ? lyric.content.trim().substring(0, 24) : lyric.content.trim()}'
              : songHash,
          'mode': mode.name,
          'trans': local?.length ?? 0,
        },
        schemaVer: 2,
      );
      final hit = _cache.get(key);
      if (hit != null) return hit;

      final originals = extractOriginalLines(lyric);
      final aligned = local == null
          ? const <TranslatedLine>[]
          : alignTranslation(originals, local);
      final hasTrans = aligned.isNotEmpty;

      final out = <DisplayLine>[];
      for (var i = 0; i < originals.length; i++) {
        final t = i < aligned.length ? aligned[i].translation : '';
        switch (mode) {
          case LyricsDisplayMode.original:
            out.add(DisplayLine(main: originals[i], lineIndex: i));
          case LyricsDisplayMode.bilingual:
            out.add(DisplayLine(
                main: originals[i], sub: t, lineIndex: i));
          case LyricsDisplayMode.translation:
            out.add(DisplayLine(
                main: t.isNotEmpty ? t : originals[i], lineIndex: i));
        }
      }
      if (!hasTrans &&
          mode != LyricsDisplayMode.original &&
          originals.isNotEmpty) {
        Log.w(_tag,
            'translation unavailable mode=${mode.name} lines=${originals.length}, showing originals');
      }
      final result = List<DisplayLine>.unmodifiable(out);
      _cache.put(key, result);
      return result;
    } catch (e, st) {
      Log.e(_tag, 'displayFor failed', e, st);
      return const <DisplayLine>[];
    }
  }

  void invalidatePrefix({String userid = ''}) {
    try {
      _cache.clear(); // 无译文外部源，整表失效即可（键空间小）
      Log.d(_tag, 'translation cache cleared userid=$userid');
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
    }
  }
}
