// L4 core/net/endpoints · 端点强类型结果模型（集中定义，字段缺失给默认值不崩）
// 禁 import logic/surface/flutter；仅 SDK + 同级 kugou_client。
import '../../../kernel/kernel.dart' show Log;

const String _tag = 'endpoints.models';

/// 容错取值工具：类型不符返回 fallback，绝不抛出。
int safeInt(Object? v, [int fallback = 0]) {
  try {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  } catch (e, st) {
    Log.e(_tag, 'safeInt failed v=$v', e, st);
    return fallback;
  }
}

String safeStr(Object? v, [String fallback = '']) {
  try {
    if (v == null) return fallback;
    return '$v';
  } catch (e, st) {
    Log.e(_tag, 'safeStr failed', e, st);
    return fallback;
  }
}

double safeDouble(Object? v, [double fallback = 0.0]) {
  try {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  } catch (e, st) {
    Log.e(_tag, 'safeDouble failed', e, st);
    return fallback;
  }
}

bool safeBool(Object? v, [bool fallback = false]) {
  try {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      return v == '1' || v.toLowerCase() == 'true';
    }
    return fallback;
  } catch (e, st) {
    Log.e(_tag, 'safeBool failed', e, st);
    return fallback;
  }
}

/// 容错从响应根取 data 子对象（缺失返回空 map，不崩）。
Map<String, dynamic> dataOf(Map<String, dynamic> root) {
  try {
    final d = root['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return d.map((k, v) => MapEntry('$k', v));
    return const <String, dynamic>{};
  } catch (e, st) {
    Log.e(_tag, 'dataOf failed', e, st);
    return const <String, dynamic>{};
  }
}

/// 容错取列表：缺失/类型不符返回空列表。
List<Map<String, dynamic>> listOf(Object? v) {
  try {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((m) => m.map((k, val) => MapEntry('$k', val)))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  } catch (e, st) {
    Log.e(_tag, 'listOf failed', e, st);
    return const <Map<String, dynamic>>[];
  }
}

/// 歌曲摘要（搜索 data.lists[] / 歌单 data.info[] 通用映射）。
/// 实测字段：FileHash/FileName/SingerName/MixSongID/AlbumAudioId/Duration/Bitrate/FileSize。
class SongBrief {
  const SongBrief({
    this.hash = '',
    this.name = '',
    this.singer = '',
    this.mixSongId = 0,
    this.albumAudioId = 0,
    this.durationSec = 0,
    this.bitrate = 0,
    this.fileSize = 0,
    this.albumId = '',
    this.albumName = '',
    this.isVip = false,
  });

  final String hash; // FileHash（小写化）
  final String name; // FileName / name
  final String singer; // SingerName / singername
  final int mixSongId; // MixSongID（评论/上报用 mxid）
  final int albumAudioId; // AlbumAudioId / album_audio_id
  final int durationSec; // Duration / timelength(秒)
  final int bitrate;
  final int fileSize;
  final String albumId;
  final String albumName;
  final bool isVip; // musicpack_advance==1

  factory SongBrief.fromSearchList(Map<String, dynamic> m) {
    try {
      return SongBrief(
        hash: safeStr(m['FileHash']).toLowerCase(),
        name: safeStr(m['FileName'], m['name'] ?? ''),
        singer: safeStr(m['SingerName'], m['singername'] ?? ''),
        mixSongId: safeInt(m['MixSongID']),
        albumAudioId: safeInt(m['AlbumAudioId']),
        durationSec: safeInt(m['Duration']),
        bitrate: safeInt(m['Bitrate']),
        fileSize: safeInt(m['FileSize']),
        albumId: safeStr(m['AlbumID']),
        albumName: safeStr(m['AlbumName']),
        isVip: safeBool(m['musicpack_advance']),
      );
    } catch (e, st) {
      Log.e(_tag, 'SongBrief.fromSearchList failed', e, st);
      return const SongBrief();
    }
  }

  factory SongBrief.fromTrackInfo(Map<String, dynamic> m) {
    try {
      return SongBrief(
        hash: safeStr(m['hash'], m['FileHash'] ?? '').toLowerCase(),
        name: safeStr(m['name'], m['FileName'] ?? ''),
        singer: safeStr(m['singername'], m['SingerName'] ?? ''),
        mixSongId: safeInt(m['mixsongid'], safeInt(m['MixSongID'])),
        albumAudioId: safeInt(m['album_audio_id'], safeInt(m['AlbumAudioId'])),
        durationSec: safeInt(m['timelength'], safeInt(m['Duration'])),
        bitrate: safeInt(m['bitrate'], safeInt(m['Bitrate'])),
        fileSize: safeInt(m['filesize'], safeInt(m['FileSize'])),
        albumId: safeStr(m['album_id'], safeStr(m['AlbumID'])),
        albumName: safeStr(m['album_name'], safeStr(m['AlbumName'])),
        isVip: safeBool(m['musicpack_advance']),
      );
    } catch (e, st) {
      Log.e(_tag, 'SongBrief.fromTrackInfo failed', e, st);
      return const SongBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'hash': hash, 'name': name, 'singer': singer,
        'mixSongId': mixSongId, 'albumAudioId': albumAudioId,
        'durationSec': durationSec, 'bitrate': bitrate,
        'fileSize': fileSize, 'albumId': albumId,
        'albumName': albumName, 'isVip': isVip,
      };

  @override
  String toString() {
    try {
      return 'SongBrief(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'SongBrief.toString failed', e, st);
      return 'SongBrief(<unavailable>)';
    }
  }
}

/// 搜索结果：total 来自 data.total，items 来自 data.lists[]（FINDINGS.md §3）。
class SearchResult {
  const SearchResult({this.total = 0, this.items = const <SongBrief>[]});
  final int total;
  final List<SongBrief> items;

  Map<String, Object?> toMap() => <String, Object?>{
        'total': total,
        'items': items.map((s) => s.toMap()).toList(growable: false),
      };

  @override
  String toString() {
    try {
      return 'SearchResult(total=$total, items=${items.length})';
    } catch (e, st) {
      Log.e(_tag, 'SearchResult.toString failed', e, st);
      return 'SearchResult(<unavailable>)';
    }
  }
}

/// 搜索联想/热搜的单条建议。
class SearchSuggestItem {
  const SearchSuggestItem({this.keyword = '', this.type = ''});
  final String keyword;
  final String type; // music/album/author/mv …

  Map<String, Object?> toMap() => <String, Object?>{'keyword': keyword, 'type': type};
}

/// play_url v5 解析结果：响应顶层即数据（FINDINGS.md §1）。
class PlayResult {
  const PlayResult({
    this.status = 0,
    this.privStatus = 0,
    this.errcode = 0,
    this.error = '',
    this.urls = const <String>[],
    this.backupUrls = const <String>[],
    this.bitrate = 0,
    this.extName = '',
    this.timeLengthSec = 0,
    this.isVipTrack = false,
    this.isFreePart = false,
    this.hash = '',
  });

  final int status; // 1=出URL；2=err（20028 匿名风控等）
  final int privStatus; // 1=有权限；0=无权限（VIP 曲非 VIP 号）
  final int errcode; // 20028 …
  final String error;
  final List<String> urls; // url 数组（顶层 url）
  final List<String> backupUrls; // backupUrl
  final int bitrate; // bitRate
  final String extName; // mp3/flac …
  final int timeLengthSec; // timeLength
  final bool isVipTrack; // tracker_through.musicpack_advance==1
  final bool isFreePart; // 试听片段
  final String hash;

  bool get playable {
    try {
      return status == 1 && privStatus == 1 && urls.isNotEmpty;
    } catch (e, st) {
      Log.e(_tag, 'PlayResult.playable failed', e, st);
      return false;
    }
  }

  bool get needsVerification {
    try {
      return errcode == 20028 || status == 2 && privStatus == 0 && urls.isEmpty;
    } catch (e, st) {
      Log.e(_tag, 'PlayResult.needsVerification failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'status': status, 'privStatus': privStatus, 'errcode': errcode,
        'error': error, 'urls': urls, 'backupUrls': backupUrls,
        'bitrate': bitrate, 'extName': extName,
        'timeLengthSec': timeLengthSec, 'isVipTrack': isVipTrack,
        'isFreePart': isFreePart, 'hash': hash, 'playable': playable,
      };

  @override
  String toString() {
    try {
      return 'PlayResult(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'PlayResult.toString failed', e, st);
      return 'PlayResult(<unavailable>)';
    }
  }
}

/// 权益批量（privilege_lite）单资源结果。
/// 注意 FINDINGS.md §10：privilege 是 int 标量（非数组），权限判定不依赖此接口。
class PrivilegeItem {
  const PrivilegeItem({
    this.hash = '',
    this.privilege = 0,
    this.status = 0,
  });
  final String hash;
  final int privilege; // int 标量
  final int status;

  Map<String, Object?> toMap() => <String, Object?>{
        'hash': hash, 'privilege': privilege, 'status': status,
      };
}

/// 歌单摘要（recommend 列表项 / 用户歌单项）。
class PlaylistBrief {
  const PlaylistBrief({
    this.id = '',
    this.name = '',
    this.cover = '',
    this.playCount = 0,
    this.trackCount = 0,
    this.creator = '',
    this.intro = '',
  });

  final String id; // global_collection_id / specialid / listid
  final String name; // specialname
  final String cover; // imgurl
  final int playCount;
  final int trackCount; // count
  final String creator; // username
  final String intro;

  factory PlaylistBrief.fromMap(Map<String, dynamic> m) {
    try {
      return PlaylistBrief(
        id: safeStr(
            m['global_collection_id'] ?? m['specialid'] ?? m['listid'] ??
                m['id'] ?? ''),
        name: safeStr(m['specialname'] ?? m['name'] ?? ''),
        cover: safeStr(m['imgurl'] ?? m['cover'] ?? ''),
        playCount: safeInt(m['playcount'] ?? m['play_count']),
        trackCount: safeInt(m['count'] ?? m['track_count']),
        creator: safeStr(m['username'] ?? m['nickname'] ?? ''),
        intro: safeStr(m['intro'] ?? ''),
      );
    } catch (e, st) {
      Log.e(_tag, 'PlaylistBrief.fromMap failed', e, st);
      return const PlaylistBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'name': name, 'cover': cover, 'playCount': playCount,
        'trackCount': trackCount, 'creator': creator, 'intro': intro,
      };
}

/// 歌单详情（playlist_detail data[] 首项）。
class PlaylistDetail {
  const PlaylistDetail({
    this.id = '',
    this.name = '',
    this.cover = '',
    this.playCount = 0,
    this.trackCount = 0,
    this.intro = '',
    this.creator = '',
    this.tags = const <String>[],
  });

  final String id;
  final String name;
  final String cover;
  final int playCount;
  final int trackCount;
  final String intro;
  final String creator;
  final List<String> tags;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'name': name, 'cover': cover, 'playCount': playCount,
        'trackCount': trackCount, 'intro': intro, 'creator': creator,
        'tags': tags,
      };
}

/// 歌单曲目分页（playlistTracks：data.info[] + data.count）。
class TrackPage {
  const TrackPage({
    this.total = 0,
    this.beginIdx = 0,
    this.pageSize = 0,
    this.items = const <SongBrief>[],
  });
  final int total; // data.count
  final int beginIdx;
  final int pageSize;
  final List<SongBrief> items;

  bool get hasMore {
    try {
      return beginIdx + items.length < total;
    } catch (e, st) {
      Log.e(_tag, 'TrackPage.hasMore failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'total': total, 'beginIdx': beginIdx, 'pageSize': pageSize,
        'hasMore': hasMore,
        'items': items.map((s) => s.toMap()).toList(growable: false),
      };
}

/// 排行榜条目（rank list data.info[]）。
class RankBrief {
  const RankBrief({
    this.rankId = 0,
    this.name = '',
    this.cover = '',
    this.updateTime = '',
    this.intro = '',
  });

  final int rankId; // rankid
  final String name; // rankname
  final String cover; // imgurl
  final String updateTime;
  final String intro;

  factory RankBrief.fromMap(Map<String, dynamic> m) {
    try {
      return RankBrief(
        rankId: safeInt(m['rankid']),
        name: safeStr(m['rankname'] ?? m['name'] ?? ''),
        cover: safeStr(m['imgurl'] ?? m['img'] ?? ''),
        updateTime: safeStr(m['updatetime'] ?? ''),
        intro: safeStr(m['intro'] ?? ''),
      );
    } catch (e, st) {
      Log.e(_tag, 'RankBrief.fromMap failed', e, st);
      return const RankBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'rankId': rankId, 'name': name, 'cover': cover,
        'updateTime': updateTime, 'intro': intro,
      };
}

/// 歌词结果（lyricSearch 候选 / lyricDownload 内容）。
class LyricResult {
  const LyricResult({
    this.id = 0,
    this.accessKey = '',
    this.fmt = '',
    this.content = '',
    this.durationMs = 0,
    this.isKrc = false,
  });

  final int id; // candidates[].id（供 /download 使用）
  final String accessKey; // candidates[].accesskey
  final String fmt; // krc / lrc
  final String content; // 解密后的纯文本（krc 已 inflate，lrc 已 base64 解）
  final int durationMs; // duration（毫秒）
  final bool isKrc; // contenttype==0 → krc

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'accessKey': accessKey, 'fmt': fmt, 'durationMs': durationMs,
        'isKrc': isKrc, 'contentLength': content.length,
      };
}
