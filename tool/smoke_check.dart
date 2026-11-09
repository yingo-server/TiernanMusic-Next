// smoke_check.dart — 纯 Dart 静态冒烟（不依赖 Flutter SDK，dart run tool/smoke_check.dart）
// 检查项：
//   a) 括号配平：lib/**/*.dart 的 () {} [] 计数配平（字符串/注释内的括号按字符态跳过）
//   b) 禁 import：
//      - core/logic/kernel 层文件出现 'package:flutter/' → 违规（surface 层才许碰 UI SDK；
//        surface/ 目录内文件不算违规）
//      - logic/ 出现任何 'package:flutter' → 违规（logic 层零 UI 依赖）
//      - init/ 出现指向 core/logic/surface 的 import 且非白名单（init/main.dart → surface/app_root.dart）
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

// ---------- b) 禁 import ----------
const _layerFlutterPrefix = 'package:flutter/';

void _checkForbiddenImports(String rel, String src) {
  final re = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
  for (final m in re.allMatches(src)) {
    final imp = m.group(1)!;
    final top = rel.contains('/') ? rel.split('/')[0] : rel;

    // surface/ 目录内的文件允许 package:flutter/
    final inSurfaceDir = rel.startsWith('surface/');
    if (imp.startsWith(_layerFlutterPrefix)) {
      if (top == 'logic') {
        _fail(rel, 'logic 层禁止出现 package:flutter import: $imp');
      } else if ((top == 'core' || top == 'kernel') && !inSurfaceDir) {
        _fail(rel, 'core/kernel 层禁止出现 package:flutter/ import: $imp');
      }
    }

    // init/ 只许 import bootloader 桥与白名单（main → app_root）
    if (top == 'init') {
      final isOwnBridge = imp.contains('/bridges/') || imp.contains('bridge_');
      final whitelist = rel == 'init/main.dart' &&
          (imp.contains('surface/app_root.dart') ||
              imp.contains('app_root.dart'));
      if (!isOwnBridge && !whitelist) {
        final pointsToUpperLayer = RegExp(r'(\.\./)*(core|logic|surface)/')
            .hasMatch(imp);
        if (pointsToUpperLayer) {
          _fail(rel, 'init 层非法跨层 import（仅白名单 main→app_root）：$imp');
        }
      }
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
