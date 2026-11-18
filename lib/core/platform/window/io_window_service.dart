// lib/core/platform/window · dart:io 平台的窗口服务（bitsdojo + window_manager）
//
// 职责分离：
// - window_manager：窗口尺寸/最大化/关闭/焦点事件（WindowListener 范式）
// - bitsdojo_window：appWindow（原生句柄/拖拽区）由 desktop_titlebar 直接用，
//   本服务不重复封装（避免两套 API 交叉）。
// 本文件是 window_manager 唯一出现处；上层经 bridge_core 的 WindowService 抽象。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:window_manager/window_manager.dart';

import '../../capability/platform_capabilities.dart';

/// window_manager 的 WindowListener 转发到 [events] 流。
class _Listener with WindowListener {
  _Listener(this._onChange);
  final void Function() _onChange;

  @override
  void onWindowMaximize() => _onChange();

  @override
  void onWindowUnmaximize() => _onChange();

  @override
  void onWindowFocus() => _onChange();

  @override
  void onWindowBlur() => _onChange();
}

class IoWindowService implements WindowService {
  IoWindowService();

  bool _initialized = false;
  bool _maximized = false;
  bool _focused = true;
  final _Listener _listener = _Listener(_scheduleSync);
  static late final IoWindowService _self;
  final StreamController<WindowEvent> _events =
      StreamController<WindowEvent>.broadcast();

  /// windowManager.addListener 需要实例方法回调，用静态桥接。
  static void _scheduleSync() => _self._sync();

  @override
  bool get isAvailable =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Object? get nativeHandle => null; // 原生句柄由 bitsdojo appWindow 提供

  /// 桌面端初始化（须在 runApp 前 await）。
  Future<void> ensureInitialized({
    required double minWidth,
    required double minHeight,
    required bool customTitleBar,
  }) async {
    if (_initialized || !isAvailable) return;
    _self = this;
    try {
      await windowManager.ensureInitialized();
      final opts = WindowOptions(
        minimumSize: Size(minWidth, minHeight),
        titleBarStyle:
            customTitleBar ? TitleBarStyle.hidden : TitleBarStyle.normal,
        windowButtonVisibility: !customTitleBar,
        skipTaskbar: false,
        center: false,
      );
      await windowManager.waitUntilReadyToShow(opts, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      windowManager.addListener(_listener);
      _maximized = await windowManager.isMaximized();
      _initialized = true;
    } catch (e) {
      debugPrint('platform.window: init failed: $e');
    }
  }

  Future<void> _sync() async {
    try {
      final nowMax = await windowManager.isMaximized();
      if (nowMax != _maximized) {
        _maximized = nowMax;
        _events.add(nowMax ? WindowEvent.maximized : WindowEvent.unmaximized);
      }
      final nowFocus = await windowManager.isFocused();
      if (nowFocus != _focused) {
        _focused = nowFocus;
        _events.add(nowFocus ? WindowEvent.focused : WindowEvent.unfocused);
      }
    } catch (e) {
      debugPrint('platform.window: sync error: $e');
    }
  }

  @override
  Future<void> setMinimumSize(WindowSizeRequest request) async {
    if (!isAvailable) return;
    try {
      await windowManager.setMinimumSize(
        Size(request.minWidth ?? 640, request.minHeight ?? 480),
      );
    } catch (e) {
      debugPrint('platform.window: setMinimumSize failed: $e');
    }
  }

  @override
  Future<void> setTitle(String title) async {
    if (!isAvailable) return;
    try {
      await windowManager.setTitle(title);
    } catch (e) {
      debugPrint('platform.window: setTitle failed: $e');
    }
  }

  @override
  Future<void> minimize() async {
    if (!isAvailable) return;
    try {
      await windowManager.minimize();
    } catch (e) {
      debugPrint('platform.window: minimize failed: $e');
    }
  }

  @override
  Future<void> maximize() async {
    if (!isAvailable) return;
    try {
      await windowManager.maximize();
    } catch (e) {
      debugPrint('platform.window: maximize failed: $e');
    }
  }

  @override
  Future<void> unmaximize() async {
    if (!isAvailable) return;
    try {
      await windowManager.unmaximize();
    } catch (e) {
      debugPrint('platform.window: unmaximize failed: $e');
    }
  }

  @override
  Future<void> close() async {
    if (!isAvailable) return;
    try {
      await windowManager.close();
    } catch (e) {
      debugPrint('platform.window: close failed: $e');
    }
  }

  @override
  bool get isMaximized => _maximized;

  @override
  bool get isFocused => _focused;

  @override
  Stream<WindowEvent> get events => _events.stream;

  void dispose() {
    try {
      if (_initialized) windowManager.removeListener(_listener);
    } catch (e) {
      debugPrint('platform.window: dispose failed: $e');
    }
    _events.close();
  }
}
