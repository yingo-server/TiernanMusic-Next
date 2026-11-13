// L4 core/net/endpoints · 歌曲域模型（SongBrief/SearchResult/SearchSuggestItem）
// 来源拆分：models.dart（614 行超行拆分，R2-A）；类体逐字搬移，零逻辑改动。
import '../../../bridges/bridge_kernel.dart' show Log;
import 'models_util.dart';


const String _tag = 'net.models.song';
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
    this.cover = '',
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

  /// 封面图 URL（最佳努力映射：Image/album_cover/cover 等键）。
  /// 为空时 UI 显示占位图标，不伪造封面。
  final String cover;
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
        // 封面：搜索列表常见键 Image；同时容错 img/cover。
        cover: safeStr(m['Image'],
            safeStr(m['img'], safeStr(m['cover'], m['AlbumImage'] ?? ''))),
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

  /// 批N2-B 实测（docs/API_FIELDS_TRUTH.md A4-2，2026-11-12）：
  /// /v1/album_audio/lite data.songs[] 映射。item 10 键：base{audio_name/
  /// author_name/album_id/audio_id/album_audio_id}/audio_info{hash/hash_128/
  /// filesize/duration(ms)/bitrate/extname}/album_info{album_name/cover}/
  /// authors[{author_name,author_id}]/copyright/deprecated/extend/extra/
  /// mvdata[{typ,trk,hash,id}]/trans_param。与 pubsongs nofilt 口径
  ///（fromTrackInfo）不同族，专用工厂。
  factory SongBrief.fromAlbumLite(Map<String, dynamic> m) {
    try {
      final base = m['base'];
      final ai = m['audio_info'];
      final alb = m['album_info'];
      final baseMap = base is Map ? base : const <String, dynamic>{};
      final aiMap = ai is Map ? ai : const <String, dynamic>{};
      final albMap = alb is Map ? alb : const <String, dynamic>{};
      // duration 实测毫秒（如 226873），>100000 视为毫秒修正。
      final dur = safeInt(aiMap['duration']);
      return SongBrief(
        hash: safeStr(aiMap['hash'] ?? aiMap['hash_128'] ??
                m['hash'] ?? m['FileHash'])
            .toLowerCase(),
        name: safeStr(baseMap['audio_name'] ?? m['name'] ??
            m['FileName'] ?? ''),
        // 实测：顶层无 singer 键；base.author_name 优先，authors[] 聚合兜底。
        singer: safeStr(baseMap['author_name'], () {
          final authors = m['authors'];
          if (authors is List && authors.isNotEmpty &&
              authors.first is Map) {
            final names = <String>[];
            for (final a in authors) {
              if (a is Map && a['author_name'] != null) {
                names.add('${a['author_name']}');
              }
            }
            return names.join('、');
          }
          return '';
        }()),
        mixSongId: safeInt(m['mixsongid'] ?? baseMap['audio_id']),
        albumAudioId: safeInt(baseMap['album_audio_id'] ??
            m['album_audio_id']),
        durationSec: dur > 100000 ? dur ~/ 1000 : dur,
        bitrate: safeInt(aiMap['bitrate']),
        fileSize: safeInt(aiMap['filesize']),
        albumId: safeStr(baseMap['album_id'] ?? m['album_id']),
        albumName: safeStr(albMap['album_name']),
        isVip: safeBool(m['musicpack_advance'],
            safeBool(m['trans_param'] is Map
                ? (m['trans_param'] as Map)['musicpack_advance']
                : null)),
      );
    } catch (e, st) {
      Log.e(_tag, 'SongBrief.fromAlbumLite failed', e, st);
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
        // 批N3-C 实测（A4-2' audio_group/author）：item 顶层键为 audio_name，
        // 无 name/songname —— 加 audio_name 兜底（放 songname 之后，
        // 不影响既有 pubsongs/rank 口径）。
        name: safeStr(m['name'],
            m['FileName'] ?? m['songname'] ?? m['audio_name'] ?? ''),
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
        cover: safeStr(m['album_cover'],
            safeStr(m['album_img'],
                safeStr(m['Image'], safeStr(m['img'], m['cover'] ?? '')))),
        // 批N3-C 实测：audio_group/author 的 musicpack_advance 在 trans_param
        // 内（顶层无 musicpack_advance）——补 trans_param 兜底。
        isVip: safeBool(m['musicpack_advance'],
            safeBool(m['trans_param'] is Map
                ? (m['trans_param'] as Map)['musicpack_advance']
                : null)),
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
        'albumName': albumName, 'cover': cover, 'isVip': isVip,
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

