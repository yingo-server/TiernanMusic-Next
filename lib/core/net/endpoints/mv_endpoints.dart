// L4 core/net/endpoints · MV/视频端点封装（批1-B · GAP_ANALYSIS #16）
// 端点出处（docs/KUGOU_API.md §3.9 / docs/PARITY_NOTES.md §1）：
// - mvDetail: POST /kmr/v1/audio/mv，x-router openapi.kugou.com，kg-tid 38，
//   body {data:[{album_audio_id}], fields:''}；返回 data 是**嵌套数组**
//   data[0][]（批N2-B 实测 2026-11-12，n2b_mv_dump.json），首项即 MV 摘要。
// 铁律：全部字段容错（safe*/dataOf/listOf），每函数 try/catch + Log('ep.mv')。
// - anonymousSongUrl（批3-F1 新增，⚠️ 待实测）：GET /v5/url @ trackercdn，
//   notSign（signType none）、encryptKey、匿名随机 dfid、IsFreePart 试听
//   （song_url.js L32/49-52，batch3_c3.md §1）——见 anonymousPlayUrl。
// - registerDevice（批3-F1 新增，⚠️ 待实测）：POST /risk/v2/r_register_dev
//   取真实 dfid（register_dev.js，batch3_c3.md §4）——见 registerDevice。
// - videoDetail: POST /v1/video，x-router kmr.service.kugou.com；响应
//   data[0] 平铺清晰度档位（ld/sd/hd/fhd/qhd 各配 hash/filesize/bitrate/
//   width/height + *_265 + mkv_*）。⚠️ 实测签名形态：clearDefaultParams +
//   body 全参数（含 key=signParamsKey）——见 getVideoQualities 注释与
//   EndpointRegistry.videoDetail 声明。备用 /kmr/v2/videos 已弃用（三态
//   实测 404，批3-F1 删除 fallback）。
// - videoUrl: GET /v2/interface/index，x-router trackermv.kugou.com，
//   参数 backupdomain=1/cmd=123/ext=mp4/ismp3=0/hash/pid=1/type=1，
//   ⚠️ 必带 key=md5(hash+57ae12eb…+appid+mid+userid||0)（signKey），否则
//   errcode 40003 "Empty key"（批N2-B 实测）；返回 data[hash].downurl(字符串)
//   + backupdownurl(数组)。
import 'dart:convert';

import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import '../crypto_rsa.dart'
    show playlistAesEncrypt, rsaEncrypt2, playlistAesDecrypt;
import '../signing.dart' show KugouSign, md5Hex;
import 'models.dart' show safeInt, safeStr, dataOf, listOf;
import 'cover_url.dart' show normalizeCoverUrl;

const String _tag = 'ep.mv';

/// MV 摘要（kmr/audio/mv data[0][0]）。
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
        name: safeStr(
          m['mv_name'] ?? m['mvname'] ?? m['filename'] ?? m['name'] ?? '',
        ),
        singer: safeStr(
          m['singername'] ?? m['author_name'] ?? m['singer'] ?? '',
        ),
        // 实测键：duration（毫秒，如 231732=3:51）。
        durationMs: safeInt(m['duration'] ?? m['timelength']),
        // 实测键：hdpic（{size} 模板高清封面）/ thumb（缩略图）。
        coverUrl: normalizeCoverUrl(
          safeStr(
            m['hdpic'] ??
                m['imgurl'] ??
                m['cover'] ??
                m['thumb'] ??
                m['suaac_cover'] ??
                m['img'] ??
                '',
          ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'MvBrief.fromMap failed', e, st);
      return const MvBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'hash': hash,
    'name': name,
    'singer': singer,
    'durationMs': durationMs,
    'coverUrl': coverUrl,
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

/// MV 清晰度档位（video/detail data[0] 平铺档位列表项）。
class MvQuality {
  const MvQuality({
    this.id = '',
    this.label = '',
    this.hash = '',
    this.size = 0,
  });

  final String id; // 档位 id（ld/sd/hd/fhd/qhd(+_265)/mkv_qhd）
  final String label; // 展示名
  final String hash; // 该档位视频 hash（videoUrl 用）
  final int size; // 字节数（*_filesize）

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

  /// 批N2-B 实测（/v1/video data[0] 平铺档位）：档位以 ld/sd/hd/fhd/qhd
  /// 前缀展开（ld_hash/…/qhd_hash_265/mkv_*），由 data[0] 直接抽取列表。
  static List<MvQuality> fromFlat(Map<String, dynamic> d) {
    try {
      final out = <MvQuality>[];
      const tiers = <String, String>{
        'ld': '流畅 270P',
        'sd': '标清 432P',
        'hd': '高清 720P',
        'fhd': '全高清 1080P',
        'qhd': '超高清 540P',
      };
      for (final e in tiers.entries) {
        final h = safeStr(d['${e.key}_hash']).toLowerCase();
        if (h.isEmpty) continue;
        out.add(
          MvQuality(
            id: e.key,
            label: e.value,
            hash: h,
            size: safeInt(d['${e.key}_filesize']),
          ),
        );
        final h265 = safeStr(d['${e.key}_hash_265']).toLowerCase();
        if (h265.isNotEmpty) {
          out.add(
            MvQuality(
              id: '${e.key}_265',
              label: '${e.value} H.265',
              hash: h265,
              size: safeInt(d['${e.key}_filesize_265']),
            ),
          );
        }
      }
      final mkvH = safeStr(d['mkv_qhd_hash']).toLowerCase();
      if (mkvH.isNotEmpty) {
        out.add(
          MvQuality(
            id: 'mkv_qhd',
            label: 'MKV 超高清',
            hash: mkvH,
            size: safeInt(d['mkv_qhd_filesize']),
          ),
        );
      }
      return out;
    } catch (e, st) {
      Log.e(_tag, 'MvQuality.fromFlat failed', e, st);
      return const <MvQuality>[];
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'label': label,
    'hash': hash,
    'size': size,
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

  final List<String> urls; // downurl 主链 + 备链（调用方逐个容错）
  final String quality; // 实际命中的档位 id
  final String title;

  bool get playable => urls.isNotEmpty;

  Map<String, Object?> toMap() => <String, Object?>{
    'urls': urls,
    'quality': quality,
    'title': title,
  };
}

/// 容错收集字符串数组字段（数组/逗号串/单串均兼容）。
List<String> _collectUrls(Object? v) {
  try {
    if (v is List) {
      return v.map((u) => safeStr(u)).where((u) => u.isNotEmpty).toList();
    }
    final s = v is String ? v : '';
    if (s.contains(',')) {
      return s
          .split(',')
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
    }
    return s.isEmpty ? const <String>[] : <String>[s];
  } catch (e, st) {
    Log.e(_tag, '_collectUrls failed', e, st);
    return const <String>[];
  }
}

/// getMvBySong：按 album_audio_id 查 MV（kmr/audio/mv）。查不到返回 null。
Future<MvBrief?> getMvBySong(KugouClient client, int albumAudioId) async {
  try {
    if (albumAudioId <= 0) {
      Log.w(_tag, 'getMvBySong invalid albumAudioId=$albumAudioId');
      return null;
    }
    // 批N2-B 实测（n2b_mv_dump.json）：POST /kmr/v1/audio/mv（kg-tid 38），
    // body {data:[{album_audio_id}], fields:''}；响应 data 嵌套数组 data[0][]。
    final res = await client.request(
      EndpointRegistry.mvDetail,
      const <String, Object?>{},
      body: <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'album_audio_id': '$albumAudioId'},
        ],
        'fields': '',
      },
    );
    final data = dataOf(res);
    // 嵌套数组容错：data[0][] 优先，回退 data.list / data.info / data 平铺。
    var list = <Map<String, dynamic>>[];
    final dd = data['data'];
    if (dd is List && dd.isNotEmpty) {
      final first = dd.first;
      list = first is List ? listOf(first) : listOf(dd);
    }
    if (list.isEmpty) {
      list = listOf(data['list'] ?? data['info'] ?? data['mv_list'] ?? data);
    }
    if (list.isEmpty) {
      Log.d(_tag, 'getMvBySong empty list aid=$albumAudioId');
      return null;
    }
    final mv = MvBrief.fromMap(list.first);
    Log.d(
      _tag,
      'getMvBySong aid=$albumAudioId '
      'hash=${mv.hash.isEmpty ? '-' : mv.hash}',
    );
    if (mv.hash.isEmpty) return null;
    return mv;
  } catch (e, st) {
    Log.e(_tag, 'getMvBySong failed aid=$albumAudioId', e, st);
    return null;
  }
}

/// getVideoQualities：MV 清晰度档位（POST /v1/video，batch3_c1.md §1.2
/// 契约对齐）。body 按 video_detail.js 上游契约：clearDefaultParams 全参
/// data:[{video_id}], show_resolution:1, mid, uuid=md5(dfid+mid),
/// key=signParamsKey(clienttime 秒)（时间 md5，非盐 key，匿名可构造）。
/// 响应 data[0] 平铺档位 → MvQuality.fromFlat；kmr/v2 fallback 已删
/// （三态实测 404，registry 注「已弃用」）。
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
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final mid = client.session.mid.isEmpty ? '0' : client.session.mid;
    final body = <String, Object?>{
      'appid': KugouSign.appid,
      'clientver': KugouSign.clientver,
      'clienttime': clienttime,
      'mid': mid,
      'uuid': md5Hex('${client.session.dfid}$mid'),
      'dfid': client.session.dfid,
      'token': client.session.token,
      'key': KugouSign.signParamsKey('$clienttime'),
      'show_resolution': 1,
      'data': <Object?>[
        <String, Object?>{'video_id': h},
      ],
    };
    final res = await client.request(
      EndpointRegistry.videoDetail,
      const <String, Object?>{},
      body: body,
    );
    final data = dataOf(res);
    // 实测形态（field_truth L600-617）：data[0] 平铺 ld/sd/hd/fhd/qhd(+265/
    // mkv_*) hash 键。优先 data[0]（Map 形态），兜底 data 平铺。
    final d0 = data['data'] is List && (data['data'] as List).isNotEmpty
        ? (data['data'] as List).first
        : null;
    final items = d0 is Map
        ? MvQuality.fromFlat(d0.map((k, v) => MapEntry('$k', v)))
        : data.isNotEmpty
        ? MvQuality.fromFlat(data)
        : const <MvQuality>[];
    if (items.isEmpty) {
      Log.w(
        _tag,
        'getVideoQualities no flat tiers hash=$h '
        '(kmr/v2 fallback removed: 404 deprecated)',
      );
    }
    Log.d(_tag, 'getVideoQualities hash=$h got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getVideoQualities failed hash=$mvHash', e, st);
    return const <MvQuality>[];
  }
}

/// getVideoUrl：按清晰度 hash 取播放地址（GET /v2/interface/index，
/// x-router trackermv）。批N2-B 实测：必带 backupdomain=1/cmd=123/ext=mp4/
/// ismp3=0/pid=1/type=1 + hash + key=md5(hash+salt+appid+mid+userid||0)
/// （encryptKey 自动注入），缺 key 40003 "Empty key"；响应
/// data[hash].downurl(串)+backupdownurl(数组)。
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
    final res = await client.request(
      EndpointRegistry.videoUrl,
      <String, Object?>{
        'hash': h,
        'backupdomain': 1,
        'cmd': 123,
        'ext': 'mp4',
        'ismp3': 0,
        'pid': 1,
        'type': 1,
      },
    );
    // 实测形态：data[hash].downurl（单串）+ data[hash].backupdownurl（数组）。
    final data = dataOf(res);
    final db = data[h];
    var bucket = db is Map
        ? db.map((k, v) => MapEntry('$k', v))
        : <String, dynamic>{};
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
    Log.d(_tag, 'getVideoUrl hash=$h cdn=${urls.length} ok=${r.playable}');
    return r;
  } catch (e, st) {
    Log.e(_tag, 'getVideoUrl failed hash=$qualityHash', e, st);
    return const MvPlayResult();
  }
}

/// registerDevice（批3-F1 新增封装，⚠️ 待实测）：匿名设备注册取真实 dfid
/// （POST /risk/v2/r_register_dev，batch3_c3.md §4 register_dev.js）。
/// body = playlistAesEncrypt(dataMap)（30+ 设备指纹默认值，L13-96）；
/// query part=1, platid=2（⚠️ 上游 L100 明示 platid:1，变体待实测定稿），
/// p=rsaEncrypt2({aes,uid:'0',token:''})（hex 大小写形态待实测）；
/// 响应 AES 解密，status==1 时 data.dfid 回写 session.dfid（L119-122）。
/// 成功返回 dfid，失败 ''；未实测前调用方不得依赖此 dfid。
