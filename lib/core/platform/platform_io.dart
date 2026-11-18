// lib/platform · dart:io 平台实现（Windows/Linux/macOS/Android/iOS）
//
// 唯一允许出现 Platform.isXxx 的地方（平台层本身）。
// 上层（logic/surface）一律通过能力网关/能力集合感知差异。
library;

import 'dart:async';
import 'dart:io';

import '../capability/capability_gateway.dart';
import '../capability/platform_capabilities.dart';
import 'capability/io_capability_gateway.dart';
import 'window/io_window_service.dart';

bool _isDesktop() =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

bool _isMobile() => Platform.isAndroid || Platform.isIOS;

/// 平台能力集合（io 平台）。
PlatformCapabilities buildPlatformCapabilities() {
  final desktop = _isDesktop();
  final mobile = _isMobile();
  return PlatformCapabilities(
    isDesktop: desktop,
    isMobile: mobile,
    isWeb: false,
    // 自定义标题栏：Windows/Linux 可用；macOS 保留原生红绿灯（仅做顶部色带）。
    supportsCustomTitleBar:
        Platform.isWindows || Platform.isLinux,
    supportsWindowSize: desktop,
    supportsTray: desktop,
    supportsGlobalShortcuts: desktop,
    supportsFileDialog: true,
    supportsDragDrop: desktop,
    supportsMultiWindow: desktop,
    supportsNotifications: true,
    supportsClipboardWrite: true,
    supportsMediaSession: true,
    supportsScreenReader: true,
    requiresGestureNavigation: mobile,
  );
}

/// 权限网关（io 平台）。
CapabilityGateway buildCapabilityGateway() => IoCapabilityGateway();

/// 窗口服务（io 平台）。
WindowService buildWindowService() => IoWindowService();
