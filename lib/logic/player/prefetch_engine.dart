// L5 logic/player · 预读引擎（纯逻辑，网络由注入的 fetch 承担）
//
// 对标旧版 PrefetchEngine 的冻结契约（只读参照，不复制源码）：
//   - 启动预热：enqueueHashes 按 spacing 逐个入队，单次上限 60
//   - 队列补充：updateUpcoming 对未来 window 首去重补充（插队头）
//   - 去重闸门：LRU 上限 512（防长时间使用内存单调上涨）
//   - 只预请求 JSON（URL/歌词/封面），不下载媒体
//   - dispose 后回调先查存活状态；一切队列有界；失败不重试、不阻塞调用方
// 设计说明：本类只认 hash（预读不需要完整 SongBrief），由装配层闭包捕获歌曲对象，
// 从而不 import core 模型，保持可单测、无 isar/flutter 依赖。
// 铁律：每方法 try/catch + Log；不 import flutter。

import 'dart:async';

import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'logic.prefetch';

/// 预读引擎（实例化使用，便于测试与 dispose）。
class PrefetchEngine {
  PrefetchEngine({
    this.maxEnqueuePerCall = 60,
    this.maxRequested = 512,
    this.upcomingWindow = 15,
  });

  /// 单次入队上限（覆盖首屏可见量级）。
  final int maxEnqueuePerCall;

  /// 去重集合上限（LRU 淘汰最旧）。
  final int maxRequested;

  /// updateUpcoming 默认窗口。
  final int upcomingWindow;

  /// 真正执行预取的注入回调（hash, quality → 完成 Future）。
  /// 未调用 attach 前只入队不请求（与旧版语义一致）。
  Future<void> Function(String hash, String quality)? _fetch;

  /// 请求音质（默认 320）。
  String quality = '320';

  final List<String> _pending = <String>[];
  final Set<String> _requested = <String>{};
  final List<String> _requestedOrder = <String>[];

  Timer? _timer;
  bool _disposed = false;
  bool _draining = false;

  int _queued = 0;
  int _prefetched = 0;
  int _errors = 0;

  bool get isDisposed => _disposed;
  int get pendingCount => _pending.length;
  int get prefetchedCount => _prefetched;

  /// 绑定取数回调（装配层用闭包把 hash 还原成歌曲并解析播放源）。
  void attach(Future<void> Function(String hash, String quality) fetch) {
    try {
      _fetch = fetch;
      Log.d(_tag, 'attached');
    } catch (e, st) {
      Log.e(_tag, 'attach failed', e, st);
    }
  }

  /// 启动预热：预留启动预热入口，待接线；非阻塞，按 spacing 逐个消费；已入队/已请求的 hash 跳过。
  void enqueueHashes(
    Iterable<String> hashes, {
    Duration spacing = const Duration(milliseconds: 100),
  }) {
    try {
      if (_disposed) return;
      // 容量必须在入队前快照：循环里 _pending 增长会把上限越算越小
      // （批04 自测抓到：60 的首批实际只入队 30）。
      final int capacity = maxEnqueuePerCall - _pending.length;
      if (capacity <= 0) return;
      var taken = 0;
      for (final raw in hashes) {
        if (taken >= capacity) break;
        final hash = raw.trim();
        if (hash.isEmpty || _requested.contains(hash)) continue;
        _pending.add(hash);
        _markRequested(hash); // 入队即占位，避免重复入队
        taken++;
      }
      if (taken == 0) return;
      _queued += taken;
      Log.d(_tag, 'enqueue $taken (pending=${_pending.length})');
      _schedule(spacing);
    } catch (e, st) {
      Log.e(_tag, 'enqueueHashes failed', e, st);
    }
  }

  /// 播放队列补充：未来 window 首插入队头（近的先算）。
  void updateUpcoming(
    List<String> queue,
    int currentIndex, {
    int? window,
  }) {
    try {
      if (_disposed || queue.isEmpty) return;
      final w = window ?? upcomingWindow;
      final start = (currentIndex < 0 || currentIndex >= queue.length)
          ? 0
          : currentIndex;
      final upcoming = <String>[];
      for (var i = start; i < queue.length && upcoming.length < w; i++) {
        final hash = queue[i].trim();
        if (hash.isEmpty || _requested.contains(hash)) continue;
        upcoming.add(hash);
        _markRequested(hash);
      }
      if (upcoming.isEmpty) return;
      _pending.insertAll(0, upcoming);
      _queued += upcoming.length;
      Log.d(_tag, 'upcoming +${upcoming.length} (pending=${_pending.length})');
      _schedule(const Duration(milliseconds: 100));
    } catch (e, st) {
      Log.e(_tag, 'updateUpcoming failed', e, st);
    }
  }

  /// 释放：取消定时器、清空队列；之后所有入队/消费直接返回。
  void dispose() {
    try {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      _pending.clear();
      _requested.clear();
      _requestedOrder.clear();
      Log.d(_tag,
          'disposed (queued=$_queued prefetched=$_prefetched errors=$_errors)');
    } catch (e, st) {
      Log.e(_tag, 'dispose failed', e, st);
    }
  }

  /// 指标快照（供设置页存储诊断/日志）。
  Map<String, Object> get stats => <String, Object>{
        'queued': _queued,
        'prefetched': _prefetched,
        'errors': _errors,
        'pending': _pending.length,
        'requested': _requested.length,
      };

  // ── 内部 ──

  void _markRequested(String hash) {
    if (_requested.add(hash)) {
      _requestedOrder.add(hash);
      while (_requestedOrder.length > maxRequested) {
        final old = _requestedOrder.removeAt(0);
        _requested.remove(old);
      }
    }
  }

  void _schedule(Duration spacing) {
    if (_disposed || _draining) return;
    _timer?.cancel();
    _timer = Timer(spacing, () {
      _timer = null;
      _drainOnce(spacing);
    });
  }

  Future<void> _drainOnce(Duration spacing) async {
    if (_disposed || _draining) return;
    _draining = true;
    try {
      if (_pending.isEmpty) return;
      final hash = _pending.removeAt(0);
      final fetch = _fetch;
      if (fetch == null) {
        // 审查修复：未 attach 时把 hash 放回队首并撤销占位——旧实现弹出后
        // return，attach 前入队的所有 hash 永久丢失（既不预取也永不重入队）。
        _pending.insert(0, hash);
        _requested.remove(hash);
        _requestedOrder.remove(hash);
        return; // 未 attach：只收集不请求
      }
      try {
        await fetch(hash, quality);
        _prefetched++;
      } catch (e, st) {
        // fire-and-forget：失败不重试、不上抛
        _errors++;
        Log.w(_tag, 'prefetch $hash failed: $e');
        Log.e(_tag, 'prefetch $hash stack', e, st);
      }
    } finally {
      _draining = false;
      if (!_disposed && _pending.isNotEmpty) {
        _schedule(spacing);
      }
    }
  }
}
