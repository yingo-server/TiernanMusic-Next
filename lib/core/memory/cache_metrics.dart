// cache_metrics.dart — L4 core 内存缓存指标统计
//
// 用途：给预读/三级缓存提供命中率、字节、淘汰统计，供设置页存储诊断展示。
// 纯 Dart，无 IO、无 flutter 依赖；单 isolate 内使用，无需锁。
// 所有公开方法内部 try/catch，失败经 bridge_kernel 的 Log 留痕，不静默吞。

import '../../bridges/bridge_kernel.dart';

/// 单个 namespace 的不可变统计快照。
class CacheMetricsSnapshot {
  final String namespace;
  final int hits;
  final int misses;
  final int stores;
  final int evictions;
  final int errors;
  final int bytesStored;

  const CacheMetricsSnapshot({
    required this.namespace,
    required this.hits,
    required this.misses,
    required this.stores,
    required this.evictions,
    required this.errors,
    required this.bytesStored,
  });

  /// 命中率 = hits / (hits + misses)，分母为 0 时返回 0，clamp 到 0..1。
  double get hitRate {
    final denom = hits + misses;
    if (denom <= 0) return 0;
    final r = hits / denom;
    if (r.isNaN) return 0;
    return r.clamp(0.0, 1.0).toDouble();
  }

  @override
  String toString() =>
      'CacheMetricsSnapshot($namespace hits=$hits misses=$misses stores=$stores '
      'evictions=$evictions errors=$errors bytesStored=$bytesStored '
      'hitRate=${hitRate.toStringAsFixed(3)})';
}

/// 按 namespace 计数的缓存指标收集器。
class CacheMetrics {
  static const String defaultNs = 'default';

  final Map<String, _Counters> _counters = {};

  String _normalize(String? ns) =>
      (ns == null || ns.trim().isEmpty) ? defaultNs : ns.trim();

  _Counters _of(String ns) => _counters.putIfAbsent(ns, () => _Counters());

  /// 缓存命中，bytes 为本次命中数据的字节数（负值忽略）。
  void hit(String ns, {int bytes = 0}) {
    try {
      final c = _of(_normalize(ns));
      c.hits++;
      if (bytes > 0) c.bytesStored += bytes;
    } catch (e, st) {
      Log.e('CacheMetrics.hit failed: $e\n$st');
    }
  }

  /// 缓存未命中。
  void miss(String ns) {
    try {
      _of(_normalize(ns)).misses++;
    } catch (e, st) {
      Log.e('CacheMetrics.miss failed: $e\n$st');
    }
  }

  /// 写入缓存，bytes 为写入字节数（负值忽略）。
  void store(String ns, {int bytes = 0}) {
    try {
      final c = _of(_normalize(ns));
      c.stores++;
      if (bytes > 0) c.bytesStored += bytes;
    } catch (e, st) {
      Log.e('CacheMetrics.store failed: $e\n$st');
    }
  }

  /// 淘汰缓存条目，bytes 为被淘汰的字节数（负值忽略）。
  void evict(String ns, {int bytes = 0}) {
    try {
      final c = _of(_normalize(ns));
      c.evictions++;
      if (bytes > 0) c.bytesStored -= bytes;
    } catch (e, st) {
      Log.e('CacheMetrics.evict failed: $e\n$st');
    }
  }

  /// 缓存操作错误计数。
  void error(String ns) {
    try {
      _of(_normalize(ns)).errors++;
    } catch (e, st) {
      Log.e('CacheMetrics.error failed: $e\n$st');
    }
  }

  /// 指定 ns（缺省全部 ns 合并）的快照。
  CacheMetricsSnapshot snapshot([String? ns]) {
    try {
      final key = _normalize(ns);
      if (ns == null) {
        int h = 0, m = 0, s = 0, ev = 0, er = 0, b = 0;
        _counters.forEach((_, c) {
          h += c.hits; m += c.misses; s += c.stores;
          ev += c.evictions; er += c.errors; b += c.bytesStored;
        });
        return CacheMetricsSnapshot(
            namespace: defaultNs, hits: h, misses: m,
            stores: s, evictions: ev, errors: er, bytesStored: b);
      }
      final c = _counters[key];
      return CacheMetricsSnapshot(
        namespace: key,
        hits: c?.hits ?? 0, misses: c?.misses ?? 0, stores: c?.stores ?? 0,
        evictions: c?.evictions ?? 0, errors: c?.errors ?? 0,
        bytesStored: c?.bytesStored ?? 0,
      );
    } catch (e, st) {
      Log.e('CacheMetrics.snapshot failed: $e\n$st');
      return CacheMetricsSnapshot(namespace: defaultNs, hits: 0, misses: 0,
          stores: 0, evictions: 0, errors: 0, bytesStored: 0);
    }
  }

  /// 重置：传 ns 重置该 ns，缺省重置全部。
  void reset([String? ns]) {
    try {
      if (ns == null) {
        _counters.clear();
      } else {
        _counters.remove(_normalize(ns));
      }
    } catch (e, st) {
      Log.e('CacheMetrics.reset failed: $e\n$st');
    }
  }

  /// 全部 namespace 的快照（不含合并视图）。
  Map<String, CacheMetricsSnapshot> get all {
    try {
      final out = <String, CacheMetricsSnapshot>{};
      for (final key in _counters.keys) {
        final c = _counters[key]!;
        out[key] = CacheMetricsSnapshot(
          namespace: key,
          hits: c.hits, misses: c.misses, stores: c.stores,
          evictions: c.evictions, errors: c.errors, bytesStored: c.bytesStored,
        );
      }
      return Map.unmodifiable(out);
    } catch (e, st) {
      Log.e('CacheMetrics.all failed: $e\n$st');
      return const {};
    }
  }
}

class _Counters {
  int hits = 0;
  int misses = 0;
  int stores = 0;
  int evictions = 0;
  int errors = 0;
  int bytesStored = 0;
}
