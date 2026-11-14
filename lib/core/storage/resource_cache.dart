// L4 core · 磁盘资源缓存 ResourceCache。
// 缓存键维度 = namespace + 业务 key。调用方必须自行把
// path + 排序后的 query + userid 拼接进业务 key（本类只做键安全化与存取），
// 以保证同一资源对不同用户/不同排序参数互相隔离。
// 纯标准库（dart:io / dart:convert / dart:async），无 flutter 依赖。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../bridges/bridge_kernel.dart' as bk;

const String _tag = 'ResourceCache';

/// 统计快照。
class ResourceCacheStats {
  final int entries;
  final int bytes;
  final int hits;
  final int misses;
  final int evictions;
  const ResourceCacheStats({
    required this.entries,
    required this.bytes,
    required this.hits,
    required this.misses,
    required this.evictions,
  });
  Map<String, dynamic> toMap() => {
        'entries': entries,
        'bytes': bytes,
        'hits': hits,
        'misses': misses,
        'evictions': evictions,
      };
  @override
  String toString() => 'CacheStats${toMap()}';
}

/// L2 磁盘缓存：namespace 隔离 + LRU/TTL + 原子索引替换。
class ResourceCache {
  /// 缓存根目录（下含 <namespace>/ 子目录）。
  final Directory rootDir;

  /// 容量上限（字节），cleanup 后目标 ≤ maxBytes * 0.8。
  final int maxBytes;

  /// 条目存活时长。
  final Duration ttl;

  /// 命名空间：索引与文件均在 rootDir/<namespace>/ 下。
  final String namespace;

  ResourceCache({
    required this.rootDir,
    this.maxBytes = 200 * 1024 * 1024,
    this.ttl = const Duration(days: 7),
    this.namespace = 'default',
  })  : assert(maxBytes > 0),
        assert(!namespace.contains('/') && !namespace.contains('\\'));

  Directory get _dir => Directory(
      '${rootDir.path}${rootDir.path == '/' ? '' : Platform.pathSeparator}'
      '$namespace');

  File get _indexFile =>
      File('${_dir.path}${Platform.pathSeparator}index.json');

  // 进程内计数（stats 用，非持久化）。
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  // ---------- 键安全化 ----------

  /// sha1（纯 dart 实现同批 core 内通用；此处用简化 FNV-1a 64 位 hex +
  /// 长度后缀即可保证文件名安全唯一性，标准库无 crypto）。
  /// 规则：先拒绝非法键，再 hex 编码，原始 key 永不作为路径。
  String safeName(String key) {
    for (final int code in key.codeUnits) {
      if (code < 0x20 || code == 0x7f) {
        throw ArgumentError('cache key contains control char');
      }
    }
    if (key.contains('..') || key.contains('/') || key.contains('\\')) {
      throw ArgumentError('cache key contains path separator');
    }
    // FNV-1a 64bit → 16 hex 字符，加长度后缀降低碰撞混淆。
    int h = 0xcbf29ce484222325;
    for (final int c in utf8.encode(key)) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xffffffffffffffff;
    }
    final String hex = h.toRadixString(16).padLeft(16, '0');
    return '${hex}_${key.length.toRadixString(16)}';
  }

  // ---------- 索引 ----------

  Map<String, Map<String, dynamic>> _loadIndex() {
    try {
      if (!_indexFile.existsSync()) return {};
      final String raw = _indexFile.readAsStringSync();
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw FormatException('bad index');
      final Map<String, Map<String, dynamic>> out = {};
      decoded.forEach((String k, dynamic v) {
        if (v is Map<String, dynamic>) out[k] = v;
      });
      return out;
    } catch (e, st) {
      // 索引损坏：留痕、丢弃重建，不抛。
      bk.logW(_tag, 'index corrupt, rebuild. ns=$namespace err=$e st=$st');
      try {
        if (_indexFile.existsSync()) _indexFile.deleteSync();
      } catch (e2, st2) {
        bk.logE(_tag, 'delete corrupt index failed err=$e2', e2, st2);
      }
      return {};
    }
  }

  /// 临时文件 + rename 原子替换索引。
  bool _saveIndex(Map<String, Map<String, dynamic>> index) {
    try {
      _dir.createSync(recursive: true);
      final File tmp = File(
          '${_dir.path}${Platform.pathSeparator}index.json.tmp');
      tmp.writeAsStringSync(jsonEncode(index), flush: true);
      if (_indexFile.existsSync()) _indexFile.deleteSync();
      tmp.renameSync(_indexFile.path);
      return true;
    } catch (e, st) {
      bk.logE(_tag, 'saveIndex failed ns=$namespace err=$e', e, st);
      return false;
    }
  }

  // ---------- API ----------

  /// 命中且未过期 → 更新 lastAccess 并返回内容；过期/缺失/异常 → null。
  Future<String?> getString(String key) async {
    try {
      final Map<String, Map<String, dynamic>> index = _loadIndex();
      final Map<String, dynamic>? meta = index[key];
      if (meta == null) {
        _misses++;
        return null;
      }
      final int createdAt = (meta['createdAt'] as num?)?.toInt() ?? 0;
      final DateTime now = DateTime.now();
      if (now.millisecondsSinceEpoch - createdAt >= ttl.inMilliseconds) {
        _misses++;
        await _removeEntry(key, index);
        return null;
      }
      final String path = (meta['file'] as String?) ?? '';
      if (path.isEmpty) {
        _misses++;
        return null;
      }
      final File f = File(path);
      if (!f.existsSync()) {
        _misses++;
        index.remove(key);
        _saveIndex(index);
        return null;
      }
      final String value = f.readAsStringSync();
      _hits++;
      meta['lastAccess'] = now.millisecondsSinceEpoch;
      meta['bytes'] = utf8.encode(value).length;
      _saveIndex(index);
      return value;
    } catch (e, st) {
      bk.logE(_tag, 'getString failed key=$key err=$e', e, st);
      _misses++;
      return null;
    }
  }

  /// 写文件 + 更新索引 + 触发容量回收。
  Future<void> putString(String key, String value) async {
    try {
      final List<int> bytes = utf8.encode(value);
      final String safe = safeName(key);
      _dir.createSync(recursive: true);
      final String path =
          '${_dir.path}${Platform.pathSeparator}$safe.dat';
      final File tmp = File('$path.tmp');
      tmp.writeAsBytesSync(bytes, flush: true);
      if (File(path).existsSync()) File(path).deleteSync();
      tmp.renameSync(path);

      final Map<String, Map<String, dynamic>> index = _loadIndex();
      final int now = DateTime.now().millisecondsSinceEpoch;
      index[key] = <String, dynamic>{
        'file': path,
        'bytes': bytes.length,
        'createdAt': now,
        'lastAccess': now,
      };
      _saveIndex(index);
      await cleanup();
    } catch (e, st) {
      bk.logE(_tag, 'putString failed key=$key err=$e', e, st);
    }
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    try {
      final String? raw = await getString(key);
      if (raw == null) return null;
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      bk.logW(_tag, 'getJson non-map payload key=$key');
      return null;
    } catch (e, st) {
      bk.logE(_tag, 'getJson failed key=$key err=$e', e, st);
      return null;
    }
  }

  Future<void> putJson(String key, Map<String, dynamic> value) async {
    try {
      await putString(key, jsonEncode(value));
    } catch (e, st) {
      bk.logE(_tag, 'putJson failed key=$key err=$e', e, st);
    }
  }

  /// 按 lastAccess LRU 删除，直到 ≤ maxBytes * 80%；返回删除字节数。
  Future<int> cleanup() async {
    try {
      final Map<String, Map<String, dynamic>> index = _loadIndex();
      final int target = (maxBytes * 8) ~/ 10;
      int total = 0;
      for (final Map<String, dynamic> m in index.values) {
        total += (m['bytes'] as num?)?.toInt() ?? 0;
      }
      if (total <= target) return 0;
      // 最久未访问优先删除。
      final List<MapEntry<String, Map<String, dynamic>>> entries =
          index.entries.toList()
            ..sort((a, b) => ((a.value['lastAccess'] as num?)?.toInt() ?? 0)
                .compareTo((b.value['lastAccess'] as num?)?.toInt() ?? 0));
      int removed = 0;
      for (final e in entries) {
        if (total - removed <= target) break;
        removed += await _removeEntry(e.key, index);
      }
      _evictions += entries.length - index.length;
      _saveIndex(index);
      if (removed > 0) {
        bk.logD(_tag, 'cleanup ns=$namespace removed=$removed bytes');
      }
      return removed;
    } catch (e, st) {
      bk.logE(_tag, 'cleanup failed ns=$namespace err=$e', e, st);
      return 0;
    }
  }

  Future<int> _removeEntry(
      String key, Map<String, Map<String, dynamic>> index) async {
    final Map<String, dynamic>? meta = index.remove(key);
    if (meta == null) return 0;
    final int bytes = (meta['bytes'] as num?)?.toInt() ?? 0;
    try {
      final String path = (meta['file'] as String?) ?? '';
      if (path.isNotEmpty) {
        final File f = File(path);
        if (f.existsSync()) f.deleteSync();
      }
    } catch (e, st) {
      bk.logW(_tag, 'remove file failed key=$key err=$e st=$st');
    }
    return bytes;
  }

  /// entries / bytes / hits / misses / evictions。
  Future<ResourceCacheStats> stats() async {
    try {
      final Map<String, Map<String, dynamic>> index = _loadIndex();
      int bytes = 0;
      for (final Map<String, dynamic> m in index.values) {
        bytes += (m['bytes'] as num?)?.toInt() ?? 0;
      }
      return ResourceCacheStats(
        entries: index.length,
        bytes: bytes,
        hits: _hits,
        misses: _misses,
        evictions: _evictions,
      );
    } catch (e, st) {
      bk.logE(_tag, 'stats failed ns=$namespace err=$e', e, st);
      return ResourceCacheStats(
          entries: 0, bytes: 0, hits: _hits, misses: _misses, evictions: _evictions);
    }
  }
}
