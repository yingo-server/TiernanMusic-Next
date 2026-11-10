// L4 core/net 级 · HTTP 传输与端点声明注册表
// 原则：SDK 优先（dart:io HttpClient），每端点一模块声明式配置。
import 'dart:convert';
import 'dart:io';

import 'signing.dart';

/// 端点声明：路径、方法、签名类型、x-router、默认参数开关。
class Endpoint {
  const Endpoint({
    required this.id,
    required this.path,
    this.method = 'GET',
    this.signType = SignType.android,
    this.router,
    this.base = 'https://gateway.kugou.com',
    this.clearDefaultParams = false,
    this.encryptKey = false,
    // kmr 系端点需要 kg-tid 头（出处 PARITY_NOTES.md：kmr/audio/mv KG-TID:38、
    // kmr/v2/albums KG-TID:255——本端点注册表需支持透传）。
    this.tid,
  });
  final String id;
  final String path;
  final String method;
  final SignType signType;
  final String? router;
  final String base;
  final bool clearDefaultParams;
  final bool encryptKey;
  final String? tid;
}

enum SignType { android, web, register, none }

/// 会话态（token/userid/mid/dfid），由 logic 层注入。
class KugouSession {
  String token = '';
  String userid = '';
  String mid = '';
  String dfid = '-';
  Map<String, String> cookies = {};
}

/// 端点注册表：所有端点在此声明，改 API 只改这里。
class EndpointRegistry {
  static const base = 'https://gateway.kugou.com';

  // ── 搜索 ──
  static const searchSong = Endpoint(
      id: 'search_song', path: '/v3/search/song',
      router: 'complexsearch.kugou.com');
  static const searchComplex = Endpoint(
      id: 'search_complex',
      base: 'https://complexsearch.kugou.com',
      path: '/v6/search/complex');
  static const searchSuggest = Endpoint(
      id: 'search_suggest', path: '/v2/getSearchTip',
      router: 'searchtip.kugou.com');
  static const searchHot = Endpoint(
      id: 'search_hot', path: '/api/v3/search/hot_tab',
      router: 'msearch.kugou.com');

  // ── 播放/下载 ──
  static const playUrlV5 = Endpoint(
      id: 'play_url_v5', path: '/v5/url',
      router: 'trackercdn.kugou.com', encryptKey: true);
  static const playUrlV6 = Endpoint(
      id: 'play_url_v6',
      base: 'http://tracker.kugou.com',
      path: '/v6/priv_url', method: 'POST');
  static const privilegeLite = Endpoint(
      id: 'privilege_lite', path: '/v2/get_res_privilege/lite', method: 'POST',
      router: 'media.store.kugou.com');

  // ── 歌单 ──
  static const playlistRecommend = Endpoint(
      id: 'playlist_recommend', path: '/v2/special_recommend', method: 'POST',
      router: 'specialrec.service.kugou.com');
  static const playlistDetail = Endpoint(
      id: 'playlist_detail', path: '/v3/get_list_info', method: 'POST',
      router: 'pubsongs.kugou.com');
  static const playlistTracks = Endpoint(
      id: 'playlist_tracks',
      path: '/pubsongs/v2/get_other_list_file_nofilt');
  static const playlistAddSongs = Endpoint(
      id: 'playlist_add_songs', path: '/v2/add_songs_by_hash', method: 'POST');

  // ── 排行榜 ──
  static const rankList = Endpoint(
      id: 'rank_list', path: '/ocean/v6/rank/list');
  static const rankInfo = Endpoint(
      id: 'rank_info', path: '/ocean/v6/rank/info');

  // ── 歌词 ──
  static const lyricSearch = Endpoint(
      id: 'lyric_search',
      base: 'https://lyrics.kugou.com', path: '/v1/search',
      signType: SignType.none, clearDefaultParams: true);
  static const lyricDownload = Endpoint(
      id: 'lyric_download',
      base: 'https://lyrics.kugou.com', path: '/download',
      signType: SignType.none, clearDefaultParams: true);

  // ── 歌手/专辑 ──
  static const artistList = Endpoint(
      id: 'artist_list', path: '/ocean/v6/singer/list');
  // 歌手详情（功能对齐批4-A · GAP_ANALYSIS #22）：POST /kmr/v3/author，
  // x-router openapi.kugou.com，kg-tid: 36，body {author_id}
  // （出处 docs/KUGOU_API.md §3.6、docs/PARITY_NOTES.md §1）。
  static const artistDetail = Endpoint(
      id: 'artist_detail', path: '/kmr/v3/author', method: 'POST',
      router: 'openapi.kugou.com', tid: '36');
  // 歌手热门歌曲：POST /kmr/v1/author/audios（任务口径；docs 仅留
  // module/artist_audios.js 名称，未留路径样，见 KUGOU_API.md §3.6）。
  // ⚠️ 签名须 defaultParams + body 合并：clearDefaultParams=true 会返回 20006
  //    （docs/PARITY_NOTES.md §1 / FEATURE_PARITY.md「特殊签名要求」）。
  //    故保持默认参数注入（clearDefaultParams=false），端点封装把业务参数放
  //    POST body —— KugouClient.request 对 POST 将 jsonEncode(body) 拼进
  //    android 签名串，即 defaultParams+params+body 同时参与签名。
  //    kg-tid 未留样暂不设；x-router 按 §3.6 与 albumDetail 同域类比。
  static const artistAudios = Endpoint(
      id: 'artist_audios', path: '/kmr/v1/author/audios', method: 'POST',
      router: 'openapi.kugou.com');
  // 歌手专辑：GET /v1/author/albums（任务口径）。
  // ⚠️ 口径差异留痕：PARITY_NOTES.md §1 / FEATURE_PARITY.md 记
  //    「kmr/v1/author/albums」；本声明按任务口径，三态实测后只改这里。
  //    x-router 同 §3.6 kmr 系 openapi 类比；kg-tid 未留样不设置。
  static const artistAlbums = Endpoint(
      id: 'artist_albums', path: '/v1/author/albums',
      router: 'openapi.kugou.com');
  static const albumDetail = Endpoint(
      id: 'album_detail', path: '/kmr/v2/albums', method: 'POST',
      router: 'openapi.kugou.com');
  // 功能对齐批4-B · GAP #23：专辑歌曲（docs/KUGOU_API.md §3.6），
  // x-router openapi.kugou.com，kg-tid 255，body {album_id,page,pagesize,is_buy}。
  static const albumSongs = Endpoint(
      id: 'album_songs', path: '/v1/album_audio/lite', method: 'POST',
      router: 'openapi.kugou.com', tid: '255');
  // 功能对齐批4-B · GAP #24：相似歌单（docs/KUGOU_API.md §3.3），
  // POST /pubsongs/v1/kmr_get_similar_lists；gateway 无 x-router
  //（pubsongs 子域直连 404，见「直连域名可用性矩阵」）。
  static const playlistSimilar = Endpoint(
      id: 'playlist_similar',
      path: '/pubsongs/v1/kmr_get_similar_lists', method: 'POST');

  // ── 推荐/FM ──
  static const recommendSongs = Endpoint(
      id: 'recommend_songs', path: '/everyday_song_recommend', method: 'POST',
      router: 'everydayrec.service.kugou.com');
  static const personalFm = Endpoint(
      id: 'personal_fm', path: '/v1/fm/play', method: 'POST');
  // fmSongs：GET /v1/fm/songs（docs/KUGOU_API.md §3.7「电台歌曲：
  // fm_songs.js（fmid/fmtype/offset/size 批量，key 同 §1.6）」）。
  // ⚠️ 需先实测：路径/路由/完整参数契约/响应字段均未三态留样（PARITY_NOTES.md
  //    §3「个人 FM / 电台全缺」）；探针确认后只改本声明或 fm_endpoints.dart，
  //    不动 KugouClient.request。只连酷狗官方 gateway 域名。
  static const fmSongs = Endpoint(
      id: 'fm_songs', path: '/v1/fm/songs');

  // ── MV/视频（批1-B · GAP #16）──
  // mvDetail：POST /kmr/audio/mv，x-router: openapi.kugou.com，kg-tid: 38，
  // body {album_audio_id}（出处：PARITY_NOTES.md §1「kmr/audio/mv openapi + KG-TID:38,
  // body album_audio_id」；KUGOU_API.md §3.9）。
  static const mvDetail = Endpoint(
      id: 'mv_detail', path: '/kmr/audio/mv', method: 'POST',
      router: 'openapi.kugou.com', tid: '38');
  // videoDetail：POST /v1/video/detail，x-router: kmr.service.kugou.com，
  // 返回清晰度 hash 档位列表（出处：PARITY_NOTES.md「video/detail 清晰度 hash 齐全」；
  // KUGOU_API.md §3.9 video_detail）。备用形态 /kmr/v2/videos 同路由（mv_endpoints
  // 内部 404/空档时容错回退，不在此重复注册 —— 见 videoDetailKmrV2）。
  static const videoDetail = Endpoint(
      id: 'video_detail', path: '/v1/video/detail', method: 'POST',
      router: 'kmr.service.kugou.com');
  static const videoDetailKmrV2 = Endpoint(
      id: 'video_detail_kmr_v2', path: '/kmr/v2/videos', method: 'POST',
      router: 'kmr.service.kugou.com');
  // videoUrl：GET /v2/interface/index，x-router: trackermv.kugou.com，
  // 参数 hash/quality，返回 downurl 多 CDN（出处：PARITY_NOTES.md
  // 「video/url downurl」；KUGOU_API.md §3.9 video_url）。
  static const videoUrl = Endpoint(
      id: 'video_url', path: '/v2/interface/index',
      router: 'trackermv.kugou.com');

  // ── 账号 ──
  static const loginQrKey = Endpoint(
      id: 'login_qr_key',
      base: 'https://login-user.kugou.com', path: '/v2/qrcode',
      signType: SignType.web);
  static const loginQrCheck = Endpoint(
      id: 'login_qr_check',
      base: 'https://login-user.kugou.com', path: '/v2/get_userinfo_qrcode',
      signType: SignType.web);
  static const loginToken = Endpoint(
      id: 'login_token',
      base: 'http://login.user.kugou.com', path: '/v5/login_by_token',
      method: 'POST');

  // ── 评论（docs/PARITY_NOTES.md：comment/music 参数走 query 非 body；count 走 web 签名） ──
  static const commentMusic = Endpoint(
      id: 'comment_music', path: '/mcomment/v1/cmtlist',
      router: 'mcomment.kugou.com');
  static const commentFloor = Endpoint(
      id: 'comment_floor', path: '/mcomment/v1/hot_replylist',
      router: 'mcomment.kugou.com');
  // comment/count：web 签名（PARITY_NOTES.md §2：WEB_SALT，x-router sum.comment.service）
  static const commentCount = Endpoint(
      id: 'comment_count', path: '/v1/comment/count',
      signType: SignType.web, router: 'sum.comment.service.kugou.com');

  // ── 收藏（批2-C · 数据层，只加声明，不动 KugouClient.request）──
  // favoriteCount：GET /v1/favorite/count（docs/KUGOU_API.md §3.9 favorite_count.js）。
  // x-router 按 docs：KUGOU_API.md §3 的网关转发约定，路由名类比
  // PARITY_NOTES.md §2 唯一留痕的 count 端点（comment/count → sum.comment.service）。
  // 签名用默认 android（docs §2 的 WEB_SALT 清单不含 favorite_count）。
  // ⚠️ 待三态实测（anon/nonvip/vip）：favorite_count 的路径/路由/签名/响应字段
  //    均未留样；实测后只改本声明（或端点封装），不改 request 实现。
  static const favoriteCount = Endpoint(
      id: 'favorite_count', path: '/v1/favorite/count',
      router: 'sum.comment.service.kugou.com');
  // collectSong：POST /v2/collect（收藏歌曲写端点；登录守卫在 logic 层）。
  static const collectSong = Endpoint(
      id: 'collect_song', path: '/v2/collect', method: 'POST');
  // cancelCollect：POST /v2/cancel_collect（取消收藏写端点）。
  // ⚠️ docs/PARITY_NOTES.md / FEATURE_PARITY.md 记录：归档项目 cancel 走**二进制 body**；
  //    二进制载荷形态待三态实测，当前用 query 参数退化（端点层参数放 query、
  //    body 留空），实测后只改声明/封装，不改 request 实现。
  static const cancelCollect = Endpoint(
      id: 'cancel_collect', path: '/v2/cancel_collect', method: 'POST');

  /// 按 id 查端点。
  static Endpoint byId(String id) => _all.firstWhere((e) => e.id == id,
      orElse: () => throw StateError('unknown endpoint: $id'));

  static const _all = [
    searchSong, searchComplex, searchSuggest, searchHot,
    playUrlV5, playUrlV6, privilegeLite,
    playlistRecommend, playlistDetail, playlistTracks, playlistAddSongs,
    rankList, rankInfo, lyricSearch, lyricDownload,
    artistList, artistDetail, artistAudios, artistAlbums, albumDetail,
    albumSongs, playlistSimilar, recommendSongs, personalFm, fmSongs,
    mvDetail, videoDetail, videoDetailKmrV2, videoUrl,
    loginQrKey, loginQrCheck, loginToken,
    commentMusic, commentFloor, commentCount,
    // 收藏域三声明（批2-C）：count / collect / cancel_collect。
    favoriteCount, collectSong, cancelCollect,
  ];
}

/// 统一请求执行器：dart:io HttpClient + 签名注入 + 防爬头。
/// 三态实测结论（.test_creds/FINDINGS.md）：
/// - 参数全显式在场（多参不缺参），签名用原始类型（数字不带引号）
/// - play_url：响应顶层即数据（url/status/priv_status），无 data 包层
class KugouClient {
  KugouClient(this.session);
  final KugouSession session;
  HttpClient? _http;
  HttpClient get _h => _http ??= HttpClient()
    ..userAgent = KugouSign.defaultUa
    ..connectionTimeout = const Duration(seconds: 10);

  /// 执行端点请求。params：查询参数；body：POST JSON 体（参与签名）。
  Future<Map<String, dynamic>> request(
    Endpoint ep,
    Map<String, Object?> params, {
    Map<String, Object?> body = const {},
  }) async {
    final p = Map<String, Object?>.from(params);
    final bodyStr =
        ep.method == 'POST' ? jsonEncode(body) : '';
    if (!ep.clearDefaultParams) {
      p..putIfAbsent('dfid', () => session.dfid)
        ..putIfAbsent('uuid', () => '-')
        ..putIfAbsent('appid', () => KugouSign.appid)
        ..putIfAbsent('clientver', () => KugouSign.clientver)
        ..putIfAbsent('srcappid', () => KugouSign.srcappid)
        ..putIfAbsent('clienttime',
            () => DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if (session.token.isNotEmpty) p.putIfAbsent('token', () => session.token);
      if (session.userid.isNotEmpty) {
        p.putIfAbsent('userid', () => session.userid);
      }
    }
    if (ep.encryptKey && p['hash'] != null) {
      p['key'] = KugouSign.playKey(
          '${p['hash']}'.toLowerCase(), session.mid, session.userid);
    }
    switch (ep.signType) {
      case SignType.android:
        p['signature'] = KugouSign.android(p, body: bodyStr);
      case SignType.web:
        p['signature'] = KugouSign.web(p);
      case SignType.register:
        p['signature'] = KugouSign.register(p);
      case SignType.none:
        break;
    }
    final q = p.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value.toString())}')
        .join('&');
    // 实测注意：签名串用原始类型（数字不带引号），发送统一字符串化。
    // 参数多参不缺参：默认参数恒显式在场并参与签名（FINDINGS.md §4-5）。
    final uri = Uri.parse('${ep.base}${ep.path}?$q');
    final req = await _h.openUrl(ep.method, uri);
    if (ep.router != null) req.headers.set('x-router', ep.router!);
    if (ep.tid != null) req.headers.set('kg-tid', ep.tid!);
    final ct = DateTime.now().millisecondsSinceEpoch;
    req.headers
      ..set('dfid', session.dfid)
      ..set('clienttime', '${ct ~/ 1000}')
      ..set('mid', session.mid)
      ..set('kg-rc', '1')
      ..set('kg-thash', '5d816a0')
      ..set('kg-rec', '1')
      ..set('kg-rf', 'B9EDA08A64250DEFFBCADDEE00F8F25F');
    session.cookies.forEach((k, v) =>
        req.headers.set('Cookie', session.cookies.keys
            .map((k2) => '$k2=${session.cookies[k2]}').join('; ')));
    if (bodyStr.isNotEmpty) {
      req.headers.contentType = ContentType.json;
      req.write(bodyStr);
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw KugouApiException(res.statusCode, 'http ${res.statusCode}: $text');
    }
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    // 实测（FINDINGS.md §1）：play_url 等端点成功时顶层即数据，
    // 调用方按端点自行取 url/status/priv_status 等顶层字段。
    throw KugouApiException(res.statusCode, 'unexpected response shape');
  }

  void close() => _http?.close();
}

class KugouApiException implements Exception {
  KugouApiException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'KugouApiException($code): $message';
}
