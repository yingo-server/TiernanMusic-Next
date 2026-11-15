// inflight.dart — L4 core 请求合并器（单飞 in-flight coalescing）· 线C 阶段2 确认
//
// 作用：同一 key 的并发请求只执行一次，其余等待者共享同一个 Future。
// 键维度由调用方自行拼接（建议：method + path + 排序后 query + userid），
// 本类不感知业务语义，只负责按字符串 key 合并。
//
// 语义（阶段2 逐项确认，均为「已满足」，无需改逻辑）：
//  - 任务完成/失败后在 finally 中移除 key（失败不缓存，后续请求重新执行）。
//  - timeout 只作用于等待者（不取消底层任务）：f.timeout 不触碰 _pending，
//    底层 Future 继续执行并由 finally 自行移除；超时抛 TimeoutException 并计数。
//  - 任务抛异常时，所有等待者收到同一异常对象（共享同一 Future，不吞）。
//  - clear() 仅清空等待表（测试/登出用），不取消已发出的底层请求。
//
// 阶段2 补强（不改语义）：
//  · clear() 加 try/catch + Log（六桥留痕铁律），并保留「不取消底层任务」语义；
//    注意 _pending.clear() 会让后续同 key 请求成为新任务，而旧任务完成时
//    finally 的 _pending.remove(key) 只删同字符串键——这是既有语义，本版不改。
//  · 新增只读 getter（started/coalesced/failed/timedOut/pendingCount），让
//    统计可被上层公开读取；KugouClient 未转出这些 getter → CacheService
//    仍无法取到底层真实计数（见 docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md C1）。
//  · 纯 dart:async，无新第三方包。≤200 行。

import 'dart:async';

import '../../bridges/bridge_kernel.dart';

const String _tag = 'InFlight';

/// 单飞合并器：同一 key 并发请求只执行一次。
class InFlight<T> {
  final Map<String, Future<T>> _pending = <String, Future<T>>{};
  // 统计计数（私有字段，经只读 getter 暴露；外部不可写）。
  int _started = 0;
  int _coalesced = 0;
  int _failed = 0;
  int _timedOut = 0;

  /// key 是否正在执行中。
  bool has(String key) => _pending.containsKey(key);

  /// 当前进行中的请求数。
  int get pendingCount => _pending.length;

  /// 真实启动过的底层任务数。
  int get started => _started;

  /// 真实被合并（共享既有 Future）的等待次数。
  int get coalesced => _coalesced;

  /// 真实失败次数。
  int get failed => _failed;

  /// 真实等待侧超时次数（底层任务未被取消）。
  int get timedOut => _timedOut;

  /// 清空等待表（不取消已发出的底层请求）。
  /// 桥 try/catch + Log 留痕；失败也不上抛，避免登出流程被日志异常中断。
  void clear() {
    try {
      final int n = _pending.length;
      _pending.clear();
      logD(_tag, 'clear: pending table emptied (was $n)');
    } catch (e, st) {
      logE(_tag, 'clear failed', e, st);
    }
  }

  /// 执行或合并请求。timeout 仅作用于本次调用的等待侧。
  Future<T> run(String key, Future<T> Function() task, {Duration? timeout}) {
    final Future<T>? existing = _pending[key];
    if (existing != null) {
      _coalesced++;
      logD(_tag, 'coalesced on key=$key (coalesced=$_coalesced)');
      return _awaitWithTimeout(key, existing, timeout);
    }

    _started++;
    final Future<T> future = _execute(key, task);
    // 立即登记：_execute 同步段内已注册失败钩子前，防止并发窗口二次创建。
    _pending[key] = future;
    logD(_tag, 'started key=$key (started=$_started)');
    return _awaitWithTimeout(key, future, timeout);
  }

  Future<T> _execute(String key, Future<T> Function() task) {
    return () async {
      try {
        return await task();
      } catch (e, st) {
        _failed++;
        logE(_tag, 'task failed key=$key (failed=$_failed)', e, st);
        rethrow;
      } finally {
        // 完成/失败一律移除；失败不缓存，后续请求重新执行。
        _pending.remove(key);
      }
    }();
  }

  /// 超时只包裹等待侧 Future：底层任务继续执行、仍由 _execute 的 finally
  /// 自行移除 key；不取消、不干预底层任务。
  Future<T> _awaitWithTimeout(String key, Future<T> f, Duration? timeout) {
    if (timeout == null) return f;
    return f.timeout(timeout).catchError((Object e) {
      if (e is TimeoutException) {
        _timedOut++;
        logW(_tag, 'waiter timeout key=$key (timedOut=$_timedOut)');
      }
      throw e;
    });
  }
}
