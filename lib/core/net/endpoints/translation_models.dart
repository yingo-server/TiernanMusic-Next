// L4 core/net/endpoints · 逐行翻译结果模型（纯数据，零 IO / 零上层依赖）
// 契约：TranslatedLine.lineIndex 与歌词行下标一一对应；默认空值不崩。

/// 单条逐行翻译：原文 / 译文 / 对应歌词行下标（0 起）。
class TranslatedLine {
  const TranslatedLine({
    this.original = '',
    this.translation = '',
    this.lineIndex = 0,
  });

  final String original;
  final String translation;
  final int lineIndex;

  Map<String, Object?> toMap() => <String, Object?>{
        'original': original,
        'translation': translation,
        'lineIndex': lineIndex,
      };

  @override
  String toString() => 'TranslatedLine(${toMap()})';
}

/// 一整首歌的翻译结果：默认空（端点未实测 / 无译文时安全返回）。
class TranslationResult {
  const TranslationResult({
    this.lines = const <TranslatedLine>[],
    this.sourceLang = '',
    this.targetLang = '',
  });

  final List<TranslatedLine> lines;
  final String sourceLang;
  final String targetLang;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  Map<String, Object?> toMap() => <String, Object?>{
        'lines': lines.map((l) => l.toMap()).toList(growable: false),
        'sourceLang': sourceLang,
        'targetLang': targetLang,
      };

  @override
  String toString() => 'TranslationResult(${toMap()})';
}

/// 歌词显示模式：原文 / 双语（原文+译文）/ 仅译文。
enum LyricsDisplayMode { original, bilingual, translation }
