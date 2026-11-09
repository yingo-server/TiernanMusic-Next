// L4 core/memory · 唯一缓存键规则与前缀失效
// 键格式：json:<ns>:<u=userid>:<path>:<sorted(query)>:v<schemaVer>
// 所有公开函数 try/catch + kernel Log；全部段做组件编码，避免 ':' / '/' 撞段。
import 'dart:convert';

import '../../kernel/kernel.dart' show Log;

const String _tag = 'memory.keys';
const String _scheme = 'json';
const int _defaultSchemaVer = 1;

/// 默认 schema 版本；业务域可覆写后传给 buildKey。
const int kDefaultSchemaVer = _defaultSchemaVer;

/// 归一化段：Uri.encodeQueryComponent 会把 ':'、'/'、'&' 等编码，保证分隔符唯一。
String _seg(String raw) {
  try {
    return Uri.encodeQueryComponent(raw);
  } catch (e, st) {
    Log.e(_tag, 'segment encode failed raw=$raw', e, st);
    return '';
  }
}

/// 递归规范化：Map 按键 ASCII 排序后重排，List 保序递归，Set 转字符串排序。
Object? _canonical(Object? value) {
  try {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      final out = <String, Object?>{};
      for (final k in keys) {
        for (final orig in value.keys) {
          if ('$orig' == k) {
            out[k] = _canonical(value[orig]);
            break;
          }
        }
      }
      return out;
    }
    if (value is Iterable) {
      return value.map(_canonical).toList(growable: false);
    }
    if (value == null) return '';
    if (value is String || value is num || value is bool) return value;
    return '$value';
  } catch (e, st) {
    Log.e(_tag, 'canonicalize failed type=${value.runtimeType}', e, st);
    return '';
  }
}

/// 把任意值渲染成稳定字符串：Map/List 用 jsonEncode（Map 已排序）。
String _render(Object? value) {
  try {
    final c = _canonical(value);
    if (c is String) return c;
    if (c is Map || c is List) return jsonEncode(c);
    if (c == null) return '';
    return '$c';
  } catch (e, st) {
    Log.e(_tag, 'render failed', e, st);
    return '';
  }
}

/// 排序后的查询片段：键按 ASCII 升序，`k=v` 用 & 连接；组件级编码。
/// 单独导出便于测试与日志比对；null 值以空串保留（保证参数集合稳定）。
String sortedQuery([Map<String, Object?>? params]) {
  try {
    final src = params ?? const <String, Object?>{};
    final keys = src.keys.toList()..sort();
    return keys
        .map((k) => '${_seg(k)}=${_seg(_render(src[k]))}')
        .join('&');
  } catch (e, st) {
    Log.e(_tag, 'sortedQuery failed', e, st);
    return '';
  }
}

/// 生成唯一缓存键。
/// ns：业务命名空间（如 'search'、'play'、'playlist'）；
/// userid：会话态用户 ID，未登录传 ''；path：端点路径（含 /）；
/// params：参与请求语义的查询/业务参数；schemaVer：模型版本，升版自动失效老键。
String buildKey({
  String ns = 'default',
  String userid = '',
  String path = '/',
  Map<String, Object?> params = const <String, Object?>{},
  int schemaVer = _defaultSchemaVer,
}) {
  try {
    final namespace = ns.trim().isEmpty ? 'default' : ns.trim();
    final uid = userid.trim();
    final p = path.trim().isEmpty ? '/' : path.trim();
    final version = schemaVer < 0 ? 0 : schemaVer;
    final key = '$_scheme:${_seg(namespace)}:u=${_seg(uid)}:${_seg(p)}:'
        '${sortedQuery(params)}:v$version';
    Log.d(_tag, 'buildKey ns=$namespace uid=$uid path=$p v=$version');
    return key;
  } catch (e, st) {
    Log.e(_tag, 'buildKey failed ns=$ns path=$path', e, st);
    // 兜底键：仍满足唯一键前缀结构，不抛异常给调用方。
    return '$_scheme:${_seg('default')}:u=${_seg('')}:'
        '${_seg('/')}::v0';
  }
}

/// 按 (ns, userid) 失效的前缀，直接用于 LruCache.invalidatePrefix。
/// 返回形如 `json:<ns>:u=<userid>:`，与 buildKey 的段编码完全一致。
String prefixOf(String ns, [String userid = '']) {
  try {
    final namespace = ns.trim().isEmpty ? 'default' : ns.trim();
    final uid = userid.trim();
    final prefix = '$_scheme:${_seg(namespace)}:u=${_seg(uid)}:';
    Log.d(_tag, 'prefixOf ns=$namespace uid=$uid');
    return prefix;
  } catch (e, st) {
    Log.e(_tag, 'prefixOf failed ns=$ns', e, st);
    return '$_scheme:${_seg('default')}:u=${_seg('')}:';
  }
}

/// 仅按命名空间失效（跨用户），例如 schema 改版或全局刷新。
String namespacePrefixOf(String ns) {
  try {
    final namespace = ns.trim().isEmpty ? 'default' : ns.trim();
    return '$_scheme:${_seg(namespace)}:';
  } catch (e, st) {
    Log.e(_tag, 'namespacePrefixOf failed ns=$ns', e, st);
    return '$_scheme:';
  }
}

/// 按 schema 版本失效：需要扫描时配合 CacheKeyInfo.schemaVer 使用。
String schemaSuffixOf(int schemaVer) {
  try {
    return ':v${schemaVer < 0 ? 0 : schemaVer}';
  } catch (e, st) {
    Log.e(_tag, 'schemaSuffixOf failed', e, st);
    return ':v0';
  }
}

/// 缓存键解析结果；容错解析失败时 valid=false，字段给默认值。
class CacheKeyInfo {
  const CacheKeyInfo({
    required this.raw,
    required this.valid,
    this.namespace = '',
    this.userid = '',
    this.path = '',
    this.query = '',
    this.schemaVer = 0,
  });

  final String raw;
  final bool valid;
  final String namespace;
  final String userid;
  final String path;
  final String query;
  final int schemaVer;

  bool matchesPrefix(String prefix) {
    try {
      return raw.startsWith(prefix);
    } catch (e, st) {
      Log.e(_tag, 'matchesPrefix failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() {
    try {
      return <String, Object?>{
        'raw': raw,
        'valid': valid,
        'namespace': namespace,
        'userid': userid,
        'path': path,
        'query': query,
        'schemaVer': schemaVer,
      };
    } catch (e, st) {
      Log.e(_tag, 'CacheKeyInfo.toMap failed', e, st);
      return const <String, Object?>{};
    }
  }

  @override
  String toString() {
    try {
      return 'CacheKeyInfo(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'CacheKeyInfo.toString failed', e, st);
      return 'CacheKeyInfo(<unavailable>)';
    }
  }
}

/// 解析 buildKey 产出的键；供失效/迁移/诊断使用，不抛异常。
CacheKeyInfo parseKey(String key) {
  try {
    final parts = key.split(':');
    // 键共 6 段：json / ns / u=uid / path / query / vN
    // query 中 ':' 已被 _seg 编码，故 split(':') 稳定。
    if (parts.length < 6 || parts[0] != _scheme || parts[1].isEmpty) {
      Log.w(_tag, 'parseKey invalid shape len=${parts.length}');
      return CacheKeyInfo(raw: key, valid: false);
    }
    final ns = Uri.decodeQueryComponent(parts[1]);
    final uidRaw = parts[2].startsWith('u=') ? parts[2].substring(2) : '';
    final uid = Uri.decodeQueryComponent(uidRaw);
    final path = Uri.decodeQueryComponent(parts[3]);
    final v = parts.last.startsWith('v')
        ? int.tryParse(parts.last.substring(1)) ?? 0
        : 0;
    final query = parts.sublist(4, parts.length - 1).join(':');
    return CacheKeyInfo(
      raw: key,
      valid: true,
      namespace: ns,
      userid: uid,
      path: path,
      query: query,
      schemaVer: v,
    );
  } catch (e, st) {
    Log.e(_tag, 'parseKey failed key=$key', e, st);
    return CacheKeyInfo(raw: key, valid: false);
  }
}

/// 便捷：为一组 (ns, userid, path, params) 生成键并返回其前缀，便于写入+失效。
class CacheKeyPair {
  const CacheKeyPair({required this.key, required this.prefix});
  final String key;
  final String prefix;
}

CacheKeyPair keyWithPrefix({
  required String ns,
  String userid = '',
  required String path,
  Map<String, Object?> params = const <String, Object?>{},
  int schemaVer = _defaultSchemaVer,
}) {
  try {
    return CacheKeyPair(
      key: buildKey(
        ns: ns,
        userid: userid,
        path: path,
        params: params,
        schemaVer: schemaVer,
      ),
      prefix: prefixOf(ns, userid),
    );
  } catch (e, st) {
    Log.e(_tag, 'keyWithPrefix failed', e, st);
    return CacheKeyPair(key: buildKey(), prefix: prefixOf('default'));
  }
}

/// 批失效辅助：收集匹配任一前缀的键（调用方再喂给 LruCache.remove）。
List<String> keysMatching(Iterable<String> keys, List<String> prefixes) {
  try {
    final safe = prefixes.where((p) => p.isNotEmpty).toList(growable: false);
    if (safe.isEmpty) return <String>[];
    return keys
        .where((k) => safe.any((p) => k.startsWith(p)))
        .toList(growable: false);
  } catch (e, st) {
    Log.e(_tag, 'keysMatching failed', e, st);
    return <String>[];
  }
}
