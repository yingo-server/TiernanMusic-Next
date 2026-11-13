// L4 core/net · 网络阶段播报（纯 Dart，无 UI 依赖）
// 目的：让「>500ms 的网络阶段必须可见」有单一事实源（旧版 network_phase 同语义）。
// - 枚举粒度：resolving（解析播放地址/详情）/ buffering（引擎装载首帧）
// - 深度计数支持并发嵌套：同阶段重复 begin 计数递增，归零才回落 idle
// - broadcast 流：多组件订阅互不影响；UI 侧指示器自行节流显示
// 铁律：所有公开方法 try/catch + Log 留痕；不 import flutter。

import 'dart:async';

import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'core.networkPhase';

/// 网络阶段（idle 表示无活动阶段）。
enum NetworkPhase { idle, resolving, buffering }

/// 一次阶段切换事件。
class NetworkPhaseEvent {
  NetworkPhaseEvent(this.phase, {this.detail = ''})
      : at = DateTime.now();

  final NetworkPhase phase;

  /// 诊断上下文（歌曲 hash 等），UI 不得直接展示。
  final String detail;

  /// 事件时刻（本地时钟，仅诊断用）。
  final DateTime at;

  @override
  String toString() => 'NetworkPhaseEvent(${phase.name}, $detail)';
}

/// 全局阶段播报器（单例）。begin/end 必须由同一段代码配对调用，
/// 推荐 `try { begin(...); ... } finally { end(...); }`。
class NetworkPhaseTracker {
  NetworkPhaseTracker._();

  static final NetworkPhaseTracker instance = NetworkPhaseTracker._();

  StreamController<NetworkPhaseEvent> _controller =
      StreamController<NetworkPhaseEvent>.broadcast();

  NetworkPhase _current = NetworkPhase.idle;
  int _resolvingDepth = 0;
  int _bufferingDepth = 0;

  /// 阶段事件流（broadcast）。
  Stream<NetworkPhaseEvent> get events => _controller.stream;

  /// 当前阶段（并发时 resolving 优先于 buffering 表达给用户）。
  NetworkPhase get current => _current;

  /// 进入某阶段（重复 begin 同阶段安全，计数递增）。
  void begin(NetworkPhase phase, {String detail = ''}) {
    try {
      if (phase == NetworkPhase.idle) return;
      _bump(phase, 1);
      _push(_current, detail);
    } catch (e, st) {
      Log.e(_tag, 'begin ${phase.name} failed', e, st);
    }
  }

  /// 离开某阶段（与 begin 配对；计数归零才回落 idle）。
  void end(NetworkPhase phase) {
    try {
      if (phase == NetworkPhase.idle) return;
      _bump(phase, -1);
      _push(_current, '');
    } catch (e, st) {
      Log.e(_tag, 'end ${phase.name} failed', e, st);
    }
  }

  /// 测试/登出用：清零并回落 idle（不关闭事件流）。
  void reset() {
    try {
      _resolvingDepth = 0;
      _bufferingDepth = 0;
      _current = NetworkPhase.idle;
      _push(NetworkPhase.idle, 'reset');
    } catch (e, st) {
      Log.e(_tag, 'reset failed', e, st);
    }
  }

  void _bump(NetworkPhase phase, int delta) {
    switch (phase) {
      case NetworkPhase.resolving:
        _resolvingDepth = (_resolvingDepth + delta).clamp(0, 1 << 30);
        break;
      case NetworkPhase.buffering:
        _bufferingDepth = (_bufferingDepth + delta).clamp(0, 1 << 30);
        break;
      case NetworkPhase.idle:
        break;
    }
    if (_resolvingDepth > 0) {
      _current = NetworkPhase.resolving;
    } else if (_bufferingDepth > 0) {
      _current = NetworkPhase.buffering;
    } else {
      _current = NetworkPhase.idle;
    }
  }

  void _push(NetworkPhase phase, String detail) {
    try {
      if (_controller.isClosed) return;
      _controller.add(NetworkPhaseEvent(phase, detail: detail));
    } catch (e, st) {
      Log.e(_tag, 'push failed', e, st);
    }
  }
}
