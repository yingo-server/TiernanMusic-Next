// L6 surface · PlayerController（riverpod StateNotifier）
// 持有 QueueState + PlayerState，对外提供播放控制方法。
// 播放真正执行依赖注入的 resolver（PlaybackService.resolvePlaySource 门面签名）
// + AudioEngine 抽象（批5 用 just_audio 实现；本批 NullAudioEngine 占位）。
// 铁律：每方法 try/catch + Log；本文件属 L6，只 import flutter/riverpod/桥。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridges/bridge_core.dart'
    show SongBrief, KeyValueSettings, StoragePaths;
import '../bridges/bridge_logic.dart' show Log;
import '../bridges/bridge_logic.dart'
    show PlaySource, QueueState, PlayerState, PlayerStatus, PlayMode,
        PlaybackAction, StartLoad, Playing, Paused, Progress, Completed,
        ErrorAction, SeekTo, QueueJump, SetVolume, Resume, Stop,
        SetSpeed, playbackReducer;

const String _tag = 'surface.player';

void _d(String msg) {
  try {
    Log.d(_tag, msg);
  } catch (e, st) {
    // Log 自身失败：兜底 print（不可再调 Log，否则递归）。
    // ignore: avoid_print
    print('$_tag: $msg (log failed: $e)');
  }
}

void _e(String msg, Object? err, StackTrace? st) {
  try {
    Log.e(_tag, msg, err, st);
  } catch (e, st) {
    // Log 自身失败：兜底 print（不可再调 Log，否则递归）。
    // ignore: avoid_print
    print('$_tag: $msg ERR=$err ST=$st (log failed: $e)');
  }
}

/// 倍速偏好存储门面（经 bridge_core 暴露的 KeyValueSettings）。
/// 注入优先；未注入时懒取 StoragePaths.I 单例（bootloader 已装配），
/// 任何失败都 Log 留痕并返回 null（不静默吞、不阻断播放）。
KeyValueSettings? _fallbackSettings;

KeyValueSettings? _settingsOf(KeyValueSettings? injected) {
  try {
    if (injected != null) return injected;
    final existing = _fallbackSettings;
    if (existing != null) return existing;
    final created = KeyValueSettings(StoragePaths.I);
    _fallbackSettings = created;
    return created;
  } catch (e, st) {
    _e('resolve KeyValueSettings failed', e, st);
    return null;
  }
}

/// 从 KeyValueSettings 恢复倍速（键 preferred_speed，失败留痕降级 1.0）。
/// getDouble 兼容历史字符串值与数值，越界 clamp。
double _readSpeed(KeyValueSettings? injected) {
  try {
    final v = _settingsOf(injected)?.getDouble('preferred_speed') ?? 1.0;
    return v.isNaN ? 1.0 : v.clamp(0.5, 2.0);
  } catch (e, st) {
    _e('read preferred_speed failed', e, st);
    return 1.0;
  }
}

// ── 播放引擎抽象（批5 用 just_audio 实现 JustAudioEngine） ──

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

// ── 组合状态：队列 + 播放器 ──

/// 不可变组合快照（StateNotifier 单状态约束）。
class PlayerSnapshot {
  const PlayerSnapshot({
    this.queue = const QueueState(),
    this.player = const PlayerState(),
  });

  final QueueState queue;
  final PlayerState player;

  /// 倍速（0.5~2.0；唯一真源为 L5 PlayerState.speed，默认 1.0）。
  double get speed => player.speed;

  PlayerSnapshot copyWith({
    QueueState? queue,
    PlayerState? player,
    double? speed,
  }) {
    try {
      final nextPlayer = player ??
          (speed == null ? this.player : this.player.copyWith(speed: speed));
      return PlayerSnapshot(
          queue: queue ?? this.queue, player: nextPlayer);
    } catch (e, st) {
      Log.e(_tag, 'PlayerSnapshot.copyWith failed', e, st);
      return this;
    }
  }
}

// ── 控制器 ──

/// 解析播放源门面签名：注入 (song, quality) -> PlaySource。
/// 批5 装配：PlaybackService 实例的 resolvePlaySource tear-off。
typedef PlaySourceResolver = Future<PlaySource> Function(SongBrief song, String quality);

class PlayerController extends StateNotifier<PlayerSnapshot> {
  PlayerController({
    required PlaySourceResolver resolver,
    AudioEngine? engine,
    String quality = '128',
    KeyValueSettings? settings,
  })  : _resolver = resolver,
        _engine = engine ?? NullAudioEngine(),
        _quality = quality,
        _settings = settings,
        super(PlayerSnapshot(
            player: PlayerState(speed: _readSpeed(settings)))) {
    _d('init engine=${_engine.runtimeType} quality=$_quality speed=${state.speed}');
  }

  final PlaySourceResolver _resolver;
  final AudioEngine _engine;
  final String _quality;
  final KeyValueSettings? _settings;
  Timer? _ticker;

  // ── 引擎事件入口（批5-A：JustAudioEngine onAction 回调落点） ──

  /// 引擎动作统一入口：JustAudioEngine 经 onAction 上报
  /// Playing/Paused/Progress/Completed/ErrorAction，此处分发 reducer。
  /// Completed 时由真实引擎驱动自动下一曲（非 loopOne）。
  void handleEngineAction(PlaybackAction action) {
    try {
      _dispatch(action);
      if (action is Completed) {
        _ticker?.cancel();
        if (state.queue.mode == PlayMode.loopOne) {
          _startCurrent();
        } else {
          next();
        }
      }
    } catch (e, st) {
      _e('handleEngineAction ${action.runtimeType} failed', e, st);
    }
  }

  // ── 对外播放入口 ──

  /// 单曲起播：replaceQueue 单曲列表 + resolve + engine.play。
  Future<void> playSong(SongBrief song) async {
    try {
      _d('playSong ${song.hash}');
      final q = state.queue.replaceQueue(<SongBrief>[song], 0);
      state = state.copyWith(queue: q);
      await _startCurrent();
    } catch (e, st) {
      _e('playSong failed ${song.hash}', e, st);
    }
  }

  /// 整列表起播：replaceQueue(list, start) 后从 start 播放。
  Future<void> playAll(List<SongBrief> songs, int start) async {
    try {
      _d('playAll n=${songs.length} start=$start');
      final q = state.queue.replaceQueue(songs, start);
      state = state.copyWith(queue: q);
      await _startCurrent();
    } catch (e, st) {
      _e('playAll failed', e, st);
    }
  }

  // ── 队列控制 ──

  /// 跳转到队列第 i 首（播放队列 sheet 用）。
  Future<void> playAt(int index) async {
    try {
      final items = state.queue.items;
      if (index < 0 || index >= items.length) {
        _d('playAt out of range i=$index len=${items.length}');
        return;
      }
      await playAll(items, index);
    } catch (e, st) {
      _e('playAt failed $index', e, st);
    }
  }

  /// 从队列移除第 i 首（移除当前曲时保持播放态，由引擎继续推进）。
  void removeFromQueue(int index) {
    try {
      final items = state.queue.items;
      if (index < 0 || index >= items.length) {
        _d('removeFromQueue out of range i=$index len=${items.length}');
        return;
      }
      final q = state.queue.removeAt(index);
      state = state.copyWith(queue: q);
      _d('removeFromQueue i=$index left=${q.items.length}');
    } catch (e, st) {
      _e('removeFromQueue failed $index', e, st);
    }
  }

  /// 插入到下一首播放（歌单/收藏「下一首播放」用）。
  void insertNext(SongBrief song) {
    try {
      final q = state.queue.insert(song);
      state = state.copyWith(queue: q);
      _d('insertNext ${song.hash} len=${q.items.length}');
    } catch (e, st) {
      _e('insertNext failed', e, st);
    }
  }

  Future<void> next() async {
    try {
      final q = state.queue.next();
      if (q == null) return;
      state = state.copyWith(queue: q);
      await _startCurrent();
    } catch (e, st) {
      _e('next failed', e, st);
    }
  }

  Future<void> prev() async {
    try {
      final q = state.queue.prev();
      if (q == null) return;
      state = state.copyWith(queue: q);
      await _startCurrent();
    } catch (e, st) {
      _e('prev failed', e, st);
    }
  }

  /// 播放/暂停切换（idle/loading 态下无效）。
  Future<void> toggle() async {    try {
      final p = state.player;
      if (p.status == PlayerStatus.playing) {
        _dispatch(const Paused());
        await _engine.pause();
      } else if (p.status == PlayerStatus.paused) {
        _dispatch(const Resume());
        await _engine.resume();
      } else {
        _d('toggle noop status=${p.status}');
      }
    } catch (e, st) {
      _e('toggle failed', e, st);
    }
  }

  /// 暂停（保活编排 onBackgroundPause 用；playing 态才生效）。
  Future<void> pause() async {
    try {
      if (state.player.status != PlayerStatus.playing) {
        _d('pause noop status=${state.player.status}');
        return;
      }
      _dispatch(const Paused());
      await _engine.pause();
    } catch (e, st) {
      _e('pause failed', e, st);
    }
  }

  /// 跳转进度（毫秒）。
  Future<void> seek(int positionMs) async {
    try {
      _dispatch(SeekTo(positionMs));
      await _engine.seek(positionMs);
    } catch (e, st) {
      _e('seek failed $positionMs', e, st);
    }
  }

  /// 切换播放模式 sequence → loopOne → shuffle → sequence。
  void setMode(PlayMode mode) {
    try {
      final q = state.queue.withMode(mode);
      state = state.copyWith(queue: q);
      _d('setMode $mode');
    } catch (e, st) {
      _e('setMode failed $mode', e, st);
    }
  }

  /// 倍速 0.5~2.0：越界 clamp + Log.w 留痕；经 reducer 写入
  /// PlayerState.speed（唯一真源）、引擎 setSpeed 生效，并持久化
  /// KeyValueSettings('preferred_speed')（经 bridge_core 门面）。
  Future<void> setSpeed(double speed) async {
    try {
      var s = speed.isNaN ? 1.0 : speed;
      if (s < 0.5 || s > 2.0) {
        Log.w(_tag, 'setSpeed out of range $speed, clamped to 0.5~2.0');
        s = s.clamp(0.5, 2.0);
      }
      _dispatch(SetSpeed(s));
      await _engine.setSpeed(s);
      try {
        _settingsOf(_settings)?.setDouble('preferred_speed', s);
      } catch (e, st) {
        _e('persist preferred_speed failed $s', e, st);
      }
      _d('setSpeed $s');
    } catch (e, st) {
      _e('setSpeed failed $speed', e, st);
    }
  }

  /// 音量 0.0~1.0。
  Future<void> setVolume(double volume) async {
    try {
      _dispatch(SetVolume(volume));
      await _engine.setVolume(volume);
    } catch (e, st) {
      _e('setVolume failed $volume', e, st);
    }
  }

  /// 当前倍速（唯一真源：PlayerState.speed，默认 1.0）。
  double get speed => state.speed;

  // ── 内部：起播当前曲 ──

  Future<void> _startCurrent() async {
    final song = state.queue.current;
    if (song == null) {
      _d('startCurrent empty queue');
      return;
    }
    _dispatch(StartLoad(song, index: state.queue.index));
    try {
      final src = await _resolver(song, _quality);
      if (!src.ok) {
        _dispatch(ErrorAction('resolve failed: ${src.error?.name ?? 'unknown'}'));
        return;
      }
      final urlOrPath = src.localPath ?? src.urls.first;
      await _engine.play(urlOrPath);
      if (_engine is NullAudioEngine) {
        // NullEngine 无真实回调，用 1s ticker 模拟推进；真实引擎走
        // handleEngineAction（positionStream → Progress）。
        final durMs = (src.timeLengthSec > 0
            ? src.timeLengthSec
            : song.durationSec > 0
                ? song.durationSec
                : 0) *
            1000;
        _dispatch(Playing(durationMs: durMs));
        _startTicker();
      }
    } catch (e, st) {
      _e('startCurrent failed ${song.hash}', e, st);
      _dispatch(ErrorAction('$e'));
    }
  }

  /// 占位进度推进：NullEngine 无真实回调，用 1s ticker 模拟推进。
  /// 批5 JustAudioEngine 接 positionStream 后可移除。
  void _startTicker() {
    try {
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          if (!mounted || !state.player.isPlaying) return;
          final p = state.player;
          final pos = p.positionMs + 1000;
          if (p.durationMs > 0 && pos >= p.durationMs) {
            _dispatch(const Completed());
            _ticker?.cancel();
            // 单曲循环在本层处理；其余模式自动下一曲。
            if (state.queue.mode == PlayMode.loopOne) {
              _startCurrent();
            } else {
              next();
            }
            return;
          }
          _dispatch(Progress(positionMs: pos));
        } catch (e, st) {
          _e('ticker tick failed', e, st);
        }
      });
    } catch (e, st) {
      _e('startTicker failed', e, st);
    }
  }

  /// reducer 统一入口（纯函数 + 留痕）。
  void _dispatch(PlaybackAction action) {
    try {
      final player = playbackReducer(state.player, action);
      state = state.copyWith(player: player);
      _d('dispatch ${action.runtimeType}');
    } catch (e, st) {
      _e('dispatch ${action.runtimeType} failed', e, st);
    }
  }

  @override
  void dispose() {
    try {
      _ticker?.cancel();
      _engine.stop();
      _engine.dispose();
      _d('dispose');
    } catch (e, st) {
      _e('dispose failed', e, st);
    }
    super.dispose();
  }
}

// ── 全局 provider（boot 处可 overrideWithValue 注入已装配的控制器） ──

/// 全局 provider（boot 处可 overrideWithValue 注入已装配的控制器）。
final playerProvider =
    StateNotifierProvider<PlayerController, PlayerSnapshot>((ref) {
  throw UnimplementedError(
      'playerProvider must be overridden with the assembled PlayerController '
      '(see defaultModules / bootloader)。');
});

/// 便捷读取当前 PlayerController（消费方经 ref.read 使用）。
/// 与 playerProvider 同一实例（boot 处统一 override）。
final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlayerSnapshot>((ref) {
  throw UnimplementedError(
      'playerControllerProvider must be overridden (see defaultModules)。');
});
