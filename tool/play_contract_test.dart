// tool/play_contract_test.dart · 播放链路契约自检（纯 Dart，无 flutter）
// 目的：钉死 play_url 三态判定与音质降级语义，防止回归。
// 运行：dart run tool/play_contract_test.dart
import '../lib/logic/player/play_source_parser.dart';
import '../lib/logic/player/quality_policy.dart';

int _pass = 0;
int _fail = 0;

void eq(Object? a, Object? b, String name) {
  if (a == b) {
    _pass++;
    print('PASS  $name');
  } else {
    _fail++;
    print('FAIL  $name  (got=$a want=$b)');
  }
}

void main() {
  // ── 三态判定（字段锚点：API_FIELDS_TRUTH §A3-1）──
  // 1) 匿名 + VIP 曲：status=2 + errcode=20028 → needVerify
  eq(
      verdictOf(<String, dynamic>{
        'status': 2,
        'errcode': 20028,
        'error': '本次请求需要验证'
      }),
      PlayVerdict.needVerify,
      '匿名VIP曲 → needVerify(20028)');

  // 2) 非VIP + VIP 曲：status=2 + priv_status=0 → noPrivilege
  eq(
      verdictOf(<String, dynamic>{'status': 2, 'priv_status': 0}),
      PlayVerdict.noPrivilege,
      '非VIP对VIP曲 → noPrivilege');

  // 3) VIP：status=1 + priv_status=1 + url → ok
  eq(
      verdictOf(<String, dynamic>{
        'status': 1,
        'priv_status': 1,
        'url': <String>['http://a/1.mp3']
      }),
      PlayVerdict.ok,
      'VIP → ok');

  // 4) 匿名免费曲：status=1 + url，但**无 priv_status 键** → ok（不得误杀）
  eq(
      verdictOf(<String, dynamic>{
        'status': 1,
        'url': <String>['http://a/free.mp3']
      }),
      PlayVerdict.ok,
      '匿名免费曲(无priv键) → ok');

  // 5) 非 Map / 空 → malformed
  eq(verdictOf(null), PlayVerdict.malformed, 'null → malformed');
  eq(verdictOf(<String, dynamic>{}), PlayVerdict.malformed, '空Map → malformed');

  // ── 解析：顶层结构 + 兼容形态 ──
  final p = parse(<String, dynamic>{
    'status': 1,
    'priv_status': 1,
    'url': <String>['http://a/1.mp3'],
    'backupUrl': 'http://b/1.mp3',
    'bitRate': 320000,
    'extName': 'mp3',
    'timeLength': 245,
    'end_byte': 123456,
    'IsFreePart': 1,
    'tracker_through': <String, dynamic>{'musicpack_advance': 1},
  });
  eq(p.status, 1, 'parse.status');
  eq(p.privStatus, 1, 'parse.privStatus');
  eq(p.urls.length, 1, 'parse.urls 数组');
  eq(p.backupUrls.length, 1, 'parse.backupUrl 单串兼容');
  eq(p.bitRate, 320000, 'parse.bitRate');
  eq(p.extName, 'mp3', 'parse.extName');
  eq(p.timeLengthSec, 245, 'parse.timeLength(秒)');
  eq(p.endByte, 123456, 'parse.end_byte');
  eq(p.isFreePart, true, 'parse.IsFreePart=1 → true');
  eq(p.musicpackAdvance, 1, 'parse.tracker_through.musicpack_advance');
  eq(p.isPlayable, true, 'parse.isPlayable');

  // 数字字符串也要能解析（上游偶发）
  final p2 = parse(<String, dynamic>{'status': '1', 'priv_status': '1', 'url': 'http://a/x.mp3'});
  eq(p2.status, 1, '字符串 status → int');
  eq(p2.urls.length, 1, '字符串 url → 列表');

  // ── 音质降级 ──
  eq(downgradeChain('flac').join(','), 'flac,320,128', '降级链 flac→320→128');
  eq(downgradeChain('unknown').join(','), '320,128', '未知档位 → 安全链');
  eq(nextQuality('flac', 0, 3), '320', 'flac 下一档 → 320');
  eq(nextQuality('320', 0, 3), '128', '320 下一档 → 128');
  eq(nextQuality('128', 0, 3), null, '链尾 → exhausted');
  eq(nextQuality('flac', 3, 3), null, '超次数 → exhausted');

  // 决策：有 url 优先（匿名免费曲 priv 缺失）
  eq(
      decide(const QualityAttempt(
          quality: '320', status: 1, privStatus: 0, hasUrl: true, privKnown: false)),
      PlayDecision.play,
      'decide: 有url+priv未知 → play');
  eq(
      decide(const QualityAttempt(
          quality: '320', status: 1, privStatus: 0, hasUrl: false, privKnown: true)),
      PlayDecision.noPrivilege,
      'decide: priv=0 且无url → noPrivilege');
  eq(
      decide(const QualityAttempt(
          quality: 'flac', status: 2, privStatus: 0, hasUrl: false, privKnown: false)),
      PlayDecision.needVerify,
      'decide: status=2 无url → needVerify');

  print('---- play contract self-check: $_pass passed, $_fail failed ----');
  if (_fail > 0) throw StateError('play contract FAILED');
}
