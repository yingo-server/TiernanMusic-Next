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
  });
  final String id;
  final String path;
  final String method;
  final SignType signType;
  final String? router;
  final String base;
  final bool clearDefaultParams;
  final bool encryptKey;
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
  static const albumDetail = Endpoint(
      id: 'album_detail', path: '/kmr/v2/albums', method: 'POST',
      router: 'openapi.kugou.com');

  // ── 推荐/FM ──
  static const recommendSongs = Endpoint(
      id: 'recommend_songs', path: '/everyday_song_recommend', method: 'POST',
      router: 'everydayrec.service.kugou.com');
  static const personalFm = Endpoint(
      id: 'personal_fm', path: '/v1/fm/play', method: 'POST');

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

  /// 按 id 查端点。
  static Endpoint byId(String id) => _all.firstWhere((e) => e.id == id,
      orElse: () => throw StateError('unknown endpoint: $id'));

  static const _all = [
    searchSong, searchComplex, searchSuggest, searchHot,
    playUrlV5, playUrlV6, privilegeLite,
    playlistRecommend, playlistDetail, playlistTracks, playlistAddSongs,
    rankList, rankInfo, lyricSearch, lyricDownload,
    artistList, albumDetail, recommendSongs, personalFm,
    loginQrKey, loginQrCheck, loginToken,
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
