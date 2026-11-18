// lib/platform · Web 平台实现
//
// 浏览器权限模型：通知需授权、剪贴板写需用户手势、文件系统用 input[type=file]。
// 窗口不可控（无标题栏 / 无窗口尺寸 API）。
library;

import 'dart:async';

import '../capability/capability_gateway.dart';
import '../capability/platform_capabilities.dart';
import 'capability/web_capability_gateway.dart';

/// 平台能力集合（Web）。
PlatformCapabilities buildPlatformCapabilities() => const PlatformCapabilities(
  isDesktop: false,
  isMobile: false,
  isWeb: true,
  supportsCustomTitleBar: false,
  supportsWindowSize: false,
  supportsTray: false,
  supportsGlobalShortcuts: false,
  supportsFileDialog: true, // <input type=file>
  supportsDragDrop: true, // HTML5 drag&drop
  supportsMultiWindow: false,
  supportsNotifications: true, // 需浏览器授权
  supportsClipboardWrite: true, // 需用户手势
  supportsMediaSession: true,
  supportsScreenReader: true,
  requiresGestureNavigation: false,
);

/// 权限网关（Web）。
CapabilityGateway buildCapabilityGateway() => WebCapabilityGateway();

/// 窗口服务（Web：不可用）。
WindowService buildWindowService() => const _WebWindowService();

class _WebWindowService implements WindowService {
  const _WebWindowService();

  @override
  bool get isAvailable => false;

  @override
  Future<void> ensureInitialized({
    required double minWidth,
    required double minHeight,
    required bool customTitleBar,
  }) async {}

  @override
  void startDragging() {}

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
