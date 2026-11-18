// L5 logic/player · 播放器不可变状态（纯 Dart，零 IO，零 flutter import）
// 每个方法 try/catch + Log（tag: logic.state）。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show SongBrief;

const String _tag = 'logic.state';

/// 播放器状态。
enum PlayerStatus { idle, loading, playing, paused, completed, error }

/// 不可变播放器状态。
class PlayerState {
  const PlayerState({
    this.status = PlayerStatus.idle,
    this.positionMs = 0,
    this.durationMs = 0,
    this.bufferMs = 0,
    this.volume = 1.0,
    this.speed = 1.0,
    this.current,
    this.lastError = '',
    this.lastErrorCode = '',
    this.sourceKind = 'kugou',
  });

  final PlayerStatus status;
  final int positionMs;
  final int durationMs;
  final int bufferMs;
  final double volume; // 0.0 ~ 1.0
  final double speed; // 0.5 ~ 2.0
  final SongBrief? current;
  final String lastError;

  /// 结构化错误码（审查修复 阶段B B7）：供 L7 按码取 i18n 文案与决定可操作项
  /// （如 needsVerification → 显示"重试"）。只放语义码，不放文案（文案归 L7/i18n）。
  /// 取值：'needsVerification' / 'noPrivilege' / 'notFound' / 'network' / ''。
  final String lastErrorCode;

  /// 音源类型（批3-F2）：'kugou' = 常规酷狗音源；'mv-audio' = MV 音频兜底。
  /// 其他取值视同 'kugou'；构造默认 'kugou' 不破坏现有调用。
  final String sourceKind;

  bool get isPlaying {
    try {
      return status == PlayerStatus.playing;
    } catch (e, st) {
      Log.e(_tag, 'isPlaying failed', e, st);
      return false;
    }
  }

  /// 进度 0.0~1.0（duration 未知/为 0 返回 0）。
  double get progress {
    try {
      if (durationMs <= 0) return 0.0;
      final p = positionMs / durationMs;
      if (p < 0) return 0.0;
      if (p > 1) return 1.0;
      return p;
    } catch (e, st) {
      Log.e(_tag, 'progress failed', e, st);
      return 0.0;
    }
  }

  PlayerState copyWith({
    PlayerStatus? status,
    int? positionMs,
    int? durationMs,
    int? bufferMs,
    double? volume,
    double? speed,
    SongBrief? current,
    bool clearCurrent = false,
    String? lastError,
    bool clearError = false,
    String? lastErrorCode,
    String? sourceKind,
  }) {
    try {
      return PlayerState(
        status: status ?? this.status,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        bufferMs: bufferMs ?? this.bufferMs,
        volume: volume ?? this.volume,
        speed: speed ?? this.speed,
        current: clearCurrent ? null : (current ?? this.current),
        lastError: clearError ? '' : (lastError ?? this.lastError),
        lastErrorCode: clearError
            ? ''
            : (lastErrorCode ?? this.lastErrorCode),
        sourceKind: sourceKind ?? this.sourceKind,
      );
    } catch (e, st) {
      Log.e(_tag, 'copyWith failed', e, st);
      return this;
    }
  }

  @override
  String toString() {
    try {
      return 'PlayerState(status=$status, pos=$positionMs/$durationMs, '
          'buf=$bufferMs, vol=$volume, speed=$speed, '
          'current=${current?.hash ?? '-'}, err=$lastError, '
          'src=$sourceKind)';
    } catch (e, st) {
      Log.e(_tag, 'toString failed', e, st);
      return 'PlayerState(<unavailable>)';
    }
  }
}
