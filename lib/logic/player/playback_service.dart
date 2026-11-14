// L5 logic/player · 播放源编排器
// 职责：本地优先解析播放源 → 否则在线取 URL。
// 三态原则（.test_creds/FINDINGS.md 实测）：
//  - 匿名（未登录/缺 token）：play_url v5 一律 status=2 errcode=20028 → needsVerification。
//  - VIP 曲目（tracker_through.musicpack_advance=1）非 VIP 账号：status=2 priv_status=0 → noPrivilege。
//  - 其余失败（hash 无效、无返回 URL 等）→ notFound；传输层异常 → network。
// 铁律：每方法 try/catch + Log('logic.playback')；可 import core/kernel；禁 import surface/flutter。

import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show DownloadStore, KugouClient, PlayResult, SongBrief, SongDao, getPlayUrlV5;
const String _tag = 'logic.playback';

/// 播放失败语义枚举。
enum PlaybackError {
  /// 需要验证：匿名或风控要求验证（errcode=20028）。匿名必然落此态。
  needsVerification,

  /// 无权限：VIP 曲目 + 非 VIP 账号（priv_status=0，status=2）。
  noPrivilege,

  /// 未找到：hash 无效 / 响应无 URL / status 非 1 且非上述两态。
  notFound,

/// 网络异常：传输层失败（解析/HTTP 非 200）。
  network,
}

/// 解析结果：localPath 优先（已下载）；否则 urls（在线直链）。
class PlaySource {
  const PlaySource({
    this.localPath,
    this.urls = const <String>[],
    this.backupUrls = const <String>[],
    this.quality = '',
    this.extName = '',
    this.bitrate = 0,
    this.timeLengthSec = 0,
    this.isFreePart = false,
    this.error,
  });

  /// 本地文件绝对路径（已下载命中时非空，其余字段为空）。
  final String? localPath;

  /// 在线播放直链（urls[0] 为主链，backupUrls 备用）。
  final List<String> urls;
  final List<String> backupUrls;
  final String quality; // 请求音质（128/320/flac/high/魔法音质）
  final String extName; // mp3/flac …
  final int bitrate;
  final int timeLengthSec;
  final bool isFreePart;

  /// 失败语义；null = 成功。
  final PlaybackError? error;

  bool get ok => error == null && (localPath != null || urls.isNotEmpty);

  Map<String, Object?> toMap() => <String, Object?>{
        'ok': ok,
        'localPath': localPath,
        'urls': urls,
        'backupUrls': backupUrls,
        'quality': quality,
        'extName': extName,
        'bitrate': bitrate,
        'timeLengthSec': timeLengthSec,
        'isFreePart': isFreePart,
        'error': error?.name,
      };

  @override
  String toString() {
    try {
      return 'PlaySource(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'PlaySource.toString failed', e, st);
      return 'PlaySource(<unavailable>)';
    }
  }
}

/// 播放服务编排器：resolvePlaySource。
/// 构造注入 KugouClient + DownloadStore（SongDao 保留装配兼容）。
class PlaybackService {
  PlaybackService({
    required KugouClient client,
    required SongDao songDao,
    required DownloadStore downloadStore,
  })  : _client = client,
        _store = downloadStore;

  final KugouClient _client;
  final DownloadStore _store;

  /// 解析播放源：
  /// 1) 先查 DownloadStore（complete 且实体文件存在）→ 本地路径优先；
  /// 2) 否则 getPlayUrlV5 按 hash+quality 取 URL；
  /// 3) status!=1 时映射语义错误（needsVerification / noPrivilege / notFound）。
  Future<PlaySource> resolvePlaySource(SongBrief song, String preferQuality) async {
    final hash = song.hash.trim().toLowerCase();
    final quality = preferQuality.trim().isEmpty ? '128' : preferQuality.trim();
    try {
      // 1) 本地优先。
      final rec = _store.getByHash(hash);
      if (rec != null && rec.complete) {
        final path = _store.absolutePathOf(rec);
        // 边界防御：索引 complete 但实体文件已被清理时必须回退在线，否则
        // engine 拿到悬空路径直接报错且无降级。
        if (path != null && File(path).existsSync()) {
          Log.d(_tag, 'resolvePlaySource local hit $hash (${rec.quality})');
          return PlaySource(localPath: path, quality: rec.quality);
        }
        Log.w(_tag, 'local record missing file, fallback online $hash');
      }
      // 2) 在线取 URL。
      final pr = await getPlayUrlV5(_client, hash, quality);
      // 3) 语义错误映射（status!=1）。
      if (pr.status != 1 || pr.urls.isEmpty) {
        final err = _mapError(pr);
        Log.w(_tag,
            'resolvePlaySource failed $hash q=$quality status=${pr.status} '
            'priv=${pr.privStatus} err=${pr.errcode} -> ${err.name}');
        return PlaySource(quality: quality, error: err);
      }
      Log.d(_tag,
          'resolvePlaySource online $hash q=$quality urls=${pr.urls.length} '
          'ext=${pr.extName} free=${pr.isFreePart}');
      return PlaySource(
        urls: pr.urls,
        backupUrls: pr.backupUrls,
        quality: quality,
        extName: pr.extName,
        bitrate: pr.bitrate,
        timeLengthSec: pr.timeLengthSec,
        isFreePart: pr.isFreePart,
      );
    } catch (e, st) {
      Log.e(_tag, 'resolvePlaySource $hash q=$quality', e, st);
      return PlaySource(quality: quality, error: PlaybackError.network);
    }
  }

  /// PlayResult → PlaybackError 语义映射。
  /// 匿名必然 needsVerification（20028）；VIP 曲非 VIP 号 noPrivilege（priv_status=0）。
  PlaybackError _mapError(PlayResult pr) {
    try {
      if (pr.errcode == 20028) {
        // VerificationLogic 是唯一验证门面，播放链路只上报状态，不在本文件另写验证实现。
        return PlaybackError.needsVerification;
      }
      // status=2 且 priv_status=0：过风控但无权限（VIP 曲非 VIP 号典型态）。
      if (pr.status == 2 && pr.privStatus == 0) {
        return PlaybackError.noPrivilege;
      }
      // 兜底：VIP 曲目标记 + 无 URL 也视为无权限。
      if (pr.urls.isEmpty && pr.isVipTrack) return PlaybackError.noPrivilege;
      return PlaybackError.notFound;
    } catch (e, st) {
      Log.e(_tag, '_mapError failed', e, st);
      return PlaybackError.notFound;
    }
  }
}

/// 播放编排业务异常（携带语义错误）。
class PlaybackException implements Exception {
  PlaybackException(this.error, [this.detail = '']);
  final PlaybackError error;
  final String detail;
  @override
  String toString() => 'PlaybackException(${error.name}): $detail';
}
