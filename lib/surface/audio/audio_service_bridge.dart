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
/// - 批5-F2：系统事件 next/prev 已接（外部注入回调，见 bind）；seek 仍直连 player。
/// - TODO(art): 封面 artUrl 未接（SongBrief 无封面字段映射）；
/// - TODO(lifecycle): AudioService.init 需在宿主 main/boot 处调用，本文件不负责。
class MinimalAudioHandler extends BaseAudioHandler {
  MinimalAudioHandler({
    required AudioPlayer player,
    void Function()? onNext,
    void Function()? onPrev,
  })  : _player = player,
        _onNext = onNext,
        _onPrev = onPrev {
    try {
      // playerState → playbackState（通知栏按钮态）
      _player.playerStateStream.listen((ps) {
        try {
          final playing = ps.playing;
          playbackState.add(playbackState.value.copyWith(
            // 批5-F2：通知栏补 next/prev（队列长度未知 → 常显）。
            controls: playing
                ? <MediaControl>[
                    MediaControl.pause,
                    MediaControl.stop,
                    MediaControl.skipToPrevious,
                    MediaControl.skipToNext,
                  ]
                : <MediaControl>[
                    MediaControl.play,
                    MediaControl.stop,
                    MediaControl.skipToPrevious,
                    MediaControl.skipToNext,
                  ],
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

  /// 通知栏「下一首 / 上一首」回调（批5-F2）。
  /// bridge 不反向依赖 controller，故由装配层（modules.dart）构造完
  /// PlayerController 后经 bind 注入；未绑定时系统事件只 Log.w 不阻断。
  void Function()? _onNext;
  void Function()? _onPrev;

  /// 绑定通知栏 next/prev 回调（可在 controller 建好后调用）。
  void bind({
    required void Function() onNext,
    required void Function() onPrev,
  }) {
    try {
      _onNext = onNext;
      _onPrev = onPrev;
      Log.d(_tag, 'bind next/prev controls');
    } catch (e, st) {
      Log.e(_tag, 'bind failed', e, st);
    }
  }

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

  // ── 通知栏 next/prev（批5-F2） ──

  @override
  Future<void> skipToNext() async {
    try {
      final cb = _onNext;
      if (cb == null) {
        Log.w(_tag, 'skipToNext ignored (no callback bound)');
        await super.skipToNext();
        return;
      }
      cb();
    } catch (e, st) {
      Log.e(_tag, 'skipToNext failed', e, st);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      final cb = _onPrev;
      if (cb == null) {
        Log.w(_tag, 'skipToPrevious ignored (no callback bound)');
        await super.skipToPrevious();
        return;
      }
      cb();
    } catch (e, st) {
      Log.e(_tag, 'skipToPrevious failed', e, st);
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
