// L5 logic · play_url 解析器（纯 Dart，无 flutter / 无 IO / 无网络）。
//
// 字段锚点 = docs/API_FIELDS_TRUTH.md §A3-1（play_url v5，x-router trackercdn.kugou.com）：
// - 成功响应【顶层即数据】（无 data 包层）：url[]/backupUrl[]/bitRate/extName/status/
//   priv_status/timeLength(秒)/tracker_through.musicpack_advance 等 22 键均在顶层。
// - flac 档实测 bitRate 恒 0（extName=flac），不可用 bitRate 判档。
// - 三态矩阵：匿名→status=2+errcode=20028（需验证）；非 VIP 曲→status=2+priv_status=0；
//   VIP→status=1+priv_status=1+url[]。
// play_url v5 顶层结构的解析产物
import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'logic.playParse';

/// play_url v5 顶层结构的解析产物（字段名即实测顶层键名的规范化映射）。
class ParsedPlayUrl {
  final int status;
  final int privStatus;
  final List<String> urls;
  final List<String> backupUrls;
  final int bitRate;
  final String extName;
  final int musicpackAdvance;
  final bool isFreePart;
  final int endByte;
  final int timeLengthSec;
  final String traceId;

  const ParsedPlayUrl({
    this.status = 0,
    this.privStatus = 0,
    this.urls = const <String>[],
    this.backupUrls = const <String>[],
    this.bitRate = 0,
    this.extName = '',
    this.musicpackAdvance = 0,
    this.isFreePart = false,
    this.endByte = 0,
    this.timeLengthSec = 0,
    this.traceId = '',
  });

  /// 可播放：status=1 且有 url。
  bool get isPlayable => status == 1 && urls.isNotEmpty;
}

/// 数值安全转换：int/num/数字字符串→int，其余（含缺失/null/异常）→ fallback。
int _safeInt(Object? v, [int fallback = 0]) {
  try {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return fallback;
      return int.parse(s);
    }
    return fallback;
  } catch (e, st) {
    Log.w(_tag, '_safeInt($v) fallback=$fallback');
    Log.e(_tag, '_safeInt failed', e, st);
    return fallback;
  }
}

/// 布尔安全转换：bool/1/'1'/true→true，其余 false。
bool _safeBool(Object? v) {
  try {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true';
    }
    return false;
  } catch (e, st) {
    Log.e(_tag, '_safeBool failed', e, st);
    return false;
  }
}

/// url / backupUrl 双形态兼容：单串或数组 → 非空串列表。
List<String> _safeUrlList(Object? v) {
  try {
    if (v is List) {
      return v
          .map((u) => u is String ? u.trim() : u?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toList(growable: false);
    }
    if (v is String && v.trim().isNotEmpty) return <String>[v.trim()];
    return const <String>[];
  } catch (e, st) {
    Log.e(_tag, '_safeUrlList failed', e, st);
    return const <String>[];
  }
}

/// 解析 play_url v5 响应为 [ParsedPlayUrl]。
/// 严格按实测顶层结构取数（§A3-1）：url/backupUrl/bitRate/extName/status/priv_status/
/// tracker_through.musicpack_advance/IsFreePart/end_byte/timeLength 均在顶层，非 data[]。
/// 任何字段缺失/类型异常均安全兜底（0/空/''），整体异常返回 malformed 基线并留痕。
ParsedPlayUrl parse(Map<String, dynamic> res) {
  try {
    final status = _safeInt(res['status']);
    final privStatus = _safeInt(res['priv_status']);
    final urls = _safeUrlList(res['url']);
    final backupUrls = _safeUrlList(res['backupUrl']);

    // tracker_through 顶层嵌套 map → musicpack_advance（1=VIP 曲）。
    var musicpackAdvance = 0;
    final tt = res['tracker_through'];
    if (tt is Map) {
      musicpackAdvance = _safeInt(tt['musicpack_advance']);
    }

    final parsed = ParsedPlayUrl(
      status: status,
      privStatus: privStatus,
      urls: urls,
      backupUrls: backupUrls,
      // flac 档实测 bitRate 恒 0 —— 不可用于判档，仅如实透传。
      bitRate: _safeInt(res['bitRate']),
      extName: res['extName'] is String ? res['extName'] as String : '',
      musicpackAdvance: musicpackAdvance,
      isFreePart: _safeBool(res['IsFreePart']),
      endByte: _safeInt(res['end_byte']),
      timeLengthSec: _safeInt(res['timeLength']),
      traceId: res['traceId'] is String ? res['traceId'] as String : '',
    );
    Log.d(_tag,
        'parse status=$status priv=$privStatus urls=${urls.length} '
        'backup=${backupUrls.length} mp=$musicpackAdvance bit=${parsed.bitRate}');
    return parsed;
  } catch (e, st) {
    Log.e(_tag, 'parse failed', e, st);
    return const ParsedPlayUrl(); // 兜底：全零基线（verdict 侧由调用方按 malformed 处理）
  }
}
