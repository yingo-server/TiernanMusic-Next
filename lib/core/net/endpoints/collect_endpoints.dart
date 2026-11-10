// L4 core/net/endpoints · 收藏域端点封装（功能对齐批2-C · 数据层）
// 出处：KUGOU_API.md §3.9（favorite_count）；PARITY_NOTES.md /
//   FEATURE_PARITY.md（cancel_collect 二进制 body 经验、登录守卫、写操作防重）。
// ⚠️ 三态（anon/nonvip/vip）未留样：favoriteCount 路由/签名按 docs 类比（待实测）；
//   cancel_collect 二进制 body 待实测，当前用 query 退化（body 显式留空）。
// 登录守卫只由 logic 层做，端点层不判（needsLogin 恒 false）。
// 铁律：字段容错；每函数 try/catch + Log('ep.collect')；
//   dfid/mid/uuid 恒显式携带并参与签名；只连酷狗官方 gateway 域名。
import '../../../kernel/kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show safeInt, safeStr, dataOf, listOf;

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

/// 写端点成功语义容错（docs：成功语义因端点而异 / 写操作 maybeSucceeded
/// 不回退、失败留痕）。待三态实测校准。
bool _writeSucceeded(Map<String, dynamic> res, String op) {
  try {
    final data = dataOf(res);
    final errRaw = res['errcode'] ?? res['err_code'] ?? res['ec'] ??
        data['errcode'] ?? data['err_code'] ?? data['ec'];
    if (safeInt(errRaw) != 0) {
      Log.w(_tag, '$op rejected err=$errRaw');
      return false;
    }
    final raw = res['status'] ?? data['status'] ??
        res['result'] ?? data['result'];
    if (raw != null) {
      final n = safeInt(raw, -1);
      final s = safeStr(raw).toLowerCase();
      final ok = n == 1 || n == 200 || s == '1' || s == 'ok' ||
          s == 'success' || s == 'true';
      if (!ok) Log.w(_tag, '$op rejected status=$raw');
      return ok;
    }
    final errMsg = safeStr(res['error'] ?? res['errmsg'] ?? res['msg'] ??
        res['message'] ?? data['errmsg'] ?? data['error']);
    if (errMsg.isNotEmpty || res.isEmpty) {
      Log.w(_tag, '$op rejected msg=$errMsg empty=${res.isEmpty}');
      return false;
    }
    // 无 status/errcode/error：写操作 maybeSucceeded，不回退、不重投。
    Log.w(_tag, '$op maybeSucceeded keys=${res.keys.length} (unverified)');
    return true;
  } catch (e, st) {
    Log.e(_tag, '_writeSucceeded failed op=$op', e, st);
    return false;
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

/// 收藏歌曲（POST /v2/collect）。hash 恒小写；mixSongId 显式携带。
/// body 参与 android 签名；session 中的 userid/token 只透传，不判登录。
Future<CollectResult> collectSongByHash(
  KugouClient client,
  String hash,
  int mixSongId,
) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'collectSongByHash empty hash');
      return const CollectResult();
    }
    final params = <String, Object?>{
      ..._baseParams(client),
      'hash': h,
      'mixsongid': mixSongId,
      if (client.session.userid.isNotEmpty) 'userid': client.session.userid,
    };
    final body = <String, Object?>{
      'hash': h,
      'mixsongid': mixSongId,
      'userid': client.session.userid,
      'token': client.session.token,
      'plat': 1,
      'source': 1,
    };
    final res = await client.request(EndpointRegistry.collectSong, params,
        body: body);
    final ok = _writeSucceeded(res, 'collect');
    final count = _countOf(res);
    Log.d(_tag, 'collectSongByHash hash=$h mix=$mixSongId ok=$ok count=$count');
    return CollectResult(ok: ok, count: count);
  } catch (e, st) {
    Log.e(_tag, 'collectSongByHash failed hash=$hash', e, st);
    return const CollectResult();
  }
}

/// 取消收藏（POST /v2/cancel_collect）。
/// ⚠️ docs：归档项目此端点走二进制 body（KugouClient.request 现只支持 JSON 体）；
///    二进制载荷待三态实测，当前用 query 退化：全部参数走 query、body 显式留空。
Future<CollectResult> cancelCollectByHash(
  KugouClient client,
  String hash,
) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'cancelCollectByHash empty hash');
      return const CollectResult();
    }
    final params = <String, Object?>{
      ..._baseParams(client),
      'hash': h,
      'op': 'cancel',
      'source': 1,
      if (client.session.userid.isNotEmpty) 'userid': client.session.userid,
    };
    final res = await client.request(EndpointRegistry.cancelCollect, params,
        body: const <String, Object?>{});
    final ok = _writeSucceeded(res, 'cancel');
    final count = _countOf(res);
    Log.d(_tag, 'cancelCollectByHash hash=$h ok=$ok count=$count (query)');
    return CollectResult(ok: ok, count: count);
  } catch (e, st) {
    Log.e(_tag, 'cancelCollectByHash failed hash=$hash', e, st);
    return const CollectResult();
  }
}

/// 收藏计数（GET /v1/favorite/count，docs/KUGOU_API.md §3.9；
/// 路由/签名按 docs 类比声明，待三态实测）。失败返回 0 且必 Log 留痕。
Future<int> getFavoriteCount(KugouClient client) async {
  try {
    final res = await client.request(
        EndpointRegistry.favoriteCount,
        <String, Object?>{
          ..._baseParams(client),
          if (client.session.userid.isNotEmpty) 'userid': client.session.userid,
        });
    final n = _countOf(res);
    Log.d(_tag, 'getFavoriteCount count=$n');
    return n;
  } catch (e, st) {
    Log.e(_tag, 'getFavoriteCount failed', e, st);
    return 0;
  }
}
