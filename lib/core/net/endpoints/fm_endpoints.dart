// L4 core/net/endpoints · 个人 FM 端点封装（功能对齐批4-C · GAP #21）
// 出处：docs/KUGOU_API.md §3.7（personal_fm / fm_songs）；
//       docs/PARITY_NOTES.md §3「个人 FM / 电台全缺（需先实测）」。
// 对应声明：EndpointRegistry.personalFm（POST /v1/fm/play）、
//           EndpointRegistry.fmSongs（GET /v1/fm/songs，本批追加，需先实测）。
// ⚠️ 状态：两端点均**未三态实测**（fm_songs/fm_recommend 需先实测）。
//    本批只落「声明 + 封装骨架 + 容错解析」；探针 flags=false 时恒返回空列表
//    并 Log.w 标注 needs probe，不发任何网络请求、**不猜参数**（query/body 归属、
//    song_pool_id/m_type/kguid/key 等全参集合一律以探针实测为准）。
// 装配方式：L5 logic/catalog/fm_logic.dart 经 bridge_logic 门面消费本文件；
//    L6 surface 只拿 FmLogic，不直接 import 端点文件。探针实测后只翻转下方两个
//    flag 并在 _fetch 调用点补实测参数契约（dfid/mid/uuid 恒显式参与签名，铁律 6），
//    不改 KugouClient.request、不改装配页。
// 铁律：只连酷狗官方 gateway 域名；每函数 try/catch + Log('ep.fm')；字段容错不崩。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart' show Endpoint, EndpointRegistry, KugouClient;
import 'models.dart' show SongBrief, dataOf, listOf, safeInt, safeStr;

const String _tag = 'ep.fm';

/// personalFm / fmSongs 是否已三态实测留样（anon / nonvip / vip）。
/// false = needs probe：只留痕返回空，禁止发请求。探针批实测后分别置 true。
const bool kFmPlayProbed = false;
const bool kFmSongsProbed = false;

/// FM 曲目最小模型（响应字段未实测；按既有搜索/歌单字段别名容错，缺失给默认）。
class FmTrack {
  const FmTrack({
    this.hash = '',
    this.name = '',
    this.singer = '',
    this.mixSongId = 0,
  });

  final String hash;
  final String name;
  final String singer;
  final int mixSongId;

  factory FmTrack.fromMap(Map<String, dynamic> m) {
    try {
      return FmTrack(
        hash: safeStr(m['hash'] ?? m['FileHash'] ?? m['file_hash'])
            .toLowerCase(),
        name: safeStr(m['name'] ?? m['FileName'] ?? m['songname']),
        singer: safeStr(m['singer'] ?? m['singername'] ?? m['SingerName']),
        mixSongId: safeInt(m['mixSongId'] ?? m['mixsongid'] ?? m['MixSongID']),
      );
    } catch (e, st) {
      Log.e(_tag, 'FmTrack.fromMap failed', e, st);
      return const FmTrack();
    }
  }

  /// 转成统一播放模型（队列/播放页只认 SongBrief）。
  SongBrief toSongBrief() {
    try {
      return SongBrief(
          hash: hash.toLowerCase(),
          name: name,
          singer: singer,
          mixSongId: mixSongId);
    } catch (e, st) {
      Log.e(_tag, 'FmTrack.toSongBrief failed', e, st);
      return const SongBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'hash': hash,
        'name': name,
        'singer': singer,
        'mixSongId': mixSongId,
      };

  @override
  String toString() {
    try {
      return 'FmTrack(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'FmTrack.toString failed', e, st);
      return 'FmTrack(<unavailable>)';
    }
  }
}

/// 容错解析 FM 歌曲列表（字段路径未实测，多别名兜底；hash 空项丢弃）。
List<SongBrief> _parseSongs(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    final raw = data['songs'] ?? data['list'] ?? data['info'] ??
        data['lists'] ?? res['songs'] ?? res['list'] ?? res['data'];
    final items = listOf(raw)
        .map(FmTrack.fromMap)
        .map((t) => t.toSongBrief())
        .where((s) => s.hash.isNotEmpty)
        .toList(growable: false);
    final ec = safeInt(res['errcode'] ?? res['err_code'] ?? data['errcode']);
    if (ec != 0) Log.w(_tag, 'parseSongs server ec=$ec');
    Log.d(_tag, 'parseSongs got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'parseSongs failed', e, st);
    return const <SongBrief>[];
  }
}

/// 唯一请求出口（探针实测后才可能真正发请求）。
/// params/body 必须由实测契约填入；空契约一律拒绝发送，防止误翻 flag 打空参。
Future<List<SongBrief>> _fetch(
  KugouClient client,
  Endpoint ep,
  Map<String, Object?> params, {
  Map<String, Object?> body = const <String, Object?>{},
}) async {
  try {
    if (params.isEmpty && body.isEmpty) {
      Log.w(_tag,
          'needs probe: empty measured contract ep=${ep.id}; no request issued');
      return const <SongBrief>[];
    }
    // 六五规则铁律 6：dfid/mid/uuid 恒显式携带并参与签名；只走酷狗官方域名。
    final p = <String, Object?>{
      ...params,
      'dfid': client.session.dfid,
      'mid': client.session.mid,
      'uuid': '-',
    };
    final res = await client.request(ep, p, body: body);
    return _parseSongs(res);
  } catch (e, st) {
    Log.e(_tag, 'fetch failed ep=${ep.id}', e, st);
    return const <SongBrief>[];
  }
}

/// 个人 FM 首批（personalFm：POST /v1/fm/play）。
/// mode/action 为 docs §3.7 已记录的动作词（'normal' / 'play'），但参数归属与
/// 全参集合未实测，本批不发送；返回空即 needs probe，装配层按空态降级。
Future<List<SongBrief>> getFmPlay(
  KugouClient client, {
  String mode = 'normal',
  String action = 'play',
}) async {
  try {
    final ep = EndpointRegistry.personalFm;
    if (!kFmPlayProbed) {
      Log.w(_tag, 'needs probe: getFmPlay ep=${ep.id} path=${ep.path} '
          'mode=$mode action=$action; no request, params not guessed');
      return const <SongBrief>[];
    }
    // 探针实测后：按实测契约填 params/body（key=signParamsKey(ms) 等），
    // 再交给 _fetch；此处不预置任何未实测参数。
    return await _fetch(client, ep, const <String, Object?>{});
  } catch (e, st) {
    Log.e(_tag, 'getFmPlay failed mode=$mode action=$action', e, st);
    return const <SongBrief>[];
  }
}

/// 电台/FM 批量歌曲（fmSongs：GET /v1/fm/songs）。
/// fmid/fmtype/offset/size 为 docs §3.7 记录的批量维度；取值与归属未实测，
/// 本批不发送（fmid/fmtype 留空、不臆造枚举值），返回空即 needs probe。
Future<List<SongBrief>> getFmSongs(
  KugouClient client, {
  String fmid = '',
  String fmtype = '',
  int offset = 0,
  int size = 0,
}) async {
  try {
    final ep = EndpointRegistry.fmSongs;
    final off = offset < 0 ? 0 : offset;
    final n = size < 0 ? 0 : size;
    if (!kFmSongsProbed) {
      Log.w(_tag, 'needs probe: getFmSongs ep=${ep.id} path=${ep.path} '
          'fmid=$fmid fmtype=$fmtype offset=$off size=$n; '
          'no request, params not guessed');
      return const <SongBrief>[];
    }
    // 探针实测后：按实测契约填 params/body，再交给 _fetch。
    return await _fetch(client, ep, const <String, Object?>{});
  } catch (e, st) {
    Log.e(_tag, 'getFmSongs failed offset=$offset size=$size', e, st);
    return const <SongBrief>[];
  }
}
