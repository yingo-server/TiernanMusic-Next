// lib/platform/capability · dart:io 平台的权限网关实现
//
// 桌面端：无运行时权限 → 除用户主动选择目录外，文件能力按「作用域内可用」返回。
// 移动端：通知需运行时权限（Android 13+ POST_NOTIFICATIONS），由上层通过
//        插件请求；此处仅提供状态与「去设置」引导。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../capability/capability_gateway.dart';

class IoCapabilityGateway implements CapabilityGateway {
  IoCapabilityGateway();

  final Map<String, CapState> _states = <String, CapState>{};
  final Map<String, StreamController<CapState>> _watchers =
      <String, StreamController<CapState>>{};

  bool get _isMobile => defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<CapState> status(String capId) async {
    final cached = _states[capId];
    if (cached != null) return cached;
    // 桌面端除通知外均视为可用；移动端通知默认未授权。
    if (capId == CapId.notification && _isMobile) {
      return _put(
        capId,
        const CapState(id: CapId.notification, status: CapStatus.denied),
      );
    }
    if (capId == CapId.notification && !_isMobile) {
      return _put(
        capId,
        const CapState(id: CapId.notification, status: CapStatus.granted),
      );
    }
    return _put(
      capId,
      CapState(id: capId, status: CapStatus.granted),
    );
  }

  @override
  Future<CapState> request(String capId) async {
    // 桌面端请求即视为授予（无系统弹窗）；移动端由上层插件先行请求后调用
    // [markResult] 回写真实结果。
    final s = await status(capId);
    if (s.status == CapStatus.granted) return s;
    return _put(
      capId,
      CapState(id: capId, status: CapStatus.denied, reason: 'request_required'),
    );
  }

  /// 由上层（拿到真实系统结果后）回写状态。
  void markResult(String capId, CapStatus status, {String? reason}) {
    _put(capId, CapState(id: capId, status: status, reason: reason));
  }

  @override
  Future<bool> openSettings() async => false; // 需平台插件，桌面默认不支持

  @override
  Stream<CapState> watch(String capId) {
    final c = _watchers.putIfAbsent(
      capId,
      () => StreamController<CapState>.broadcast(),
    );
    return c.stream;
  }

  CapState _put(String capId, CapState state) {
    _states[capId] = state;
    final c = _watchers[capId];
    if (c != null && !c.isClosed) c.add(state);
    return state;
  }
}
