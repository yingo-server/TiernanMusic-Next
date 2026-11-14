// L6 surface/audio · 音频引擎抽象与空实现（从 player_controller 拆出）
// 目的：控制文件 ≤500 行；接口与空实现无状态，独立便于测试与替换。
import 'dart:async';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.audio.engine';

/// 本文件局部日志便捷函数（从 player_controller 拆出后独立保留）。
void _d(String msg) => Log.d(_tag, msg);

abstract class AudioEngine {
  /// 播放：urlOrPath 为在线直链或本地文件绝对路径。
  Future<void> play(String urlOrPath);
  Future<void> pause();
  Future<void> resume();
  /// 跳转到毫秒位置。
  Future<void> seek(int positionMs);
  Future<void> stop();
  /// 音量 0.0 ~ 1.0。
  Future<void> setVolume(double volume);
  /// 倍速 0.5 ~ 2.0（越界由实现方 clamp）。
  Future<void> setSpeed(double speed);
  /// 引擎释放（页面/队列销毁时调用）。
  Future<void> dispose();
}

/// 占位引擎：不发声，只保证状态流可跑通（批5 替换为 just_audio 实现）。
class NullAudioEngine implements AudioEngine {
  @override
  Future<void> play(String urlOrPath) async {
    _d('NullAudioEngine.play $urlOrPath');
  }

  @override
  Future<void> pause() async => _d('NullAudioEngine.pause');

  @override
  Future<void> resume() async => _d('NullAudioEngine.resume');

  @override
  Future<void> seek(int positionMs) async => _d('NullAudioEngine.seek $positionMs');

  @override
  Future<void> stop() async => _d('NullAudioEngine.stop');

  @override
  Future<void> setVolume(double volume) async =>
      _d('NullAudioEngine.setVolume $volume');

  @override
  Future<void> setSpeed(double speed) async =>
      _d('NullAudioEngine.setSpeed $speed (no-op)');

  @override
  Future<void> dispose() async => _d('NullAudioEngine.dispose');
}

