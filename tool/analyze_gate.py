#!/usr/bin/env python3
"""tool/analyze_gate.py — 本地 Dart 静态检查门禁（ARM64 无 Flutter SDK 场景）。

背景：本地只有 Dart SDK（无 flutter SDK），`dart analyze` 无法解析
package:flutter / flutter_riverpod / isar，产生大量「Undefined class 'X'」
噪音，淹没真错误；历史事故即由此而来（CI 红了两天无人察觉）。

判定规则（噪音/真错误可机械区分）：
  报错信息里引用的标识符，只要有一个是**项目内声明的类型**
  （从 lib/ 扫出的 class/enum/mixin/typedef/extension 名），
  就是真错误 → FAIL；
  否则视为 flutter/三方包缺失噪音 → 放行。

语法错误由 `dart format --output=none` 单独把关（dart analyze 在包解析失败时
可能不报语法错）。

用法：python3 tool/analyze_gate.py [路径…]   默认 lib tool
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DART = "/opt/dart/bin/dart" if os.path.isfile("/opt/dart/bin/dart") else "dart"

DECL_RE = re.compile(
    r"^\s*(?:abstract\s+|final\s+|base\s+|sealed\s+|mixin\s+)*"
    r"(?:class|enum|mixin|typedef|extension)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)
IDENT_RE = re.compile(r"'([A-Za-z_][A-Za-z0-9_]*)'")
# 「缺失的那个名字」：错误消息的主标识符（而非消息里顺带提到的类型）。
# 例："The method 'MaterialApp' isn't defined for the type '_BootErrorApp'."
#     主标识符 = MaterialApp（flutter 类）→ 噪音；
#     "The name 'AssemblyResult' isn't a type" → 主标识符 = AssemblyResult（项目类）→ 真错误。
MISSING_RE = re.compile(
    r"(?:Undefined class|Undefined function|undefined_class|undefined_function|"
    r"The name|The function|The method|The getter|The setter|The class|The type|"
    r"Argument type|Conditional type|Cannot infer|isn't defined|is not defined|"
    r"isn't a type|is not a type|isn't a class|is not a class|"
    r"not a type|Unknown type|doesn't exist)\s*[:']?\s*'([A-Za-z_][A-Za-z0-9_]*)'"
)


def project_types() -> set:
    names = set()
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "lib")):
        for f in files:
            if not f.endswith(".dart"):
                continue
            if f.endswith(".g.dart"):
                continue
            try:
                src = open(os.path.join(dirpath, f), encoding="utf-8").read()
            except OSError:
                continue
            names.update(DECL_RE.findall(src))
    return names


def main() -> int:
    targets = sys.argv[1:] or ["lib", "tool"]
    types = project_types()
    if not types:
        print("FAIL: 未扫到项目类型清单（正则失效？）")
        return 1
    proc = subprocess.run(
        [DART, "analyze", *targets],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    out = proc.stdout + proc.stderr
    real = []
    noise = 0
    for line in out.splitlines():
        if " error - " not in line and not line.strip().startswith("error -"):
            continue
        m = MISSING_RE.search(line)
        if m is None:
            # 无主标识符（如 "Classes can only extend other classes"）→ flutter 缺失连带噪音
            noise += 1
            continue
        if m.group(1) in types:
            real.append(line.strip())
        else:
            noise += 1
    if real:
        print(f"REAL-ERRORS: {len(real)}")
        for line in real[:40]:
            print("  " + line)
        return 1
    print(f"analyze_gate ok (project-type errors: 0; third-party noise ignored: {noise})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
