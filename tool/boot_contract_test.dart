// 批07-A · 启动契约纯 Dart 自检（不 import flutter，最小桩对象）。
// 覆盖：bridge_boot.BootOutcome.fromAny 的两条路径——
//   1) Map 失败形状（bootFailure / rejected:true）
//   2) 成功对象（duck-typed BootResult 形状的桩类）
// 运行：dart run tool/boot_contract_test.dart （或 dart tool/boot_contract_test.dart）
import 'dart:io';

import '../lib/bridges/bridge_boot.dart' show BootOutcome;

int _passed = 0;
int _failed = 0;

void check(bool cond, String label) {
  if (cond) {
    _passed++;
    stdout.writeln('PASS  $label');
  } else {
    _failed++;
    stdout.writeln('FAIL  $label');
  }
}

/// 最小桩：与 L2 BootResult 同形状的成功对象（不 import L2/flutter）。
class _StubBootResult {
  final bool rejected = false;
  final Object? client = Object();
  final Object? songDao = Object();
  final Object? playlistDao = Object();
  final Object? historyDao = Object();
  final Object? downloadStore = Object();
  final Object? settings = Object();
  final Object? paths = Object();
}

void main() {
  // ── 路径1：Map 失败形状（bootFailure 产物）──
  final failMap = <String, Object?>{
    'rejected': true,
    'kernel': null,
    'error': 'runBootImpl failed',
    'detail': 'runBoot impl not installed (bootloader must register)',
  };
  final o1 = BootOutcome.fromAny(failMap);
  check(o1.rejected, 'fromAny(Map失败形状): rejected=true');
  check(o1.error == 'runBootImpl failed', 'fromAny(Map失败形状): error 透传');
  check(o1.detail.contains('not installed'),
      'fromAny(Map失败形状): detail 透传');
  check(identical(o1.dep('__raw'), failMap), 'fromAny(Map失败形状): __raw 保留原 Map');

  // 缺 error 键的失败 Map → 兜底 'boot failed'。
  final bareMap = <String, Object?>{'rejected': true};
  final o1b = BootOutcome.fromAny(bareMap);
  check(o1b.rejected && o1b.error == 'boot failed',
      'fromAny(缺error失败Map): 兜底 error=boot failed');

  // ── 路径2：成功对象（最小桩）──
  final stub = _StubBootResult();
  final o2 = BootOutcome.fromAny(stub);
  check(!o2.rejected, 'fromAny(成功对象): rejected=false');
  check(o2.error.isEmpty && o2.detail.isEmpty,
      'fromAny(成功对象): error/detail 为空');
  check(identical(o2.dep('client'), stub.client), 'fromAny(成功对象): dep(client) 桩字段');
  check(identical(o2.dep('settings'), stub.settings),
      'fromAny(成功对象): dep(settings) 桩字段');
  check(identical(o2.dep('__raw'), stub), 'fromAny(成功对象): __raw 保留原对象');

  // 幂等：fromAny(BootOutcome) 原样返回。
  check(identical(BootOutcome.fromAny(o2), o2), 'fromAny(BootOutcome): 幂等原样返回');

  stdout.writeln('---- boot contract self-check: '
      '$_passed passed, $_failed failed ----');
  exit(_failed == 0 ? 0 : 1);
}
