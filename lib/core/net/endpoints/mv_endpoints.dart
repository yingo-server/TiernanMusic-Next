// L4 core/net/endpoints · MV/视频端点封装（批1-B · GAP_ANALYSIS #16）
// 端点出处（docs/KUGOU_API.md §3.9 / docs/PARITY_NOTES.md §1）：
// - mvDetail: POST /kmr/audio/mv，x-router openapi.kugou.com，kg-tid 38，
//   body {album_audio_id}；返回 data.list[0] 为 MV 摘要。
// - videoDetail: POST /v1/video/detail（备用 /kmr/v2/videos），
//   x-router kmr.service.kugou.com；响应含清晰度档位（hash 齐全）。
// - videoUrl: GET /v2/interface/index，x-router trackermv.kugou.com，
//   参数 hash/quality；返回 downurl（多 CDN 数组）。
// 铁律：全部字段容错（safe*/dataOf/listOf），每函数 try/catch + Log('ep.mv')。
import '../../../kernel/kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show safeInt, safeStr, dataOf, listOf;

const String _tag = 'ep.mv';

/// MV 摘要（kmr/audio/mv data.list[0]）。
class MvBrief {
  const MvBrief({
    this.hash = '',
    this.name = '',
    this.singer = '',
    this.durationMs = 0,
    this.coverUrl = '',
  });

  final String hash; // MV hash（清晰度查询用）
  final String name; // mvname / filename
  final String singer; // singername / author_name
  final int durationMs; // duration（毫秒）
  final String coverUrl; // imgurl / cover / suaac_cover

  factory MvBrief.fromMap(Map<String, dynamic> m) {
    try {
      return MvBrief(
        hash: safeStr(m['hash'] ?? m['mvhash'] ?? m['video_hash'])
            .toLowerCase(),
        name: safeStr(m['mvname'] ?? m['filename'] ?? m['name'] ?? ''),
        singer: safeStr(
            m['singername'] ?? m['author_name'] ?? m['singer'] ?? ''),
        durationMs: safeInt(m['duration'] ?? m['timelength']),
        coverUrl: safeStr(
            m['imgurl'] ?? m['cover'] ?? m['suaac_cover'] ?? m['img'] ?? ''),
      );
    } catch (e, st) {
      Log.e(_tag, 'MvBrief.fromMap failed', e, st);
      return const MvBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'hash': hash, 'name': name, 'singer': singer,
        'durationMs': durationMs, 'coverUrl': coverUrl,
      };

  @override
  String toString() {
    try {
      return 'MvBrief(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'MvBrief.toString failed', e, st);
      return 'MvBrief(<unavailable>)';
    }
  }
}

/// MV 清晰度档位（video/detail 响应档位列表项）。
class MvQuality {
  const MvQuality({
    this.id = '',
    this.label = '',
    this.hash = '',
    this.size = 0,
  });

  final String id; // 档位 id（如 sd/hd/fhd/uhd 或数值串）
  final String label; // 展示名（标准/高清/超高清…）
  final String hash; // 该档位视频 hash（videoUrl 用）
  final int size; // 字节数（fileSize/size）

  factory MvQuality.fromMap(Map<String, dynamic> m) {
    try {
      return MvQuality(
        id: safeStr(m['id'] ?? m['quality'] ?? m['transcateid'] ?? ''),
        label: safeStr(m['name'] ?? m['label'] ?? m['desc'] ?? m['id'] ?? ''),
        hash: safeStr(m['hash'] ?? m['video_hash'] ?? m['filehash'])
            .toLowerCase(),
        size: safeInt(m['size'] ?? m['filesize'] ?? m['file_size']),
      );
    } catch (e, st) {
      Log.e(_tag, 'MvQuality.fromMap failed', e, st);
      return const MvQuality();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'label': label, 'hash': hash, 'size': size,
      };

  @override
  String toString() {
    try {
      return 'MvQuality(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'MvQuality.toString failed', e, st);
      return 'MvQuality(<unavailable>)';
    }
  }
}

/// MV 播放结果（video/url downurl，多 CDN 容错）。
class MvPlayResult {
  const MvPlayResult({
    this.urls = const <String>[],
    this.quality = '',
    this.title = '',
  });

  final List<String> urls; // downurl 主链 + 备链（全部保留，调用方逐个容错）
  final String quality; // 实际命中的档位 id
  final String title;

  bool get playable {
    try {
      return urls.isNotEmpty;
    } catch (e, st) {
      Log.e(_tag, 'MvPlayResult.playable failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'urls': urls, 'quality': quality, 'title': title,
      };

  @override
  String toString() {
    try {
      return 'MvPlayResult(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'MvPlayResult.toString failed', e, st);
      return 'MvPlayResult(<unavailable>)';
    }
  }
}

/// 容错收集字符串数组字段（数组/逗号串/单串均兼容）。
List<String> _collectUrls(Object? v) {
  try {
    final out = <String>[];
    if (v is List) {
      out.addAll(v.map((u) => safeStr(u)).where((u) => u.isNotEmpty));
    } else if (v is String && v.isNotEmpty) {
      if (v.contains(',')) {
        out.addAll(v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
      } else {
        out.add(v);
      }
    }
    return out;
  } catch (e, st) {
    Log.e(_tag, '_collectUrls failed', e, st);
    return const <String>[];
  }
}

/// getMvBySong：按 album_audio_id 查 MV（kmr/audio/mv，body {album_audio_id}，
/// data.list[0]）。查不到返回 null。
Future<MvBrief?> getMvBySong(KugouClient client, int albumAudioId) async {
  try {
    if (albumAudioId <= 0) {
      Log.w(_tag, 'getMvBySong invalid albumAudioId=$albumAudioId');
      return null;
    }
    final res = await client.request(EndpointRegistry.mvDetail,
        const <String, Object?>{},
        body: <String, Object?>{'album_audio_id': albumAudioId});
    final data = dataOf(res);
    final list = listOf(data['list'] ?? data['info'] ?? data['mv_list']);
    if (list.isEmpty) {
      Log.d(_tag, 'getMvBySong empty list aid=$albumAudioId');
      return null;
    }
    final mv = MvBrief.fromMap(list.first);
    Log.d(_tag,
        'getMvBySong aid=$albumAudioId hash=${mv.hash.isEmpty ? '-' : mv.hash}');
    if (mv.hash.isEmpty) return null;
    return mv;
  } catch (e, st) {
    Log.e(_tag, 'getMvBySong failed aid=$albumAudioId', e, st);
    return null;
  }
}

/// getVideoQualities：MV 清晰度档位（video/detail）。
/// 主路径 /v1/video/detail；空档/异常时容错回退 /kmr/v2/videos 同参重试一次。
Future<List<MvQuality>> getVideoQualities(
  KugouClient client,
  String mvHash,
) async {
  try {
    final h = mvHash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'getVideoQualities empty hash');
      return const <MvQuality>[];
    }
    final body = <String, Object?>{'hash': h};
    var res = await client.request(
        EndpointRegistry.videoDetail, const <String, Object?>{}, body: body);
    var items = _parseQualities(res);
    if (items.isEmpty) {
      Log.w(_tag, 'videoDetail empty qualities, fallback kmr/v2/videos');
      res = await client.request(EndpointRegistry.videoDetailKmrV2,
          const <String, Object?>{}, body: body);
      items = _parseQualities(res);
    }
    Log.d(_tag, 'getVideoQualities hash=$h got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getVideoQualities failed hash=$mvHash', e, st);
    return const <MvQuality>[];
  }
}

/// 容错解析 video/detail 响应中的档位列表。
/// 常见形态：data.list[] / data.files[] / data.translations[] / data.videos[]。
List<MvQuality> _parseQualities(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    for (final key in const ['list', 'files', 'translations', 'videos', 'data']) {
      final raw = data[key] ?? res[key];
      final items = listOf(raw).map(MvQuality.fromMap).where(
        (q) {
          try {
            return q.hash.isNotEmpty;
          } catch (e, st) {
            Log.e(_tag, '_parseQualities filter failed', e, st);
            return false;
          }
        },
      ).toList(growable: false);
      if (items.isNotEmpty) return items;
    }
    return const <MvQuality>[];
  } catch (e, st) {
    Log.e(_tag, '_parseQualities failed', e, st);
    return const <MvQuality>[];
  }
}

/// getVideoUrl：按清晰度 hash 取播放地址（video/url，GET /v2/interface/index，
/// 参数 hash/quality）。downurl 为多 CDN（主链+备链），全部收集由调用方容错。
Future<MvPlayResult> getVideoUrl(
  KugouClient client,
  String qualityHash, {
  String quality = '',
  String title = '',
}) async {
  try {
    final h = qualityHash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'getVideoUrl empty hash');
      return const MvPlayResult();
    }
    final res = await client.request(EndpointRegistry.videoUrl,
        <String, Object?>{
      'hash': h,
      'quality': quality.trim().isEmpty ? 'mp4' : quality.trim(),
      'cmd': 12,
      'pid': 2,
      'ssl': 1,
      'ext': 'mp4',
    });
    // downurl 常见：顶层 downurl（数组/分号串）或 data.downurl。
    var urls = _collectUrls(res['downurl'] ?? res['backupUrl']);
    if (urls.isEmpty) {
      final data = dataOf(res);
      urls = _collectUrls(data['downurl'] ?? data['url']);
    }
    // 分号拼接形态拆分（trackermv 常见返回 "a|b|c" 或 "a;b;c"）。
    if (urls.length == 1 && (urls.first.contains('|'))) {
      try {
        urls = urls.first
            .split(RegExp(r'[|;]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      } catch (e, st) {
        Log.e(_tag, 'getVideoUrl split multi-cdn failed', e, st);
      }
    }
    final r = MvPlayResult(urls: urls, quality: quality, title: title);
    Log.d(_tag,
        'getVideoUrl hash=$h cdn=${urls.length} ok=${r.playable}');
    return r;
  } catch (e, st) {
    Log.e(_tag, 'getVideoUrl failed hash=$qualityHash', e, st);
    return const MvPlayResult();
  }
}
