// L4 core/net/endpoints · 收藏域端点封装（批9-B · 真实请求 + 本地镜像占位）
// 出处：ENDPOINT_TRUTH.md §1/§5（favorite_count.js → GET /count/v1/audio/mget_collect）；
//   PARITY_NOTES.md / FEATURE_PARITY.md（登录守卫、写操作防重）。
// ⚠️ collect / cancel_collect：上游无歌曲收藏独立端点（ENDPOINT_TRUTH §5 明确），
//   保持本地占位，不伪造网络成功、不臆造 URL。
// 登录守卫只由 logic 层做，端点层不判（needsLogin 恒 false）。
// 铁律：字段容错；每函数 try/catch + Log('ep.collect')；
//   dfid/mid/uuid 恒显式携带并参与签名；只连酷狗官方 gateway 域名。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show safeInt, safeStr, dataOf, listOf;
import 'playlist_write_endpoints.dart'
    show addSongsToPlaylist, getUserPlaylists, removeSongsFromPlaylist;

const String _tag = 'ep.collect';

/// 收藏写操作结果（计数取自响应，缺失为 0）。
class CollectResult {
  const CollectResult({
    this.ok = false,
    this.needsLogin = false,
    this.count = 0,
  });

  final bool ok;
  // 端点层恒 false：登录守卫由 logic 层（CollectLogic）统一置位。
  final bool needsLogin;
  // 服务端收藏总数；缺失 0。logic 层以本地镜像条数为单一事实源。
  final int count;

  CollectResult copyWith({bool? ok, bool? needsLogin, int? count}) =>
      CollectResult(ok: ok ?? this.ok,
          needsLogin: needsLogin ?? this.needsLogin, count: count ?? this.count);

  Map<String, Object?> toMap() => <String, Object?>{
        'ok': ok, 'needsLogin': needsLogin, 'count': count,
      };

  @override
  String toString() {
    try {
      return 'CollectResult(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'CollectResult.toString failed', e, st);
      return 'CollectResult(<unavailable>)';
    }
  }
}

/// 会话/设备三参恒显式入场（参与签名）：dfid / mid / uuid。
Map<String, Object?> _baseParams(KugouClient client) {
  try {
    return <String, Object?>{
      'dfid': client.session.dfid, 'mid': client.session.mid,
      'uuid': '-', 'plat': 1,
    };
  } catch (e, st) {
    Log.e(_tag, '_baseParams failed', e, st);
    return const <String, Object?>{
      'dfid': '-', 'mid': '', 'uuid': '-', 'plat': 1,
    };
  }
}

/// 收藏总数容错提取：data.count / total / favorite_count / 顶层同键，
/// 再退化到 data.lists|list|info 数组长度（字段缺失不崩）。
int _countOf(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    for (final v in <Object?>[
      data['favorite_count'], data['collect_count'], data['song_count'],
      data['count'], data['total'], res['favorite_count'], res['count'],
      res['total'],
    ]) {
      final n = safeInt(v, -1);
      if (n >= 0) return n;
    }
    return listOf(
        data['lists'] ?? data['list'] ?? data['info'] ?? res['lists']).length;
  } catch (e, st) {
    Log.e(_tag, '_countOf failed', e, st);
    return 0;
  }
}

/// 收藏歌曲（上游无此端点，本地镜像为准，不伪造网络成功）。
/// 真实收藏：把歌曲加入「我喜欢」歌单（不是已弃用的「默认收藏」概念版）。
/// 实测 2026-11-12：/v7/get_all_list 返回 listid=1「默认收藏」(弃用)、
/// listid=2「我喜欢」(真正的收藏，count=484)；cloudlist 系须 omitSrcappid。
/// 链路：getUserPlaylists 找 name=='我喜欢' 的 listid → v6/add_song 写入。
/// 歌单字段来自 SongBrief（hash/name/albumAudioId/mixSongId/durationSec 等），
/// 缺字段用 0/空串占位（多参不缺参），不猜上游字段。
Future<CollectResult> collectSongByHash(
  KugouClient client,
  String hash,
  int mixSongId, {
  String name = '',
  String albumAudioId = '',
  String size = '',
  String timelen = '',
  String bitrate = '',
  String albumId = '',
}) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'collectSongByHash empty hash');
      return const CollectResult();
    }
    final listid = await favoriteListId(client);
    if (listid == null) {
      Log.w(_tag, 'collectSongByHash no 我喜欢 playlist hash=$h');
      return const CollectResult(ok: false, needsLogin: true);
    }
    final rows = await addSongsToPlaylist(client, listid, <Map<String, String>>[
      <String, String>{
        'name': name,
        'hash': h,
        'albumId': albumId,
        'mixsongid': '$mixSongId',
        'size': size,
        'timelen': timelen,
        'bitrate': bitrate,
      },
    ]);
    final ok = rows.isNotEmpty;
    Log.d(_tag, 'collectSongByHash via 我喜欢 listid=$listid ok=$ok hash=$h');
    return CollectResult(ok: ok, count: ok ? 1 : 0);
  } catch (e, st) {
    Log.e(_tag, 'collectSongByHash failed hash=$hash', e, st);
    return const CollectResult();
  }
}

/// 取消收藏：从「我喜欢」歌单删除（fileid = album_audio_id，实测契约）。
/// 形参沿用 hash 兼容旧调用，albumAudioId 传入时优先作为 fileIds。
Future<CollectResult> cancelCollectByHash(
  KugouClient client,
  String hash, {
  String albumAudioId = '',
}) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'cancelCollectByHash empty hash');
      return const CollectResult();
    }
    final listid = await favoriteListId(client);
    if (listid == null) {
      Log.w(_tag, 'cancelCollectByHash no 我喜欢 playlist hash=$h');
      return const CollectResult(ok: false, needsLogin: true);
    }
    final ok = await removeSongsFromPlaylist(
        client, listid, <String>[albumAudioId.isEmpty ? h : albumAudioId]);    Log.d(_tag, 'cancelCollectByHash via 我喜欢 listid=$listid ok=$ok');
    return CollectResult(ok: ok, count: 0);
  } catch (e, st) {
    Log.e(_tag, 'cancelCollectByHash failed hash=$hash', e, st);
    return const CollectResult();
  }
}

/// 查找「我喜欢」歌单 listid（跳过 listid=1「默认收藏」概念版）。
/// 登录态缺失时 getUserPlaylists 返回空 → null。
/// 公开导出供 logic 层（collect_logic 首次进入回填镜像）使用。
Future<String?> favoriteListId(KugouClient client) async {
  try {
    if (client.session.userid.isEmpty) return null;
    final lists = await getUserPlaylists(client, page: 1, pageSize: 100);
    for (final p in lists) {
      if (p.name.trim() != '我喜欢') continue;
      final id = p.listid.trim();
      if (id.isEmpty) {
        Log.w(_tag, '我喜欢 playlist has empty listid');
        return null;
      }
      Log.d(_tag, 'favorite playlist 我喜欢 listid=$id');
      return id;
    }
    Log.w(_tag, 'favorite playlist 我喜欢 not found (n=${lists.length})');
    return null;
  } catch (e, st) {
    Log.e(_tag, 'favorite playlist lookup failed', e, st);
    return null;
  }
}

/// 收藏计数（GET /count/v1/audio/mget_collect，ENDPOINT_TRUTH.md §1/§5
/// favorite_count.js：query mixsongids（逗号分隔）+ 默认参数，android 签名；
/// 响应 body.data 为 mixsongid→收藏数映射）。失败返回 0 且必 Log 留痕。
/// 注：函数签名固定无 ids 入参，mixsongids 以空串占位并 Log.w（多参不缺参）。
/// 批N3-A 实测（A5-5）：GET /count/v1/audio/mget_collect 匿名可读，
/// 响应 `data.list[]{mixsongid,count,count_text}`，不是 mixsongid→count 映射。
Future<int> getFavoriteCount(KugouClient client,
    {String mixSongIds = ''}) async {
  try {
    if (mixSongIds.isEmpty) {
      Log.w(_tag, 'getFavoriteCount no mixsongids -> empty query');
    }
    final res = await client.request(
        EndpointRegistry.favoriteCount,
        <String, Object?>{
          'mixsongids': mixSongIds,
          ..._baseParams(client),
          if (client.session.userid.isNotEmpty) 'userid': client.session.userid,
        });
    final data = dataOf(res);
    var n = -1;
    final list = data['list'];
    if (list is List) {
      var sum = 0;
      for (final item in list) {
        if (item is Map) sum += safeInt(item['count']);
      }
      n = sum;
    }
    if (n < 0 && data['count'] != null) n = safeInt(data['count']);
    if (n < 0) n = _countOf(res);
    final ec = safeInt(res['error_code'] ?? res['errcode'] ??
        data['error_code'] ?? data['errcode'], 0);
    if (ec != 0) Log.w(_tag, 'getFavoriteCount server ec=$ec');
    Log.d(_tag, 'getFavoriteCount count=$n');
    return n < 0 ? 0 : n;
  } catch (e, st) {
    Log.e(_tag, 'getFavoriteCount failed', e, st);
    return 0;
  }
}
