// L6 surface · audio_service 桥（批5-A 精简版）
// audio_service 的 AudioHandler 最小实现：通知栏 metadata（title/artist）+
// play/pause/stop 转发到 JustAudioEngine。
// 铁律：surface 层；每方法 try/catch + Log('surface.audio')。
// 只 import flutter / audio_service / just_audio / bridge_logic / 本层。
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.audio';

/// 最小 AudioHandler：
/// - 外部注入 just_audio 的 AudioPlayer（来自 JustAudioEngine.rawPlayer），
///   play/pause/stop 直接转发，不另建播放链路。
/// - 通知栏 metadata 由 [updateMetadata] 推送（title/artist，album/artUri 可选）。
/// 未完成项（批5-A 精简，TODO 批5-B/后续批）：
/// - TODO(queue): playbackState 的系统事件（seek/next/prev）未接队列控制；
/// - TODO(art): 封面 artUrl 未接（SongBrief 无封面字段映射）；
/// - TODO(lifecycle): AudioService.init 需在宿主 main/boot 处调用，本文件不负责。
class MinimalAudioHandler extends BaseAudioHandler {
  MinimalAudioHandler({required AudioPlayer player}) : _player = player {
    try {
      // playerState → playbackState（通知栏按钮态）
      _player.playerStateStream.listen((ps) {
        try {
          final playing = ps.playing;
          playbackState.add(playbackState.value.copyWith(
            controls: playing
                ? [MediaControl.pause, MediaControl.stop]
                : [MediaControl.play, MediaControl.stop],
            processingState: _mapProcessing(_player.processingState),
            playing: playing,
            updatePosition: _player.position,
            bufferedPosition: _player.bufferedPosition,
            speed: _player.speed,
          ));
        } catch (e, st) {
          Log.e(_tag, 'playbackState sync failed', e, st);
        }
      }, onError: (Object e, StackTrace st) {
        Log.e(_tag, 'playerStateStream error', e, st);
      });
    } catch (e, st) {
      Log.e(_tag, 'MinimalAudioHandler init failed', e, st);
    }
  }

  final AudioPlayer _player;

  /// 推送通知栏 metadata（title/artist 必填，其余可空）。
  void updateMetadata({
    required String title,
    required String artist,
    String? album,
    String? artUri,
    int? durationMs,
  }) {
    try {
      mediaItem.add(MediaItem(
        id: 'tiernan_music_next://current',
        title: title,
        artist: artist,
        album: album,
        artUri: artUri != null ? Uri.tryParse(artUri) : null,
        duration: durationMs != null && durationMs > 0
            ? Duration(milliseconds: durationMs)
            : null,
      ));
      Log.d(_tag, 'updateMetadata title=$title artist=$artist');
    } catch (e, st) {
      Log.e(_tag, 'updateMetadata failed', e, st);
    }
  }

  AudioProcessingState _mapProcessing(ProcessingState s) {
    try {
      switch (s) {
        case ProcessingState.idle:
          return AudioProcessingState.idle;
        case ProcessingState.loading:
          return AudioProcessingState.loading;
        case ProcessingState.buffering:
          return AudioProcessingState.buffering;
        case ProcessingState.ready:
          return AudioProcessingState.ready;
        case ProcessingState.completed:
          return AudioProcessingState.completed;
      }
    } catch (e) {
      Log.w(_tag, 'mapProcessing fallback ERR=$e');
      return AudioProcessingState.ready;
    }
  }

  // ── 通知栏按钮转发 ──

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } catch (e, st) {
      Log.e(_tag, 'handler play failed', e, st);
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e, st) {
      Log.e(_tag, 'handler pause failed', e, st);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      await super.stop();
    } catch (e, st) {
      Log.e(_tag, 'handler stop failed', e, st);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e, st) {
      Log.e(_tag, 'handler seek failed', e, st);
    }
  }
}

/// 装配入口：宿主 boot 处调用（需在 runApp 前后按 audio_service 要求时机）。
/// 返回 handler 供 PlayerController 侧推 metadata。
/// TODO(批5-A 未完成项)：AudioService.init 的 androidNotificationChannel 配置
/// 细化（channelId/description/importance）交由批5-B 定。
Future<MinimalAudioHandler> initAudioService(AudioPlayer player) async {
  try {
    return await AudioService.init(
      builder: () => MinimalAudioHandler(player: player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.tiernan.music.next.audio',
        androidNotificationChannelName: 'TiernanMusicNext 播放',
        androidNotificationOngoing: true,
      ),
    );
  } catch (e, st) {
    Log.e(_tag, 'initAudioService failed', e, st);
    rethrow;
  }
}
