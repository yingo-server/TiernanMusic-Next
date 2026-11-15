// L4 core/audio · 系统通知栏网关（成熟库 audio_service，零 Widget）
// 只做平台通道适配：把 audio_service 的 media control 事件转成纯回调，
// 由 L6 session 决定 next/prev/seek；本层不持有队列、不画 UI。
library;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'core.notification';

/// 通知栏元数据（纯数据；L6 起播成功后推）。
class NotificationMeta {
  const NotificationMeta({
    required this.title,
    required this.artist,
    this.artUri,
    this.durationMs = 0,
  });
  final String title;
  final String artist;
  final String? artUri;
  final int durationMs;
}

/// 控制回调（由 session 绑定，避免 handler 反向 import 上层）。
class NotificationControls {
  const NotificationControls({this.onNext, this.onPrev, this.onSeek});
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrev;
  final Future<void> Function(int ms)? onSeek;
}

/// 最小 AudioHandler：状态同步 + 控制转发。
class MusicAudioHandler extends BaseAudioHandler {
  MusicAudioHandler(this._player) {
    _bind();
  }

  final AudioPlayer _player;
  NotificationControls _controls = const NotificationControls();

  void bind(NotificationControls controls) {
    try {
      _controls = controls;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            MediaControl.play,
            MediaControl.pause,
            MediaControl.skipToNext,
          ],
        ),
      );
      Log.d(_tag, 'controls bound');
    } catch (e, st) {
      Log.e(_tag, 'bind failed', e, st);
    }
  }

  void _bind() {
    try {
      _player.playbackEventStream.listen(
        (event) {
          final playing = _player.playing;
          playbackState.add(
            playbackState.value.copyWith(
              controls: [
                MediaControl.skipToPrevious,
                MediaControl.play,
                MediaControl.pause,
                MediaControl.skipToNext,
              ],
              androidCompactActionIndices: const [0, 1, 3],
              systemActions: const {MediaAction.seek},
              processingState: const {
                ProcessingState.idle: AudioProcessingState.idle,
                ProcessingState.loading: AudioProcessingState.loading,
                ProcessingState.buffering: AudioProcessingState.buffering,
                ProcessingState.ready: AudioProcessingState.ready,
                ProcessingState.completed: AudioProcessingState.completed,
              }[event.processingState]!,
              playing: playing,
              updatePosition: event.updatePosition,
              bufferedPosition: event.bufferedPosition,
              speed: _player.speed,
            ),
          );
        },
        onError: (Object e, StackTrace st) {
          Log.e(_tag, 'event stream failed', e, st);
        },
      );
    } catch (e, st) {
      Log.e(_tag, '_bind failed', e, st);
    }
  }

  /// 推元数据（歌名/歌手/封面/时长）。
  Future<void> updateMetadata(NotificationMeta meta) async {
    try {
      mediaItem.add(
        MediaItem(
          id: meta.title.hashCode.toString(),
          title: meta.title,
          artist: meta.artist,
          artUri: meta.artUri == null ? null : Uri.parse(meta.artUri!),
          duration: meta.durationMs > 0
              ? Duration(milliseconds: meta.durationMs)
              : null,
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'updateMetadata failed', e, st);
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    try {
      await _controls.onNext?.call();
    } catch (e, st) {
      Log.e(_tag, 'skipToNext failed', e, st);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      await _controls.onPrev?.call();
    } catch (e, st) {
      Log.e(_tag, 'skipToPrevious failed', e, st);
    }
  }
}

/// 初始化 audio_service（成熟库）；失败返回 null 由调用方降级，不抛。
Future<MusicAudioHandler?> initNotification(
  AudioPlayer player,
  NotificationControls controls,
) async {
  try {
    final handler = await AudioService.init(
      builder: () => MusicAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'tiernan.music.next',
        androidNotificationChannelName: 'TiernanMusicNext',
        androidNotificationOngoing: true,
      ),
    );
    (handler as MusicAudioHandler).bind(controls);
    Log.d(_tag, 'audio_service ready');
    return handler as MusicAudioHandler;
  } catch (e, st) {
    Log.e(_tag, 'initNotification failed', e, st);
    return null;
  }
}
