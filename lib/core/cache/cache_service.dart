// L4 core/cache · 统一缓存服务（**缓存 ⊃ 预读**，线C 深度融合收口）
//
// 76 原则 §0：L4 core 只写 IO/缓存/传输；跨层只经六桥；桥 try/catch+Log；
// 单文件 ≤500 行；成熟库优先。
//
// 单一门面契约（线C 阶段2）：
//   · 底层唯一执行者 = [KugouClient.request] 自带的 ResourceCache(L2 磁盘)
//     + InFlight(单飞)；本文件**不造第二份异步读写、不持有第二份缓存表、
//     不持有第二套调度器**，只做「策略层」。
//   · get() 与 prefetch() 走完全相同路径：构造 (Endpoint, params, body) →
//     调用本类 get() → 转发 _client.request()；预读只是「提前发起的读」，
//     命中/落盘/单飞全部由 client 同一条路径完成（缓存包容预读）。
//   · invalidateSession() 清客户端 in-flight 等待表（KugouClient.clearInflight
//     真实存在，见 kugou_client.dart:55）；磁盘键自带 uid 维度，不越权清磁盘。
//
// 统计口径（线C 诚实化）：KugouClient 的 _cache / _inflight 为私有 final 且
// **无任何公开 getter**，因此本门面无法读取 L2 真实命中/写入/淘汰计数。
// [CacheServiceStats] 的 hits/writes/evictions 一律为 0 并通过
// [CacheServiceStats.exposeRealCounters] / `source` 明示「未接线」，绝不伪造
// 数值；reads/prefetched/errors 仅为门面自身的调用计数（真实但非底层计数）。
// 如需真实计数，须由线A在 KugouClient 暴露只读 getter（待线A收口，见
// docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md 缓存结论 C1）。
//
// 本文件零 Widget、零 BuildContext、零 dart:io；L6 session 只决定「预测哪些键」。
library;

import 'dart:convert';

import '../../bridges/bridge_kernel.dart' show Log;
import '../net/endpoint_registry.dart' show Endpoint;
import '../net/kugou_client.dart' show KugouClient;

const String _tag = 'core.cache';

/// 缓存来源标记（供诊断/埋点分类；本门面不再据此分支，仅保留桥导出兼容）。
enum CacheOrigin { network, prefetch, hit }

/// 缓存服务统计快照。
///
/// reads / prefetched / errors = 门面自身调用计数（真实）。
/// hits / writes / evictions = 底层 L2 真实计数，**当前固定 0**：
/// KugouClient 未暴露 ResourceCache.stats() / InFlight 计数的公开 getter，
/// 门面不得臆造。exposeRealCounters=false、source 说明原因。
class CacheServiceStats {
  const CacheServiceStats({
    this.reads = 0,
    this.prefetched = 0,
    this.errors = 0,
    this.hits = 0,
    this.writes = 0,
    this.evictions = 0,
    this.exposeRealCounters = false,
    this.source = kFacadeOnlySource,
  });

  /// 底层真实计数未接线时的来源说明常量。
  static const String kFacadeOnlySource =
      'facade-only; KugouClient has no public cache/inflight stats getter';

  /// 正常读（含换号后的读）发起次数。
  final int reads;

  /// 预读（提前发起的读）成功次数。
  final int prefetched;

  /// 门面捕获的失败次数。
  final int errors;

  /// L2 缓存真实命中数（未接线 → 恒 0）。
  final int hits;

  /// L2 缓存真实写入数（未接线 → 恒 0）。
  final int writes;

  /// L2 缓存真实淘汰数（未接线 → 恒 0）。
  final int evictions;

  /// 是否反映了底层真实计数（当前恒 false）。
  final bool exposeRealCounters;

  /// 计数来源说明（诊断页可直接展示，避免把 0 误读为「无缓存活动」）。
  final String source;

  Map<String, Object?> toMap() => <String, Object?>{
    'reads': reads,
    'prefetched': prefetched,
    'errors': errors,
    'hits': hits,
    'writes': writes,
    'evictions': evictions,
    'exposeRealCounters': exposeRealCounters,
    'source': source,
  };
}

/// 统一入口：get / prefetch / invalidate / stats（策略层门面）。
///
/// 底层就是 [KugouClient.request] 的 L2 磁盘缓存 + 单飞，本类不另起缓存表、
/// 不另起调度器、不另起异步读写（深度融合、单一真源）。
class CacheService {
  CacheService(this._client);

  final KugouClient _client;

  // 门面自身调用计数（非底层 L2 计数；底层计数无公开 getter，见类注释）。
  int _reads = 0;
  int _prefetched = 0;
  int _errors = 0;

  /// 正常读：业务端点请求。
  /// 只负责「构造 + 转发 + try/catch+Log」，缓存命中/落盘/单飞全在 client。
  /// 失败返回空 Map（门面既有降级语义，不改变调用方契约）。
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

  /// 预读：缓存的**写入策略**，不是外挂引擎、不是独立调度器。
  ///
  /// 只构造预测请求并调用本类 [get]（与正常读完全同路径，无第二套状态）；
  /// 命中/落盘/单飞由 client 执行。get 已吞异常并留痕，故此处无重复 catch。
  /// [requests] 每项 = (endpoint, params)；返回实际发起数。
  Future<int> prefetch(
    List<({Endpoint ep, Map<String, Object?> params})> requests, {
    int maxPerCall = 60,
  }) async {
    var n = 0;
    try {
      for (final r in requests.take(maxPerCall)) {
        await get(r.ep, r.params);
        _prefetched++;
        n++;
        Log.d(_tag, 'prefetch issued ep=${r.ep.id}');
      }
    } catch (e, st) {
      // 构造/迭代层的兜底留痕；单次请求失败已由 get 处理。
      _errors++;
      Log.e(_tag, 'prefetch batch failed', e, st);
    }
    return n;
  }

  /// 按用户/播放键使单飞等待表失效（磁盘键已含 uid，无需全清）。
  /// [KugouClient.clearInflight] 真实存在（kugou_client.dart:55-61），无需臆造。
  void invalidateSession() {
    try {
      _client.clearInflight();
      Log.d(_tag, 'session invalidated (client inflight cleared)');
    } catch (e, st) {
      Log.e(_tag, 'invalidateSession failed', e, st);
    }
  }

  /// 统计：底层 L2 真实计数固定 0 且标注 source，不伪造。
  CacheServiceStats get stats => CacheServiceStats(
    reads: _reads,
    prefetched: _prefetched,
    errors: _errors,
  );

  /// 供诊断页读取序列化统计（含「未接线」说明，避免 0 被误读）。
  String toJson() => jsonEncode(stats.toMap());
}
