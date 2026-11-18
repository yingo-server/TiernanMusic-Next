// lib/platform · 不支持平台的降级实现（Web 以外的非 io 平台 / 测试）
//
// 能力集合全部按「无」返回；窗口服务不可用；权限网关用内存实现。
library;

import 'dart:async';

import '../capability/capability_gateway.dart';
import '../capability/platform_capabilities.dart';

/// 平台能力（降级：全部不支持）。
PlatformCapabilities buildPlatformCapabilities() => PlatformCapabilities.none;

/// 权限网关（降级：全部 unsupported）。
CapabilityGateway buildCapabilityGateway() => InMemoryCapabilityGateway();

/// 窗口服务（降级：不可用）。
WindowService buildWindowService() => const _UnavailableWindowService();

class _UnavailableWindowService implements WindowService {
  const _UnavailableWindowService();

  @override
  bool get isAvailable => false;

  @override
  Object? get nativeHandle => null;

  @override
  Future<void> setMinimumSize(WindowSizeRequest request) async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> maximize() async {}

  @override
  Future<void> unmaximize() async {}

  @override
  Future<void> close() async {}

  @override
  bool get isMaximized => false;

  @override
  bool get isFocused => true;

  @override
  Stream<WindowEvent> get events => const Stream<WindowEvent>.empty();
}
