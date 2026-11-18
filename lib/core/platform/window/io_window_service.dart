// lib/platform/window · dart:io 平台的窗口服务（bitsdojo_window + window_manager）
//
// 职责分离：
// - bitsdojo_window：取原生窗口句柄、置标题栏透明/无边框（自定义标题栏用）
// - window_manager：最小尺寸/最大化/全屏/焦点事件
// 二者都只在本文件调用，上层（surface）经 bridge 拿抽象接口。
library;

import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../capability/platform_capabilities.dart';

class IoWindowService implements WindowService {
  IoWindowService();

  bool _initialized = false;
  bool _maximized = false;
  bool _focused = true;
  final StreamController<WindowEvent> _events =
      StreamController<WindowEvent>.broadcast();

  @override
  bool get isAvailable => defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Object? get nativeHandle {
    try {
      return bitsdojo.windowManager.nativeHandle;
    } catch (e) {
      debugPrint('platform.window: nativeHandle unavailable: $e');
      return null;
    }
  }

  /// 桌面端初始化（须在 runApp 前 await）。
  Future<void> ensureInitialized({
    required double minWidth,
    required double minHeight,
    required bool customTitleBar,
  }) async {
    if (_initialized || !isAvailable) return;
    try {
      await windowManager.ensureInitialized();
      final opts = WindowOptions(
        minimumSize: Size(minWidth, minHeight),
        titleBarStyle: customTitleBar
            ? TitleBarStyle.hidden
            : TitleBarStyle.normal,
        windowButtonVisibility: customTitleBar
            ? false
            : true,
        skipTaskbar: false,
        center: false,
      );
      await windowManager.waitUntilReadyToShow(opts, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      windowManager.addListener(_onWindowListener);
      _initialized = true;
    } catch (e) {
      debugPrint('platform.window: init failed: $e');
    }
  }

  void _onWindowListener() {
    try {
      final nowMax = windowManager.isMaximized();
      if (nowMax != _maximized) {
        _maximized = nowMax;
        _events.add(nowMax ? WindowEvent.maximized : WindowEvent.unmaximized);
      }
      final nowFocus = windowManager.isFocused;
      if (nowFocus != _focused) {
        _focused = nowFocus;
        _events.add(nowFocus ? WindowEvent.focused : WindowEvent.unfocused);
      }
    } catch (e) {
      debugPrint('platform.window: listener error: $e');
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
  bool get isMaximized {
    try {
      return isAvailable ? windowManager.isMaximized() : false;
    } catch (e) {
      return _maximized;
    }
  }

  @override
  bool get isFocused {
    try {
      return isAvailable ? windowManager.isFocused : true;
    } catch (e) {
      return _focused;
    }
  }

  @override
  Stream<WindowEvent> get events => _events.stream;

  void dispose() {
    try {
      if (_initialized) windowManager.removeListener(_onWindowListener);
    } catch (e) {
      debugPrint('platform.window: dispose failed: $e');
    }
    _events.close();
  }
}
