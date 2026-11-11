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
/// ENDPOINT_TRUTH.md §5：KuGouMusicApi/module/ 内不存在歌曲 collect 端点，
/// 不臆造 /collect URL。本函数不发网络请求、不猜 URL；
/// ok=false，收藏条数以 logic 层本地镜像为单一事实源。
/// hash 恒小写；mixSongId 仅留档。
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
    Log.w(_tag, 'collectSongByHash upstream has no endpoint '
        '(ENDPOINT_TRUTH §5): local mirror only, no network call, '
        'no fake success hash=$h mix=$mixSongId');
    return const CollectResult(ok: false);
  } catch (e, st) {
    Log.e(_tag, 'collectSongByHash failed hash=$hash', e, st);
    return const CollectResult();
  }
}

/// 取消收藏（上游无此端点，本地镜像为准，不伪造网络成功）。
/// ENDPOINT_TRUTH.md §5：上游无歌曲 cancel_collect 模块，不应臆造 URL。
/// 本函数不发网络请求、不猜 URL；ok=false，取消结果以 logic 层本地镜像为准。
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
    Log.w(_tag, 'cancelCollectByHash upstream has no endpoint '
        '(ENDPOINT_TRUTH §5): local mirror only, no network call, '
        'no fake success hash=$h');
    return const CollectResult(ok: false);
  } catch (e, st) {
    Log.e(_tag, 'cancelCollectByHash failed hash=$hash', e, st);
    return const CollectResult();
  }
}

/// 收藏计数（GET /count/v1/audio/mget_collect，ENDPOINT_TRUTH.md §1/§5
/// favorite_count.js：query mixsongids（逗号分隔）+ 默认参数，android 签名；
/// 响应 body.data 为 mixsongid→收藏数映射）。失败返回 0 且必 Log 留痕。
/// 注：函数签名固定无 ids 入参，mixsongids 以空串占位并 Log.w（多参不缺参）。
Future<int> getFavoriteCount(KugouClient client) async {
  try {
    Log.w(_tag, 'getFavoriteCount no mixsongids in signature -> '
        'placeholder empty string');
    final res = await client.request(
        EndpointRegistry.favoriteCount,
        <String, Object?>{
          'mixsongids': '',
          ..._baseParams(client),
          if (client.session.userid.isNotEmpty) 'userid': client.session.userid,
        });
    // 数值容错：data 为映射时求和；退化 _countOf 常规键。
    final data = dataOf(res);
    var n = -1;
    if (data.isNotEmpty && data['count'] == null && data['total'] == null) {
      var sum = 0;
      var numeric = false;
      data.forEach((_, v) {
        final x = safeInt(v, -1);
        if (x >= 0) {
          sum += x;
          numeric = true;
        }
      });
      if (numeric) n = sum;
    }
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
