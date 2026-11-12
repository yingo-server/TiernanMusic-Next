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
    // 批N3-B 实测：srcappid 入签 → cloudlist 系端点 20006，默认不注入。
    this.omitSrcappid = false,
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
  /// 批N3-B 实测（2026-11-12）：srcappid 参与签名时 cloudlist 系端点
  /// （add_list/delete_list/delete_songs/get_all_list）返回 error_code 20006。
  /// 置 true 则默认参数不注入 srcappid。
  final bool omitSrcappid;
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
  // ── 歌单写操作（批N3-B 三态实测 2026-11-12，docs/API_FIELDS_TRUTH.md A6）──
  // 建歌单：POST /cloudlist.service/v5/add_list（URL 前缀式，无 x-router）。
  // 成功 data.info.listid（⚠️ 非 data.listid）。srcappid 不得参与签名。
  static const playlistCreate = Endpoint(
      id: 'playlist_create', path: '/cloudlist.service/v5/add_list',
      method: 'POST', omitSrcappid: true);
  // 删歌单：POST /v2/delete_list + x-router cloudlist.service.kugou.com。
  // 批F1-B：加密契约据 KuGouMusicApi util/crypto.js + module/playlist_del.js
  // 实现于 crypto_rsa.dart / playlist_write_endpoints.deletePlaylist：
  // p=rsaEncrypt2({aes,uid,token}) PKCS1-V1_5 + body=AES-128-CBC Base64
  // {listid,total_ver,type:1}（待实测验证 20010 是否消除）。
  static const playlistDelete = Endpoint(
      id: 'playlist_delete', path: '/v2/delete_list', method: 'POST',
      router: 'cloudlist.service.kugou.com', omitSrcappid: true);
  // 歌单删歌：POST /v4/delete_songs + x-router cloudlist.service.kugou.com。
  // body data:[{fileid}]（fileid=audio_id/album_audio_id，非 hash）。
  static const playlistDelSongs = Endpoint(
      id: 'playlist_del_songs', path: '/v4/delete_songs', method: 'POST',
      router: 'cloudlist.service.kugou.com', omitSrcappid: true);
  // 歌单加歌（批N3-B 实测）：POST /cloudlist.service/v6/add_song（URL 前缀式）。
  // query last_time/last_area=gztx/userid/token；body data:[{number,name,hash
  // (小写),size,sort,timelen,bitrate,album_id,mixsongid}]。成功 data.info[]
  // 逐曲回执（fileid/hash/name/cover/audio_id）。
  // 实测 2026-11-12：URL 前缀式 /cloudlist.service/v6/add_song 网关 404；
  // 真实可用 = /v6/add_song + x-router cloudlist.service（VIP 加/删往返 status=1）。
  static const playlistAddSongs = Endpoint(
      id: 'playlist_add_songs', path: '/v6/add_song',
      method: 'POST', router: 'cloudlist.service.kugou.com',
      omitSrcappid: true);
  // 走 gateway（无 x-router；pubsongs 子域直连 404，见可用性矩阵）。
  static const playlistTags = Endpoint(
      id: 'playlist_tags',
      path: '/pubsongs/v1/get_tags_by_type', method: 'POST');
  // 用户歌单：POST /v7/get_all_list，x-router cloudlist.service.kugou.com，
  // docs §3.3（query plat=1&userid&token；body userid/token/total_ver/type=2/page/pagesize）。
  // ⚠️ 全部写端点路径/参数/响应形态均「待三态实测」，实测后只改本声明，不动 request。
  static const userPlaylists = Endpoint(
      id: 'user_playlists', path: '/v7/get_all_list', method: 'POST',
      router: 'cloudlist.service.kugou.com', omitSrcappid: true);

  // ── 排行榜 ──
  static const rankList = Endpoint(
      id: 'rank_list', path: '/ocean/v6/rank/list');
  // 批N1-B 实测（docs/API_FIELDS_TRUTH.md A2-6）：/ocean/v6/rank/info 只回
  // 榜单元信息 + 3 首 songinfo 预览，无完整曲目列表（data.songs/list 不存在）。
  // 取榜单曲目改走 POST /openapi/kmr/v2/rank/audio（kg-tid 369，无 x-router；
  // 缺 kg-tid → error_code 20006 "err KG-TID"）。
  static const rankAudio = Endpoint(
      id: 'rank_audio', path: '/openapi/kmr/v2/rank/audio', method: 'POST',
      tid: '369');
  static const rankInfo = Endpoint(
      id: 'rank_info', path: '/ocean/v6/rank/info');

  // ── 歌词 ──
  // 批N2-A 实测（API_FIELDS_TRUTH.md §A3-3/4，2026-11-12）：lyrics.kugou.com
  // 裸请求一律 HTTP 200 空响应体——必须 android 签名 + dfid/mid/uuid/clienttime
  // 默认参在场并参与签名（不能用 none/clearDefaultParams）。成功语义 status=200。
  // 批N2-C 实测（API_FIELDS_TRUTH.md A3-2）：lyrics.kugou.com 直连恒返回空体
  //（HTTP 200 + 0 字节），必须走 gateway + 头 x-router: lyrics.kugou.com，
  // android 签名 + 默认参数（dfid/mid/uuid/appid/clientver/clienttime）恒携带。
  static const lyricSearch = Endpoint(
      id: 'lyric_search', path: '/v1/search',
      router: 'lyrics.kugou.com');
  static const lyricDownload = Endpoint(
      id: 'lyric_download', path: '/download',
      router: 'lyrics.kugou.com');

  // ── 歌手/专辑 ──
  static const artistList = Endpoint(
      id: 'artist_list', path: '/ocean/v6/singer/list');
  // 歌手详情（功能对齐批4-A · GAP_ANALYSIS #22）：POST /kmr/v3/author，
  // x-router openapi.kugou.com，kg-tid: 36，body {author_id}
  // （出处 docs/KUGOU_API.md §3.6、docs/PARITY_NOTES.md §1）。
  static const artistDetail = Endpoint(
      id: 'artist_detail', path: '/kmr/v3/author', method: 'POST',
      router: 'openapi.kugou.com', tid: '36');
  // 歌手热门歌曲（批N3-C 实测修正 2026-11-12）：POST /kmr/v1/audio_group/author，
  // x-router openapi.kugou.com，kg-tid 220，body {author_id,page,pagesize}
  // ——旧口径 /kmr/v1/author/audios 实测 502（见 API_FIELDS_TRUTH.md §A4-5）。
  // ⚠️ 签名须 defaultParams + body 合并：clearDefaultParams=true 会返回 20006
  //    （docs/PARITY_NOTES.md §1 / FEATURE_PARITY.md「特殊签名要求」）。
  //    故保持默认参数注入（clearDefaultParams=false），端点封装把业务参数放
  //    POST body —— KugouClient.request 对 POST 将 jsonEncode(body) 拼进
  //    android 签名串，即 defaultParams+params+body 同时参与签名。
  static const artistAudios = Endpoint(
      id: 'artist_audios', path: '/kmr/v1/audio_group/author',
      method: 'POST', router: 'openapi.kugou.com', tid: '220');
  // 歌手专辑：/v1/author/albums 与 /kmr/v1/author/albums（tid 36）批N3-C 复测
  //（2026-11-12，author_id=3520）仍 502 —— 端点不可达，声明维持任务口径原样、
  // 不猜字段；数据源改走已实证的 albumDetail（/kmr/v2/albums）路径由调用方降级。
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
  // mvDetail（批N2-B 实测修正）：POST /kmr/v1/audio/mv，x-router:
  // openapi.kugou.com，kg-tid: 38，body {data:[{album_audio_id}], fields:''}
  // ——响应 data 为嵌套数组 data[0][]（旧口径 /kmr/audio/mv 实测 502 不存在）。
  static const mvDetail = Endpoint(
      id: 'mv_detail', path: '/kmr/v1/audio/mv', method: 'POST',
      router: 'openapi.kugou.com', tid: '38');
  // videoDetail（批N2-B 实测修正）：POST /v1/video，x-router:
  // kmr.service.kugou.com；⚠️ 实测需 clearDefaultParams 全参 body：
  // appid/clientver/clienttime(秒)/mid/uuid/dfid/token/key=signParamsKey(秒)/
  // show_resolution=1/data:[{video_id}]（网关默认参数形态 404/502）。
  // 响应 data[0] 平铺 ld/sd/hd/fhd/qhd 档位 hash/filesize/bitrate。
  static const videoDetail = Endpoint(
      id: 'video_detail', path: '/v1/video', method: 'POST',
      router: 'kmr.service.kugou.com', clearDefaultParams: true);
  static const videoDetailKmrV2 = Endpoint(
      id: 'video_detail_kmr_v2', path: '/kmr/v2/videos', method: 'POST',
      router: 'kmr.service.kugou.com');
  // videoUrl（批N2-B 实测修正）：GET /v2/interface/index，x-router:
  // trackermv.kugou.com，参数 backupdomain=1/cmd=123/ext=mp4/ismp3=0/pid=1/
  // type=1/hash；⚠️ encryptKey=true → KugouClient 自动注入
  // key=md5(hash+signKeySalt+appid+mid+userid||0)，缺 key 实测 40003
  // "Empty key"。响应 data[hash].downurl(串)+backupdownurl(数组)。
  static const videoUrl = Endpoint(
      id: 'video_url', path: '/v2/interface/index',
      router: 'trackermv.kugou.com', encryptKey: true);

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
  // smsLogin：POST https://loginserviceretry.kugou.com/v7/login_by_verifycode
  // （出处 docs/KUGOU_API.md §3.8 login_cellphone.js：body params=AES 加密 hex
  // + pk=RSA hex，UA Android16-1070-11440-130-0-LOGIN-wifi —— UA 由端点封装
  // /探针阶段处理，KugouClient 默认 UA 不改）。⚠️ 未三态实测，探针确认前
  // auth_endpoints.smsLogin 只构造不外发。crypto：signType none（加密载荷
  // 由端点层构造，注册表不做 android 签名注入，docs 未留样签名要求）。
  static const smsLogin = Endpoint(
      id: 'sms_login',
      base: 'https://loginserviceretry.kugou.com',
      path: '/v7/login_by_verifycode', method: 'POST',
      signType: SignType.none, clearDefaultParams: true);
  // sendSmsCode：发送短信验证码（真实路径据 ENDPOINT_TRUTH.md §2
  // captcha_sent.js：http://login.user.kugou.com/v7/send_mobile_code，
  // body { businessid:5, mobile, plat:3 }）。参数契约待三态实测。
  static const sendSmsCode = Endpoint(
      id: 'send_sms_code',
      base: 'http://login.user.kugou.com',
      path: '/v7/send_mobile_code', method: 'POST',
      signType: SignType.none, clearDefaultParams: true); // 真实路径据 ENDPOINT_TRUTH.md

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
      id: 'favorite_count', path: '/count/v1/audio/mget_collect',
      router: 'sum.comment.service.kugou.com'); // 真实路径据 ENDPOINT_TRUTH.md
  // collectSong / cancelCollect：上游无此模块（ENDPOINT_TRUTH.md §5：歌曲收藏
  // 不应臆造 URL），路径不改、上游无此端点，本地镜像实现为准。
  static const collectSong = Endpoint(
      id: 'collect_song', path: '/v2/collect', method: 'POST'); // 上游无此端点，本地镜像实现为准
  // cancelCollect：POST /v2/cancel_collect（取消收藏写端点）。
  // ⚠️ docs/PARITY_NOTES.md / FEATURE_PARITY.md 记录：归档项目 cancel 走**二进制 body**；
  //    二进制载荷形态待三态实测，当前用 query 参数退化（端点层参数放 query、
  //    body 留空），实测后只改声明/封装，不改 request 实现。
  static const cancelCollect = Endpoint(
      id: 'cancel_collect', path: '/v2/cancel_collect', method: 'POST'); // 上游无此端点，本地镜像实现为准

  // ── 用户域/上报（批6-A · 只加声明，不动 KugouClient.request）──
  // ⚠️ 以下五端点全部「需三态实测，未实测不猜参数」：路径/参数/响应形态
  //    均未留样（docs/PARITY_NOTES.md §4），实测后只改本声明，不动 request。
  // userDetail：POST /v3/get_my_info（用户详情：昵称/头像/VIP/等级）。
  static const userDetail = Endpoint(
      id: 'user_detail', path: '/v3/get_my_info', method: 'POST',
      router: 'usercenter.kugou.com'); // 真实路径据 ENDPOINT_TRUTH.md
  // playHistoryUpload：POST /playhistory/v1/upload_songs（听歌上报批量）。
  static const playHistoryUpload = Endpoint(
      id: 'play_history_upload', path: '/playhistory/v1/upload_songs',
      method: 'POST'); // 需三态实测，未实测不猜参数
  // songClimax：GET https://expendablekmrcdn.kugou.com/v1/audio_climax/audio
  // （真实路径据 ENDPOINT_TRUTH.md §1 song_climax，非 gateway）。
  static const songClimax = Endpoint(
      id: 'song_climax',
      base: 'https://expendablekmrcdn.kugou.com',
      path: '/v1/audio_climax/audio');
  // userCloud：POST /v1/user_cloud（用户云盘歌曲列表）。
  static const userCloud = Endpoint(
      id: 'user_cloud', path: '/v1/user_cloud', method: 'POST'); // 需三态实测，未实测不猜参数
  // listenReport：真实为「获取收听列表」listenservice.kugou.com/v2/get_list
  // （ENDPOINT_TRUTH.md §1；上游无独立「单曲上报」端点，上报由 personal_fm 的 action/playtime 承载）。
  // 真实路径据 ENDPOINT_TRUTH.md
  static const listenReport = Endpoint(
      id: 'user_listen_report',
      base: 'https://listenservice.kugou.com',
      path: '/v2/get_list',
      method: 'POST'); // 需三态实测，未实测不猜参数

  /// 按 id 查端点。
  static Endpoint byId(String id) => _all.firstWhere((e) => e.id == id,
      orElse: () => throw StateError('unknown endpoint: $id'));

  static const _all = [
    searchSong, searchComplex, searchSuggest, searchHot,
    playUrlV5, playUrlV6, privilegeLite,
    playlistRecommend, playlistDetail, playlistTracks, playlistAddSongs,
    playlistCreate, playlistDelete, playlistDelSongs, playlistTags,
    userPlaylists,
    rankList, rankInfo, rankAudio, lyricSearch, lyricDownload,
    artistList, artistDetail, artistAudios, artistAlbums, albumDetail,
    albumSongs, playlistSimilar, recommendSongs, personalFm, fmSongs,
    mvDetail, videoDetail, videoDetailKmrV2, videoUrl,
    loginQrKey, loginQrCheck, loginToken,
    // 认证域两声明（功能对齐批5-A · GAP #31）：短信登录 + 发送验证码（needs probe）。
    smsLogin, sendSmsCode,
    commentMusic, commentFloor, commentCount,
    // 收藏域三声明（批2-C）：count / collect / cancel_collect。
    favoriteCount, collectSong, cancelCollect,
    // 用户域/上报五声明（批6-A）：全部 needs probe，未实测不发请求。
    userDetail, playHistoryUpload, songClimax, userCloud, listenReport,
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
  /// rawBody（批F1-B）：非 null 时原样作为请求体发送并参与 android 签名
  /// （出处 KuGouMusicApi util/request.js：data 为字符串时直接签名/发送，
  /// delete_list 的 AES Base64 密文即此类）；响应非 JSON 时回退返回
  /// {'_raw_text': text} 交由端点层解密，不抛形状异常。
  Future<Map<String, dynamic>> request(
    Endpoint ep,
    Map<String, Object?> params, {
    Map<String, Object?> body = const {},
    String? rawBody,
  }) async {
    final p = Map<String, Object?>.from(params);
    final bodyStr =
        rawBody ?? (ep.method == 'POST' ? jsonEncode(body) : '');
    if (!ep.clearDefaultParams) {
      p..putIfAbsent('dfid', () => session.dfid)
        ..putIfAbsent('uuid', () => '-')
        ..putIfAbsent('appid', () => KugouSign.appid)
        ..putIfAbsent('clientver', () => KugouSign.clientver);
      // 批N3-B 实测（A6）：srcappid 参与签名 → cloudlist 系端点全线
      // error_code 20006；不带 srcappid 则 status=1。omitSrcappid 端点不注入。
      if (!ep.omitSrcappid) {
        p.putIfAbsent('srcappid', () => KugouSign.srcappid);
      }
      p..putIfAbsent('mid', () => session.mid.isEmpty ? '0' : session.mid)
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
    // rawBody 端点（加密响应如 delete_list）回退原文，由端点层解密。
    if (rawBody != null) return <String, dynamic>{'_raw_text': text};
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
