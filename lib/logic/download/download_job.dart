// L5 logic/download · 下载运行句柄与中断信号
// 从 download_manager 拆出：运行句柄/异常类型是纯数据契约，便于
// manager 文件控制长度（≤500 行）。同层同包互调合法。
// 铁律：纯数据，无 IO、无 flutter 依赖。

import 'dart:async';

/// 运行中任务句柄：abort 标志由 pause/cancel 设置，下载循环每 chunk 自检。
class RunningJob {
  /// pause/cancel 置位，下载循环每 chunk 自检。
  bool abort = false;

  /// cancel 置位：收尾不得再 emit 已取消任务的 paused 幽灵事件
  /// （任务已从任务表移出，事件流不应再出现它的状态变更）。
  bool cancelled = false;

  /// 运行体退出信号（cancel 等待它结束后才清理 .dlpart 残留）。
  final done = Completer<void>();
}

/// 主动中断信号：pause/cancel 造成的中断，不是 URL 失败。
/// 语义约束：不得降级备用链、不得置 failed、不得写错误信息。
class DownloadAborted implements Exception {
  const DownloadAborted();

  @override
  String toString() => 'aborted';
}

/// 中断收尾判定（生产逻辑，供 DownloadManager 与契约自检共用）：
/// cancel（cancelled=true）→ 任务已移出任务表，不得再 emit 其 paused 幽灵事件；
/// pause（cancelled=false）→ 仍须 emit paused，UI 才不会悬挂在「下载中」。
bool shouldEmitPausedOnAbort({required bool cancelled}) => !cancelled;
