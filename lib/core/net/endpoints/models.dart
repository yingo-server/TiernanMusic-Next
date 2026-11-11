// L4 core/net/endpoints · 端点强类型结果模型（集中定义，字段缺失给默认值不崩）
// 禁 import logic/surface/flutter；仅 SDK + 同级 kugou_client。
import '../../../bridges/bridge_kernel.dart' show Log;

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
  final String singer; // SingerName / singername / singerinfo[].name 聚合
  final int mixSongId; // MixSongID（评论/上报用 mxid）
  final int albumAudioId; // AlbumAudioId / album_audio_id / Audioid
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
        // 批N1-C 实测（2026-11-12 probe，API_FIELDS_TRUTH.md A1-1）：
        // v3/song 列表项无 AlbumAudioId 键，音频 id 在 Audioid（=Scid）。
        albumAudioId: safeInt(m['AlbumAudioId'],
            safeInt(m['album_audio_id'], safeInt(m['Audioid']))),
        durationSec: safeInt(m['Duration']),
        bitrate: safeInt(m['Bitrate']),
        fileSize: safeInt(m['FileSize']),
        albumId: safeStr(m['AlbumID']),
        albumName: safeStr(m['AlbumName']),
        // 批N1-A 实测（A1-1）：musicpack_advance 在 trans_param 内。
        isVip: safeBool(m['musicpack_advance'],
            safeBool(m['trans_param'] is Map
                ? (m['trans_param'] as Map)['musicpack_advance']
                : null)),
      );
    } catch (e, st) {
      Log.e(_tag, 'SongBrief.fromSearchList failed', e, st);
      return const SongBrief();
    }
  }

  /// 批N1-B 实测（docs/API_FIELDS_TRUTH.md A2-5）：
  /// rank/audio songlist[] 映射。hash 在 audio_info.hash_128（deprecated.hash
  /// 兜底）；时长 audio_info.duration_*（毫秒）；名次 business.sort（不落本模型）。
  factory SongBrief.fromRankAudio(Map<String, dynamic> m) {
    try {
      final ai = m['audio_info'];
      final dep = m['deprecated'];
      final aiMap = ai is Map ? ai : const <String, dynamic>{};
      final depMap = dep is Map ? dep : const <String, dynamic>{};
      final dur = safeInt(aiMap['duration_128'],
          safeInt(depMap['duration']));
      final authors = m['authors'];
      final authorFallback = (authors is List && authors.isNotEmpty &&
              authors.first is Map)
          ? safeStr((authors.first as Map)['author_name'])
          : '';
      final albumInfo = m['album_info'];
      return SongBrief(
        hash: safeStr(aiMap['hash_128'], safeStr(depMap['hash']))
            .toLowerCase(),
        name: safeStr(m['songname'], m['name'] ?? ''),
        singer: safeStr(m['author_name'], authorFallback),
        mixSongId: safeInt(m['audio_id']),
        albumAudioId: safeInt(m['album_audio_id']),
        durationSec: dur > 100000 ? dur ~/ 1000 : dur,
        bitrate: safeInt(aiMap['bitrate'], safeInt(depMap['bitrate'])),
        fileSize: safeInt(aiMap['filesize_128'],
            safeInt(depMap['filesize'])),
        albumId: safeStr(m['album_id']),
        albumName: safeStr(
            albumInfo is Map ? safeStr(albumInfo['album_name']) : ''),
        // 实测：rank/audio 无 musicpack_advance；deprecated.pay_type 为
        // 权益位（值示例 0/1，非 0 视为付费/VIP 曲目）。
        isVip: safeBool(depMap['pay_type']),
      );
    } catch (e, st) {
      Log.e(_tag, 'SongBrief.fromRankAudio failed', e, st);
      return const SongBrief();
    }
  }

  factory SongBrief.fromTrackInfo(Map<String, dynamic> m) {
    try {
      // 批N1-B 实测（docs/API_FIELDS_TRUTH.md A2-3/A2-5）：
      // - 时长键是 timelen（毫秒），非 timelength；秒 = timelen/1000。
      // - 大小键是 size（bytes），非 filesize。
      // - songs[] 顶层无 singername/album_name：singer 从 singerinfo[0].name
      //   或 author_name 兜底；albumName 从 albuminfo.name 兜底。
      final tLen = safeInt(m['timelen'],
          safeInt(m['timelength'], safeInt(m['Duration'])));
      // rank/info songinfo[] 实测仅 songname/author/album_audio_id/album_cover
      //（docs/API_FIELDS_TRUTH.md A2-6），name 需 songname 兜底。
      final nm = safeStr(m['name'], safeStr(m['FileName'] ?? m['songname'] ?? ''));
      final singerInfo = m['singerinfo'];
      // 批N1-C 实测：singerinfo 是完整数组（多歌手），聚合为「、」连接。
      String singerAgg = '';
      if (singerInfo is List) {
        final names = <String>[];
        for (final si in singerInfo) {
          if (si is Map && si['name'] != null) names.add('${si['name']}');
        }
        singerAgg = names.join('、');
      }
      final singerFallback = singerAgg;
      final albumInfo = m['albuminfo'];
      final albumNameFallback = (albumInfo is Map)
          ? safeStr(albumInfo['name'],
              safeStr(albumInfo['album_name']))
          : '';
      return SongBrief(
        hash: safeStr(m['hash'], m['FileHash'] ?? '').toLowerCase(),
        name: safeStr(m['name'], m['FileName'] ?? m['songname'] ?? ''),
        singer: safeStr(m['singername'],
            safeStr(m['author_name'], singerFallback)),
        mixSongId: safeInt(m['mixsongid'], safeInt(m['MixSongID'])),
        albumAudioId: safeInt(m['album_audio_id'],
            safeInt(m['audio_id'], safeInt(m['AlbumAudioId']))),
        // timelen 单位为毫秒 → 秒；Duration（搜索域）已是秒，>100000 视为毫秒修正。
        durationSec: tLen > 100000
            ? tLen ~/ 1000
            : safeInt(m['Duration'], tLen),
        bitrate: safeInt(m['bitrate'], safeInt(m['Bitrate'])),
        fileSize: safeInt(m['size'], safeInt(m['filesize'],
            safeInt(m['FileSize']))),
        albumId: safeStr(m['album_id'], safeStr(m['AlbumID'])),
        albumName: safeStr(m['album_name'],
            safeStr(m['AlbumName'], albumNameFallback)),
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
  final String cover; // imgurl（recommend）/ pic（detail）/ img（search special）
  final int playCount;
  final int trackCount; // count / song_count
  final String creator; // username / list_create_username / nickname
  final String intro;

  factory PlaylistBrief.fromMap(Map<String, dynamic> m) {
    try {
      return PlaylistBrief(
        id: safeStr(
            m['global_collection_id'] ?? m['specialid'] ?? m['listid'] ??
                m['id'] ?? ''),
        name: safeStr(m['specialname'] ?? m['name'] ?? ''),
        // 批N1-C 实测（API_FIELDS_TRUTH.md A2-2/A2-3/A2-4）：
        // - recommend special_list[]：cover 键 imgurl（recommend 命中），搜索
        //   special 命中是 img；play_count（下划线）、song_count。
        // - detail 首项：cover 键 pic（无 imgurl）、count、creator 键
        //   list_create_username（无 username）。tags 为逗号分隔字符串。
        cover: safeStr(m['imgurl'] ?? m['pic'] ?? m['img'] ?? m['cover'] ?? ''),
        playCount: safeInt(m['playcount'] ?? m['play_count']),
        trackCount: safeInt(m['count'] ?? m['song_count'] ?? m['track_count']),
        creator: safeStr(m['username'] ?? m['list_create_username'] ??
            m['nickname'] ?? ''),
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
      // 批N1-B 实测（docs/API_FIELDS_TRUTH.md A2-4）：rank/list info[] 无
      // updatetime 键；更新时间键是 rank_id_publish_date（期号发布时间），
      // 另有 update_frequency（频率描述）/ rank_cid（本期快照 id）/ issue（期号）。
      return RankBrief(
        rankId: safeInt(m['rankid']),
        name: safeStr(m['rankname'] ?? m['name'] ?? ''),
        cover: safeStr(m['imgurl'] ?? m['img'] ?? ''),
        // 批N1-C 实测（A2-4 rank/list info[]）：更新时间键是
        // rank_id_publish_date；另有 update_frequency（频率描述）。
        updateTime: safeStr(m['rank_id_publish_date'] ??
            m['updatetime'] ?? m['update_frequency'] ?? ''),
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

final int id; // candidates[].id（供 /download 使用；批N2-A 实测为字符串，safeInt 容错）
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
