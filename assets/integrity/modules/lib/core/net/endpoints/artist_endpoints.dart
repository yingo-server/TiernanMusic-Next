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
const String kArtistAudiosPath = '/kmr/v1/author/audios';
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
List<Map<String, dynamic>> _pickList(
    Map<String, dynamic> res, List<String> keys) {
  try {
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
class ArtistBrief {
  const ArtistBrief({this.id = '', this.name = '', this.avatar = '',
      this.fans = 0});
  final String id; final String name; final String avatar; final int fans;
  factory ArtistBrief.fromMap(Map<String, dynamic> m) {
    try {
      return ArtistBrief(
        id: safeStr(m['author_id'] ?? m['authorid'] ?? m['singerid'] ?? m['id']),
        name: safeStr(m['author_name'] ?? m['singername'] ?? m['name']),
        avatar: safeStr(m['sizable_avatar'] ?? m['avatar'] ?? m['imgurl'] ??
            m['pic']),
        fans: safeInt(m['fans'] ?? m['fans_count'] ?? m['fans_num']),
      );
    } catch (e, st) {
      Log.e(_tag, 'ArtistBrief.fromMap failed', e, st);
      return const ArtistBrief();
    }
  }
}
/// 歌手详情：id/name/intro/avatar 全容错。
class ArtistDetail {
  const ArtistDetail({this.id = '', this.name = '', this.intro = '',
      this.avatar = ''});
  final String id; final String name; final String intro; final String avatar;
  factory ArtistDetail.fromMap(Map<String, dynamic> m) {
    try {
      final b = ArtistBrief.fromMap(m);
      return ArtistDetail(id: b.id, name: b.name, avatar: b.avatar,
        intro: safeStr(m['intro'] ?? m['introduction'] ?? m['desc'] ??
            m['description'] ?? m['brief'] ?? m['biography']));
    } catch (e, st) {
      Log.e(_tag, 'ArtistDetail.fromMap failed', e, st);
      return const ArtistDetail();
    }
  }
}
/// 专辑摘要（本文件内定义，不与批4-B 专辑页模型互相 import）。
class AlbumBrief {
  const AlbumBrief({this.id = '', this.name = '', this.cover = '',
      this.publishDate = '', this.songCount = 0});
  final String id; final String name; final String cover;
  final String publishDate; final int songCount;
  factory AlbumBrief.fromMap(Map<String, dynamic> m) {
    try {
      return AlbumBrief(
        id: safeStr(m['album_id'] ?? m['albumid'] ?? m['id']),
        name: safeStr(m['album_name'] ?? m['name'] ?? m['albumname']),
        cover: safeStr(m['sizable_cover'] ?? m['imgurl'] ?? m['img'] ??
            m['cover']),
        publishDate: safeStr(m['publish_date'] ?? m['publishdate'] ??
            m['publishtime']),
        songCount: safeInt(m['song_count'] ?? m['count'] ?? m['songnum']),
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
/// 歌手热门歌曲（POST /kmr/v1/author/audios），page 从 1 起。
/// ⚠️【body/params 合并语义 · 必读】docs/PARITY_NOTES.md §1 与
/// FEATURE_PARITY.md「特殊签名要求」：本端点签名需 defaultParams+body 合并，
/// clearDefaultParams=true 会 20006。落到 KugouClient：
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
