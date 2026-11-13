// inflight.dart — L4 core 请求合并器（单飞 in-flight coalescing）
//
// 作用：同一 key 的并发请求只执行一次，其余等待者共享同一个 Future。
// 键维度由调用方自行拼接（建议：method + path + 排序后 query + userid），
// 本类不感知业务语义，只负责按字符串 key 合并。
//
// 语义：
//  - 任务完成/失败后在 finally 中移除 key；失败不缓存，后续请求重新执行。
//  - timeout 只作用于等待者（不取消底层任务），超时抛 TimeoutException 并计数。
//  - 任务抛异常时，所有等待者收到同一异常对象（不吞）。
//  - clear() 仅清空等待表（测试/登出用），不取消已发出的底层请求。

import 'dart:async';

import '../../bridges/bridge_kernel.dart';

/// 统计计数器
class InFlightStats {
  int started = 0; // 首次真正执行的任务数
  int coalesced = 0; // 被合并的等待者数
  int failed = 0; // 任务失败次数
  int timedOut = 0; // 等待者超时次数

  @override
  String toString() =>
      'InFlightStats(started=$started, coalesced=$coalesced, '
      'failed=$failed, timedOut=$timedOut)';
}

/// 单飞合并器：同一 key 并发请求只执行一次。
class InFlight<T> {
  final Map<String, Future<T>> _pending = {};
  final InFlightStats _stats = InFlightStats();

  InFlightStats get stats => _stats;

  /// key 是否正在执行中
  bool has(String key) => _pending.containsKey(key);

  /// 当前进行中的请求数
  int get pendingCount => _pending.length;

  /// 清空等待表（不取消已发出的底层请求）。
  void clear() {
    try {
      _pending.clear();
      logD('InFlight', 'clear: pending table emptied');
    } catch (e, st) {
      logE('InFlight', 'clear failed', e, st);
    }
  }

  /// 执行或合并请求。timeout 仅作用于本次调用的等待侧。
  Future<T> run(String key, Future<T> Function() task,
      {Duration? timeout}) {
    final existing = _pending[key];
    if (existing != null) {
      _stats.coalesced++;
      logD('InFlight',
          'coalesced on key=$key (coalesced=${_stats.coalesced})');
      return _awaitWithTimeout(key, existing, timeout);
    }

    _stats.started++;
    final future = _execute(key, task);
    // 立即登记：_execute 同步段内已注册失败钩子前，防止并发窗口二次创建。
    _pending[key] = future;
    logD('InFlight', 'started key=$key (started=${_stats.started})');
    return _awaitWithTimeout(key, future, timeout);
  }

  Future<T> _execute(String key, Future<T> Function() task) {
    final f = () async {
      try {
        return await task();
      } catch (e, st) {
        _stats.failed++;
        logE('InFlight', 'task failed key=$key (failed=${_stats.failed})',
            e, st);
        rethrow;
      } finally {
        _pending.remove(key);
      }
    }();
    return f;
  }

  Future<T> _awaitWithTimeout(String key, Future<T> f, Duration? timeout) {
    if (timeout == null) return f;
    return f.timeout(timeout).catchError((Object e) {
      if (e is TimeoutException) {
        _stats.timedOut++;
        logW('InFlight',
            'waiter timeout key=$key (timedOut=${_stats.timedOut})');
      }
      throw e;
    });
  }
}
