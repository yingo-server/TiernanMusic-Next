// L5 logic/player · 播放队列状态机（纯 Dart，零 IO，零 flutter import）
// 铁律：不可变状态 + 纯函数；每个公开方法 try/catch + Log（tag: logic.queue）。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show SongBrief;

const String _tag = 'logic.queue';

/// 播放模式：sequence 顺序 / loopOne 单曲（循环由播放器处理，状态机只前进） / shuffle 随机。
enum PlayMode { sequence, loopOne, shuffle }

/// 不可变播放队列状态。
class QueueState {
  const QueueState({
    this.items = const <SongBrief>[],
    this.index = -1,
    this.mode = PlayMode.sequence,
    this.seed = 0,
  });

  final List<SongBrief> items;
  final int index; // -1 = 无当前曲
  final PlayMode mode;
  final int seed; // shuffle 模式的可复现随机种子

  bool get isEmpty {
    try {
      return items.isEmpty || index < 0 || index >= items.length;
    } catch (e, st) {
      Log.e(_tag, 'isEmpty failed', e, st);
      return true;
    }
  }

  /// 当前曲；越界/空返回 null。
  SongBrief? get current {
    try {
      if (index < 0 || index >= items.length) return null;
      return items[index];
    } catch (e, st) {
      Log.e(_tag, 'current failed', e, st);
      return null;
    }
  }

  int get length {
    try {
      return items.length;
    } catch (e, st) {
      Log.e(_tag, 'length failed', e, st);
      return 0;
    }
  }

  QueueState _with(List<SongBrief> newItems, int newIndex, {PlayMode? mode, int? seed}) {
    try {
      return QueueState(
        items: List.unmodifiable(newItems),
        index: newIndex,
        mode: mode ?? this.mode,
        seed: seed ?? this.seed,
      );
    } catch (e, st) {
      Log.e(_tag, '_with failed', e, st);
      return this;
    }
  }

  /// 下一曲。空队列返回 null；loopOne 也前进（单曲循环由播放器负责）。
  QueueState? next() {
    try {
      if (items.isEmpty) {
        Log.d(_tag, 'next on empty queue → null');
        return null;
      }
      if (mode == PlayMode.shuffle) return _shuffleStep(1);
      var ni = index + 1;
      if (ni >= items.length) ni = 0; // 循环整个队列
      return _with(items, ni);
    } catch (e, st) {
      Log.e(_tag, 'next failed', e, st);
      return null;
    }
  }

  /// 上一曲。空队列返回 null。
  QueueState? prev() {
    try {
      if (items.isEmpty) {
        Log.d(_tag, 'prev on empty queue → null');
        return null;
      }
      if (mode == PlayMode.shuffle) return _shuffleStep(-1);
      var pi = index - 1;
      if (pi < 0) pi = items.length - 1;
      return _with(items, pi);
    } catch (e, st) {
      Log.e(_tag, 'prev failed', e, st);
      return null;
    }
  }

  /// shuffle 步进：以 seed 派生伪随机序列，prev/next 走同一条序列，可复现。
  QueueState _shuffleStep(int dir) {
    try {
      final n = items.length;
      if (n <= 1) return _with(items, 0);
      // 基于当前 index+seed 的伪随机哈希取下一位置（双向可逆性不保证，但同 seed 可复现）。
      var base = (index + 1) % n;
      base = (base + dir + n) % n;
      var h = (seed ^ (base * 0x9E3779B9)) & 0x7FFFFFFF;
      h = (h ^ (h >> 13)) * 0x85EBCA6B & 0x7FFFFFFF;
      h ^= h >> 16;
      final target = h % n;
      if (target == index) return _with(items, (index + 1) % n);
      return _with(items, target);
    } catch (e, st) {
      Log.e(_tag, '_shuffleStep failed', e, st);
      return _with(items, index % items.length);
    }
  }

  /// 跳到第 i 首；越界返回 null。
  QueueState? jumpTo(int i) {
    try {
      if (i < 0 || i >= items.length) {
        Log.w(_tag, 'jumpTo out of range i=$i len=${items.length}');
        return null;
      }
      return _with(items, i);
    } catch (e, st) {
      Log.e(_tag, 'jumpTo failed', e, st);
      return null;
    }
  }

  /// 追加一首；原队列空则成为当前曲。
  QueueState append(SongBrief song) {
    try {
      final list = List<SongBrief>.of(items)..add(song);
      // index 越界（历史状态残留）时钳位：未播放过指向新追加项，越界指向尾部。
      int ni;
      if (index < 0) {
        ni = list.length - 1;
      } else if (index >= list.length) {
        ni = list.length - 1;
      } else {
        ni = index;
      }
      return _with(list, ni);
    } catch (e, st) {
      Log.e(_tag, 'append failed', e, st);
      return this;
    }
  }

  QueueState appendAll(List<SongBrief> songs) {
    try {
      final list = List<SongBrief>.of(items)..addAll(songs);
      final ni = index < 0 ? (songs.isEmpty ? -1 : 0) : index;
      return _with(list, ni);
    } catch (e, st) {
      Log.e(_tag, 'appendAll failed', e, st);
      return this;
    }
  }

  /// 在当前位置后插入（next 播放它）；原队列空则成为当前曲。
  QueueState insert(SongBrief song) {
    try {
      if (index < 0 || index >= items.length) {
        final list = List<SongBrief>.of(items)..add(song);
        return _with(list, index < 0 ? 0 : index);
      }
      final list = List<SongBrief>.of(items)..insert(index + 1, song);
      return _with(list, index);
    } catch (e, st) {
      Log.e(_tag, 'insert failed', e, st);
      return this;
    }
  }

  /// 删除第 i 首；索引修正：删当前曲则指向下一首（越界取尾部），删前曲则 index-1。
  QueueState removeAt(int i) {
    try {
      if (i < 0 || i >= items.length) {
        Log.w(_tag, 'removeAt out of range i=$i');
        return this;
      }
      final list = List<SongBrief>.of(items)..removeAt(i);
      if (list.isEmpty) return _with(list, -1);
      var ni = index;
      if (i < index) {
        ni = index - 1;
      } else if (i == index) {
        // 语义「删当前曲则指向下一首」：删除后原 index 位置即原下一首；
        // 仅当删的是队尾才回退到新的尾部。原实现 index 未变，导致
        // 删当前曲后索引指向被删曲的后一首（跳歌）。
        ni = index >= list.length ? list.length - 1 : index;
      }
      return _with(list, ni);
    } catch (e, st) {
      Log.e(_tag, 'removeAt failed', e, st);
      return this;
    }
  }

  /// 整队替换并从 startIndex 开始；列表空返回空态。
  QueueState replaceQueue(List<SongBrief> list, int startIndex) {
    try {
      if (list.isEmpty) return _with(const <SongBrief>[], -1);
      final si = (startIndex >= 0 && startIndex < list.length) ? startIndex : 0;
      return _with(List<SongBrief>.of(list), si);
    } catch (e, st) {
      Log.e(_tag, 'replaceQueue failed', e, st);
      return this;
    }
  }

  /// shuffle 化重排：以 [seed]（缺省沿用/生成新值）确定性打乱 items，
  /// 当前曲固定在首位，index 置 0；再次调用可还原顺序（mode 切回 sequence 时按 items 顺序播）。
  QueueState shuffled({int? seed}) {
    try {
      final s = seed ?? (this.seed == 0 ? 20261110 : this.seed);
      final cur = current;
      final rest = <SongBrief>[];
      for (var i = 0; i < items.length; i++) {
        if (i != index) rest.add(items[i]);
      }
      // Fisher–Yates with LCG，确定性。
      var state = s & 0x7FFFFFFF;
      for (var i = rest.length - 1; i > 0; i--) {
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
        final j = state % (i + 1);
        final t = rest[i];
        rest[i] = rest[j];
        rest[j] = t;
      }
      final list = cur == null ? rest : <SongBrief>[cur, ...rest];
      return _with(list, list.isEmpty ? -1 : 0, mode: PlayMode.shuffle, seed: s);
    } catch (e, st) {
      Log.e(_tag, 'shuffled failed', e, st);
      return this;
    }
  }

  /// 切换模式（不重排）。
  QueueState withMode(PlayMode m) {
    try {
      return _with(items, index, mode: m);
    } catch (e, st) {
      Log.e(_tag, 'withMode failed', e, st);
      return this;
    }
  }

  QueueState copyWith({List<SongBrief>? items, int? index, PlayMode? mode, int? seed}) =>
      _with(items ?? this.items, index ?? this.index, mode: mode, seed: seed);

  @override
  String toString() {
    try {
      return 'QueueState(len=${items.length}, index=$index, mode=$mode, seed=$seed)';
    } catch (e, st) {
      Log.e(_tag, 'toString failed', e, st);
      return 'QueueState(<unavailable>)';
    }
  }
}
