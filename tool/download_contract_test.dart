// tool/download_contract_test.dart · 下载中断契约自检（纯 Dart，无 flutter）
// 目的：钉死两条语义，防止回归：
//   ① cancel：运行体收尾不得 emit 已取消任务的 paused 幽灵事件；
//   ② pause ：运行体收尾仍要 emit paused（UI 不能悬挂在「下载中」）。
// 运行：dart run tool/download_contract_test.dart
import '../lib/logic/download/download_job.dart';

int _passed = 0;
int _failed = 0;

void check(bool cond, String name) {
  if (cond) {
    _passed++;
    print('PASS  $name');
  } else {
    _failed++;
    print('FAIL  $name');
  }
}

void main() {
  // 句柄契约
  final job = RunningJob();
  check(job.abort == false, 'RunningJob: 初始 abort=false');
  check(job.cancelled == false, 'RunningJob: 初始 cancelled=false');
  check(!job.done.isCompleted, 'RunningJob: done 初始未完成');

  // cancel 路径：abort+cancelled 都置位 → 不 emit paused
  job.abort = true;
  job.cancelled = true;
  check(shouldEmitPausedOnAbort(cancelled: job.cancelled) == false,
      'cancel: 收尾不 emit paused（无幽灵事件）');

  // pause 路径：仅 abort → 仍 emit paused
  final paused = RunningJob()..abort = true;
  check(shouldEmitPausedOnAbort(cancelled: paused.cancelled) == true,
      'pause: 收尾仍 emit paused（UI 不悬挂）');

  // 中断信号类型
  const aborted = DownloadAborted();
  check(aborted is Exception, 'DownloadAborted: 是 Exception');
  check(aborted.toString() == 'aborted', 'DownloadAborted: toString=aborted');

  // 收尾置 paused 的判定：cancel 不置；已 resume 的任务也不置（保持 pending）
  check(!shouldMarkPausedOnAbort(cancelled: true, alreadyResumed: false),
      'cancel: 不置 paused');
  check(shouldMarkPausedOnAbort(cancelled: false, alreadyResumed: false),
      'pause: 置 paused');
  check(!shouldMarkPausedOnAbort(cancelled: false, alreadyResumed: true),
      '已 resume: 不回写 paused（保持 pending 可重新调度）');

  // done 信号可完成（cancel 等待它）
  final j2 = RunningJob();
  j2.done.complete();
  check(j2.done.isCompleted, 'RunningJob: done 可完成（cancel 等待它）');

  print('---- download contract self-check: $_passed passed, $_failed failed ----');
  if (_failed > 0) throw StateError('download contract FAILED');
}
