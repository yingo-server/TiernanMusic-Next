// L4 core/net/endpoints · 端点模型容错工具（由 models.dart 拆出，纯移动）
// 来源拆分：models.dart（614 行超行拆分，R2-A）；工具函数原文搬移，零逻辑改动。
// 禁 import logic/surface/flutter；仅 SDK + 同级 kugou_client。
import '../../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'endpoints.models';

/// 容错取值工具：类型不符返回 fallback，绝不抛出。
int safeInt(Object? v, [int fallback = 0]) {
  try {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  } catch (e, st) {
    Log.e(_tag, 'safeInt failed v=$v', e, st);
    return fallback;
  }
}

String safeStr(Object? v, [String fallback = '']) {
  try {
    if (v == null) return fallback;
    return '$v';
  } catch (e, st) {
    Log.e(_tag, 'safeStr failed', e, st);
    return fallback;
  }
}

double safeDouble(Object? v, [double fallback = 0.0]) {
  try {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  } catch (e, st) {
    Log.e(_tag, 'safeDouble failed', e, st);
    return fallback;
  }
}

bool safeBool(Object? v, [bool fallback = false]) {
  try {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      return v == '1' || v.toLowerCase() == 'true';
    }
    return fallback;
  } catch (e, st) {
    Log.e(_tag, 'safeBool failed', e, st);
    return fallback;
  }
}

/// 容错从响应根取 data 子对象（缺失返回空 map，不崩）。
Map<String, dynamic> dataOf(Map<String, dynamic> root) {
  try {
    final d = root['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return d.map((k, v) => MapEntry('$k', v));
    return const <String, dynamic>{};
  } catch (e, st) {
    Log.e(_tag, 'dataOf failed', e, st);
    return const <String, dynamic>{};
  }
}

/// 容错取列表：缺失/类型不符返回空列表。
List<Map<String, dynamic>> listOf(Object? v) {
  try {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((m) => m.map((k, val) => MapEntry('$k', val)))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  } catch (e, st) {
    Log.e(_tag, 'listOf failed', e, st);
    return const <Map<String, dynamic>>[];
  }
}
