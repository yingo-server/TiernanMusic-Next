// L4 core/audio · 音频引擎网关（成熟库 just_audio，零 Widget）
// 只做 IO 适配：把 session 的 play/pause/seek 等意图映射到 AudioPlayer，
// 并把引擎状态流以「原始数值」回调给 session（session 自己转成 reducer action）。
// 铁律：try/catch + Log；dispose 取消三订阅并释放播放器。
import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'core.audio';

/// 引擎事件（纯数据，session 消费）。
class AudioEvent {
  const AudioEvent(this.type, {this.positionMs = 0, this.durationMs = 0});
  final AudioEventType type;
  final int positionMs;
  final int durationMs;
}

enum AudioEventType { playing, paused, completed, progress, error }

/// 引擎抽象（session 只认这个接口；可替换为 NullAudioEngine 做测试）。
abstract class AudioEngine {
  Future<void> play(String urlOrPath);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(int positionMs);
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

/// 空引擎：测试/装配失败兜底，不发声音也不崩。
class NullAudioEngine implements AudioEngine {
  @override
  Future<void> play(String urlOrPath) async => Log.d(_tag, 'null play');
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(int positionMs) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> dispose() async {}
}

/// just_audio 实现。构造注入 [onEvent]；可注入 [player] 便于测试。
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({required this.onEvent, AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _bind();
  }

  final void Function(AudioEvent event) onEvent;
  final AudioPlayer _player;
  bool _disposed = false;

  /// just_audio 的 PlayerState 流；用 dynamic 避免与 L5 PlayerState 同名歧义。
  StreamSubscription<dynamic>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;

  AudioPlayer get rawPlayer => _player;

  void _bind() {
    try {
      _stateSub = _player.playerStateStream.listen(
        (s) {
          if (_disposed) return;
          if (s.processingState == ProcessingState.completed) {
            onEvent(const AudioEvent(AudioEventType.completed));
          } else if (s.playing) {
            onEvent(const AudioEvent(AudioEventType.playing, durationMs: -1));
          } else {
            onEvent(const AudioEvent(AudioEventType.paused));
          }
        },
        onError: (Object e, StackTrace st) {
          Log.e(_tag, 'state stream failed', e, st);
        },
      );
      _positionSub = _player.positionStream.listen(
        (d) {
          if (_disposed) return;
          onEvent(
            AudioEvent(AudioEventType.progress, positionMs: d.inMilliseconds),
          );
        },
        onError: (Object e, StackTrace st) {
          Log.e(_tag, 'position stream failed', e, st);
        },
      );
      _durationSub = _player.durationStream.listen(
        (d) {
          if (_disposed) return;
          onEvent(
            AudioEvent(
              AudioEventType.progress,
              positionMs: -1,
              durationMs: d?.inMilliseconds ?? 0,
            ),
          );
        },
        onError: (Object e, StackTrace st) {
          Log.e(_tag, 'duration stream failed', e, st);
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'bind failed', e, st);
    }
  }

  @override
  Future<void> play(String urlOrPath) async {
    try {
      if (urlOrPath.startsWith('http')) {
        await _player.setUrl(urlOrPath);
      } else {
        await _player.setFilePath(urlOrPath);
      }
      await _player.play();
    } catch (e, st) {
      Log.e(_tag, 'play failed', e, st);
      onEvent(const AudioEvent(AudioEventType.error));
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e, st) {
      Log.e(_tag, 'pause failed', e, st);
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _player.play();
    } catch (e, st) {
      Log.e(_tag, 'resume failed', e, st);
    }
  }

  @override
  Future<void> seek(int positionMs) async {
    try {
      await _player.seek(Duration(milliseconds: positionMs));
    } catch (e, st) {
      Log.e(_tag, 'seek failed', e, st);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e, st) {
      Log.e(_tag, 'stop failed', e, st);
    }
  }

  @override
  Future<void> setVolume(double v) async {
    try {
      await _player.setVolume(v.clamp(0.0, 1.0));
    } catch (e, st) {
      Log.e(_tag, 'setVolume failed', e, st);
    }
  }

  @override
  Future<void> setSpeed(double v) async {
    try {
      await _player.setSpeed(v.clamp(0.5, 2.0));
    } catch (e, st) {
      Log.e(_tag, 'setSpeed failed', e, st);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _disposed = true;
      await _stateSub?.cancel();
      await _durationSub?.cancel();
      await _positionSub?.cancel();
      await _player.dispose();
    } catch (e, st) {
      Log.e(_tag, 'dispose failed', e, st);
    }
  }
}
