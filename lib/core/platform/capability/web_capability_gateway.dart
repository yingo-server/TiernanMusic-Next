// lib/platform/capability · Web 平台的权限网关实现
//
// 浏览器权限模型：
// - notification: Notification.requestPermission() → granted / denied / default
// - clipboard: 写入需用户手势（navigator.clipboard.writeText 在非手势下抛）
// - fileRead: <input type=file> 由 file_selector 处理，网关只报状态
library;

import 'dart:async';

import '../../capability/capability_gateway.dart';

class WebCapabilityGateway implements CapabilityGateway {
  final Map<String, CapState> _states = <String, CapState>{};

  @override
  Future<CapState> status(String capId) async {
    final cached = _states[capId];
    if (cached != null) return cached;
    return _put(
      capId,
      CapState(id: capId, status: CapStatus.denied, reason: 'not_requested'),
    );
  }

  @override
  Future<CapState> request(String capId) async {
    final s = await status(capId);
    if (s.status == CapStatus.granted) return s;
    return _put(
      capId,
      CapState(id: capId, status: CapStatus.denied, reason: 'browser_denied'),
    );
  }

  /// 上层拿到浏览器真实授权结果后回写。
  void markResult(String capId, CapStatus status, {String? reason}) {
    _put(capId, CapState(id: capId, status: status, reason: reason));
  }

  @override
  Future<bool> openSettings() async => false;

  @override
  Stream<CapState> watch(String capId) => const Stream<CapState>.empty();

  CapState _put(String capId, CapState state) {
    _states[capId] = state;
    return state;
  }
}
