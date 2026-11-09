// L4 core/memory · 容量受限 LRU 缓存（Map + LinkedHashSet 双向访问序）
// 依赖纪律：仅 SDK + kernel Log；所有公开方法 try/catch 留痕，失败不静默吞。
import 'dart:collection';

import '../../kernel/kernel.dart' show Log;

const String _tag = 'memory.lru';

/// 淘汰回调：收到被淘汰的键与值。
typedef LruEvictCallback<K, V> = void Function(K key, V value);

/// LruCache<K,V>：容量注入；_order 头部=最久未用(LRU)，尾部=最近使用(MRU)。
/// get/put 均把键移动到尾部，超容量时从头淘汰并触发 onEvict。
class LruCache<K, V> {
  LruCache({int capacity = 128, LruEvictCallback<K, V>? onEvict})
      : _capacity = capacity > 0 ? capacity : 1,
        _onEvict = onEvict {
    try {
      Log.d(_tag, 'create capacity=$_capacity');
    } catch (e, st) {
      Log.e(_tag, 'create failed', e, st);
    }
  }

  final Map<K, V> _entries = <K, V>{};
  final LinkedHashSet<K> _order = LinkedHashSet<K>();
  final LruEvictCallback<K, V>? _onEvict;
  int _capacity;
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  int get capacity {
    try {
      return _capacity;
    } catch (e, st) {
      Log.e(_tag, 'capacity failed', e, st);
      return 1;
    }
  }

  set capacity(int value) => resize(value);

  int get hits {
    try {
      return _hits;
    } catch (e, st) {
      Log.e(_tag, 'hits failed', e, st);
      return 0;
    }
  }

  int get misses {
    try {
      return _misses;
    } catch (e, st) {
      Log.e(_tag, 'misses failed', e, st);
      return 0;
    }
  }

  int get evictions {
    try {
      return _evictions;
    } catch (e, st) {
      Log.e(_tag, 'evictions failed', e, st);
      return 0;
    }
  }

  int get length {
    try {
      return _entries.length;
    } catch (e, st) {
      Log.e(_tag, 'length failed', e, st);
      return 0;
    }
  }

  bool get isEmpty {
    try {
      return _entries.isEmpty;
    } catch (e, st) {
      Log.e(_tag, 'isEmpty failed', e, st);
      return true;
    }
  }

  bool get isNotEmpty {
    try {
      return _entries.isNotEmpty;
    } catch (e, st) {
      Log.e(_tag, 'isNotEmpty failed', e, st);
      return false;
    }
  }

  double get hitRate {
    try {
      final total = _hits + _misses;
      return total == 0 ? 0.0 : _hits / total;
    } catch (e, st) {
      Log.e(_tag, 'hitRate failed', e, st);
      return 0.0;
    }
  }

  CacheStats get stats {
    try {
      return CacheStats(
        hits: _hits,
        misses: _misses,
        evictions: _evictions,
        size: _entries.length,
        capacity: _capacity,
      );
    } catch (e, st) {
      Log.e(_tag, 'stats failed', e, st);
      return const CacheStats();
    }
  }

  /// 读取并刷新访问序；命中 hits++，未命中 misses++。
  V? get(K key) {
    try {
      if (!_entries.containsKey(key)) {
        _misses++;
        return null;
      }
      _hits++;
      _order.remove(key);
      _order.add(key);
      return _entries[key];
    } catch (e, st) {
      Log.e(_tag, 'get failed key=$key', e, st);
      _misses++;
      return null;
    }
  }

  V? operator [](K key) {
    try {
      return get(key);
    } catch (e, st) {
      Log.e(_tag, 'operator[] failed', e, st);
      return null;
    }
  }

  /// 写入并刷新访问序；超容量按 LRU 顺序淘汰。
  void put(K key, V value) {
    try {
      if (_entries.containsKey(key)) {
        _order.remove(key);
      }
      _entries[key] = value;
      _order.add(key);
      while (_entries.length > _capacity) {
        if (_order.isEmpty) break;
        final oldest = _order.first;
        _order.remove(oldest);
        final old = _entries.remove(oldest);
        _evictions++;
        if (old != null && _onEvict != null) {
          try {
            _onEvict!(oldest, old);
          } catch (e, st) {
            Log.e(_tag, 'evict callback failed key=$oldest', e, st);
          }
        }
        Log.d(_tag, 'evict key=$oldest size=${_entries.length}');
      }
    } catch (e, st) {
      Log.e(_tag, 'put failed key=$key', e, st);
    }
  }

  void operator []=(K key, V value) {
    try {
      put(key, value);
    } catch (e, st) {
      Log.e(_tag, 'operator[]= failed', e, st);
    }
  }

  /// 只读窥视：不改变访问序、不计 hit/miss。
  V? peek(K key) {
    try {
      return _entries[key];
    } catch (e, st) {
      Log.e(_tag, 'peek failed key=$key', e, st);
      return null;
    }
  }

  bool containsKey(K key) {
    try {
      return _entries.containsKey(key);
    } catch (e, st) {
      Log.e(_tag, 'containsKey failed key=$key', e, st);
      return false;
    }
  }

  /// 显式删除（不触发淘汰回调）。
  V? remove(K key) {
    try {
      final value = _entries.remove(key);
      _order.remove(key);
      return value;
    } catch (e, st) {
      Log.e(_tag, 'remove failed key=$key', e, st);
      return null;
    }
  }

  /// 容量热调整：缩容时立即淘汰多余项。
  void resize(int newCapacity) {
    try {
      final next = newCapacity > 0 ? newCapacity : 1;
      _capacity = next;
      while (_entries.length > _capacity) {
        if (_order.isEmpty) break;
        final oldest = _order.first;
        _order.remove(oldest);
        final old = _entries.remove(oldest);
        _evictions++;
        if (old != null && _onEvict != null) {
          try {
            _onEvict!(oldest, old);
          } catch (e, st) {
            Log.e(_tag, 'resize callback failed', e, st);
          }
        }
      }
      Log.d(_tag, 'resize capacity=$_capacity size=${_entries.length}');
    } catch (e, st) {
      Log.e(_tag, 'resize failed', e, st);
    }
  }

  /// 条件失效：返回被移除的键（供 cache_keys 前缀失效使用）。
  List<K> invalidateWhere(bool Function(K key) test) {
    final removed = <K>[];
    try {
      for (final key in _order.toList(growable: false)) {
        var drop = false;
        try {
          drop = test(key);
        } catch (e, st) {
          Log.e(_tag, 'invalidate predicate failed key=$key', e, st);
        }
        if (drop) {
          _entries.remove(key);
          _order.remove(key);
          removed.add(key);
        }
      }
      return removed;
    } catch (e, st) {
      Log.e(_tag, 'invalidateWhere failed', e, st);
      return removed;
    }
  }

  /// 按 cache_keys.prefixOf 产出的前缀批量失效。
  List<K> invalidatePrefix(String prefix) {
    try {
      return invalidateWhere((key) => '$key'.startsWith(prefix));
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed prefix=$prefix', e, st);
      return <K>[];
    }
  }

  void clear() {
    try {
      _entries.clear();
      _order.clear();
      Log.d(_tag, 'clear done');
    } catch (e, st) {
      Log.e(_tag, 'clear failed', e, st);
    }
  }

  void resetStats() {
    try {
      _hits = 0;
      _misses = 0;
      _evictions = 0;
      Log.d(_tag, 'stats reset');
    } catch (e, st) {
      Log.e(_tag, 'resetStats failed', e, st);
    }
  }

  /// 默认返回 MRU→LRU；mostRecentFirst=false 返回 LRU→MRU。
  List<K> keys({bool mostRecentFirst = true}) {
    try {
      final lruOrder = _order.toList(growable: false);
      return mostRecentFirst
          ? lruOrder.reversed.toList(growable: false)
          : lruOrder;
    } catch (e, st) {
      Log.e(_tag, 'keys failed', e, st);
      return <K>[];
    }
  }

  List<V> values({bool mostRecentFirst = true}) {
    final out = <V>[];
    try {
      for (final key in keys(mostRecentFirst: mostRecentFirst)) {
        final value = _entries[key];
        if (value != null) out.add(value);
      }
      return out;
    } catch (e, st) {
      Log.e(_tag, 'values failed', e, st);
      return out;
    }
  }

  List<MapEntry<K, V>> entries({bool mostRecentFirst = true}) {
    final out = <MapEntry<K, V>>[];
    try {
      for (final key in keys(mostRecentFirst: mostRecentFirst)) {
        final value = _entries[key];
        if (value != null) out.add(MapEntry<K, V>(key, value));
      }
      return out;
    } catch (e, st) {
      Log.e(_tag, 'entries failed', e, st);
      return out;
    }
  }

  void forEach(void Function(K key, V value) action) {
    try {
      for (final entry in entries()) {
        try {
          action(entry.key, entry.value);
        } catch (e, st) {
          Log.e(_tag, 'forEach action failed', e, st);
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'forEach failed', e, st);
    }
  }

  Map<K, V> toMap() {
    try {
      return Map<K, V>.of(_entries);
    } catch (e, st) {
      Log.e(_tag, 'toMap failed', e, st);
      return <K, V>{};
    }
  }

  @override
  String toString() {
    try {
      return 'LruCache(size=${_entries.length}/$_capacity, hits=$_hits, '
          'misses=$_misses, evictions=$_evictions)';
    } catch (e, st) {
      Log.e(_tag, 'toString failed', e, st);
      return 'LruCache(<unavailable>)';
    }
  }
}

/// 命中/未命中/淘汰统计快照。
class CacheStats {
  const CacheStats({
    this.hits = 0,
    this.misses = 0,
    this.evictions = 0,
    this.size = 0,
    this.capacity = 0,
  });

  final int hits;
  final int misses;
  final int evictions;
  final int size;
  final int capacity;

  double get hitRate {
    try {
      final total = hits + misses;
      return total == 0 ? 0.0 : hits / total;
    } catch (e, st) {
      Log.e(_tag, 'CacheStats.hitRate failed', e, st);
      return 0.0;
    }
  }

  Map<String, Object?> toMap() {
    try {
      return <String, Object?>{
        'hits': hits,
        'misses': misses,
        'evictions': evictions,
        'size': size,
        'capacity': capacity,
        'hitRate': hitRate,
      };
    } catch (e, st) {
      Log.e(_tag, 'CacheStats.toMap failed', e, st);
      return const <String, Object?>{};
    }
  }

  @override
  String toString() {
    try {
      return 'CacheStats(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'CacheStats.toString failed', e, st);
      return 'CacheStats(<unavailable>)';
    }
  }
}
