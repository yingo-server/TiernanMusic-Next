// tool/resolve_contract_test.dart · 76 原则「缓存 ⊃ 预读」静态契约自检
//
// V2：独立 PrefetchEngine 已删除，预读能力深度融合进 L4 core/cache/CacheService，
// 由 L6 session/bootstrap.dart 在队列变化时驱动。本测试不依赖
// flutter/isar/just_audio（本地 ARM64 Dart SDK 可跑），只校验架构事实与
// PlayResolver / QualityPolicy 的静态契约。
import 'dart:io';

int _pass = 0;
int _fail = 0;

void check(bool ok, String label) {
  if (ok) {
    _pass++;
    print('PASS  $label');
  } else {
    _fail++;
    print('FAIL  $label');
  }
}

String read(String p) => File(p).readAsStringSync();

void main() {
  // ── ① 缓存 ⊃ 预读：独立预读器不得复活 ──
  check(!File('lib/logic/player/prefetch_engine.dart').existsSync(),
      '独立 PrefetchEngine 已删除（预读归缓存）');
  final cache = read('lib/core/cache/cache_service.dart');
  check(cache.contains('Future<int> prefetch('),
      'CacheService 暴露 prefetch（缓存包容预读）');
  check(cache.contains('Future<Map<String, dynamic>> get('),
      'CacheService 暴露 get（读穿即缓存）');
  check(cache.contains('invalidateSession'),
      'CacheService 暴露换号失效');
  check(!cache.contains('extends ChangeNotifier') &&
      !cache.contains("import 'package:flutter"),
      'CacheService 零 UI 依赖');

  // ── ② L6 装配把队列变化接到缓存 ──
  final boot = read('lib/session/bootstrap.dart');
  check(boot.contains('CacheService(client)'), 'bootstrap 构造统一缓存服务');
  check(boot.contains('onQueueChanged'), 'bootstrap 接队列变化回调');
  check(boot.contains('cacheService.prefetch'), '队列变化触发预读');
  check(boot.contains('cache: cacheService'), 'AppGraph 持有缓存服务');

  // ── ③ 桥导出（L7 不碰 core 内部） ──
  final coreBridge = read('lib/bridges/bridge_core.dart');
  check(coreBridge.contains("core/cache/cache_service.dart"),
      'bridge_core 导出 CacheService');
  final sessionBridge = read('lib/bridges/bridge_session.dart');
  check(sessionBridge.contains("session/playback_session.dart"),
      'bridge_session 导出 PlaybackSession');

  // ── ④ PlayResolver / QualityPolicy 静态契约 ──
  final resolver = read('lib/logic/player/play_resolver.dart');
  final policy = read('lib/logic/player/quality_policy.dart');
  check(resolver.contains('firstHealthy') || resolver.contains('checkHealth'),
      'PlayResolver 保留主备链健康检查');
  check(policy.contains('downgradeChain'), 'QualityPolicy 保留降档链');
  check(policy.contains('privKnown'), 'QualityPolicy 保留 privKnown 三态守卫');

  // ── ⑤ L4 音频网关（成熟库） ──
  check(File('lib/core/audio/audio_gateway.dart').existsSync(),
      'L4 core/audio 网关存在');
  final gw = read('lib/core/audio/audio_gateway.dart');
  check(gw.contains('just_audio'), '音频网关使用成熟库 just_audio');
  check(!gw.contains("import 'package:flutter"), '音频网关零 Widget 依赖');

  print('---- resolve contract self-check: $_pass passed, $_fail failed ----');
  if (_fail > 0) throw StateError('resolve contract FAILED');
}
