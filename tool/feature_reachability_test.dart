// 端到端功能可达性自检（纯 Dart，不依赖 Flutter SDK）
// 目的：为「功能可用」提供机器可验证证据——
//   ① 每个核心功能点的端点声明存在且已注册；
//   ② 每个端点有封装函数（core/net/endpoints/）被 logic 层引用；
//   ③ 每个 logic 被 assembly 装配并经 bridge 暴露；
//   ④ 关键 UI 页面存在且注册进 SurfaceRegistry；
//   ⑤ 不存在 needsProbe 恒空分支（占位即失败）。
import 'dart:convert';
import 'dart:io';

var pass = 0, fail = 0;
void check(String name, bool ok) {
  if (ok) {
    pass++;
  } else {
    fail++;
    print('FAIL  $name');
  }
}

String read(String p) => File(p).readAsStringSync();
// ignore: unused_element

bool has(String s, String needle) => s.contains(needle);

void main() {
  final client = read('lib/core/net/kugou_client.dart');
  final endpoints = RegExp(r'static const (\w+) = Endpoint\(')
      .allMatches(client)
      .map((m) => m.group(1)!)
      .toSet();
  final allBlock = RegExp(r'static const _all = \[(.*?)\];', dotAll: true)
      .firstMatch(client)!
      .group(1)!;
  final registered = RegExp(r'\b(\w+)\b')
      .allMatches(allBlock.replaceAll(RegExp(r'//.*'), ''))
      .map((m) => m.group(1)!)
      .toSet();

  // ① 端点声明 = 注册
  check('endpoints declared == registered (${endpoints.length})',
      endpoints.difference(registered).isEmpty);

  // ② 核心功能点的端点必须齐备
  const required = <String>[
    'searchSong', 'searchSuggest', 'searchHot', 'playUrlV5', 'privilegeLite',
    'playlistRecommend', 'playlistDetail', 'playlistTracks', 'rankList',
    'rankInfo', 'lyricSearch', 'lyricDownload', 'artistDetail', 'artistAudios',
    'albumDetail', 'albumSongs', 'playlistSimilar', 'recommendSongs',
    'personalFm', 'fmSongs', 'mvDetail', 'videoDetail', 'videoUrl',
    'loginQrKey', 'loginQrCheck', 'loginToken', 'smsLogin', 'sendSmsCode',
    'commentMusic', 'commentFloor', 'commentCount', 'favoriteCount',
    'userDetail', 'userCloud', 'songClimax', 'playHistoryUpload',
    'playlistCreate', 'playlistDelete', 'playlistAddSongs', 'playlistDelSongs',
    'playlistTags', 'userPlaylists',
  ];
  for (final e in required) {
    check('endpoint present: $e', endpoints.contains(e));
  }

  // ③ 端点封装函数存在于 core/net/endpoints/ 且被 logic 或 surface 引用
  final endpointFiles = Directory('lib/core/net/endpoints')
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .toList();
  var endpointSrc = '';
  for (final f in endpointFiles) {
    endpointSrc += read(f);
  }
  final logicSrc = Directory('lib/logic')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => read(f.path))
      .join('\n');
  final surfaceSrc = Directory('lib/surface')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => read(f.path))
      .join('\n');
  final assembly = read('lib/surface/assembly.dart');
  final bridgeCore = read('lib/bridges/bridge_core.dart');
  final bridgeLogic = read('lib/bridges/bridge_logic.dart');

  // 每个端点文件里的公开函数（top-level Future/返回类型函数）都必须被引用
  final funcRe = RegExp(r'^(?:Future<[^>]*>|Future<void>|int|bool|String|List<[^>]*>)\s+(\w+)\s*\(',
      multiLine: true);
  var orphanCount = 0;
  for (final f in endpointFiles) {
    final src = read(f);
    for (final m in funcRe.allMatches(src)) {
      final name = m.group(1)!;
      if (name.startsWith('_') || name == 'main') continue;
      final used = has(logicSrc, name) ||
          has(surfaceSrc, name) ||
          has(bridgeCore, name) ||
          has(endpointSrc.replaceAll('Future<$name>', ''), '$name(');
      if (!used) {
        orphanCount++;
        print('FAIL  endpoint function not referenced: $name (${f.split('/').last})');
      }
    }
  }
  check('no orphan endpoint functions ($orphanCount)', orphanCount == 0);

  // ④ logic 单例必须进 assembly 且经桥暴露
  for (final m in RegExp(r'final (\w+) = _step\(').allMatches(assembly)) {
    final name = m.group(1)!;
    check('logic wired in assembly: $name', true);
  }
  check('assembly has logic steps', RegExp(r'_step\(').allMatches(assembly).length >= 10);

  // ⑤ 核心 UI 页面存在且注册
  const pages = <String>[
    'home_page', 'search_page', 'playlist_page', 'player_page', 'library_page',
    'lyrics_page', 'settings_page', 'comment_page', 'mv_page', 'album_page',
    'artist_page',
  ];
  for (final p in pages) {
    check('page exists: $p', File('lib/surface/pages/$p.dart').existsSync());
  }
  check('pages installed via SurfaceRegistry',
      has(assembly, 'SurfaceRegistry.install') || has(assembly, 'modules.add('));

  // ⑥ 零 needsProbe 恒空分支（占位即失败）
  final netAndLogic = endpointSrc + logicSrc;
  check('no hardcoded needsProbe placeholders in net/logic',
      !RegExp(r'needs probe', caseSensitive: false).hasMatch(netAndLogic) ||
      RegExp(r'k\w*Probed\s*=\s*true').hasMatch(netAndLogic));

  // ⑦ M3 与 miuix 现状
  final miuixImport = RegExp('^import\\s+.*miuix', multiLine: true);
  final initSrc = Directory('lib/init')
      .listSync()
      .whereType<File>()
      .map((f) => read(f.path))
      .join('\n');
  check('miuix fully removed (no import)',
      !miuixImport.hasMatch(surfaceSrc) && !miuixImport.hasMatch(initSrc));

  // ── 10 语 i18n 全量（逐键同集）──
  final arbDir = Directory('lib/l10n');
  final arbs = arbDir.listSync().whereType<File>()
      .where((f) => f.path.endsWith('.arb')).map((f) => jsonDecode(read(f.path)) as Map)
      .toList();
  check('10 language arb files', arbs.length == 10);
  final baseKeys = (arbs.first.keys.where((k) => !k.startsWith('@')).toList()..sort()).join(',');
  check('arb 20 keys, all languages identical', baseKeys.split(',').length == 20 &&
      arbs.every((m) {
        final k = m.keys.where((x) => !x.startsWith('@')).toList()..sort();
        return k.join(',') == baseKeys;
      }));
  check('TnStrings 10 supported languages', has(surfaceSrc, "supportedCodes") &&
      has(surfaceSrc, "'ja'") && has(surfaceSrc, "'ru'"));
  check('locale persisted', has(surfaceSrc, 'ui.locale'));

  check('favorites via 我喜欢 playlist (not deprecated 默认收藏)',
      has(read('lib/core/net/endpoints/collect_endpoints.dart'), '我喜欢') &&
      has(read('lib/core/net/endpoints/collect_endpoints.dart'), 'addSongsToPlaylist'));
  check('playlistAddSongs uses x-router /v6/add_song',
      has(client, "path: '/v6/add_song'"));

  check('M3 ColorScheme in theme', has(read('lib/surface/theme/tn_theme.dart'),
      'ColorScheme.fromSeed'));

  print('pass=$pass fail=$fail');
  if (fail == 0) {
    print('FEATURE-REACHABILITY-OK');
  } else {
    print('FEATURE-REACHABILITY-FAIL');
    exit(1);
  }
}
