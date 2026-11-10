// L4 core/net/endpoints · 逐行翻译数据层（对齐 / 原文抽取 / 预留端点封装）
// 契约：lineIndex 为列表 0 起下标；原文与译文按同下标配对，不臆造、不补齐。
// 端点未实测：fetchTranslation 暂不发起请求、不声明新端点，待探针确认后再补。
import '../../../kernel/kernel.dart' show Log;
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

/// 逐行翻译端点预留封装（未实测，禁止猜测 URL/参数）。
/// 当前恒返回空 TranslationResult 并 Log.w 标注；不连任何非官方域名、
/// 不改 KugouClient / EndpointRegistry。探针实测后在此补请求与响应解析
/// （届时可用 dataOf / listOf 解析 data 列表、safeInt / safeStr 容错取值）。
Future<TranslationResult> fetchTranslation(
  KugouClient client,
  int lyricId,
  String accessKey,
) async {
  try {
    final id = safeInt(lyricId);
    final key = safeStr(accessKey).trim();
    // client 为预留参数：待端点实测后承载请求；此刻不发起任何网络调用。
    Log.w('ep.translation',
        'translation endpoint needs probe id=$id keyLen=${key.length} client=${client.runtimeType}');
    return const TranslationResult();
  } catch (e, st) {
    Log.e(_tag, 'fetchTranslation failed id=$lyricId', e, st);
    return const TranslationResult();
  }
}
