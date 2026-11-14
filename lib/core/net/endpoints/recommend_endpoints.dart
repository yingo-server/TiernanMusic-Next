// L4 core/net/endpoints · 每日推荐端点封装（功能对齐批3-C · GAP #20）
// 端点声明见 EndpointRegistry.recommendSongs：POST /everyday_song_recommend，
// x-router: everydayrec.service.kugou.com（docs/KUGOU_API.md §3.7）。
// ⚠️ 参数放置（docs/PARITY_NOTES.md §1「everyday/recommend：platform 必须是 query 参数」）：
//   platform 放 QUERY（不能放 body），userid/token 放 BODY；
//   dfid/mid/uuid 恒显式携带并参与签名（六五规则铁律 6，KugouClient 只自动补
//   dfid/uuid，mid 仅在 header，故此处三参在 params 中显式补齐全）。
// 响应 data.songs[] / data.list[] 双容错 → SongBrief.fromTrackInfo。
// 铁律：try/catch + Log('ep.recommend')，失败返回空列表不静默吞。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show SongBrief, dataOf, listOf, safeInt, safeStr;

const String _tag = 'ep.recommend';
const String kDailyRecommendPath = '/everyday_song_recommend';

/// 每日推荐（分页从 1 起）。登录态由 session 提供；匿名可返回空列表。
/// 参数：platform/page/pagesize + dfid/mid/uuid → query；userid/token → body。
Future<List<SongBrief>> getDailyRecommend(
  KugouClient client, {
  int page = 1,
  int pageSize = 30,
}) async {
  try {
    final p = page < 1 ? 1 : page;
    final ps = pageSize < 1 ? 30 : pageSize;
    final session = client.session;
    final params = <String, Object?>{
      // 实测：platform 必须是 query 参数。
      'platform': 'android',
      'page': p,
      'pagesize': ps,
      // 三参恒显式入场并参与 android 签名。
      'dfid': session.dfid,
      'mid': session.mid,
      'uuid': '-',
    };
    final body = <String, Object?>{
      'userid': session.userid,
      'token': session.token,
    };
    final res = await client.request(EndpointRegistry.recommendSongs, params,
        body: body);
    final data = dataOf(res);
    final raw = data['songs'] ?? data['list'] ?? data['info'] ??
        res['songs'] ?? res['list'];
    final items = listOf(raw)
        .map(SongBrief.fromTrackInfo)
        .where((s) => s.hash.isNotEmpty)
        .toList(growable: false);
    final errCode = safeInt(res['errcode'] ?? data['errcode'], 0);
    final errMsg = safeStr(res['error'] ?? data['error'] ?? data['errmsg']);
    // 实测（API_TEST_REPORT）：未登录态 errcode=200103、data 为字符串。
    // 显式留痕 + 如实返回空（UI 侧按「需登录」提示，不冒充「暂无推荐」）。
    if (errCode == 200103) {
      Log.w(_tag, 'getDailyRecommend: 200103 (login required)');
      return const <SongBrief>[];
    }
    if (errCode != 0 || errMsg.isNotEmpty) {
      Log.w(_tag, 'getDailyRecommend page=$p server ec=$errCode msg=$errMsg');
    }
    Log.d(_tag, 'getDailyRecommend page=$p got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getDailyRecommend failed page=$page', e, st);
    return const <SongBrief>[];
  }
}
