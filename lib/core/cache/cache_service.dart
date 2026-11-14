// L4 core/cache · 统一缓存服务（**缓存包容预读**，V2 深度融合）
//
// 用户裁定：「预读完了不就得缓存吗？缓存包容预读」——
//   prefetch() 不是独立调度器，而是 CacheService 的写入策略：
//   对预测键执行 get()，由底层 KugouClient 的 L1/L2/单飞同一路径落缓存，
//   命中时与正常请求完全同路径，无第二套状态。
// 本文件零 Widget、零 BuildContext；L6 session 只决定「预测哪些键」。
library;

import 'dart:convert';

import '../../bridges/bridge_kernel.dart' show Log;
import '../net/endpoint_registry.dart' show Endpoint;
import '../net/kugou_client.dart' show KugouClient;

const String _tag = 'core.cache';

enum CacheOrigin { network, prefetch, hit }

class CacheServiceStats {
  const CacheServiceStats({
    this.reads = 0,
    this.prefetched = 0,
    this.errors = 0,
  });
  final int reads;
  final int prefetched;
  final int errors;
}

/// 统一入口：get / prefetch / invalidate / stats。
/// 底层就是 [KugouClient.request] 自带的 L1 内存 + L2 磁盘 + 单飞，
/// 不另起缓存表、不另起调度器（深度融合）。
class CacheService {
  CacheService(this._client);

  final KugouClient _client;
  int _reads = 0;
  int _prefetched = 0;
  int _errors = 0;

  /// 正常读：业务端点请求（与预读共享同一缓存路径）。
  Future<Map<String, dynamic>> get(
    Endpoint ep,
    Map<String, Object?> params, {
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    try {
      _reads++;
      return await _client.request(ep, params, body: body);
    } catch (e, st) {
      _errors++;
      Log.e(_tag, 'get failed ep=${ep.id}', e, st);
      return <String, dynamic>{};
    }
  }

  /// 预读：缓存的**写入策略**，不是外挂引擎。
  /// 对预测请求逐个发起低优先级 get()；命中/失败都只留计数，不上抛。
  /// [requests] 每项 = (endpoint, params)；返回实际发起数。
  Future<int> prefetch(
    List<({Endpoint ep, Map<String, Object?> params})> requests, {
    int maxPerCall = 60,
  }) async {
    var n = 0;
    try {
      for (final r in requests.take(maxPerCall)) {
        try {
          await _client.request(r.ep, r.params);
          _prefetched++;
          n++;
        } catch (e, st) {
          _errors++;
          Log.w(_tag, 'prefetch failed ep=${r.ep.id}: $e');
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'prefetch batch failed', e, st);
    }
    return n;
  }

  /// 按用户/播放键使单飞等待表失效（磁盘键已含 uid，无需全清）。
  void invalidateSession() {
    try {
      _client.clearInflight();
      Log.d(_tag, 'session invalidated');
    } catch (e, st) {
      Log.e(_tag, 'invalidateSession failed', e, st);
    }
  }

  CacheServiceStats get stats => CacheServiceStats(
        reads: _reads,
        prefetched: _prefetched,
        errors: _errors,
      );

  /// 供诊断页读取序列化统计。
  String toJson() => jsonEncode(<String, Object?>{
        'reads': _reads,
        'prefetched': _prefetched,
        'errors': _errors,
      });
}
