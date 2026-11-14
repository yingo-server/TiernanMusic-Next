// L6 session · 播放编排会话（纯 Dart，无 Widget）
// 职责：持有 L5 的 QueueState/PlayerState/reducer 与 L4 音频引擎门面，
// 向 L7 暴露不可变快照 + 意图方法。L7 只 ref.watch 快照、发意图，零状态机。
import '../bridges/bridge_core.dart'
    show SongBrief, AudioEngine, NullAudioEngine, JustAudioEngine,
        AudioEvent, AudioEventType, MusicAudioHandler, NotificationMeta,
        NotificationControls, initNotification;
import '../bridges/bridge_logic.dart'
    show PlaybackService, HistoryRecorder, PlayMode, QueueState, PlayerState,
        PlayerStatus, StartLoad, Playing, Paused, Progress, Completed,
        ErrorAction, SeekTo, SetVolume, SetSpeed, Resume, Stop,
        playbackReducer, Log;


const String _tag = 'session.playback';

/// L7 消费的唯一快照（不可变；字段全 final）。
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queue,
    required this.player,
    required this.mode,
    required this.speed,
    required this.volume,
  });

  final QueueState queue;
  final PlayerState player;
  final PlayMode mode;
  final double speed;
  final double volume;

  SongBrief? get current => player.current;
}

/// 全局播放会话（单例）。构造由 session/bootstrap 装配时调用 [attach]。
class PlaybackSession {
  PlaybackSession._();
  static final PlaybackSession instance = PlaybackSession._();

  PlaybackService? _service;
  HistoryRecorder? _history;
  AudioEngine _engine = NullAudioEngine();
  final List<void Function()> _listeners = <void Function()>[];

  /// 订阅播放态变更（L7 用；与 flutter ChangeNotifier 同形，session 零 flutter）。
  void addListener(void Function() listener) {
    try {
      _listeners.add(listener);
    } catch (e, st) {
      Log.e(_tag, 'addListener failed', e, st);
    }
  }

  void removeListener(void Function() listener) {
    try {
      _listeners.remove(listener);
    } catch (e, st) {
      Log.e(_tag, 'removeListener failed', e, st);
    }
  }

  /// 队列变化回调（bootstrap 接给 CacheService 做 upcoming 预读）。
  void Function(List<String> hashes)? onQueueChanged;
  MusicAudioHandler? _notification;
  String _quality = '128';

  QueueState _queue = const QueueState();
  PlayerState _player = const PlayerState();

  PlaybackSnapshot get snapshot => PlaybackSnapshot(
        queue: _queue,
        player: _player,
        mode: _queue.mode,
        speed: _player.speed,
        volume: _player.volume,
      );

  /// bootloader/session 装配唯一入口（引擎默认 NullAudioEngine，安全静音）。
  void attach({
    required PlaybackService service,
    HistoryRecorder? history,
    AudioEngine? engine,
    String quality = '128',
  }) {
    try {
      _service = service;
      _history = history;
      if (engine != null) _engine = engine;
      // 成熟库 just_audio 默认接入；若外部已注入引擎（测试/替换）则尊重注入。
      if (engine == null && _engine is NullAudioEngine) {
        final just = JustAudioEngine(onEvent: _onEngineEvent);
        _engine = just;
        // 通知栏：成熟库 audio_service，控制回调绑定回本会话（无反向 import）。
        initNotification(
          just.rawPlayer,
          NotificationControls(
            onNext: next,
            onPrev: prev,
          ),
        ).then((h) {
          _notification = h;
          Log.d(_tag, 'notification ready=${h != null}');
        }).catchError((Object e, StackTrace st) {
          Log.w(_tag, 'notification unavailable: $e');
        });
      }
      _quality = quality.isEmpty ? '128' : quality;
      Log.d(_tag, 'attached quality=$_quality');
      _notify();
    } catch (e, st) {
      Log.e(_tag, 'attach failed', e, st);
    }
  }

  /// L4 引擎事件 → L5 reducer（session 是唯一翻译点，L7 无状态机）。
  void _onEngineEvent(AudioEvent event) {
    try {
      switch (event.type) {
        case AudioEventType.progress:
          onProgress(event.positionMs < 0 ? _player.positionMs : event.positionMs,
              durationMs: event.durationMs);
          break;
        case AudioEventType.playing:
          _emit(playbackReducer(_player, const Playing()));
          break;
        case AudioEventType.paused:
          _emit(playbackReducer(_player, const Paused()));
          break;
        case AudioEventType.completed:
          onCompleted();
          break;
        case AudioEventType.error:
          _emit(playbackReducer(_player,
              ErrorAction('引擎播放失败')));
          break;
      }
    } catch (e, st) {
      Log.e(_tag, 'engine event failed', e, st);
    }
  }

  void _notify() {
    try {
      for (final l in List<void Function()>.of(_listeners)) {
        try {
          l();
        } catch (e, st) {
          Log.e(_tag, 'listener failed', e, st);
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'notify failed', e, st);
    }
  }

  void _emit(PlayerState next, {QueueState? queue}) {
    try {
      if (queue != null) _queue = queue;
      _player = next;
      _notify();
    } catch (e, st) {
      Log.e(_tag, 'emit failed', e, st);
    }
  }

  /// 播放单曲：队列替换为 [song] 并从 0 起播。
  Future<void> playSong(SongBrief song) async {
    await _start(const <SongBrief>[], 0, song: song);
  }

  /// 播放整个列表（歌单/搜索结果/专辑详情共用）。
  Future<void> playAll(List<SongBrief> songs, int start) async {
    if (songs.isEmpty) return;
    // 缓存 ⊃ 预读：队列变化即预热后续曲目（bootstrap 绑定 CacheService）。
    onQueueChanged?.call(
        songs.map((s) => s.hash).where((h) => h.isNotEmpty).toList());
    await _start(songs, start);
  }

  Future<void> _start(List<SongBrief> songs, int start, {SongBrief? song}) async {
    try {
      final q = song != null
          ? const QueueState().replaceQueue(<SongBrief>[song], 0)
          : const QueueState().replaceQueue(songs, start);
      final cur = q.current;
      if (cur == null) return;
      final loading = playbackReducer(_player, StartLoad(cur, index: q.index));
      _emit(loading, queue: q);
      final src = await _service?.resolvePlaySource(cur, _quality);
      if (src == null || !src.ok) {
        _emit(playbackReducer(_player,
            ErrorAction(src?.error?.toString() ?? '播放源不可播或需登录')));
        return;
      }
      // 本地已下载优先，其次在线主链。
      final target = src.localPath ?? src.urls.first;
      await _engine.play(target);
      _emit(playbackReducer(_player, Playing()), queue: q);
      _history?.recordPlay(cur, 0);
      _notification?.updateMetadata(NotificationMeta(
        title: cur.name.isEmpty ? cur.hash : cur.name,
        artist: cur.singer,
        artUri: cur.cover.isEmpty ? null : cur.cover,
        durationMs: src.timeLengthSec * 1000,
      ));
    } catch (e, st) {
      Log.e(_tag, 'start failed', e, st);
      _emit(playbackReducer(_player, ErrorAction('$e')));
    }
  }

  void toggle() {
    try {
      if (_player.status == PlayerStatus.playing) {
        _engine.pause();
        _emit(playbackReducer(_player, const Paused()));
      } else {
        _engine.resume();
        _emit(playbackReducer(_player, const Resume()));
      }
    } catch (e, st) {
      Log.e(_tag, 'toggle failed', e, st);
    }
  }

  void pause() {
    try {
      _engine.pause();
      _emit(playbackReducer(_player, const Paused()));
    } catch (e, st) {
      Log.e(_tag, 'pause failed', e, st);
    }
  }

  Future<void> next() async {
    try {
      final q = _queue.next();
      if (q == null || q.current == null) return;
      await _start(q.items, q.index);
    } catch (e, st) {
      Log.e(_tag, 'next failed', e, st);
    }
  }

  Future<void> prev() async {
    try {
      final q = _queue.prev();
      if (q == null || q.current == null) return;
      await _start(q.items, q.index);
    } catch (e, st) {
      Log.e(_tag, 'prev failed', e, st);
    }
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _queue.items.length) return;
    await _start(_queue.items, index);
  }

  void removeAt(int index) {
    try {
      final q = _queue.removeAt(index);
      _emit(_player, queue: q);
    } catch (e, st) {
      Log.e(_tag, 'removeAt failed', e, st);
    }
  }

  void insertNext(SongBrief song) {
    try {
      _emit(_player, queue: _queue.insert(song));
    } catch (e, st) {
      Log.e(_tag, 'insertNext failed', e, st);
    }
  }

  void setMode(PlayMode mode) {
    try {
      _emit(_player, queue: _queue.withMode(mode));
    } catch (e, st) {
      Log.e(_tag, 'setMode failed', e, st);
    }
  }

  void seek(int ms) {
    try {
      _engine.seek(ms);
      _emit(playbackReducer(_player, SeekTo(ms)));
    } catch (e, st) {
      Log.e(_tag, 'seek failed', e, st);
    }
  }

  void setVolume(double v) {
    try {
      _engine.setVolume(v);
      _emit(playbackReducer(_player, SetVolume(v)));
    } catch (e, st) {
      Log.e(_tag, 'setVolume failed', e, st);
    }
  }

  void setSpeed(double v) {
    try {
      _engine.setSpeed(v);
      _emit(playbackReducer(_player, SetSpeed(v)));
    } catch (e, st) {
      Log.e(_tag, 'setSpeed failed', e, st);
    }
  }

  void setQuality(String q) {
    try {
      if (q.isEmpty || q == _quality) return;
      _quality = q;
      final cur = _player.current;
      if (cur != null) _start(_queue.items, _queue.index);
      Log.d(_tag, 'quality=$q');
    } catch (e, st) {
      Log.e(_tag, 'setQuality failed', e, st);
    }
  }

  void onProgress(int positionMs, {int durationMs = -1, int bufferMs = -1}) {
    _emit(playbackReducer(_player,
        Progress(positionMs: positionMs, durationMs: durationMs, bufferMs: bufferMs)));
  }

  void onCompleted() {
    _emit(playbackReducer(_player, const Completed()));
    next();
  }

  void stop() {
    try {
      _engine.stop();
      _emit(playbackReducer(_player, const Stop()), queue: const QueueState());
    } catch (e, st) {
      Log.e(_tag, 'stop failed', e, st);
    }
  }
}
