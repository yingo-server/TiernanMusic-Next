// L4 core/net/endpoints · MV/视频端点封装（批1-B · GAP_ANALYSIS #16）
// 端点出处（docs/KUGOU_API.md §3.9 / docs/PARITY_NOTES.md §1）：
// - mvDetail: POST /kmr/v1/audio/mv，x-router openapi.kugou.com，kg-tid 38，
//   body {data:[{album_audio_id}], fields:''}；返回 data 是**嵌套数组**
//   data[0][]（批N2-B 实测 2026-11-12，n2b_mv_dump.json），首项即 MV 摘要。
// - videoDetail: POST /v1/video（备用 /kmr/v2/videos），
//   x-router kmr.service.kugou.com；响应 data[0] 平铺清晰度档位
//   （ld/sd/hd/fhd/qhd 各配 hash/filesize/bitrate/width/height + *_265 + mkv_*）。
//   ⚠️ 实测签名形态：clearDefaultParams + body 全参数（含 key=signParamsKey）
//   ——见 getVideoQualities 注释与 EndpointRegistry.videoDetail 声明。
// - videoUrl: GET /v2/interface/index，x-router trackermv.kugou.com，
//   参数 backupdomain=1/cmd=123/ext=mp4/ismp3=0/hash/pid=1/type=1，
//   ⚠️ 必带 key=md5(hash+57ae12eb…+appid+mid+userid||0)（signKey），否则
//   errcode 40003 "Empty key"（批N2-B 实测）；返回 data[hash].downurl(字符串)
//   + backupdownurl(数组)。
// 铁律：全部字段容错（safe*/dataOf/listOf），每函数 try/catch + Log('ep.mv')。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show safeInt, safeStr, dataOf, listOf;
import 'cover_url.dart' show normalizeCoverUrl;

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
  final String name; // mv_name / filename
  final String singer; // singername / author_name
  final int durationMs; // duration（毫秒，实测 231732=3:51）
  final String coverUrl; // hdpic / thumb（{size} 模板）

  factory MvBrief.fromMap(Map<String, dynamic> m) {
    try {
      return MvBrief(
        // 批N2-B 实测（kmr/v1/audio/mv data[0][0]）：hash 键是 deprecated.hash /
        // mvdata[].hash 携带于上层 song 项；MV 摘要项本身标识键是 video_id，
        // hash 由上游 mvdata 传入 → 保留 hash/mvhash/video_hash 三兜底。
        hash: safeStr(m['hash'] ?? m['mvhash'] ?? m['video_hash'])
            .toLowerCase(),
        // 实测键：mv_name（非 mvname/filename）。
        name: safeStr(m['mv_name'] ?? m['mvname'] ?? m['filename'] ?? m['name'] ?? ''),
        singer: safeStr(
            m['singername'] ?? m['author_name'] ?? m['singer'] ?? ''),
        // 实测键：duration（毫秒，如 231732=3:51）。
        durationMs: safeInt(m['duration'] ?? m['timelength']),
        // 实测键：hdpic（{size} 模板高清封面）/ thumb（缩略图）。
        coverUrl: normalizeCoverUrl(safeStr(
            m['hdpic'] ?? m['imgurl'] ?? m['cover'] ?? m['thumb'] ??
            m['suaac_cover'] ?? m['img'] ?? '')),
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

  /// 批N2-B 实测（/v1/video data[0] 平铺档位）：无档位数组，档位以
  /// `ld/sd/hd/fhd/qhd` 前缀展开（ld_hash/sd_hash/…/qhd_hash_265/mkv_*）。
  /// 由 data[0] 直接抽取 [MvQuality] 列表（主档 + 265 档 + mkv 档）。
  static List<MvQuality> fromFlat(Map<String, dynamic> d) {
    try {
      final out = <MvQuality>[];
      const tiers = <String, String>{
        'ld': '流畅 270P', 'sd': '标清 432P', 'hd': '高清 720P',
        'fhd': '全高清 1080P', 'qhd': '超高清 540P',
      };
      for (final e in tiers.entries) {
        final h = safeStr(d['${e.key}_hash']).toLowerCase();
        if (h.isEmpty) continue;
        out.add(MvQuality(
          id: e.key,
          label: e.value,
          hash: h,
          size: safeInt(d['${e.key}_filesize']),
        ));
        final h265 = safeStr(d['${e.key}_hash_265']).toLowerCase();
        if (h265.isNotEmpty) {
          out.add(MvQuality(
            id: '${e.key}_265',
            label: '${e.value} H.265',
            hash: h265,
            size: safeInt(d['${e.key}_filesize_265']),
          ));
        }
      }
      final mkvH = safeStr(d['mkv_qhd_hash']).toLowerCase();
      if (mkvH.isNotEmpty) {
        out.add(MvQuality(
          id: 'mkv_qhd', label: 'MKV 超高清',
          hash: mkvH, size: safeInt(d['mkv_qhd_filesize']),
        ));
      }
      return out;
    } catch (e, st) {
      Log.e(_tag, 'MvQuality.fromFlat failed', e, st);
      return const <MvQuality>[];
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
    // 批N2-B 实测（n2b_mv_dump.json）：真实口径 POST /kmr/v1/audio/mv
    // （kg-tid 38），body {data:[{album_audio_id}], fields:''}；响应 data 为
    // 嵌套数组 data[0][]。/kmr/audio/mv 旧口径实测 502（网关不存在）。
    final res = await client.request(EndpointRegistry.mvDetail,
        const <String, Object?>{},
        body: <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'album_audio_id': '$albumAudioId'},
          ],
          'fields': '',
        });
    final data = dataOf(res);
    // 嵌套数组容错：data[0][] 优先，回退 data.list / data.info / data 平铺。
    var list = <Map<String, dynamic>>[];
    if (data['data'] is List && (data['data'] as List).isNotEmpty) {
      final first = (data['data'] as List).first;
      if (first is List) {
        list = listOf(first);
      } else {
        list = listOf(data['data']);
      }
    }
    if (list.isEmpty) {
      list = listOf(data['list'] ?? data['info'] ?? data['mv_list'] ?? data);
    }
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

/// getVideoUrl：按清晰度 hash 取播放地址（GET /v2/interface/index，
/// x-router trackermv）。
/// 批N2-B 实测：参数必须 backupdomain=1/cmd=123/ext=mp4/ismp3=0/pid=1/type=1
/// + hash，且 **必带 key=md5(hash+signKeySalt+appid+mid+userid||0)**
/// （signKey；endpoint 声明 encryptKey=true 由 KugouClient 自动注入），
/// 否则 errcode 40003 "Empty key"/"Bad cmd"（cmd=12/4/25 均拒绝）。
/// 成功响应：{status:1, privileges:{hash:0/1}, data:{hash:{downurl:"…",
/// backupdownurl:["…"], filesize}}}——downurl 为单串（主链），
/// backupdownurl 为备链数组。
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
      'backupdomain': 1,
      'cmd': 123,
      'ext': 'mp4',
      'ismp3': 0,
      'pid': 1,
      'type': 1,
    });
    // 实测形态：data[hash].downurl（单串）+ data[hash].backupdownurl（数组）。
    final data = dataOf(res);
    var bucket = <String, dynamic>{};
    final db = data[h];
    if (db is Map) bucket = db.map((k, v) => MapEntry('$k', v));
    var urls = <String>[
      ..._collectUrls(bucket['downurl']),
      ..._collectUrls(bucket['backupdownurl']),
    ];
    // 兼容旧形态：顶层 downurl / data.downurl / backupUrl。
    if (urls.isEmpty) {
      urls = _collectUrls(res['downurl'] ?? res['backupUrl']);
    }
    if (urls.isEmpty) {
      urls = _collectUrls(data['downurl'] ?? data['url']);
    }
    // 去重（主链与备链偶有重叠）。
    final seen = <String>{};
    urls = urls.where((u) => seen.add(u)).toList(growable: false);
    final r = MvPlayResult(urls: urls, quality: quality, title: title);
    Log.d(_tag,
        'getVideoUrl hash=$h cdn=${urls.length} ok=${r.playable}');
    return r;
  } catch (e, st) {
    Log.e(_tag, 'getVideoUrl failed hash=$qualityHash', e, st);
    return const MvPlayResult();
  }
}
