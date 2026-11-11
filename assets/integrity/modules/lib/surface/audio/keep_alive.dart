// L6 surface/audio · 后台保活编排（批5 补充）
// 职责：App 生命周期监听 + 播放态感知的保活策略。
// 原则：保活为「播放服务伴生」——只在播放中/下载中申请前台保活，
// 空闲时主动让出，避免系统资源滥用与耗电投诉。
// 铁律：surface 层；每方法 try/catch + Log('surface.keepalive')。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show PlayerState, PlayerStatus, Log;

const String _tag = 'surface.keepalive';

/// 保活编排器：
/// - [WidgetsBindingObserver] 监听前后台切换；
/// - 播放中（playing/loading/paused）→ 通知栏前台服务已由 audio_service 桥
///   提供（androidNotificationOngoing=true），此处负责生命周期记录与
///   后台时暂停策略的可配置钩子；
/// - 下载中任务由 DownloadManager 自身的 HttpClient 流维持（无需 UI 侧介入）。
class KeepAliveCoordinator with WidgetsBindingObserver {
  KeepAliveCoordinator({
    required PlayerState Function() playerStateProvider,
    this.pauseOnBackground = false,
  }) : _playerStateProvider = playerStateProvider;

  /// 当前播放状态提供者（PlayerController.state）。
  final PlayerState Function() _playerStateProvider;

  /// 后台是否自动暂停播放（默认 false：后台继续播——音乐 App 核心体验）。
  /// 可被设置页暴露为开关（批后续）。
  final bool pauseOnBackground;

  AppLifecycleState? _last;
  DateTime _sessionStart = DateTime.now();
  bool _started = false;

  /// 启动监听（AppRoot.initState 调用一次）。
  void start() {
    if (_started) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _started = true;
      Log.d(_tag, 'started');
    } catch (e, st) {
      Log.e(_tag, 'start failed', e, st);
    }
  }

  /// 停止监听（AppRoot.dispose 调用）。
  void stop() {
    try {
      if (_started) WidgetsBinding.instance.removeObserver(this);
      _started = false;
      Log.d(_tag, 'stopped');
    } catch (e, st) {
      Log.e(_tag, 'stop failed', e, st);
    }
  }

  /// 是否处于「应保活」状态：播放中或加载中。
  bool get shouldKeepAlive {
    try {
      final s = _playerStateProvider();
      return s.status == PlayerStatus.playing ||
          s.status == PlayerStatus.loading ||
          s.status == PlayerStatus.paused;
    } catch (e, st) {
      Log.e(_tag, 'shouldKeepAlive failed', e, st);
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      final prev = _last;
      _last = state;
      final playing = shouldKeepAlive;
      Log.d(_tag, 'lifecycle $prev -> $state keepAlive=$playing');
      if (state == AppLifecycleState.resumed) {
        final dur = DateTime.now().difference(_sessionStart);
        Log.d(_tag, 'backgrounded for ${dur.inSeconds}s');
        return;
      }
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _sessionStart = DateTime.now();
        if (pauseOnBackground && playing) {
          Log.d(_tag, 'pauseOnBackground engaged');
          // 暂停动作由 PlayerController 经 onBackgroundPause 回调执行（解耦）。
          onBackgroundPause?.call();
        }
        // 播放中不暂停：audio_service 前台服务保活（通知栏 ongoing）。
        // 非播放态不申请任何保活：让系统按正常策略回收。
      }
    } catch (e, st) {
      Log.e(_tag, 'didChangeAppLifecycleState failed', e, st);
    }
  }

  /// 后台自动暂停钩子（AppRoot 装配时注入 controller.pause）。
  void Function()? onBackgroundPause;
}

/// Android 原生层保活要点（AndroidManifest 由 CI 构建期生成，此处记录契约）：
/// 1. audio_service 插件自带 FOREGROUND_SERVICE + audio 权限声明（manifest merge）；
/// 2. 通知栏 channel ongoing=true（见 audio_service_bridge.dart 配置）；
/// 3. 下载走 HttpClient 流（无 UI 线程依赖），进程在前台服务存在期间自然存活；
/// 4. 不得使用 START_STICKY 粘性服务以外的非法唤醒锁——遵守各厂商后台策略，
///    后台被杀时下次冷启动由 restoreSession/DownloadStore 恢复状态。
