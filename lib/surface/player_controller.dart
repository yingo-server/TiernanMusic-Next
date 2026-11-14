// L6 surface · PlayerController（riverpod StateNotifier）
// 持有 QueueState + PlayerState，对外提供播放控制方法；playback 依赖注入的
// resolver（PlaybackService.resolvePlaySource）与批5 just_audio 引擎抽象。
// 铁律：每方法 try/catch + Log；本文件属 L6，只 import flutter/riverpod/桥。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridges/bridge_core.dart'
    show SongBrief, KeyValueSettings, StoragePaths, fromPref, toPlayUrlQuality;
import '../bridges/bridge_logic.dart'
    show Log, PrefetchEngine, HistoryRecorder, PlaySource, QueueState,
        PlayerState, PlayerStatus, PlayMode, PlaybackAction, StartLoad,
        Playing, Paused, Progress, Completed, ErrorAction, SeekTo,
        QueueJump, SetVolume, Resume, Stop, SetSpeed, playbackReducer;

import 'audio/audio_engine.dart' show AudioEngine, NullAudioEngine;
import 'audio/audio_service_bridge.dart' show MinimalAudioHandler;

export 'audio/audio_engine.dart' show AudioEngine, NullAudioEngine;

const String _tag = 'surface.player';

void _d(String msg) {
  try { Log.d(_tag, msg); } catch (e, st) {
    // Log 自身失败：兜底 print（不可再调 Log，否则递归）。
    // ignore: avoid_print
    print('$_tag: $msg (log failed: $e)');
  }
}

void _e(String msg, Object? err, StackTrace? st) {
  try { Log.e(_tag, msg, err, st); } catch (e, st) {
    // Log 自身失败：兜底 print（不可再调 Log，否则递归）。
    // ignore: avoid_print
    print('$_tag: $msg ERR=$err ST=$st (log failed: $e)');
  }
}

/// 倍速偏好门面（bridge_core 的 KeyValueSettings）：注入优先，
/// 未注入时懒取 StoragePaths.I；失败 Log 留痕返回 null，不阻断播放。
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

/// 从 KeyValueSettings 恢复倍速（键 preferred_speed，失败降级 1.0）。
/// getDouble 兼容历史字符串/数值，越界 clamp。
double _readSpeed(KeyValueSettings? injected) {
  try {
    final v = _settingsOf(injected)?.getDouble('preferred_speed') ?? 1.0;
    return v.isNaN ? 1.0 : v.clamp(0.5, 2.0);
  } catch (e, st) {
    _e('read preferred_speed failed', e, st);
    return 1.0;
  }
}

/// 偏好串 toPref（魔法档带 magic_ 前缀）→ 播放裸名：fromPref→toPlayUrlQuality；
/// 兼容历史 getInt 数值；读不到/失败返回 fallback（构造参数 quality 兜底）。
String _readPlayQuality(KeyValueSettings? injected, String fallback) {
  try {
    final s = _settingsOf(injected);
    final v = s?.getString('preferred_quality') ?? s?.getInt('preferred_quality')?.toString();
    return (v == null || v.trim().isEmpty) ? fallback : toPlayUrlQuality(fromPref(v));
  } catch (e, st) { _e('read preferred_quality failed', e, st); return fallback; }
}

// ── 组合状态：队列 + 播放器 ──

/// 不可变组合快照（StateNotifier 单状态约束）。
class PlayerSnapshot {
  const PlayerSnapshot({this.queue = const QueueState(), this.player = const PlayerState()});

  final QueueState queue;
  final PlayerState player;

  /// 倍速（0.5~2.0；唯一真源为 L5 PlayerState.speed，默认 1.0）。
  double get speed => player.speed;

  PlayerSnapshot copyWith({QueueState? queue, PlayerState? player, double? speed}) {
    try {
      final nextPlayer = player ??
          (speed == null ? this.player : this.player.copyWith(speed: speed));
      return PlayerSnapshot(queue: queue ?? this.queue, player: nextPlayer);
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
    required PlaySourceResolver resolver, AudioEngine? engine,
    String quality = '128', KeyValueSettings? settings,
    PrefetchEngine? prefetch, MinimalAudioHandler? audioHandler,
    HistoryRecorder? historyRecorder,
  })  : _resolver = resolver,
        _prefetch = prefetch,
        _engine = engine ?? NullAudioEngine(),
        _quality = _readPlayQuality(settings, quality),
        _settings = settings,
        _audioHandler = audioHandler,
        _historyRecorder = historyRecorder,
        super(PlayerSnapshot(player: PlayerState(speed: _readSpeed(settings)))) {
    _d('init engine=${_engine.runtimeType} quality=$_quality speed=${state.speed}');
    // 预读回调：只解析播放源（不落盘），命中缓存时播放更快。
    _prefetch?.attach((hash, q) async {
      try { await _resolver(SongBrief(hash: hash), q); }
      catch (e, st) { _e('prefetch resolve failed $hash', e, st); }
    });
  }

  final PlaySourceResolver _resolver;
  final AudioEngine _engine;
  String _quality;
  final KeyValueSettings? _settings;
  final PrefetchEngine? _prefetch; // 队列变化预热播放源（可选）
  final MinimalAudioHandler? _audioHandler; // 通知栏 metadata（可选）
  final HistoryRecorder? _historyRecorder; // 播放历史（待 assembly 注入）
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
      // 预读：当前队列后续曲目（hash 维度；近的先算）。
      try {
        _prefetch?.updateUpcoming(
          <String>[for (final s in songs) s.hash],
          start,
        );
      } catch (e, st) {
        _e('prefetch updateUpcoming failed', e, st);
      }
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
      final removingCurrent = index == state.queue.index;
      final q = state.queue.removeAt(index);
      // 删当前曲后 queue.current 已指向下一首：经 QueueJump reducer 同步
      // player.current（不扩接口），并保留原播放态；空队列则清 current。
      final nextSong = q.current;
      final player = removingCurrent
          ? (nextSong != null
              ? playbackReducer(state.player, QueueJump(nextSong, index: q.index))
                  .copyWith(status: state.player.status)
              : state.player.copyWith(clearCurrent: true))
          : state.player;
      state = state.copyWith(queue: q, player: player);
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

  /// 切换播放档位：参数是 toPlayUrlQuality 裸名串（非 toPref 偏好串）。
  /// 空串忽略；有当前曲则用新档重新解析并起播，无当前曲只更新字段。
  void setQuality(String q) {
    try {
      if (q.trim().isEmpty) { _d('setQuality ignored empty'); return; }
      _quality = q.trim();
      _d('setQuality $_quality');
      if (state.queue.current == null) return;
      unawaited(() async {
        try { await _startCurrent(); } catch (e, st) { _e('setQuality restart failed', e, st); }
      }());
    } catch (e, st) { _e('setQuality failed $q', e, st); }
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
      // 起播成功：推通知栏 metadata + 落播放历史，各自 try/catch 不阻断播放；
      // 参数按 audio_service_bridge / history_recorder 的真实签名。
      try {
        final durSec = src.timeLengthSec > 0 ? src.timeLengthSec : song.durationSec;
        _audioHandler?.updateMetadata(
          title: song.name.isEmpty ? song.hash : song.name,
          artist: song.singer,
          album: song.albumName.isEmpty ? null : song.albumName,
          durationMs: durSec > 0 ? durSec * 1000 : null,
        );
      } catch (e, st) {
        _e('updateMetadata failed ${song.hash}', e, st);
      }
      final recorder = _historyRecorder;
      if (recorder != null) {
        try {
          await recorder.recordPlay(song, 0); // 起播事件：已播时长 0
        } catch (e, st) {
          _e('recordPlay failed ${song.hash}', e, st);
        }
      }
      if (_engine is NullAudioEngine) {
        // NullEngine 无真实回调，用 1s ticker 模拟推进；真实引擎走
        // handleEngineAction（positionStream → Progress）。
        final durMs = (src.timeLengthSec > 0
            ? src.timeLengthSec
            : song.durationSec > 0 ? song.durationSec : 0) * 1000;
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
