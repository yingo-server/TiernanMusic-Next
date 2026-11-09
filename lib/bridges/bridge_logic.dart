// 五桥 · bridge_logic：L5 logic 暴露给 L6 surface 的能力门面（含 Log）。
library;

import '../kernel/kernel.dart' show Log; // Log 由 kernel 层提供，桥转发使用

/// logic 能力门面：surface 只拿这个，不 import logic 内部模块。
class LogicFacade {
  const LogicFacade();
  // 播放/搜索/歌单/下载等能力将在 logic 层实现后经此门面暴露。
  // 占位：查询当前播放状态描述。
  String playbackSummary() => 'idle';
}
