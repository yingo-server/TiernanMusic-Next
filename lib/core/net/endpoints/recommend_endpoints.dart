// L4 core/net/endpoints · 每日推荐端点封装（功能对齐批3-C · GAP #20）
// 端点声明见 EndpointRegistry.recommendSongs：POST /everyday_song_recommend，
// x-router: everydayrec.service.kugou.com（docs/KUGOU_API.md §3.7）。
// ⚠️ 参数放置（docs/PARITY_NOTES.md §1「everyday/recommend：platform 必须是 query 参数」）：
//   platform 放 QUERY（不能放 body），userid/token 放 BODY；
//   dfid/mid/uuid 恒显式携带并参与签名（六五规则铁律 6，KugouClient 只自动补
//   dfid/uuid，mid 仅在 header，故此处三参在 params 中显式补齐全）。
// 响应 data.songs[] / data.list[] 双容错 → SongBrief.fromTrackInfo。
// 批3-F2：200103（未登录）/ 空推荐 / 网络异常由 DailyRecommendResult.state 显式区分，
// 不再把「未登录」冒充「无推荐」；结果对象同时实现 List<SongBrief>，
// 使尚未改造的 UI（home_page 的 Future<List<SongBrief>>）零改动仍可编译。
// 铁律：try/catch + Log('ep.recommend')，失败返回带 error 态的空结果不静默吞。
import 'dart:collection' show ListBase;

import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart' show SongBrief, dataOf, listOf, safeInt, safeStr;

const String _tag = 'ep.recommend';
const String kDailyRecommendPath = '/everyday_song_recommend';

/// 每日推荐的显式状态（批3-F2）：UI 可区分「需登录 / 真的没有 / 失败」。
enum DailyRecommendState { ok, loginRequired, empty, error }

/// 每日推荐结果：state + items。
/// 实现 ListBase<SongBrief> 以兼容未改造的调用方（当作 List<SongBrief> 消费），
/// 同时暴露 .state/.loginRequired 供后续 UI 显示「需登录」，不静默冒充空推荐。
class DailyRecommendResult extends ListBase<SongBrief> {
  DailyRecommendResult(this.state, List<SongBrief> items)
      : _items = List<SongBrief>.unmodifiable(items);

  factory DailyRecommendResult.ok(List<SongBrief> items) => DailyRecommendResult(
        items.isEmpty ? DailyRecommendState.empty : DailyRecommendState.ok,
        items,
      );

  factory DailyRecommendResult.loginRequired() =>
      DailyRecommendResult(DailyRecommendState.loginRequired, const <SongBrief>[]);

  factory DailyRecommendResult.error() =>
      DailyRecommendResult(DailyRecommendState.error, const <SongBrief>[]);

  final DailyRecommendState state;
  final List<SongBrief> _items;

  bool get loginRequired => state == DailyRecommendState.loginRequired;

  /// 供 logic 层缓存判定：只有确实拿到列表才落缓存。
  bool get cacheable => state == DailyRecommendState.ok ||
      state == DailyRecommendState.empty;

  @override
  int get length => _items.length;

  @override
  set length(int v) => throw UnsupportedError('DailyRecommendResult 只读');

  @override
  SongBrief operator [](int index) => _items[index];

  @override
  void operator []=(int index, SongBrief value) =>
      throw UnsupportedError('DailyRecommendResult 只读');

  @override
  void add(SongBrief element) => throw UnsupportedError('DailyRecommendResult 只读');

  @override
  void addAll(Iterable<SongBrief> iterable) =>
      throw UnsupportedError('DailyRecommendResult 只读');

  @override
  String toString() => 'DailyRecommendResult(${state.name}, ${_items.length})';
}

/// 每日推荐（分页从 1 起）。登录态由 session 提供；匿名返回 loginRequired 态，
/// 其余失败（网络/解析/业务错）返回 error 态；均无隐藏的「空列表即成功」语义。
/// 参数：platform/page/pagesize + dfid/mid/uuid → query；userid/token → body。
Future<DailyRecommendResult> getDailyRecommend(
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
    // 批3-F2：显式返回 loginRequired 态，UI 侧可据此提示「需登录」，
    // 不再冒充「暂无推荐」；logic 层据此拒绝把未登录固化进缓存。
    if (errCode == 200103) {
      Log.w(_tag, 'getDailyRecommend: 200103 (login required)');
      return DailyRecommendResult.loginRequired();
    }
    if (errCode != 0 || errMsg.isNotEmpty) {
      Log.w(_tag, 'getDailyRecommend page=$p server ec=$errCode msg=$errMsg');
      // 有数据时仍按列表返回（兼容旧行为）；无任何曲目才判 error 态，
      // 避免把「服务端附带提示但已给列表」误报成失败。
      if (items.isEmpty) return DailyRecommendResult.error();
    }
    Log.d(_tag, 'getDailyRecommend page=$p got=${items.length}');
    return DailyRecommendResult.ok(items);
  } catch (e, st) {
    Log.e(_tag, 'getDailyRecommend failed page=$page', e, st);
    return DailyRecommendResult.error();
  }
}
