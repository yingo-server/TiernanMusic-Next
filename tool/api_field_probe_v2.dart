// tool/api_field_probe_v2.dart — 批1-F1 三态只读字段捕获探针（纯 Dart，零新增依赖）
//
// 目的：匿名/非VIP/VIP 三态下真实调用 17 个只读端点，对每个响应记录
// 顶层键 + 关键字段的「存在/类型/长度」（域名+长度仅用于 URL 类值）。
// 复用 docs/six_b1_c2.md §F1 规格与 tool/api_probe.dart 调用样式；
// 报告汇总归 F2，本脚本不写报告、不改 lib/、不进 CI verdict（six_b1_c3.md §③）。
//
// 安全口径（沿 api_probe.dart / six_b1_c3.md）：
//  - 只读端点；禁止登录与任何写操作；凭据值不打印；
//  - token/userid/cookie/mid/dfid/signature/手机号/URL query 一律掩码；
//  - URL/封面/头像类值只留域名 + 长度；昵称只记有/无；
//  - 网络失败 / 凭据缺失 / WAF 非 JSON 一律 SKIP，不伪造数据；
//  - lib 的 print 日志在 Zone 内统一截流为长度摘要，杜绝凭据意外回显。
//
// 运行：dart run tool/api_field_probe_v2.dart [--out docs/api_samples_v2]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/core/net/kugou_client.dart';
import '../lib/core/net/endpoints/comment_endpoints.dart' show kCommentCode;
import '../lib/core/net/endpoints/user_endpoints.dart' show rsaCryptoEncrypt;
import '../lib/core/net/signing.dart' show KugouSign;

const String _vipPath = '/var/minis/workspace/.test_creds/cj_vip.txt';
const String _nonVipPath = '/var/minis/workspace/.test_creds/cj_nonvip.txt';
const String _vipSongHash = 'b3a52a7a958bf0aed0ebfba2e9a818b7'; // 周杰伦《晴天》
const String _mixSongId = '1001975428';
const String _albumId = '14350311';
const String _commentCode = kCommentCode;

/// Netscape cookie TSV（7 列）；仅取键名→值供请求使用，绝不输出。
Map<String, String> _loadCreds(String path) {
  final map = <String, String>{};
  final f = File(path);
  if (!f.existsSync()) return map;
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final parts = line.split('\t');
    if (parts.length >= 7) map[parts[5]] = parts.sublist(6).join('\t');
  }
  return map;
}

KugouSession _sessionOf(Map<String, String>? c) {
  final s = KugouSession();
  if (c == null || c.isEmpty) {
    s.dfid = '-';
    s.userid = '0'; // 匿名态 userid='0'
    return s;
  }
  s.token = c['token'] ?? '';
  s.userid = c['userid'] ?? '';
  s.mid = c['KUGOU_API_MID'] ?? '';
  s.dfid = '1234567890ABCDEF12345678';
  for (final k in <String>['t1', 'vip_type', 'vip_token', 'userid']) {
    final v = c[k];
    if (v != null && v.isNotEmpty) s.cookies[k] = v;
  }
  return s;
}

bool _isSensitive(String key) {
  final k = key.toLowerCase();
  // 数字账号/手机号、32+ 位 hex（hash 型响应键）作键名亦掩码。
  if (RegExp(r'^\d{6,}$').hasMatch(key) ||
      RegExp(r'^[0-9a-f]{32,}$').hasMatch(k)) {
    return true;
  }
  return k.contains('token') ||
      k.contains('cookie') ||
      k.contains('userid') ||
      k.contains('uid') ||
      k.contains('guid') ||
      k == 'mid' ||
      k == 'dfid' ||
      k.contains('signature') ||
      k.contains('phone') ||
      k.contains('mobile') ||
      k.contains('query') ||
      k == 'p' ||
      k.endsWith('key');
}

bool _isUrlLike(String key) {
  final k = key.toLowerCase();
  return k.contains('url') ||
      k.contains('uri') ||
      k.contains('link') ||
      k.contains('cover') ||
      k.contains('avatar') ||
      k.contains('pic') ||
      k.contains('downurl') ||
      k.contains('img');
}

String _maskKey(String key) =>
    (_isSensitive(key) || _isUrlLike(key)) ? '<redacted-key>' : key;

/// URL 类值：只留域名 + 长度；非 URL 返回 '<redacted-query>'。
List<String> _hosts(Object? v) {
  final out = <String>{};
  final list = v is List ? v : <Object?>[v];
  for (final item in list) {
    if (item is! String || item.isEmpty) continue;
    try {
      final u = Uri.parse(item);
      out.add(u.host.isEmpty ? '<redacted-query>' : u.host);
    } catch (_) {
      out.add('<redacted-query>');
    }
  }
  return out.toList()..sort();
}

const Set<String> _numericWhitelist = <String>{
  'status',
  'errcode',
  'error_code',
  'priv_status',
  'bitrate',
  'bitRate',
  'timelength',
  'count',
  'total',
  'isfreepart',
  'end_byte',
  'hash_offset',
  'fail_process',
  'musicpack_advance',
  'vip_type',
  'level',
  'contenttype',
  'duration',
  'record_count',
  'recordcount',
};

/// 字段三元组：present / type / len；数值白名单可留值，敏感键只留掩码。
Map<String, Object?> _field(String key, Object? v) {
  final leaf = key.split('.').last.toLowerCase();
  final f = <String, Object?>{
    'present': v != null,
    'type': v == null
        ? 'null'
        : v is List
        ? 'list'
        : v is Map
        ? 'map'
        : v is num
        ? 'num'
        : v is bool
        ? 'bool'
        : 'string',
    'len': v is List
        ? v.length
        : v is Map
        ? v.length
        : v is String
        ? v.length
        : (v == null ? 0 : 1),
  };
  if (_isSensitive(key) || _isSensitive(leaf)) {
    f['masked'] = true;
    return f;
  }
  if (_isUrlLike(key) || _isUrlLike(leaf)) {
    f['masked'] = true;
    f['hosts'] = _hosts(v);
    return f;
  }
  if (v is num && _numericWhitelist.contains(leaf)) f['value'] = v;
  if (v is bool && _numericWhitelist.contains(leaf)) f['value'] = v;
  if (v is String && !_isUrlLike(key) && !_isUrlLike(leaf)) {
    // 字符串值一律不落盘（昵称/名称/内容可能含个人数据）；长度已在 len。
    f['masked'] = true;
    f['domain'] = '';
  }
  return f;
}

Object? _at(Map<String, dynamic> res, String path) {
  Object? cur = res;
  for (final part in path.split('.')) {
    if (cur is Map) {
      if (!cur.containsKey(part)) return null;
      cur = cur[part];
    } else if (cur is List && int.tryParse(part) != null) {
      final i = int.parse(part);
      if (i >= cur.length) return null;
      cur = cur[i];
    } else {
      return null;
    }
  }
  return cur;
}

/// 顶层键（敏感键名掩码）+ 关键字段存在/类型/长度。
Map<String, Object?> _capture(
  Map<String, dynamic> res,
  List<String> keys,
) => <String, Object?>{
  '_topKeys': res.keys.map(_maskKey).toList(),

  '_topKeyCount': res.length,
  '_redactedTopKeys': res.keys.where((k) => _maskKey(k) != k).length,
  '_fields': <String, Object?>{for (final k in keys) k: _field(k, _at(res, k))},
};

class Spec {
  const Spec(this.name, this.ep, this.params, this.body, this.keys);
  final String name;
  final Endpoint ep;
  final Map<String, Object?> params;
  final Map<String, Object?> body;
  final List<String> keys;
}

List<Spec> _specs(KugouClient client) {
  final s = client.session;
  final ctSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final ms = '${DateTime.now().millisecondsSinceEpoch}';
  final uid = s.userid;
  return <Spec>[
    Spec(
      'search_song',
      EndpointRegistry.searchSong,
      <String, Object?>{
        'keyword': '周杰伦',
        'page': 1,
        'pagesize': 10,
        'albumhide': 0,
        'iscorrection': 1,
        'nocollect': 0,
        'platform': 'AndroidFilter',
      },
      const <String, Object?>{},
      const <String>[
        'status',
        'error_code',
        'errcode',
        'data',
        'data.total',
        'data.lists',
        'data.info',
      ],
    ),
    Spec(
      'search_suggest',
      EndpointRegistry.searchSuggest,
      <String, Object?>{
        'keyword': '周杰伦',
        'AlbumTipCount': 10,
        'CorrectTipCount': 10,
        'MVTipCount': 10,
        'MusicTipCount': 10,
        'radiotip': 1,
      },
      const <String, Object?>{},
      const <String>[
        'status',
        'error_code',
        'data',
        'data.0.RecordDatas',
        'data.0.RecordCount',
      ],
    ),
    Spec(
      'search_hot',
      EndpointRegistry.searchHot,
      <String, Object?>{'navid': 1, 'plat': 2},
      const <String, Object?>{},
      const <String>['status', 'error_code', 'data', 'data.list', 'data.info'],
    ),
    Spec(
      'rank_list',
      EndpointRegistry.rankList,
      <String, Object?>{'plat': 2, 'withsong': 1, 'parentid': 0},
      const <String, Object?>{},
      const <String>['status', 'error_code', 'data', 'data.info', 'data.list'],
    ),
    Spec(
      'daily_recommend',
      EndpointRegistry.recommendSongs,
      <String, Object?>{
        'platform': 'android',
        'page': 1,
        'pagesize': 30,
        'dfid': s.dfid,
        'mid': s.mid,
        'uuid': '-',
      },
      <String, Object?>{'userid': uid, 'token': s.token},
      const <String>[
        'status',
        'errcode',
        'error',
        'data',
        'data.songs',
        'data.list',
        'data.errcode',
      ],
    ),
    Spec(
      'user_detail',
      EndpointRegistry.userDetail,
      <String, Object?>{'plat': 1},
      <String, Object?>{
        'visit_time': ctSec,
        'usertype': 1,
        'p': rsaCryptoEncrypt('{"token":"${s.token}","clienttime":$ctSec}'),
        'userid': uid,
      },
      const <String>[
        'status',
        'error_code',
        'data',
        'nickname',
        'pic',
        'vip_type',
        'userid',
        'level',
      ],
    ),
    Spec(
      'favorite_count',
      EndpointRegistry.favoriteCount,
      <String, Object?>{
        'mixsongids': '',
        'dfid': s.dfid,
        'mid': s.mid,
        'uuid': '-',
        'plat': 1,
        if (uid.isNotEmpty && uid != '0') 'userid': uid,
      },
      const <String, Object?>{},
      const <String>[
        'status',
        'error_code',
        'errcode',
        'data',
        'data.list',
        'data.count',
        'count',
      ],
    ),
    Spec(
      'song_climax',
      EndpointRegistry.songClimax,
      <String, Object?>{'hash': _vipSongHash, 'album_audio_id': 0},
      const <String, Object?>{},
      const <String>[
        'status',
        'error_code',
        'data',
        'data.0.url',
        'data.0.start_time',
      ],
    ),
    Spec(
      'user_cloud',
      EndpointRegistry.userCloud,
      <String, Object?>{'page': 1, 'pagesize': 30},
      const <String, Object?>{},
      const <String>['status', 'error_code', 'data', 'data.list', 'data.info'],
    ),
    Spec(
      'fm_play',
      EndpointRegistry.personalFm,
      <String, Object?>{'dfid': s.dfid, 'mid': s.mid, 'uuid': '-'},
      <String, Object?>{
        'appid': KugouSign.appid,
        'clienttime': ms,
        'mid': s.mid,
        'action': 'play',
        'mode': 'normal',
        'recommend_source_locked': 0,
        'song_pool_id': 0,
        'callerid': '',
        'm_type': 1,
        'platform': 'android',
        'area_code': 1,
        'remain_songcnt': 0,
        'clientver': KugouSign.clientver,
        'is_overplay': 0,
        'fakem': 'ca981cfc583a4c37f28d2d49000013c16a0a',
        'key': KugouSign.signParamsKey(ms),
        'userid': uid,
        'kguid': uid,
        'token': s.token,
        'vip_type': 0,
        'hash': '',
        'songid': 0,
        'playtime': 0,
      },
      const <String>['status', 'error_code', 'data', 'data.songs', 'data.list'],
    ),
    Spec(
      'comment_music',
      EndpointRegistry.commentMusic,
      <String, Object?>{
        'mixsongid': _mixSongId,
        'p': 1,
        'pagesize': 10,
        'code': _commentCode,
      },
      const <String, Object?>{},
      const <String>[
        'status',
        'error_code',
        'data',
        'data.count',
        'data.total',
        'data.list',
        'data.hot_words',
      ],
    ),
    Spec(
      'comment_count',
      EndpointRegistry.commentCount,
      <String, Object?>{'code': _commentCode, 'hash': _vipSongHash},
      const <String, Object?>{},
      const <String>['status', 'error_code', _vipSongHash],
    ),
    Spec(
      'mv_by_song',
      EndpointRegistry.mvDetail,
      const <String, Object?>{},
      <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'album_audio_id': _mixSongId},
        ],
        'fields': '',
      },
      const <String>['status', 'error_code', 'data', 'data.data', 'data.list'],
    ),
    Spec(
      'album_detail',
      EndpointRegistry.albumDetail,
      const <String, Object?>{},
      <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'album_id': _albumId},
        ],
      },
      const <String>['status', 'error_code', 'data', 'data.data', 'data.list'],
    ),
    Spec(
      'lyric_search',
      EndpointRegistry.lyricSearch,
      <String, Object?>{
        'hash': _vipSongHash,
        'keyword': '晴天',
        'duration': 269000,
        'album_audio_id': 0,
        'lrctxt': 1,
        'man': 'no',
        'appid': KugouSign.appid,
        'clientver': KugouSign.clientver,
      },
      const <String, Object?>{},
      const <String>[
        'status',
        'errcode',
        'info',
        'candidates',
        'candidates.0.id',
        'candidates.0.accesskey',
      ],
    ),
    Spec(
      'privilege_lite',
      EndpointRegistry.privilegeLite,
      <String, Object?>{
        'appid': KugouSign.appid,
        'clientver': KugouSign.clientver,
        'area_code': 1,
        'behavior': 'play',
        'need_hash_offset': 1,
        'relate': 1,
        'support_verify': 1,
      },
      <String, Object?>{
        'resource': <Object?>[
          <String, Object?>{
            'type': 'audio',
            'hash': _vipSongHash,
            'album_id': '',
            'page_id': 0,
          },
        ],
        'qualities': const <String>['128', '320', 'flac', 'high'],
        'appid': KugouSign.appid,
        'clientver': KugouSign.clientver,
        'area_code': 1,
        'behavior': 'play',
      },
      const <String>['status', 'error_code', 'data', 'data.data', 'data.list'],
    ),
    Spec(
      'play_url_v5',
      EndpointRegistry.playUrlV5,
      <String, Object?>{
        'hash': _vipSongHash,
        'quality': '128',
        'album_audio_id': 0,
        'album_id': 0,
        'area_code': 1,
        'behavior': 'play',
        'ssa_flag': 'is_fromtrack',
        'version': 11430,
        'clientver': 11430,
        'page_id': 151369488,
        'ppage_id': '463467626,350369493,788954147',
        'pid': 2,
        'cmd': 26,
        'pidversion': 3001,
        'IsFreePart': 0,
        'cdnBackup': 1,
      },
      const <String, Object?>{},
      const <String>[
        'status',
        'priv_status',
        'errcode',
        'error_code',
        'url',
        'backupUrl',
        'bitRate',
        'extName',
        'timeLength',
        'IsFreePart',
        'end_byte',
        'hash_offset',
        'fail_process',
        'tracker_through.musicpack_advance',
      ],
    ),
  ];
}

class Row2 {
  const Row2({
    required this.endpoint,
    required this.state,
    required this.method,
    required this.domain,
    required this.path,
    required this.paramKeys,
    required this.bodyKeys,
    required this.ok,
    required this.ms,
    required this.captured,
    this.skip,
  });
  final String endpoint;
  final String state;
  final String method;
  final String domain;
  final String path;
  final List<String> paramKeys;
  final List<String> bodyKeys;
  final bool ok;
  final int ms;
  final Map<String, Object?> captured;
  final String? skip;

  Map<String, Object?> toJson() => <String, Object?>{
    'endpoint': endpoint,
    'state': state,
    'method': method,
    'domain': domain,
    'path': path,
    'paramKeys': paramKeys,
    'bodyKeys': bodyKeys,
    'ok': ok,
    'ms': ms,
    'captured': captured,
    if (skip != null) 'skip': skip,
  };
}

String _classifyErr(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('access den') ||
      m.contains('waf') ||
      m.contains('forbidden') ||
      m.contains('<!doctype') ||
      m.contains('<html') ||
      m.contains('invalid json') ||
      m.contains('unexpected response') ||
      m.contains('http 403') ||
      m.contains('http 405')) {
    return 'SKIP: waf/non-json';
  }
  if (m.contains('timeout') ||
      m.contains('socket') ||
      m.contains('connection') ||
      m.contains('handshake') ||
      m.contains('failed host lookup') ||
      m.contains('http ')) {
    return 'SKIP: network';
  }
  return 'SKIP: request-error';
}

Future<Row2> _run({
  required KugouClient client,
  required Spec spec,
  required String state,
}) async {
  final sw = Stopwatch()..start();
  Map<String, dynamic>? res;
  String? skip;
  try {
    res = await client
        .request(spec.ep, spec.params, body: spec.body)
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    skip = _classifyErr(e.toString());
  }
  sw.stop();
  var cap = <String, Object?>{};
  if (skip == null && res != null) {
    try {
      cap = _capture(res, spec.keys);
    } catch (e) {
      skip = 'SKIP: capture-error';
    }
  }
  return Row2(
    endpoint: spec.name,
    state: state,
    method: spec.ep.method,
    domain: Uri.parse(spec.ep.base).host,
    path: spec.ep.path,
    paramKeys: spec.params.keys.map(_maskKey).toList(),
    bodyKeys: spec.body.keys.map(_maskKey).toList(),
    ok: skip == null,
    ms: sw.elapsedMilliseconds,
    captured: cap,
    skip: skip,
  );
}

void _emit(String line) => stdout.writeln(line);

Future<void> _probe(String outDir) async {
  final vip = _loadCreds(_vipPath);
  final nonVip = _loadCreds(_nonVipPath);
  final states = <String, Map<String, String>?>{
    'anonymous': const <String, String>{},
    'nonvip': nonVip.isEmpty ? null : nonVip,
    'vip': vip.isEmpty ? null : vip,
  };
  final dir = Directory(outDir)..createSync(recursive: true);

  for (final entry in states.entries) {
    final state = entry.key;
    final creds = entry.value;
    if (creds == null) {
      final row = Row2(
        endpoint: '_session',
        state: state,
        method: '-',
        domain: '-',
        path: '-',
        paramKeys: const <String>[],
        bodyKeys: const <String>[],
        ok: false,
        ms: 0,
        captured: const <String, Object?>{},
        skip: 'SKIP: credentials missing (cj_${state}.txt)',
      );
      File('${dir.path}/$state.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<Object?>[row.toJson()]),
      );
      _emit('== state=$state == SKIP: credentials missing');
      continue;
    }
    final client = KugouClient(_sessionOf(creds));
    _emit('== state=$state == specs=${_specs(client).length}');
    final rows = <Row2>[];
    for (final spec in _specs(client)) {
      final r = await _run(client: client, spec: spec, state: state);
      rows.add(r);
      final n = r.captured['_topKeyCount'] ?? '-';
      _emit(
        '${r.endpoint.padRight(18)} ok=${r.ok} ${r.ms}ms '
        '${r.skip ?? "topKeys=$n"}',
      );
    }
    client.close();
    File('${dir.path}/$state.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert(rows.map((r) => r.toJson()).toList()),
    );
  }
  _emit('saved states=${states.keys.join(",")} → $outDir');
}

Future<void> main(List<String> args) async {
  final i = args.indexOf('--out');
  final outDir = (i >= 0 && i + 1 < args.length)
      ? args[i + 1]
      : 'docs/api_samples_v2';
  // lib 内 print 日志一律截流，避免任何凭据/响应原文回显。
  await runZoned<Future<void>>(
    () => _probe(outDir),
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        _emit('<lib-log len=${line.length}>');
      },
    ),
  );
}
