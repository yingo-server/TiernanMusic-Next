// tool/resolve_contract_test.dart · 播放解析编排 + 预读契约自检（纯 Dart，无 flutter）
// 运行：dart run tool/resolve_contract_test.dart
import '../lib/logic/player/play_resolver.dart';
import '../lib/logic/player/prefetch_engine.dart';
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

Map<String, dynamic> okResp(String quality) => <String, dynamic>{
      'status': 1,
      'priv_status': 1,
      'url': <String>['http://cdn/$quality.mp3'],
      'bitRate': quality == 'flac' ? 0 : 320000,
      'extName': quality == 'flac' ? 'flac' : 'mp3',
      'timeLength': 240,
    };

void main() async {
  // 1) VIP 首选档直接成功
  var calls = <String>[];
  var r = await PlayResolver().resolve(
    preferredQuality: 'flac',
    fetch: (q) async {
      calls.add(q);
      return okResp(q);
    },
  );
  eq(r.decision, PlayDecision.play, 'VIP 首选档 → play');
  eq(r.quality, 'flac', 'VIP 命中档 = flac');
  eq(calls.length, 1, 'VIP 只请求 1 次');

  // 2) 匿名 VIP 曲 → needVerify，不降级
  calls = <String>[];
  r = await PlayResolver().resolve(
    preferredQuality: '320',
    fetch: (q) async {
      calls.add(q);
      return <String, dynamic>{'status': 2, 'errcode': 20028};
    },
  );
  eq(r.decision, PlayDecision.needVerify, '匿名VIP曲 → needVerify');
  eq(calls.length, 1, 'needVerify 不降级（只请求 1 次）');

  // 3) 非VIP 对 VIP 曲 → noPrivilege
  r = await PlayResolver().resolve(
    preferredQuality: '320',
    fetch: (q) async => <String, dynamic>{'status': 2, 'priv_status': 0},
  );
  eq(r.decision, PlayDecision.noPrivilege, '非VIP对VIP曲 → noPrivilege');

  // 4) 匿名免费曲（无 priv 键）→ play
  r = await PlayResolver().resolve(
    preferredQuality: '128',
    fetch: (q) async => <String, dynamic>{
      'status': 1,
      'url': <String>['http://cdn/free.mp3'],
    },
  );
  eq(r.decision, PlayDecision.play, '匿名免费曲 → play');
  eq(r.quality, '128', '匿名免费曲档位 = 128');

  // 5) flac 返回 status=1 但无 url → 降级到 320
  calls = <String>[];
  r = await PlayResolver().resolve(
    preferredQuality: 'flac',
    fetch: (q) async {
      calls.add(q);
      if (q == 'flac') {
        return <String, dynamic>{'status': 1, 'priv_status': 1, 'url': <String>[]};
      }
      return okResp(q);
    },
  );
  eq(r.decision, PlayDecision.play, 'flac 无 url → 降级成功');
  eq(r.quality, '320', '降级命中 320');
  eq(calls.join(','), 'flac,320', '尝试顺序 flac→320');

  // 6) 全空 → exhausted
  r = await PlayResolver().resolve(
    preferredQuality: 'flac',
    fetch: (q) async => <String, dynamic>{},
  );
  eq(r.decision, PlayDecision.exhausted, '全空 → exhausted');
  eq(r.attempts, 3, '最多尝试 3 档');

  // 7) fetch 抛异常 → 不崩、继续降级
  calls = <String>[];
  r = await PlayResolver().resolve(
    preferredQuality: 'flac',
    fetch: (q) async {
      calls.add(q);
      if (q == 'flac') throw StateError('boom');
      return okResp(q);
    },
  );
  eq(r.decision, PlayDecision.play, 'fetch 异常 → 继续降级并成功');
  eq(r.quality, '320', '异常后命中 320');

  // ── 预读：上限/去重/窗口 ──
  final engine = PrefetchEngine(maxEnqueuePerCall: 60, maxRequested: 512);
  final hashes = List<String>.generate(100, (i) => 'h$i');
  engine.enqueueHashes(hashes);
  eq(engine.pendingCount, 60, '单次入队上限 60');
  engine.enqueueHashes(hashes);
  eq(engine.pendingCount, 60, '重复入队被去重');

  final more = List<String>.generate(30, (i) => 'n$i');
  engine.updateUpcoming(more, 0, window: 15);
  eq(engine.pendingCount, 75, 'upcoming 窗口 15 插入队头');

  engine.dispose();
  eq(engine.pendingCount, 0, 'dispose 清空队列');
  eq(engine.isDisposed, true, 'dispose 置位');

  print('---- resolve contract self-check: $_pass passed, $_fail failed ----');
  if (_fail > 0) throw StateError('resolve contract FAILED');
}
