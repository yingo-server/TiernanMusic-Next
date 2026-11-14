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

  // 内存索引：首次访问时经 _loadIndex 异步加载一次，之后 get/stats 只读内存，
  // put/cleanup 改内存后再落盘，避免每次 get/put 整读整写 index.json。
  // 用 final 保证对象不被替换，_saveIndex / cleanup 永远序列化「当前最新」内容。
  final Map<String, Map<String, dynamic>> _index =
      <String, Map<String, dynamic>>{};
  Future<void>? _loadFuture;

  // 写串行链：所有「改内存 + 落盘 + 删文件」的 RMW 都经 _enqueue 排队，
  // 禁止两个 RMW 交错，也保证 cleanup 不覆盖并发 put 的新索引。
  Future<void> _writeChain = Future<void>.value();

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

  // 首次访问（get/put/cleanup/stats）时把 index.json 读进 _index，仅一次；
  // 加载本身经串行链排队，避免与并发 put/cleanup 的 RMW 交错。
  Future<void> _ensureLoaded() {
    final Future<void>? pending = _loadFuture;
    if (pending != null) return pending;
    // 规约为「不失败」的 Future：失败留痕并清空缓存，允许下次重试，
    // 同时不污染 _writeChain（链的规约由 _swallow 负责）。
    final Future<void> done = _recoverLoad(_enqueue<void>(_loadIndex));
    _loadFuture = done;
    return done;
  }

  Future<void> _recoverLoad(Future<void> raw) async {
    try {
      await raw;
    } catch (e, st) {
      _loadFuture = null;
      bk.logE(_tag, 'ensureLoaded failed ns=$namespace err=$e', e, st);
    }
  }

  /// 异步读取索引一次；损坏则留痕、删除损坏文件、内存重建为空，不抛。
  Future<void> _loadIndex() async {
    try {
      final File idx = _indexFile;
      if (!await idx.exists()) return;
      final String raw = await idx.readAsString();
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw FormatException('bad index');
      decoded.forEach((String k, dynamic v) {
        if (v is Map<String, dynamic>) _index[k] = v;
      });
    } catch (e, st) {
      bk.logW(_tag, 'index corrupt, rebuild. ns=$namespace err=$e st=$st');
      _index.clear();
      try {
        final File idx = _indexFile;
        if (await idx.exists()) await idx.delete();
      } catch (e2, st2) {
        bk.logE(_tag, 'delete corrupt index failed err=$e2', e2, st2);
      }
    }
  }

  /// 排队执行写闭包；异常仅留痕并吞掉，保证 _writeChain 永不中断、后续写不饿死。
  /// 调用方须先 await _ensureLoaded()，保证 body 读到的 _index 已加载；
  /// body 内不得再调 _enqueue，避免自等死锁。
  Future<T> _enqueue<T>(Future<T> Function() body) {
    final Future<T> result = _writeChain.then((_) => body());
    _writeChain = _swallow(result);
    return result;
  }

  /// 把任意写结果规约为「已完成」，错误只留痕，不污染串行链。
  Future<void> _swallow<T>(Future<T> f) async {
    try {
      await f;
    } catch (e, st) {
      bk.logE(_tag, 'writeChain failed ns=$namespace err=$e', e, st);
    }
  }

  /// 从内存 _index 移除条目并异步删文件；仅由 _enqueue 内调用，不抛。
  Future<int> _removeEntry(String key) async {
    final Map<String, dynamic>? meta = _index.remove(key);
    if (meta == null) return 0;
    final int bytes = (meta['bytes'] as num?)?.toInt() ?? 0;
    try {
      final String path = (meta['file'] as String?) ?? '';
      if (path.isNotEmpty) {
        final File f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (e, st) {
      bk.logW(_tag, 'remove file failed key=$key err=$e st=$st');
    }
    return bytes;
  }

  /// 失效条目删除 + 按「当前」_index 落盘（get 的失效分支专用）。
  Future<void> _dropAndPersist(String key) => _enqueue<void>(() async {
        await _removeEntry(key);
        await _saveIndex();
      });

  /// 唯一 tmp 名 + 全异步 IO + rename 原子替换索引；
  /// 仅由 _enqueue 内调用，串行链保证跨 instance 无互踩窗口。
  /// 每次都 jsonEncode 当前 _index，绝不回写旧的 index 副本。
  Future<bool> _saveIndex() async {
    File? tmp;
    try {
      await _dir.create(recursive: true);
      tmp = File('${_dir.path}${Platform.pathSeparator}'
          'index.json.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await tmp.writeAsString(jsonEncode(_index), flush: true);
      final File idx = _indexFile;
      // dart:io 无 File.replace：直接 rename（POSIX 原子覆盖既有目标，保留
      // rename 语义）；若目标存在导致 rename 失败，退化为先删再 rename，
      // 唯一 tmp 名 + 写串行已保证跨 instance 无互踩窗口。
      try {
        await tmp.rename(idx.path);
      } catch (e, st) {
        bk.logW(_tag, 'rename over existing failed ns=$namespace err=$e st=$st');
        if (await idx.exists()) await idx.delete();
        await tmp.rename(idx.path);
      }
      return true;
    } catch (e, st) {
      bk.logE(_tag, 'saveIndex failed ns=$namespace err=$e', e, st);
      // 唯一 tmp 名在失败时会残留：尽力清理，避免临时文件累积。
      final File? leftover = tmp;
      if (leftover != null) {
        try {
          if (await leftover.exists()) await leftover.delete();
        } catch (e2, st2) {
          bk.logW(_tag, 'cleanup tmp failed err=$e2 st=$st2');
        }
      }
      return false;
    }
  }

  // ---------- API ----------

  /// 命中且未过期 → 更新 lastAccess 并返回内容；过期/缺失/异常 → null。
  /// 读路径只查内存 _index，命中不触发整索引回写；文件读取全异步。
  Future<String?> getString(String key) async {
    try {
      await _ensureLoaded();
      final Map<String, dynamic>? meta = _index[key];
      if (meta == null) {
        _misses++;
        return null;
      }
      final int createdAt = (meta['createdAt'] as num?)?.toInt() ?? 0;
      final DateTime now = DateTime.now();
      if (now.millisecondsSinceEpoch - createdAt >= ttl.inMilliseconds) {
        _misses++;
        await _dropAndPersist(key);
        return null;
      }
      final String path = (meta['file'] as String?) ?? '';
      if (path.isEmpty) {
        _misses++;
        return null;
      }
      final File f = File(path);
      if (!await f.exists()) {
        _misses++;
        await _dropAndPersist(key);
        return null;
      }
      final String value = await f.readAsString();
      _hits++;
      // lastAccess / bytes 只改内存；延迟到下次写（put/cleanup/失效删除）时落盘。
      meta['lastAccess'] = now.millisecondsSinceEpoch;
      meta['bytes'] = utf8.encode(value).length;
      return value;
    } catch (e, st) {
      bk.logE(_tag, 'getString failed key=$key err=$e', e, st);
      _misses++;
      return null;
    }
  }

  /// 写文件 + 更新索引 + 触发容量回收；写路径整体经串行链排队。
  Future<void> putString(String key, String value) async {
    try {
      await _ensureLoaded();
      await _enqueue<void>(() async {
        final List<int> bytes = utf8.encode(value);
        final String safe = safeName(key);
        await _dir.create(recursive: true);
        final String path =
            '${_dir.path}${Platform.pathSeparator}$safe.dat';
        final File tmp = File(
            '$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        final File target = File(path);
        if (await target.exists()) await target.delete();
        await tmp.rename(path);

        final int now = DateTime.now().millisecondsSinceEpoch;
        _index[key] = <String, dynamic>{
          'file': path,
          'bytes': bytes.length,
          'createdAt': now,
          'lastAccess': now,
        };
        await _saveIndex();
      });
      await _cleanupEnqueued();
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
  /// 公开的 cleanup 只负责「确保索引已加载」，真正的 RMW 全部放进串行链。
  Future<int> cleanup() async {
    try {
      await _ensureLoaded();
      return await _cleanupEnqueued();
    } catch (e, st) {
      bk.logE(_tag, 'cleanup failed ns=$namespace err=$e', e, st);
      return 0;
    }
  }

  /// 串行链内的清理体：进入时基于「最新」_index 计算，全程不再 await
  /// 其它排队任务，删除完成后再以当前 _index 落盘，不持旧副本跨 await 回写。
  Future<int> _cleanupEnqueued() => _enqueue<int>(() async {
        final int target = (maxBytes * 8) ~/ 10;
        int total = 0;
        for (final Map<String, dynamic> m in _index.values) {
          total += (m['bytes'] as num?)?.toInt() ?? 0;
        }
        if (total <= target) return 0;
        // 最久未访问优先删除（只取键与字节快照，不回写该快照）。
        final List<MapEntry<String, Map<String, dynamic>>> entries =
            _index.entries.toList()
              ..sort((a, b) =>
                  ((a.value['lastAccess'] as num?)?.toInt() ?? 0)
                      .compareTo((b.value['lastAccess'] as num?)?.toInt() ?? 0));
        int removed = 0;
        int evictedCount = 0;
        for (final MapEntry<String, Map<String, dynamic>> e in entries) {
          if (total - removed <= target) break;
          if (!_index.containsKey(e.key)) continue;
          removed += await _removeEntry(e.key);
          evictedCount++;
        }
        _evictions += evictedCount;
        // 基于删除后的最新 _index 持久化，含并发 put 已排入的新条目。
        await _saveIndex();
        if (removed > 0) {
          bk.logD(_tag, 'cleanup ns=$namespace removed=$removed bytes');
        }
        return removed;
      });

  /// entries / bytes / hits / misses / evictions；全部取自当前内存 _index。
  Future<ResourceCacheStats> stats() async {
    try {
      await _ensureLoaded();
      int bytes = 0;
      for (final Map<String, dynamic> m in _index.values) {
        bytes += (m['bytes'] as num?)?.toInt() ?? 0;
      }
      return ResourceCacheStats(
        entries: _index.length,
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
