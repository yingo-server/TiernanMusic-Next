// L4 core/net/endpoints · 歌词域模型（LyricResult）
// 来源拆分：models.dart（614 行超行拆分，R2-A）；类体逐字搬移，零逻辑改动。
import '../../../bridges/bridge_kernel.dart' show Log;
import 'models_util.dart';

class LyricResult {
  const LyricResult({
    this.id = 0,
    this.accessKey = '',
    this.fmt = '',
    this.content = '',
    this.durationMs = 0,
    this.isKrc = false,
  });

final int id; // candidates[].id（供 /download 使用；批N2-A 实测为字符串，safeInt 容错）
  final String accessKey; // candidates[].accesskey
  final String fmt; // krc / lrc
  final String content; // 解密后的纯文本（krc 已 inflate，lrc 已 base64 解）
  final int durationMs; // duration（毫秒）
  final bool isKrc; // contenttype==0 → krc

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'accessKey': accessKey, 'fmt': fmt, 'durationMs': durationMs,
        'isKrc': isKrc, 'contentLength': content.length,
      };
}
