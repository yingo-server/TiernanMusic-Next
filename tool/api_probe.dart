// tool/api_probe.dart — 三态真实调用探针（纯 Dart，无 flutter）
//
// 目的：把「代码实际使用的端点」在 匿名/非VIP/VIP 三态下真跑一遍，留档
// 调用方式、耗时、代码捕获的字段是否可用。输出脱敏 JSON，供 API_TEST_REPORT 汇总。
//
// 安全：
//  - token/userid/cookie/mid/dfid/signature 一律不落盘
//  - 播放 URL 只留 host，不留带签名的完整地址
//  - 不执行任何写操作（收藏/歌单增删/上报），避免改动真实账号数据
//
// 运行：dart run tool/api_probe.dart [--out docs/api_samples]
import 'dart:convert';
import 'dart:io';

import '../lib/core/net/kugou_client.dart';
import '../lib/core/net/endpoints/album_endpoints.dart';
import '../lib/core/net/endpoints/collect_endpoints.dart';
import '../lib/core/net/endpoints/comment_endpoints.dart';
import '../lib/core/net/endpoints/fm_endpoints.dart';
import '../lib/core/net/endpoints/misc_endpoints.dart';
import '../lib/core/net/endpoints/mv_endpoints.dart';
import '../lib/core/net/endpoints/play_endpoints.dart';
import '../lib/core/net/endpoints/play_models.dart' show PlayResult;
import '../lib/core/net/endpoints/recommend_endpoints.dart';
import '../lib/core/net/endpoints/search_endpoints.dart';
import '../lib/core/net/endpoints/user_endpoints.dart';

const String _vipPath = '/var/minis/workspace/.test_creds/cj_vip.txt';
const String _nonVipPath = '/var/minis/workspace/.test_creds/cj_nonvip.txt';

/// 样曲：周杰伦《晴天》（VIP 曲，三态差异明显）。
const String _vipSongHash = 'b3a52a7a958bf0aed0ebfba2e9a818b7';

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

String _hostOf(Object? urls) {
  try {
    final first = urls is List && urls.isNotEmpty ? urls.first : null;
    if (first is! String || first.isEmpty) return '';
    return Uri.parse(first).host;
  } catch (_) {
    return '';
  }
}

/// 一条探针记录。
class ProbeRow {
  ProbeRow({
    required this.endpoint,
    required this.state,
    required this.method,
    required this.domain,
    required this.path,
    required this.paramKeys,
    required this.ok,
    required this.ms,
    this.captured = const <String, Object?>{},
    this.error,
    this.rawSanitized,
  });

  final String endpoint;
  final String state;
  final String method;
  final String domain;
  final String path;
  final List<String> paramKeys;
  final bool ok;
  final int ms;
  final Map<String, Object?> captured;
  final String? error;
  final Map<String, Object?>? rawSanitized;

  Map<String, Object?> toJson() => <String, Object?>{
        'endpoint': endpoint,
        'state': state,
        'method': method,
        'domain': domain,
        'path': path,
        'paramKeys': paramKeys,
        'ok': ok,
        'ms': ms,
        'captured': captured,
        if (error != null) 'error': error,
        if (rawSanitized != null) 'raw': rawSanitized,
      };
}

/// 脱敏 play_url 原始响应：只留结构键与判定字段，URL 替换为占位。
Map<String, Object?> _sanitizePlayRaw(Map<String, dynamic> res) {
  final out = <String, Object?>{};
  for (final k in <String>[
    'status', 'priv_status', 'errcode', 'error_code', 'bitRate', 'extName',
    'timeLength', 'IsFreePart', 'end_byte', 'traceId',
  ]) {
    if (res.containsKey(k)) out[k] = res[k];
  }
  final tt = res['tracker_through'];
  if (tt is Map && tt.containsKey('musicpack_advance')) {
    out['tracker_through.musicpack_advance'] = tt['musicpack_advance'];
  }
  for (final k in <String>['url', 'backupUrl']) {
    final v = res[k];
    if (v is List) {
      out['$k.count'] = v.length;
      out[k] = v.isEmpty ? <String>[] : <String>['<redacted-url>'];
    } else if (v is String && v.isNotEmpty) {
      out['$k.count'] = 1;
      out[k] = <String>['<redacted-url>'];
    } else {
      out['$k.count'] = 0;
    }
  }
  out['_host'] = _hostOf(res['url']);
  out['_topKeys'] = res.keys.take(40).toList();
  return out;
}

Future<ProbeRow> _run({
  required String endpoint,
  required String state,
  required Endpoint ep,
  required Map<String, Object?> params,
  required Future<Object?> Function() call,
  Map<String, Object?> Function(Object? value)? capture,
}) async {
  final sw = Stopwatch()..start();
  var ok = true;
  Object? value;
  String? err;
  try {
    value = await call();
  } catch (e) {
    ok = false;
    err = e.toString();
  }
  sw.stop();
  Map<String, Object?> cap = const <String, Object?>{};
  if (ok) {
    try {
      cap = capture != null
          ? capture(value)
          : <String, Object?>{'type': value.runtimeType.toString()};
    } catch (e) {
      cap = <String, Object?>{'captureError': e.toString()};
    }
  }
  return ProbeRow(
    endpoint: endpoint,
    state: state,
    method: ep.method,
    domain: Uri.parse(ep.base).host,
    path: ep.path,
    paramKeys: params.keys.toList(),
    ok: ok,
    ms: sw.elapsedMilliseconds,
    captured: cap,
    error: err,
  );
}

Future<void> main(List<String> args) async {
  final outDir = args.contains('--out')
      ? args[args.indexOf('--out') + 1]
      : 'docs/api_samples';
  final vip = _loadCreds(_vipPath);
  final nonVip = _loadCreds(_nonVipPath);
  final states = <String, KugouSession>{
    'anonymous': _sessionOf(null),
    if (nonVip.isNotEmpty) 'nonvip': _sessionOf(nonVip),
    if (vip.isNotEmpty) 'vip': _sessionOf(vip),
  };

  final rows = <ProbeRow>[];
  for (final entry in states.entries) {
    final state = entry.key;
    final client = KugouClient(entry.value);
    stdout.writeln('== state=$state ==');

    // 1) 播放 URL（VIP 样曲）——走代码路径 getPlayUrlV5（含 key 计算）
    rows.add(await _run(
      endpoint: 'play_url_v5',
      state: state,
      ep: EndpointRegistry.playUrlV5,
      params: const {'hash': '<vipSongHash>', 'quality': '128'},
      call: () => getPlayUrlV5(client, _vipSongHash, '128'),
      capture: (v) {
        final r = v as PlayResult;
        return <String, Object?>{
          'status': r.status,
          'priv_status': r.privStatus,
          'errcode': r.errcode,
          'urls': r.urls.length,
          'backupUrls': r.backupUrls.length,
          'host': _hostOf(r.urls),
          'extName': r.extName,
          'bitRate': r.bitrate,
          'timeLengthSec': r.timeLengthSec,
          'isFreePart': r.isFreePart,
        };
      },
    ));

    // 2) 泛型只读端点
    Future<void> add<T>(String name, Endpoint ep, List<String> keys,
        Future<T> Function() call, Map<String, Object?> Function(T v) cap) async {
      rows.add(await _run(
        endpoint: name, state: state, ep: ep,
        params: <String, Object?>{for (final k in keys) k: '<value>'},
        call: call,
        capture: (v) => cap(v as T),
      ));
    }

    await add('search_song', EndpointRegistry.searchSong, const ['keyword', 'page', 'pagesize'],
        () => searchSongs(client, '周杰伦', 1, 10),
        (r) => <String, Object?>{
              'total': r.total,
              'items': r.items.length,
              'firstHash': r.items.isEmpty ? null : r.items.first.hash,
              'firstName': r.items.isEmpty ? null : r.items.first.name,
              'firstSinger': r.items.isEmpty ? null : r.items.first.singer,
              'firstMixSongId': r.items.isEmpty ? null : r.items.first.mixSongId,
            });
    await add('search_suggest', EndpointRegistry.searchSuggest, const ['keyword'],
        () => searchSuggest(client, '周杰伦'),
        (r) => <String, Object?>{
              'items': r.length,
              'first': r.isEmpty ? null : r.first.keyword,
            });
    await add('search_hot', EndpointRegistry.searchHot, const [],
        () => searchHot(client),
        (r) => <String, Object?>{'items': r.length, 'first': r.isEmpty ? null : r.first.keyword});
    await add('daily_recommend', EndpointRegistry.recommendSongs, const [],
        () => getDailyRecommend(client),
        (r) => <String, Object?>{'items': r.length, 'firstHash': r.isEmpty ? null : r.first.hash});
    await add('rank_list', EndpointRegistry.rankList, const [],
        () => rankList(client),
        (r) => <String, Object?>{'items': r.length, 'first': r.isEmpty ? null : r.first.toString()});
    await add('user_detail', EndpointRegistry.userDetail, const [],
        () => getUserDetail(client),
        (r) => <String, Object?>{
              'nickname': r.nickname.isEmpty ? null : '<has-nickname>',
              'vipType': r.vipType,
              'avatar': r.avatar.isEmpty ? null : '<has-avatar>',
            });
    await add('favorite_count', EndpointRegistry.favoriteCount, const ['mixsongids'],
        () => getFavoriteCount(client),
        (r) => <String, Object?>{'count': r});
    await add('song_climax', EndpointRegistry.songClimax, const ['hash'],
        () => getSongClimax(client, _vipSongHash),
        (r) => <String, Object?>{'hasResult': r != null && r.isNotEmpty});
    await add('user_cloud', EndpointRegistry.userCloud, const [],
        () => getUserCloud(client),
        (r) => <String, Object?>{'items': r.length});
    await add('fm_play', EndpointRegistry.personalFm, const [],
        () => getFmPlay(client),
        (r) => <String, Object?>{'items': r.length, 'firstHash': r.isEmpty ? null : r.first.hash});
  }

  // 交叉端点：用 VIP 搜索到的 id 继续测评论/MV/专辑（仅 vip 态）
  final vipClient = KugouClient(states['vip']!);
  try {
    final sr = await searchSongs(vipClient, '周杰伦', 1, 1);
    if (sr.items.isNotEmpty) {
      final s = sr.items.first;
      rows.add(await _run(
        endpoint: 'comment_music', state: 'vip',
        ep: EndpointRegistry.commentMusic,
        params: const {'mixsongid': '<id>', 'page': 1},
        call: () => getMusicComments(vipClient, s.mixSongId, 1, pageSize: 10),
        capture: (v) {
          final r = v as dynamic;
          return <String, Object?>{'total': r.total, 'items': (r.items as List).length};
        },
      ));
      rows.add(await _run(
        endpoint: 'comment_count', state: 'vip',
        ep: EndpointRegistry.commentCount,
        params: const {'mixsongid': '<id>', 'hash': '<hash>'},
        call: () => getCommentCount(vipClient, s.mixSongId, fileHash: s.hash),
        capture: (v) => <String, Object?>{'count': v},
      ));
      rows.add(await _run(
        endpoint: 'mv_by_song', state: 'vip',
        ep: EndpointRegistry.mvDetail,
        params: const {'album_audio_id': '<id>'},
        call: () => getMvBySong(vipClient, s.albumAudioId),
        capture: (v) {
          final r = v as dynamic;
          return <String, Object?>{'found': r != null};
        },
      ));
      if (s.albumId.isNotEmpty) {
        rows.add(await _run(
          endpoint: 'album_detail', state: 'vip',
          ep: EndpointRegistry.albumDetail,
          params: const {'album_id': '<id>'},
          call: () => getAlbumDetail(vipClient, s.albumId),
          capture: (v) {
            final r = v as dynamic;
            return <String, Object?>{'name': (r.name as String).isEmpty ? null : '<has-name>'};
          },
        ));
      }
    }
  } catch (e) {
    rows.add(ProbeRow(
      endpoint: 'cross_endpoints', state: 'vip', method: 'GET',
      domain: '-', path: '-', paramKeys: const [], ok: false, ms: 0,
      error: e.toString(),
    ));
  }

  // 落盘（按状态分文件）
  final dir = Directory(outDir)..createSync(recursive: true);
  final byState = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    byState.putIfAbsent(r.state, () => <Map<String, Object?>>[]).add(r.toJson());
    stdout.writeln('${r.state.padRight(10)} ${r.endpoint.padRight(18)} '
        'ok=${r.ok} ${r.ms}ms ${r.ok ? r.captured : r.error}');
  }
  for (final e in byState.entries) {
    File('${dir.path}/${e.key}.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(e.value));
  }
  File('${dir.path}/summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'vipSongHash': _vipSongHash,
    'states': states.keys.toList(),
    'rows': rows.map((r) => r.toJson()).toList(),
  }));
  stdout.writeln('saved ${rows.length} rows → ${dir.path}');
}
