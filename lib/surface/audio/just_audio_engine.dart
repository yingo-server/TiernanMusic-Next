// L6 surface · JustAudioEngine（批5-A）
// AudioEngine 抽象契约的真实实现：内部持有 just_audio 的 AudioPlayer 实例，
// 把 just_audio 的状态流映射为 logic 层 PlaybackAction，经构造注入的 onAction
// 回调交给 PlayerController 消费。
// 铁律：surface 层；每方法 try/catch + Log('surface.audio')；
// 只 import flutter / just_audio / bridge_logic / 本层。
import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../bridges/bridge_logic.dart'
    show
        PlaybackAction,
        Playing,
        Paused,
        Progress,
        Completed,
        ErrorAction,
        Log;
import '../player_controller.dart' show AudioEngine;

const String _tag = 'surface.audio';

void _d(String msg) {
  try {
    Log.d(_tag, msg);
  } catch (_) {}
}

void _e(String msg, Object? err, StackTrace? st) {
  try {
    Log.e(_tag, msg, err, st);
  } catch (_) {}
}

/// 真实音频引擎：just_audio 封装。
/// 用法：
/// ```dart
/// final engine = JustAudioEngine(onAction: (a) => controller.dispatch(a));
/// ```
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({required this.onAction, AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    try {
      _bindStreams();
      _d('init player=${_player.runtimeType}');
    } catch (e, st) {
      _e('init failed', e, st);
    }
  }

  /// 播放状态动作出口（PlayerController 消费）。
  final void Function(PlaybackAction action) onAction;

  final AudioPlayer _player;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _errSub;
  bool _disposed = false;

  // 暴露底层 player，audio_service_bridge 转发用（不扩大契约）。
  AudioPlayer get rawPlayer => _player;

  // ── 流绑定 ──

  void _bindStreams() {
    // playerStateStream → playing/paused/completed
    _stateSub = _player.playerStateStream.listen((ps) {
      try {
        if (_disposed) return;
        final processing = _player.processingState;
        if (processing == ProcessingState.completed) {
          onAction(const Completed());
          return;
        }
        if (ps.playing) {
          onAction(Playing(durationMs: _durationMs));
        } else {
          onAction(Paused(positionMs: _positionMs));
        }
      } catch (e, st) {
        _e('stateStream map failed', e, st);
      }
    }, onError: (Object e, StackTrace st) {
      _e('stateStream error', e, st);
      _safeAction(ErrorAction('playerStateStream: $e'));
    });

    // positionStream → Progress
    _posSub = _player.positionStream.listen((pos) {
      try {
        if (_disposed) return;
        onAction(Progress(
          positionMs: pos.inMilliseconds,
          durationMs: _durationMs,
          bufferMs: _bufferMs,
        ));
      } catch (e, st) {
        _e('positionStream map failed', e, st);
      }
    }, onError: (Object e, StackTrace st) {
      _e('positionStream error', e, st);
    });

    // playbackEventStream errorEvent → ErrorAction
    _errSub = _player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace st) {
      try {
        _e('playbackEvent error', e, st);
        _safeAction(ErrorAction('playback: $e'));
      } catch (err, st2) {
        _e('error map failed', err, st2);
      }
    });
  }

  int get _durationMs {
    try {
      return _player.duration?.inMilliseconds ?? 0;
    } catch (_) {
      return 0;
    }
  }

  int get _positionMs {
    try {
      return _player.position.inMilliseconds;
    } catch (_) {
      return 0;
    }
  }

  int get _bufferMs {
    try {
      final b = _player.bufferedPosition;
      return b.inMilliseconds;
    } catch (_) {
      return 0;
    }
  }

  void _safeAction(PlaybackAction action) {
    try {
      if (_disposed) return;
      onAction(action);
    } catch (e, st) {
      _e('onAction callback failed', e, st);
    }
  }

  // ── AudioEngine 契约实现 ──

  @override
  Future<void> play(String urlOrPath) async {
    try {
      _d('play src(${urlOrPath.startsWith('http') ? 'url' : 'file'}) len=${urlOrPath.length}');
      if (urlOrPath.startsWith('http')) {
        await _player.setUrl(urlOrPath);
      } else {
        await _player.setFilePath(urlOrPath);
      }
      await _player.play();
    } catch (e, st) {
      _e('play failed', e, st);
      _safeAction(ErrorAction('play failed: $e'));
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
      _safeAction(Paused(positionMs: _positionMs));
    } catch (e, st) {
      _e('pause failed', e, st);
    }
  }

  @override
  Future<void> resume() async {
    try {
      // completed 态重新起播需先 seek 回起点。
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    } catch (e, st) {
      _e('resume failed', e, st);
      _safeAction(ErrorAction('resume failed: $e'));
    }
  }

  @override
  Future<void> seek(int positionMs) async {
    try {
      final ms = positionMs < 0 ? 0 : positionMs;
      await _player.seek(Duration(milliseconds: ms));
      _d('seek $ms');
    } catch (e, st) {
      _e('seek failed $positionMs', e, st);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      _d('stop');
    } catch (e, st) {
      _e('stop failed', e, st);
    }
  }

  /// 音量 0.0 ~ 1.0（越界截断）。
  Future<void> setVolume(double volume) async {
    try {
      var v = volume.isNaN ? 1.0 : volume;
      if (v < 0.0) v = 0.0;
      if (v > 1.0) v = 1.0;
      await _player.setVolume(v);
      _d('setVolume $v');
    } catch (e, st) {
      _e('setVolume failed $volume', e, st);
    }
  }

  /// 倍速 0.5 ~ 2.0（越界截断）。
  Future<void> setSpeed(double speed) async {
    try {
      var s = speed.isNaN ? 1.0 : speed;
      if (s < 0.5) s = 0.5;
      if (s > 2.0) s = 2.0;
      await _player.setSpeed(s);
      _d('setSpeed $s');
    } catch (e, st) {
      _e('setSpeed failed $speed', e, st);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_disposed) return;
      _disposed = true;
      await _stateSub?.cancel();
      await _posSub?.cancel();
      await _errSub?.cancel();
      await _player.dispose();
      _d('dispose done');
    } catch (e, st) {
      _e('dispose failed', e, st);
    }
  }
}

