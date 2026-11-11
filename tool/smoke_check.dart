// smoke_check.dart — 纯 Dart 静态冒烟（不依赖 Flutter SDK，dart run tool/smoke_check.dart）
// 检查项：
//   a) 括号配平：lib/**/*.dart 的 () {} [] 计数配平（字符串/注释内的括号按字符态跳过）
//   b) 禁 import：
//      - core/logic/kernel 层文件出现 'package:flutter/' → 违规（surface 层才许碰 UI SDK；
//        surface/ 目录内文件不算违规）
//      - logic/ 出现任何 'package:flutter' → 违规（logic 层零 UI 依赖）
//      - 强约束六五规则（与 tool/layer_audit.py 一致）：
//        每层只许 import 同层、SDK(dart:*)、相邻桥（lib/bridges/ 下五桥之一）、
//        L6 额外允许 package:flutter*/miuix/riverpod/just_audio/audio_service/path_provider；
//        跨层 import 非桥 .dart 文件 → VIOLATION（含 init→surface、core→kernel、
//        logic→core、surface→kernel 等一切直连，白名单全部删除）。
//   c) 桥文件唯一性：lib/bridges/*.dart 不得存在影子目录（lib/surface/bridges、
//      lib/core/bridges、lib/logic/bridges 等任何层下名为 bridges 且含 .dart 的目录）
//   d) 输出 PASS/FAIL 汇总；任一违规退出码 1
// 本脚本只读 lib/，不修改任何业务代码。
import 'dart:io';

final _violations = <String>[];

void main() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    _fail(null, 'lib/ 不存在，请在仓库根目录运行');
    _report();
    return;
  }
  final dartFiles = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var checked = 0;
  for (final f in dartFiles) {
    final rel = _rel(f.path);
    final src = f.readAsStringSync();
    checked++;
    _checkBrackets(rel, src);
    _checkForbiddenImports(rel, src);
  }
  _checkBridgeUniqueness(lib);

  // ignore: avoid_print
  print('smoke_check: scanned $checked dart files');
  _report();
}

String _rel(String p) => p.startsWith('lib/') ? p.substring(4) : p;

void _fail(String? file, String msg) =>
    _violations.add(file == null ? msg : '$file: $msg');

// ---------- a) 括号配平 ----------
void _checkBrackets(String rel, String src) {
  // 简易词法态：跳过行注释/块注释/字符串（含原始串与三引号），统计配平。
  var i = 0, n = src.length;
  var line = 1;
  final depth = <String, int>{'(': 0, '[': 0, '{': 0};
  const closer = {')': '(', ']': '[', '}': '{'};
  String? strDelim; // 当前字符串定界符
  var inLineComment = false, inBlockComment = false;
  while (i < n) {
    final c = src[i];
    if (c == '\n') {
      line++;
      inLineComment = false;
      i++;
      continue;
    }
    if (inLineComment) {
      i++;
      continue;
    }
    if (inBlockComment) {
      if (c == '*' && i + 1 < n && src[i + 1] == '/') {
        inBlockComment = false;
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    if (strDelim != null) {
      if (c == r'\') {
        i += 2;
      } else {
        final isTriple = strDelim.length == 3;
        if (src.startsWith(strDelim, i)) {
          strDelim = null;
          i += strDelim == null ? 1 : 1; // consumed below reset
          if (strDelim == null && isTriple) i += 0;
        } else {
          i++;
        }
      }
      continue;
    }
    if (c == '/' && i + 1 < n) {
      if (src[i + 1] == '/') {
        inLineComment = true;
        i += 2;
        continue;
      }
      if (src[i + 1] == '*') {
        inBlockComment = true;
        i += 2;
        continue;
      }
    }
    if (c == "'" || c == '"') {
      final triple = src.startsWith(c * 3, i);
      strDelim = triple ? c * 3 : c;
      i += strDelim.length;
      continue;
    }
    if (c == 'r' && i + 1 < n && (src[i + 1] == "'" || src[i + 1] == '"')) {
      final q = src[i + 1];
      final triple = src.startsWith(q * 3, i + 1);
      strDelim = triple ? q * 3 : q;
      i += 1 + strDelim.length;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth[c] = depth[c]! + 1;
    } else if (closer.containsKey(c)) {
      final open = closer[c]!;
      depth[open] = depth[open]! - 1;
      if (depth[open]! < 0) {
        _fail(rel, '第 $line 行出现多余的 "$c"');
        depth[open] = 0;
      }
    }
    i++;
  }
  for (final e in depth.entries) {
    if (e.value != 0) {
      _fail(rel, '括号未配平："${e.key}" 多出 ${e.value} 个');
    }
  }
}

// ---------- b) 禁 import（强约束六五，与 layer_audit.py 同口径） ----------
const _pkg = 'tiernan_music_next';
const _layers = {'init': 1, 'bootloader': 2, 'kernel': 3, 'core': 4, 'logic': 5, 'surface': 6};
const _bridgeNames = {'bridge_boot', 'bridge_kernel', 'bridge_core', 'bridge_logic', 'bridge_surface'};
// 层-桥显式白名单（批10-A 收口，与 tool/layer_audit.py LAYER_ALLOWED_BRIDGES 同口径）：
// 这是显式枚举的每层允许桥集合，不是自动放宽；新增越级 import 必须显式修改此处并注明理由。
//   L1 init      → bridge_boot + bridge_surface（装配入口，文档已注明保留）
//   L2 bootloader → boot/kernel/core/logic 四桥（依赖装配层，组装 kernel/core/logic 的合理特例）
//   L3 kernel    → bridge_kernel
//   L4 core      → bridge_kernel + bridge_core（core 取 Log，现状）
//   L5 logic     → bridge_logic + bridge_core（logic 经 core 桥取模型，现状）
//   L6 surface   → bridge_surface + bridge_logic + bridge_core（surface 取 core 模型，现状）
const _layerAllowedBridges = <int, Set<String>>{
  1: {'bridge_boot', 'bridge_surface'},
  2: {'bridge_boot', 'bridge_kernel', 'bridge_core', 'bridge_logic'},
  3: {'bridge_kernel'},
  4: {'bridge_kernel', 'bridge_core'},
  5: {'bridge_logic', 'bridge_core', 'bridge_kernel'},
  6: {'bridge_surface', 'bridge_logic', 'bridge_core'},
};
const _l6Extra = [
  'package:flutter', 'package:miuix', 'package:riverpod',
  'package:just_audio', 'package:audio_service', 'package:path_provider',
];

String? _resolveTarget(String rel, String imp) {
  if (imp.startsWith('package:$_pkg/')) return imp.substring('package:$_pkg/'.length);
  if (imp.startsWith('../') || imp.startsWith('./')) {
    final parts = <String>[];
    for (final seg in (rel.split('/')..removeLast()..addAll(imp.split('/')))) {
      if (seg == '.' || seg.isEmpty) continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }
  // 同目录裸文件名 import（如 'models.dart'）→ 解析为同目录文件
  if (!imp.startsWith('package:')) {
    final d = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
    return d.isEmpty ? imp : '$d/$imp';
  }
  return null;
}

void _checkForbiddenImports(String rel, String src) {
  if (rel == 'bridges' || rel.startsWith('bridges/')) return; // 五桥本尊，合法
  if (rel.startsWith('l10n/')) return; // flutter gen-l10n 生成物，豁免
  final re = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
  final top = rel.contains('/') ? rel.split('/')[0] : rel;
  final lvl = _layers[top];
  if (lvl == null) {
    _fail(rel, 'lib/ 下存在六层目录之外的 dart 文件');
  }
  for (final m in re.allMatches(src)) {
    final imp = m.group(1)!;
    if (imp.startsWith('dart:')) continue;

    if (!imp.startsWith('package:')) {
      // 相对路径 import：解析目标并判层
      final t = _resolveTarget(rel, imp);
      if (t == null) {
        _fail(rel, '无法解析的 import：$imp');
        continue;
      }
      final tTop = t.contains('/') ? t.split('/')[0] : t;
      if (tTop == 'bridges') {
        final base = t.split('/').last.replaceAll('.dart', '');
        if (!_bridgeNames.contains(base)) {
          _fail(rel, '非法桥文件名 $imp（五桥固定名）');
        } else if (lvl != null) {
          // 批10-A：显式层-桥白名单（同 layer_audit.py），非自动放宽。
          final allowed = _layerAllowedBridges[lvl] ?? const <String>{};
          if (!allowed.contains(base)) {
            _fail(rel, '层 $lvl import 了非白名单桥 $imp（允许：${allowed.toList()..sort()}）');
          }
        }
        continue;
      }
      final tLayer = _layers[tTop];
      if (tLayer == null) {
        _fail(rel, 'import 非六层目录内文件：$imp');
      } else if (lvl != null && tLayer != lvl) {
        _fail(rel, '跨层直连 import 非桥文件 $imp（层 $lvl → 层 $tLayer，须改走相邻桥）');
      }
      continue;
    }

    // package: import
    if (imp.startsWith('package:$_pkg/')) {
      final t = imp.substring('package:$_pkg/'.length);
      final tTop = t.split('/')[0];
      final tLayer = _layers[tTop];
      if (tTop == 'bridges') {
        final base = t.split('/').last.replaceAll('.dart', '');
        if (!_bridgeNames.contains(base)) {
          _fail(rel, '非法桥文件名 $imp（五桥固定名）');
        } else if (lvl != null) {
          // 批10-A：显式层-桥白名单（同 layer_audit.py），非自动放宽。
          final allowed = _layerAllowedBridges[lvl] ?? const <String>{};
          if (!allowed.contains(base)) {
            _fail(rel, '层 $lvl import 了非白名单桥 $imp（允许：${allowed.toList()..sort()}）');
          }
        }
      } else if (tLayer == null) {
        _fail(rel, 'import 非六层目录内文件：$imp');
      } else if (lvl != null && tLayer != lvl) {
        _fail(rel, '跨层直连 import 非桥文件 $imp（层 $lvl → 层 $tLayer，须改走相邻桥）');
      }
      continue;
    }

    // 第三方包：L6 白名单 + L1 装配基础包 + L4 isar
    const l1Extra = ['package:flutter/material.dart',
        'package:flutter/services.dart', 'package:path_provider/path_provider.dart'];
    const l4Extra = ['package:isar/isar.dart'];
    final allowed = (lvl == 6 && _l6Extra.any((p) => imp.startsWith(p))) ||
        (lvl == 1 && l1Extra.any((p) => imp.startsWith(p))) ||
        (lvl == 4 && l4Extra.any((p) => imp.startsWith(p)));
    if (!allowed) {
      _fail(rel, '层 ${lvl ?? '?'} 禁止第三方包 import：$imp'
          '（L6 UI 包 / L1 装配基础包 / L4 isar 之外的第三方包禁止）');
    }
  }
}

// ---------- c) 桥文件唯一性 ----------
void _checkBridgeUniqueness(Directory lib) {
  final canonical = <String>{};
  final bdir = Directory('${lib.path}/bridges');
  if (bdir.existsSync()) {
    for (final f in bdir.listSync()) {
      if (f is File && f.path.endsWith('.dart')) canonical.add(_base(f.path));
    }
  }
  for (final e in lib.listSync(recursive: true)) {
    if (e is! Directory) continue;
    final rel = _rel(e.path);
    // 影子目录：任何层（非 lib/bridges 本尊）下的 bridges/ 目录
    if (rel == 'bridges' || rel.startsWith('bridges/')) continue;
    final parts = rel.split('/');
    if (parts.isNotEmpty && parts.last == 'bridges') {
      for (final f in e.listSync()) {
        if (f is File && f.path.endsWith('.dart')) {
          _fail(_rel(f.path), '桥文件影子目录：桥只允许存在于 lib/bridges/');
        }
      }
    }
  }
  if (canonical.isEmpty) {
    _fail(null, 'lib/bridges/ 为空：五桥架构要求至少存在桥文件');
  }
}

String _base(String p) => p.split('/').last;

// ---------- d) 汇总 ----------
void _report() {
  if (_violations.isEmpty) {
    // ignore: avoid_print
    print('PASS smoke_check: 括号配平 / 禁 import / 桥唯一性 全部通过');
    return;
  }
  // ignore: avoid_print
  print('FAIL smoke_check: ${_violations.length} 项违规');
  for (final v in _violations) {
    // ignore: avoid_print
    print('VIOLATION $v');
  }
  exitCode = 1;
}
