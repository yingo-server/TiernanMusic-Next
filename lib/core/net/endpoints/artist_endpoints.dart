// L4 core/net/endpoints · 歌手域端点封装（功能对齐批4-A · GAP #22）
// 装配：KugouClient 由 boot 注入 L5 ArtistLogic；模型经 bridge_core 转出 L6，
//   surface 不直接引用本文件。端点声明见 EndpointRegistry.artist*（KUGOU_API §3.6）。
// ⚠️ audios 签名需 defaultParams+body 合并，clearDefaultParams 会 20006
//   （PARITY_NOTES §1 / FEATURE_PARITY「特殊签名要求」）；详见 getArtistAudios 注释。
// 铁律：dfid/mid/uuid 恒显式携带并参与签名；只连官方 gateway；字段全容错；
//   每函数 try/catch + Log('ep.artist')，失败留痕不静默吞。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show SongBrief, dataOf, listOf, safeInt, safeStr;
const String _tag = 'ep.artist';
// 路径常量与 EndpointRegistry 声明一致；L5 缓存键复用，避免两处漂移。
const String kArtistListPath = '/ocean/v6/singer/list';
const String kArtistDetailPath = '/kmr/v3/author';
const String kArtistAudiosPath = '/kmr/v1/audio_group/author';
const String kArtistAlbumsPath = '/v1/author/albums';

/// 设备/会话三参恒显式入场参与 android 签名（mid 客户端只自动进 header）。
Map<String, Object?> _baseParams(KugouClient client) {
  try {
    return <String, Object?>{'dfid': client.session.dfid,
        'mid': client.session.mid, 'uuid': '-'};
  } catch (e, st) {
    Log.e(_tag, '_baseParams failed', e, st);
    return const <String, Object?>{'dfid': '-', 'mid': '', 'uuid': '-'};
  }
}
/// author_id 数字串按 int 送（签名用原始类型，数字不带引号）。
Object? _aid(String id) {
  try { return int.tryParse(id) ?? id; }
  catch (e, st) { Log.e(_tag, '_aid failed id=$id', e, st); return id; }
}
/// 详情响应取首个对象：data / data.author / data.data[] / 顶层等形态。
Map<String, dynamic> _detailMap(Map<String, dynamic> res) {
  try {
    final d = dataOf(res);
    for (final v in <Object?>[d['author'], d['author_info'], d['detail'],
        d['data'], d['info'], res['author'], res['data']]) {
      if (v is Map) {
        final m = v.map((k, val) => MapEntry('$k', val));
        if (m.isNotEmpty) return m;
      }
      final l = listOf(v);
      if (l.isNotEmpty) return l.first;
    }
    return d.isEmpty ? res : d;
  } catch (e, st) {
    Log.e(_tag, '_detailMap failed', e, st);
    return const <String, dynamic>{};
  }
}
/// 列表响应按候选键取第一个非空数组（data 内与顶层双查）。
/// 批N3-C：audios 实测 data 为**平铺数组**（dataOf 只收 Map）——先查
/// data 键下的数组（res['data'] 直接 listOf），再走常规 data.<key> 双查。
List<Map<String, dynamic>> _pickList(
    Map<String, dynamic> res, List<String> keys) {  try {
    // 平铺数组形态：data 本身是 List（非 Map 包裹）。
    final flat = listOf(res['data']);
    if (flat.isNotEmpty) return flat;
    final d = dataOf(res);
    for (final k in keys) {
      for (final src in <Object?>[d[k], res[k]]) {
        final l = listOf(src);
        if (l.isNotEmpty) return l;
      }
    }
    return const <Map<String, dynamic>>[];
  } catch (e, st) {
    Log.e(_tag, '_pickList failed', e, st);
    return const <Map<String, dynamic>>[];
  }
}
/// 依序取第一个非空字符串值（空串跳过，批N2-B：intro='' 需落 long_intro）。
String _nonEmpty(List<Object?> vals) {
  for (final v in vals) {
    final s = safeStr(v);
    if (s.isNotEmpty) return s;
  }
  return '';
}
/// 服务端错误码留痕（20006=audios 清默认参数后签名不匹配典型返回）。
void _logErr(String op, Map<String, dynamic> res) {
  try {
    final d = dataOf(res);
    final ec = safeInt(res['errcode'] ?? res['err_code'] ?? res['ec'] ??
        d['errcode'] ?? d['err_code'] ?? d['ec'], 0);
    final msg = safeStr(res['error'] ?? res['errmsg'] ?? res['msg'] ??
        d['error'] ?? d['errmsg'] ?? d['msg']);
    if (ec != 0 || msg.isNotEmpty) Log.w(_tag, '$op server ec=$ec msg=$msg');
  } catch (e, st) { Log.e(_tag, '_logErr failed op=$op', e, st); }
}

/// 歌手摘要：id/name/avatar/fans 全容错。
/// 批N2-B 实测：kmr/v3/author 平铺键 author_id/author_name/sizable_avatar/
/// fansnums；authors[]（album_audio/lite、/v1/video）同键 author_id/
/// author_name/sizable_avatar；搜索域 /v1/search/author 大写驼峰
/// AuthorId/AuthorName/Avatar/FansNum（API_FIELDS_TRUTH.md §A1-4）。
class ArtistBrief {
  const ArtistBrief({this.id = '', this.name = '', this.avatar = '',
      this.fans = 0});
  final String id; final String name; final String avatar; final int fans;
  factory ArtistBrief.fromMap(Map<String, dynamic> m) {
    try {
      return ArtistBrief(
        id: safeStr(m['author_id'] ?? m['AuthorId'] ?? m['authorid'] ??
            m['singerid'] ?? m['SingerID'] ?? m['id']),
        name: safeStr(m['author_name'] ?? m['AuthorName'] ??
            m['singername'] ?? m['name']),
        avatar: safeStr(m['sizable_avatar'] ?? m['Avatar'] ?? m['avatar'] ??
            m['imgurl'] ?? m['pic']),
        fans: safeInt(m['fansnums'] ?? m['fans'] ?? m['FansNum'] ??
            m['fans_count'] ?? m['fans_num']),
      );
    } catch (e, st) {
      Log.e(_tag, 'ArtistBrief.fromMap failed', e, st);
      return const ArtistBrief();
    }
  }
}
/// 歌手详情：id/name/intro/avatar/albumCount/songCount/mvCount/fans 全容错。
/// 批N2-B 实测（/kmr/v3/author data 平铺，匿名=VIP 同键集 14 键）：
/// author_id/author_name/sizable_avatar/intro/long_intro/album_count/
/// song_count/mv_count/fansnums/area_id/birthday/is_publish/pinyin_initial/
/// user_status。
class ArtistDetail {
  const ArtistDetail({this.id = '', this.name = '', this.intro = '',
      this.avatar = '', this.albumCount = 0, this.songCount = 0,
      this.mvCount = 0, this.fans = 0});
  final String id; final String name; final String intro; final String avatar;
  final int albumCount; final int songCount; final int mvCount;
  final int fans;
  factory ArtistDetail.fromMap(Map<String, dynamic> m) {
    try {
      final b = ArtistBrief.fromMap(m);
      return ArtistDetail(id: b.id, name: b.name, avatar: b.avatar,
        // 实测：intro 为短简介（可为空串），long_intro 为长文（含专辑文案）；
        // 优先 intro，空串时落 long_intro（?? 不兜空串，需序列判定）。
        intro: _nonEmpty([
          m['intro'], m['introduction'], m['desc'], m['description'],
          m['long_intro'], m['brief'], m['biography'],
        ]),
        albumCount: safeInt(m['album_count']),
        songCount: safeInt(m['song_count']),
        mvCount: safeInt(m['mv_count']),
        // 实测键：fansnums（复数形式，非 fans/fans_num）。
        fans: safeInt(m['fansnums'] ?? b.fans),
      );
    } catch (e, st) {
      Log.e(_tag, 'ArtistDetail.fromMap failed', e, st);
      return const ArtistDetail();
    }
  }
}
/// 专辑摘要（本文件内定义，不与批4-B 专辑页模型互相 import）。
/// 批N2-B 实测（2026-11-12 /kmr/v2/albums data[0]，n2b_raw.json）：
/// 键集 album_id/album_name/author_name/sizable_cover/publish_date/intro/
/// publish_company/grade/grade_count/heat/language/type/quality/…
class AlbumBrief {
  const AlbumBrief({this.id = '', this.name = '', this.cover = '',
      this.publishDate = '', this.songCount = 0});
  final String id; final String name; final String cover;
  final String publishDate; final int songCount;
  factory AlbumBrief.fromMap(Map<String, dynamic> m) {
    try {
      return AlbumBrief(
        // 实测：kmr/v2/albums 键 album_id（字符串如 '958909'）；搜索域 albumid。
        id: safeStr(m['album_id'] ?? m['albumid'] ?? m['id']),
        // 实测：album_name（kmr）/ albumname（搜索域）/ name。
        name: safeStr(m['album_name'] ?? m['albumname'] ?? m['name']),
        // 实测：sizable_cover（{size} 模板完整 URL）；cover 只是裸文件名
        // （如 '20250125121901851911.jpg'，非 URL——不映射）。
        cover: safeStr(m['sizable_cover'] ?? m['imgurl'] ?? m['img'] ??
            m['cover']),
        publishDate: safeStr(m['publish_date'] ?? m['publish_time'] ??
            m['publishdate'] ?? m['publishtime']),
        // ⚠️ kmr/v2/albums 无曲目数键（count/song_count 均不存在）——
        // 专辑歌曲数只能从 /v1/album_audio/lite 的 total 取，此处如实 0。
        songCount: safeInt(m['song_count'] ?? m['count'] ?? m['songnum'] ??
            m['songcount']),
      );
    } catch (e, st) {
      Log.e(_tag, 'AlbumBrief.fromMap failed', e, st);
      return const AlbumBrief();
    }
  }
}

/// 歌手详情（POST /kmr/v3/author，kg-tid 36，body {author_id}）。
Future<ArtistDetail> getArtistDetail(KugouClient client, String authorId) async {
  try {
    final id = authorId.trim();
    if (id.isEmpty) {
      Log.w(_tag, 'getArtistDetail empty authorId');
      return const ArtistDetail();
    }
    final a = _aid(id);
    final res = await client.request(EndpointRegistry.artistDetail,
        <String, Object?>{..._baseParams(client), 'author_id': a},
        body: <String, Object?>{'author_id': a});
    _logErr('getArtistDetail', res);
    final d = ArtistDetail.fromMap(_detailMap(res));
    Log.d(_tag, 'getArtistDetail id=$id name=${d.name}');
    // id 缺失时以入参补，保证调用方拿到可追溯的标识。
    return d.id.isEmpty ? ArtistDetail(id: id, name: d.name,
        intro: d.intro, avatar: d.avatar) : d;
  } catch (e, st) {
    Log.e(_tag, 'getArtistDetail failed id=$authorId', e, st);
    return const ArtistDetail();
  }
}
/// 歌手热门歌曲（POST /kmr/v1/audio_group/author，kg-tid 220），page 从 1 起。
/// ⚠️【批N3-C 实测 2026-11-12·n3c_artist_raw.json】旧口径
/// /kmr/v1/author/audios 502；真实路径 /kmr/v1/audio_group/author（kg-tid 220，
/// body {author_id,page,pagesize}）实测 status=1。响应 data 为**平铺数组**
/// （非 songs[] 包裹），item 实测 103 键：audio_name/author_name/album_name/
/// album_id/album_audio_id/audio_id/hash/hash_128/320/flac/high/super/
/// filesize(_128…)/timelength(**毫秒**，如 299284)/bitrate(_128…)/playcount/
/// publish_date/privilege(_128…)/pay_type(_*)/price(_*)/status(_*)/
/// fail_process(_*)/old_hide(_*)/old_cpy(_*)/rp_*/topic_*/pkg_price(_*)/
/// extname(_super)/video_hash/video_id/video_filesize/video_timelength/
/// trans_param{musicpack_advance,language,union_cover,ogg_*,hash_offset,…}/
/// has_obbligato/is_original/identity/level/mixsong_type/cid/version/remarks。
/// ⚠️ 无 singerinfo[]/albuminfo{} 键（与 pubsongs nofilt 口径不同族）——
/// singer=author_name、albumName=album_name、durationSec=timelength ms→s
///（fromTrackInfo 的 timelength 兜底链已覆盖），hash 小写化、isVip 取
/// trans_param.musicpack_advance。顶层另有 total（data 平铺于顶层）。
/// ⚠️【签名语义·沿用 docs】defaultParams+body 合并，clearDefaultParams=true
/// 会 20006（PARITY_NOTES §1）。落到 KugouClient：
///  - 声明恒 clearDefaultParams=false → request 把 dfid/uuid/appid/clientver/
///    srcappid/clienttime/token/userid 注入 query（defaultParams）；
///  - 本封装把业务参数镜像进 query params，并把同一组写进 POST body；
///  - KugouSign.android(p, body: jsonEncode(body)) 生成
///    md5(salt + sorted("k=v" 含默认参数) + bodyJSON原文 + salt)，
///    即 defaultParams 与 body 同时参与验签；缺任一环都会 20006；
///  - mid 只自动进 header，故 _baseParams 显式补 dfid/mid/uuid 进签名。
Future<List<SongBrief>> getArtistAudios(KugouClient client,
    String authorId, int page, {int pageSize = 30}) async {
  try {
    final id = authorId.trim();
    if (id.isEmpty) {
      Log.w(_tag, 'getArtistAudios empty authorId');
      return const <SongBrief>[];
    }
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    final a = _aid(id);
    final params = <String, Object?>{..._baseParams(client),
        'author_id': a, 'page': p, 'pagesize': ps};
    final body = <String, Object?>{'author_id': a, 'page': p,
        'pagesize': ps, 'userid': client.session.userid,
        'token': client.session.token};
    final res = await client.request(EndpointRegistry.artistAudios, params,
        body: body);
    _logErr('getArtistAudios', res);
    // 批N3-C 实测：data 为平铺数组（非 songs[] 包裹）；_pickList 六键容错
    // 保留以兼容潜在灰度包裹形态。映射用 fromTrackInfo（timelength ms 兜底、
    // author_name singer 兜底、album_name albumName 兜底均已实测覆盖）。
    final items = _pickList(res, <String>['songs', 'lists', 'list',
        'info', 'audio_list', 'audios', 'data'])
        .map(SongBrief.fromTrackInfo)
        .where((s) => s.hash.isNotEmpty).toList(growable: false);
    Log.d(_tag, 'getArtistAudios id=$id page=$p got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getArtistAudios failed id=$authorId page=$page', e, st);
    return const <SongBrief>[];
  }
}
/// 歌手专辑（GET /v1/author/albums），page 从 1 起。
/// ⚠️【批N3-C 复测 2026-11-12·n3c_artist_raw.json】/v1/author/albums 与
/// /kmr/v1/author/albums（tid 36，author_id=3520 匿名）仍 502 —— 端点
/// 不可达，字段树未固化、不猜。_pickList 五键容错维持原样；调用方（L5
/// ArtistLogic.albums / artist_page 专辑 Tab）应以下述实证路径降级：
/// albumDetail（POST /kmr/v2/albums，tid 255）已实证（见 AlbumBrief.fromMap
/// 注释），歌手专辑列表可经 artistLogic.detail 的专辑计数 + 专辑域端点组合，
/// 或继续以本端点为主、空表降级专辑搜索（/v1/search/album 键集已固化）。
/// ⚠️ docs 口径差异：PARITY_NOTES.md §1 记 kmr/v1/author/albums，
/// 任务口径取 /v1/author/albums；实测后只改 EndpointRegistry 声明。
Future<List<AlbumBrief>> getArtistAlbums(KugouClient client,
    String authorId, int page, {int pageSize = 30}) async {
  try {
    final id = authorId.trim();
    if (id.isEmpty) {
      Log.w(_tag, 'getArtistAlbums empty authorId');
      return const <AlbumBrief>[];
    }
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    final res = await client.request(EndpointRegistry.artistAlbums,
        <String, Object?>{..._baseParams(client),
          'author_id': _aid(id), 'page': p, 'pagesize': ps});
    _logErr('getArtistAlbums', res);
    final items = _pickList(res, <String>['albums', 'lists', 'list',
        'info', 'data']).map(AlbumBrief.fromMap).toList(growable: false);
    Log.d(_tag, 'getArtistAlbums id=$id page=$p got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getArtistAlbums failed id=$authorId page=$page', e, st);
    return const <AlbumBrief>[];
  }
}
/// 歌手列表（GET /ocean/v6/singer/list，docs §3.6 五参）。
Future<List<ArtistBrief>> getArtistList(KugouClient client) async {
  try {
    final res = await client.request(EndpointRegistry.artistList,
        <String, Object?>{..._baseParams(client),
          'hotsize': 200, 'musician': 0, 'sextype': 0,
          'showtype': 2, 'type': 0});
    _logErr('getArtistList', res);
    final items = _pickList(res, <String>['info', 'list', 'lists',
        'singerlist', 'singers', 'data'])
        .map(ArtistBrief.fromMap).toList(growable: false);
    Log.d(_tag, 'getArtistList got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getArtistList failed', e, st);
    return const <ArtistBrief>[];
  }
}
