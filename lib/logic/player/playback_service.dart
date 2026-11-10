// L5 logic/player · 播放源编排器
// 职责：本地优先解析播放源 → 否则在线取 URL；下载流落盘经 DownloadStore。
// 三态原则（.test_creds/FINDINGS.md 实测）：
//  - 匿名（未登录/缺 token）：play_url v5 一律 status=2 errcode=20028 → needsVerification。
//  - VIP 曲目（tracker_through.musicpack_advance=1）非 VIP 账号：status=2 priv_status=0 → noPrivilege。
//  - 其余失败（hash 无效、无返回 URL 等）→ notFound；传输层异常 → network。
// 铁律：每方法 try/catch + Log('logic.playback')；可 import core/kernel；禁 import surface/flutter。

import 'dart:io';

import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show DownloadRecord, DownloadStore, KugouClient, PlayResult, PlaylistDao, PlaylistDetail, PrivilegeItem, SongBrief, SongDao, TrackPage, getPlayUrlV5, getPrivilegeLite;
const String _tag = 'logic.playback';

/// 播放失败语义枚举。
enum PlaybackError {
  /// 需要验证：匿名或风控要求验证（errcode=20028）。匿名必然落此态。
  needsVerification,

  /// 无权限：VIP 曲目 + 非 VIP 账号（priv_status=0，status=2）。
  noPrivilege,

  /// 未找到：hash 无效 / 响应无 URL / status 非 1 且非上述两态。
  notFound,

  /// 网络异常：传输层失败（HttpClient/解析/HTTP 非 200）。
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

/// 播放服务编排器：resolvePlaySource / download。
/// 构造注入 KugouClient + SongDao + DownloadStore。
class PlaybackService {
  PlaybackService({
    required KugouClient client,
    required SongDao songDao,
    required DownloadStore downloadStore,
  })  : _client = client,
        _songDao = songDao,
        _store = downloadStore;

  final KugouClient _client;
  final SongDao _songDao;
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
        if (path != null) {
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
      if (pr.errcode == 20028) return PlaybackError.needsVerification;
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

  /// 下载：先 resolvePlaySource 拿在线 URL，再 HttpClient 字节流下载
  /// （网络异常重试 1 次——幂等 GET），经 DownloadStore.commitDownload 落盘。
  /// 失败抛 PlaybackException（带语义错误）。
  Future<DownloadRecord> download(SongBrief song, String quality) async {
    final hash = song.hash.trim().toLowerCase();
    try {
      final src = await resolvePlaySource(song, quality);
      if (src.error != null || src.urls.isEmpty) {
        throw PlaybackException(src.error ?? PlaybackError.notFound,
            'no url for $hash');
      }
      final url = src.urls.first;
      final data = await _fetchBytes(url);
      final fileName = _buildFileName(song, src.extName);
      final rec = _store.commitDownload(
        hash: hash,
        fileName: fileName,
        data: data,
        quality: src.quality.isEmpty ? quality : src.quality,
      );
      if (rec == null) {
        throw PlaybackException(
            PlaybackError.network, 'commitDownload failed $hash');
      }
      // 同步本地曲库：存在则补 localPath/quality，不存在建档。
      try {
        final existing = await _songDao.getByHash(hash);
        if (existing != null) {
          existing.localPath =
              _store.absolutePathOf(rec) ?? existing.localPath;
          existing.quality = rec.quality;
          await _songDao.put(existing);
        }
      } catch (e, st) {
        Log.e(_tag, 'download sync song db failed $hash', e, st);
      }
      Log.d(_tag, 'download done $hash -> ${rec.fileName} (${rec.bytes}B)');
      return rec;
    } on PlaybackException {
      rethrow;
    } catch (e, st) {
      Log.e(_tag, 'download $hash q=$quality', e, st);
      throw PlaybackException(PlaybackError.network, '$e');
    }
  }

  /// 字节流下载，网络异常重试 1 次（幂等 GET）。
  Future<List<int>> _fetchBytes(String url) async {
    try {
      return await _fetchOnce(url);
    } catch (e, st) {
      Log.w(_tag, 'fetch retry once $url ERR=$e');
      try {
        return await _fetchOnce(url);
      } catch (e2, st2) {
        Log.e(_tag, 'fetch failed after retry $url', e2, st2);
        throw PlaybackException(PlaybackError.network, '$e2');
      }
    }
  }

  Future<List<int>> _fetchOnce(String url) async {
    final http = HttpClient()
      ..userAgent = 'TiernanMusicNext'
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await http.getUrl(Uri.parse(url));
      req.headers.set('Range', 'bytes=0-'); // 完整拉取，段服务器友好
      final res = await req.close();
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw HttpException('http ${res.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      http.close();
    }
  }

  /// 落盘文件名："歌手 - 标题.ext"，净化非法字符。
  String _buildFileName(SongBrief song, String ext) {
    try {
      final raw = song.singer.isEmpty
          ? song.name
          : '${song.singer} - ${song.name}';
      final cleaned = raw
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      final name = cleaned.isEmpty ? song.hash : cleaned;
      final e = ext.trim().isEmpty ? 'mp3' : ext.trim().toLowerCase();
      return '$name.$e';
    } catch (e, st) {
      Log.e(_tag, '_buildFileName failed', e, st);
      return '${song.hash}.mp3';
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
