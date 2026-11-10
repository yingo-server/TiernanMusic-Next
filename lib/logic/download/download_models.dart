// L5 logic/download · 下载域模型（纯数据，无 IO）
// 职责：DownloadTask（任务状态机）+ DownloadEvent（进度回调事件）。
// 铁律：禁 import surface/flutter/core/net；仅被 download_manager 与桥引用。
// 每方法 try/catch + Log('logic.download')。

import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show SongBrief;
const String kDownloadModelsTag = 'logic.download';

/// 下载任务状态。
enum DownloadStatus {
  /// 排队中（未开始或等待调度槽位）。
  pending,

  /// 下载中。
  running,

  /// 已暂停（保留 bytesDownloaded 语义，恢复后从头重下——见 manager 注释）。
  paused,

  /// 已完成（文件已提交 DownloadStore，曲库已建档）。
  done,

  /// 失败（error 带原因）。
  failed,
}

/// 下载任务。
class DownloadTask {
  DownloadTask({
    required this.song,
    required this.quality,
    this.status = DownloadStatus.pending,
    this.bytesDownloaded = 0,
    this.bytesTotal = 0,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final SongBrief song;

  /// 请求音质（128/320/flac/high/魔法音质）。
  final String quality;
  DownloadStatus status;
  int bytesDownloaded;

  /// 响应 content-length；未知为 0。
  int bytesTotal;
  String? error;
  final DateTime createdAt;

  /// 业务唯一键：小写化 hash。
  String get hash => song.hash.trim().toLowerCase();

  /// 进度 0.0–1.0；bytesTotal 未知（0）时返回 -1 表示不确定。
  double get progress {
    try {
      if (bytesTotal <= 0) return -1;
      if (bytesDownloaded >= bytesTotal) return 1;
      return bytesDownloaded / bytesTotal;
    } catch (e, st) {
      Log.e(kDownloadModelsTag, 'DownloadTask.progress failed', e, st);
      return -1;
    }
  }

  /// 展示名："歌手 - 标题"，空则回退 hash。
  String get displayName {
    try {
      final raw = song.singer.isEmpty ? song.name : '${song.singer} - ${song.name}';
      return raw.trim().isEmpty ? hash : raw.trim();
    } catch (e, st) {
      Log.e(kDownloadModelsTag, 'DownloadTask.displayName failed', e, st);
      return hash;
    }
  }

  Map<String, Object?> toMap() {
    try {
      return <String, Object?>{
        'hash': hash,
        'name': song.name,
        'singer': song.singer,
        'quality': quality,
        'status': status.name,
        'bytesDownloaded': bytesDownloaded,
        'bytesTotal': bytesTotal,
        'progress': progress,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
      };
    } catch (e, st) {
      Log.e(kDownloadModelsTag, 'DownloadTask.toMap failed', e, st);
      return <String, Object?>{'hash': hash};
    }
  }

  @override
  String toString() {
    try {
      return 'DownloadTask(${toMap()})';
    } catch (e, st) {
      Log.e(kDownloadModelsTag, 'DownloadTask.toString failed', e, st);
      return 'DownloadTask(<unavailable>)';
    }
  }
}

/// 下载域事件：单任务变更 + 当前任务列表快照（快照为不可变副本）。
class DownloadEvent {
  const DownloadEvent({this.task, required this.tasks});

  /// 触发本事件的任务（enqueue/进度/状态变更/失败），可为 null（纯快照刷新）。
  final DownloadTask? task;

  /// 全量任务快照（入队顺序）。
  final List<DownloadTask> tasks;

  @override
  String toString() {
    try {
      return 'DownloadEvent(task=${task?.hash}, tasks=${tasks.length})';
    } catch (e, st) {
      Log.e(kDownloadModelsTag, 'DownloadEvent.toString failed', e, st);
      return 'DownloadEvent(<unavailable>)';
    }
  }
}
