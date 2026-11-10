// L5 logic/player · 播放 reducer（纯函数，零 IO，零 flutter import，禁 dart:io/网络层）
// 输入 (PlayerState, PlaybackAction) → 输出新 PlayerState。
// 铁律：reducer 不产生副作用；失败动作返回新状态并写 lastError（tag: logic.reducer）。
import '../../bridges/bridge_kernel.dart' show Log;
import 'player_state.dart';
import '../../bridges/bridge_core.dart' show SongBrief;

const String _tag = 'logic.reducer';

/// Action 基类（sealed 风格：外部不得继承，仅本文件子类）。
abstract class PlaybackAction {
  const PlaybackAction();
}

/// 开始加载一首曲（附带队列跳转信息，供上层对齐）。
class StartLoad extends PlaybackAction {
  const StartLoad(this.song, {this.index = -1});
  final SongBrief song;
  final int index; // 队列中的位置（未知为 -1）
}

/// 实际开始播放。
class Playing extends PlaybackAction {
  const Playing({this.durationMs = 0});
  final int durationMs;
}

class Paused extends PlaybackAction {
  const Paused({this.positionMs = -1}); // -1 = 不更新位置
  final int positionMs;
}

/// 播放进度推进。
class Progress extends PlaybackAction {
  const Progress({required this.positionMs, this.durationMs = -1, this.bufferMs = -1});
  final int positionMs;
  final int durationMs; // -1 = 不更新
  final int bufferMs; // -1 = 不更新
}

/// 自然播完。
class Completed extends PlaybackAction {
  const Completed();
}

/// 播放错误。
class ErrorAction extends PlaybackAction {
  const ErrorAction(this.message);
  final String message;
}

/// 跳转到指定位置（seek）。
class SeekTo extends PlaybackAction {
  const SeekTo(this.positionMs);
  final int positionMs;
}

/// 队列跳转：换当前曲并进入 loading。
class QueueJump extends PlaybackAction {
  const QueueJump(this.song, {this.index = -1});
  final SongBrief song;
  final int index;
}

/// 调节音量（0.0~1.0，越界截断）。
class SetVolume extends PlaybackAction {
  const SetVolume(this.volume);
  final double volume;
}

/// 调节倍速（0.5~2.0，越界截断）。
class SetSpeed extends PlaybackAction {
  const SetSpeed(this.speed);
  final double speed;
}

/// 恢复播放（paused/completed → playing）。
class Resume extends PlaybackAction {
  const Resume();
}

/// 停止回到 idle。
class Stop extends PlaybackAction {
  const Stop();
}

double _clamp(double v, double lo, double hi) {
  try {
    if (v.isNaN) return lo;
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
  } catch (e, st) {
    Log.e(_tag, '_clamp failed', e, st);
    return lo;
  }
}

/// 纯 reducer：永远返回新状态，不改入参，不抛异常。
PlayerState playbackReducer(PlayerState state, PlaybackAction action) {
  try {
    if (action is StartLoad) {
      return state.copyWith(
        status: PlayerStatus.loading,
        current: action.song,
        positionMs: 0,
        durationMs: 0,
        bufferMs: 0,
        lastError: '',
      );
    }
    if (action is QueueJump) {
      return state.copyWith(
        status: PlayerStatus.loading,
        current: action.song,
        positionMs: 0,
        durationMs: 0,
        bufferMs: 0,
        lastError: '',
      );
    }
    if (action is Playing) {
      return state.copyWith(
        status: PlayerStatus.playing,
        durationMs: action.durationMs > 0 ? action.durationMs : null,
        lastError: '',
      );
    }
    if (action is Paused) {
      return state.copyWith(
        status: PlayerStatus.paused,
        positionMs: action.positionMs >= 0 ? action.positionMs : null,
      );
    }
    if (action is Progress) {
      return state.copyWith(
        status: state.status == PlayerStatus.playing ? PlayerStatus.playing : state.status,
        positionMs: action.positionMs >= 0 ? action.positionMs : null,
        durationMs: action.durationMs >= 0 ? action.durationMs : null,
        bufferMs: action.bufferMs >= 0 ? action.bufferMs : null,
      );
    }
    if (action is Completed) {
      return state.copyWith(status: PlayerStatus.completed);
    }
    if (action is ErrorAction) {
      return state.copyWith(
        status: PlayerStatus.error,
        lastError: action.message,
      );
    }
    if (action is SeekTo) {
      final d = state.durationMs;
      final p = d > 0 && action.positionMs > d ? d : action.positionMs;
      return state.copyWith(positionMs: p < 0 ? 0 : p);
    }
    if (action is SetVolume) {
      return state.copyWith(volume: _clamp(action.volume, 0.0, 1.0));
    }
    if (action is SetSpeed) {
      return state.copyWith(speed: _clamp(action.speed, 0.5, 2.0));
    }
    if (action is Resume) {
      if (state.status == PlayerStatus.paused || state.status == PlayerStatus.completed) {
        return state.copyWith(status: PlayerStatus.playing);
      }
      Log.w(_tag, 'Resume ignored in status=${state.status}');
      return state;
    }
    if (action is Stop) {
      return state.copyWith(
        status: PlayerStatus.idle,
        positionMs: 0,
        bufferMs: 0,
      );
    }
    Log.w(_tag, 'unknown action ${action.runtimeType}');
    return state;
  } catch (e, st) {
    Log.e(_tag, 'playbackReducer crashed on ${action.runtimeType}', e, st);
    return state.copyWith(status: PlayerStatus.error, lastError: 'reducer crash: $e');
  }
}
