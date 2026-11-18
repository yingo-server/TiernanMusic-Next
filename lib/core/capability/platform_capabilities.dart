// L4 core/capability · 平台能力集合（平台无关的「有什么」描述）
//
// 与「平台实现（怎么做）」分离：
// - 本文件只回答「当前平台支持哪些能力」；
// - 怎么做（弹窗/对话框/原生调用）在 lib/platform/**，经条件导入注入。
//
// surface/logic **禁止**询问 Platform.isXxx；一律问这里的能力布尔量。
library;

import 'capability_gateway.dart';

/// 平台能力集合（不可变快照）。
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.isDesktop,
    required this.isMobile,
    required this.isWeb,
    required this.supportsCustomTitleBar,
    required this.supportsWindowSize,
    required this.supportsTray,
    required this.supportsGlobalShortcuts,
    required this.supportsFileDialog,
    required this.supportsDragDrop,
    required this.supportsMultiWindow,
    required this.supportsNotifications,
    required this.supportsClipboardWrite,
    required this.supportsMediaSession,
    required this.supportsScreenReader,
    required this.requiresGestureNavigation,
  });

  /// 桌面（Windows/Linux/macOS）。
  final bool isDesktop;

  /// 移动（Android/iOS）。
  final bool isMobile;

  /// Web。
  final bool isWeb;

  /// 可用自定义窗口标题栏（Windows/Linux）。
  final bool supportsCustomTitleBar;

  /// 可设置窗口最小尺寸/最大化。
  final bool supportsWindowSize;

  /// 系统托盘。
  final bool supportsTray;

  /// 全局快捷键。
  final bool supportsGlobalShortcuts;

  /// 原生文件对话框。
  final bool supportsFileDialog;

  /// 拖拽文件入窗。
  final bool supportsDragDrop;

  /// 多窗口。
  final bool supportsMultiWindow;

  /// 桌面通知。
  final bool supportsNotifications;

  /// 剪贴板写入（Web 需用户手势）。
  final bool supportsClipboardWrite;

  /// 媒体会话（锁屏控制）。
  final bool supportsMediaSession;

  /// 屏幕阅读器（各平台均支持）。
  final bool supportsScreenReader;

  /// 手势导航（移动端底部手势条会遮挡，需额外安全区）。
  final bool requiresGestureNavigation;

  /// 全部为 false 的空实现（不支持的平台 / 测试用）。
  static const PlatformCapabilities none = PlatformCapabilities(
    isDesktop: false,
    isMobile: false,
    isWeb: false,
    supportsCustomTitleBar: false,
    supportsWindowSize: false,
    supportsTray: false,
    supportsGlobalShortcuts: false,
    supportsFileDialog: false,
    supportsDragDrop: false,
    supportsMultiWindow: false,
    supportsNotifications: false,
    supportsClipboardWrite: false,
    supportsMediaSession: false,
    supportsScreenReader: false,
    requiresGestureNavigation: false,
  );
}

/// 窗口尺寸请求（桌面）。
class WindowSizeRequest {
  const WindowSizeRequest({
    required this.width,
    required this.height,
    this.minWidth,
    this.minHeight,
  });

  final double width;
  final double height;
  final double? minWidth;
  final double? minHeight;
}

/// 窗口服务（平台无关接口；实现见 lib/platform/window）。
abstract class WindowService {
  /// 是否可用（移动/Web 为 false）。
  bool get isAvailable;

  /// 当前窗口原生句柄（供 bitsdojo_window 使用；不可用时为 null）。
  Object? get nativeHandle;

  /// 设置最小窗口尺寸。
  Future<void> setMinimumSize(WindowSizeRequest request);

  /// 设置窗口标题（会同步到原生标题栏）。
  Future<void> setTitle(String title);

  /// 最小化 / 最大化 / 还原 / 关闭。
  Future<void> minimize();

  Future<void> maximize();

  Future<void> unmaximize();

  Future<void> close();

  /// 当前是否最大化。
  bool get isMaximized;

  /// 是否聚焦（用于标题栏失焦降对比）。
  bool get isFocused;

  /// 窗口状态变化流（聚焦/最大化变化）。
  Stream<WindowEvent> get events;
}

/// 窗口事件。
enum WindowEvent { focused, unfocused, maximized, unmaximized, closed }
