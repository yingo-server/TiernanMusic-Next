// L4 core/net/endpoints · 逐行翻译数据层（对齐 / 原文抽取 / 预留端点封装）
// 契约：lineIndex 为列表 0 起下标；原文与译文按同下标配对，不臆造、不补齐。
// ⚠️ 端点路径待 ENDPOINT_TRUTH.md 实测确认；当前按不猜参数原则返回语义空值，不伪造成功
// 端点未实测：fetchTranslation 暂不发起请求、不声明新端点，待探针确认后再补。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show LyricResult, safeInt, safeStr, listOf, dataOf;
import 'translation_models.dart' show TranslatedLine, TranslationResult;

const String _tag = 'ep.translation';

// LRC 时间标签：[mm:ss.xx] / [mm:ss:xxx]（可连续多个）。
final RegExp _lrcTimeRe = RegExp(r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]');
// KRC 行头 [start,dur] 与逐字标签 <t,d,0>。
final RegExp _krcHeadRe = RegExp(r'\[\d+,\d+\]');
final RegExp _krcWordTagRe = RegExp(r'<\d+,\d+,\d+>');
// LRC/KRC 元数据行（[ar:] / [ti:] / [offset:] …）不算歌词文本。
final RegExp _metaRe = RegExp(r'^\[[A-Za-z_]+:');

/// 按 lineIndex 对齐原文/译文：仅取 min 长度，多余丢弃，绝不臆造译文。
/// 条数不等时 Log.w 留痕；调用方可据返回条数判断是否有未覆盖行。
List<TranslatedLine> alignTranslation(
  List<String> originalLines,
  List<String> translatedLines,
) {
  try {
    final a = originalLines;
    final b = translatedLines;
    if (a.length != b.length) {
      Log.w('ep.translation',
          'line count mismatch orig=${a.length} trans=${b.length}, align min only');
    }
    final n = a.length < b.length ? a.length : b.length;
    final out = <TranslatedLine>[];
    for (var i = 0; i < n; i++) {
      out.add(TranslatedLine(
        original: safeStr(a[i]),
        translation: safeStr(b[i]),
        lineIndex: i,
      ));
    }
    Log.d(_tag, 'alignTranslation aligned=$n');
    return List<TranslatedLine>.unmodifiable(out);
  } catch (e, st) {
    Log.e(_tag, 'alignTranslation failed', e, st);
    return const <TranslatedLine>[];
  }
}

/// 从 LyricResult.content 抽纯文本原文行：去 [mm:ss.xx] / KRC [start,dur] /
/// <t,d,0> 标签；空行与元数据行跳过。返回行下标即后续 lineIndex。
/// 只做抽取，不生成任何译文。
List<String> extractOriginalLines(LyricResult r) {
  try {
    final content = safeStr(r.content);
    if (content.trim().isEmpty) {
      Log.w(_tag, 'extractOriginalLines empty content');
      return const <String>[];
    }
    final out = <String>[];
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || _metaRe.hasMatch(line)) continue;
      final text = line
          .replaceAll(_krcHeadRe, '')
          .replaceAll(_lrcTimeRe, '')
          .replaceAll(_krcWordTagRe, '')
          .trim();
      if (text.isEmpty) continue;
      out.add(text);
    }
    Log.d(_tag, 'extractOriginalLines got=${out.length}');
    return List<String>.unmodifiable(out);
  } catch (e, st) {
    Log.e(_tag, 'extractOriginalLines failed', e, st);
    return const <String>[];
  }
}

/// 本地 KRC/LRC 内嵌翻译轨抽取（不联网、不臆造 API）。
/// 抽取规则：逐行解析去标签后的歌词行；若出现「原文行 + 紧随的译文行」成对
/// 结构（同一时间轴两行——即相邻两行的首个时间标签相同，或同一时刻重复行），
/// 则第二行视为第一行的译文，收集为 translatedLines。
/// KRC 解密后 content 内嵌翻译轨即此形态；上游无独立翻译端点
/// （见 docs/ENDPOINT_TRUTH.md §6），故翻译恒为本地词典/内嵌轨处理。
List<String> extractEmbeddedTranslatedLines(LyricResult r) {
  try {
    final content = safeStr(r.content);
    if (content.trim().isEmpty) return const <String>[];
    // (firstTimeTag, text) 序列；元数据行/空行剔除。
    final rows = <(String, String)>[];
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || _metaRe.hasMatch(line)) continue;
      final tagMatch = _firstTimeTag(line);
      final text = line
          .replaceAll(_krcHeadRe, '')
          .replaceAll(_lrcTimeRe, '')
          .replaceAll(_krcWordTagRe, '')
          .trim();
      if (text.isEmpty) continue;
      rows.add((tagMatch, text));
    }
    final out = <String>[];
    for (var i = 1; i < rows.length; i++) {
      final prev = rows[i - 1], cur = rows[i];
      // 同一时间轴成对行：上一行为原文，本行为译文。
      final sameTag = prev.$1.isNotEmpty && prev.$1 == cur.$1;
      // 兜底：无时间标签但相邻两行一方疑似中文短行亦不臆测，仅按时间轴判定。
      if (sameTag) out.add(cur.$2);
    }
    Log.d(_tag, 'extractEmbeddedTranslatedLines got=${out.length}');
    return List<String>.unmodifiable(out);
  } catch (e, st) {
    Log.e(_tag, 'extractEmbeddedTranslatedLines failed', e, st);
    return const <String>[];
  }
}

/// 取一行首个时间标签归一化文本（KRC [start,dur] / LRC [mm:ss.xx]），无则空串。
String _firstTimeTag(String line) {
  final krc = _krcHeadRe.firstMatch(line);
  if (krc != null) return krc.group(0) ?? '';
  final lrc = _lrcTimeRe.firstMatch(line);
  if (lrc != null) return lrc.group(0) ?? '';
  return '';
}

/// 逐行翻译获取（本地内嵌翻译轨抽取版）。
/// ENDPOINT_TRUTH.md §6：上游无独立翻译端点，旧项目翻译为本地处理（KRC 内嵌
/// 翻译行），故本函数不联网、不请求任何端点，直接从 LyricResult.content 抽取。
/// client 参数保留签名兼容装配（历史调用点/装配注入不变），当前不使用。
Future<TranslationResult> fetchTranslation(
  KugouClient client,
  int lyricId,
  String accessKey,
) async {
  try {
    final id = safeInt(lyricId);
    final key = safeStr(accessKey).trim();
    // client：保留签名兼容装配，本地抽取不发起网络请求。
    final probe = LyricResult(id: id, accessKey: key);
    // 注意：实际内容由调用侧经 extractOriginalLines/extractEmbeddedTranslatedLines
    // 从同一 LyricResult.content 解析；此处按契约用 id/accessKey 无法还原 content，
    // 故对外仍提供 content 注入入口：见 fetchTranslationFromContent。
    Log.d(_tag, 'fetchTranslation local-extract id=$id keyLen=${key.length}');
    return await fetchTranslationFromContent(probe);
  } catch (e, st) {
    Log.e(_tag, 'fetchTranslation failed id=$lyricId', e, st);
    return const TranslationResult();
  }
}

/// 以完整 LyricResult（含 content）为输入的本地翻译轨抽取入口：
/// 无译文轨返回空 TranslationResult + Log.d('no embedded translation track')。
Future<TranslationResult> fetchTranslationFromContent(LyricResult r) async {
  try {
    final originals = extractOriginalLines(r);
    final trans = extractEmbeddedTranslatedLines(r);
    if (trans.isEmpty) {
      Log.d(_tag, 'no embedded translation track');
      return const TranslationResult();
    }
    final aligned = alignTranslation(originals, trans);
    Log.d(_tag, 'fetchTranslationFromContent lines=${aligned.length}');
    return TranslationResult(
      lines: aligned,
      sourceLang: 'auto',
      targetLang: 'zh',
    );
  } catch (e, st) {
    Log.e(_tag, 'fetchTranslationFromContent failed', e, st);
    return const TranslationResult();
  }
}
