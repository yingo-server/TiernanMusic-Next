#!/usr/bin/env python3
"""布局数值门禁：页面不得手写间距/尺寸字面量，全部经 design/layout.dart。

规则（用户 2026-11-20 指令："只允许原生控件、间隙等等完全不由你来决定"）：
- lib/surface/pages/** 与 shell.dart / app_root.dart 禁止出现：
  * EdgeInsets.all/symmetric/only/fromLTRB(数字...)      → 用 TnSpace
  * SizedBox(height: 数字 / width: 数字)                  → 用 TnSpace/TnSize
  * height: 数字 / width: 数字（容器尺寸）                → 用 TnSize
  * BorderRadius.circular(数字)                           → 用 TnRadius
- 豁免：
  * design/（token 定义处：layout.dart / tokens_v2.dart）
  * 0 / 1 / 2 / 3（结构性微调，非体系值：divider 宽度等）
  * double.infinity
- 断点判断只允许经 TnBreakpoint（页面不得手写 600/840/1200）。

采用正则启发式 + 白名单豁免（与 ui_no_custom_widgets.py 同风格）。
"""
import os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SCAN_DIRS = [
    os.path.join(ROOT, 'lib/surface/pages'),
    os.path.join(ROOT, 'lib/surface/shell.dart'),
    os.path.join(ROOT, 'lib/surface/app_root.dart'),
    os.path.join(ROOT, 'lib/surface/design/desktop_titlebar.dart'),
]

NUM = r'(?:\d+(?:\.\d+)?)'

# 违规模式（分组1 = 数字串）
PATTERNS = [
    (re.compile(r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(([^)]*\d[^)]*)\)'), 'EdgeInsets 字面量'),
    (re.compile(r'SizedBox\(\s*(?:height|width):\s*(' + NUM + r')'), 'SizedBox 尺寸'),
    (re.compile(r'(?:height|width):\s*(' + NUM + r')(?![.\w])'), '容器尺寸'),
    (re.compile(r'BorderRadius\.circular\(\s*(' + NUM + r')'), '圆角字面量'),
    (re.compile(r'Radius\.circular\(\s*(' + NUM + r')'), '圆角字面量'),
]

ALLOW_INTS = {'0', '1', '2', '3'}
ALLOW_NONINT = set()  # 非整数一律不允许（8dp 体系全是整数）

# 断点手写检查
BREAKPOINT_RE = re.compile(r'(?:maxWidth|minWidth|width)\s*[<>=]+\s*(' + NUM + r')')

def num_ok(nstr):
    try:
        v = float(nstr)
    except ValueError:
        return True
    if v == int(v):
        return str(int(v)) in ALLOW_INTS
    return False

errs = []
files = []
for p in SCAN_DIRS:
    if os.path.isdir(p):
        for root, _, names in os.walk(p):
            for n in names:
                if n.endswith('.dart'):
                    files.append(os.path.join(root, n))
    elif os.path.isfile(p):
        files.append(p)

for path in files:
    rel = os.path.relpath(path, ROOT)
    src = open(path, encoding='utf-8').read()
    # 逐行剥注释
    lines = []
    for ln in src.split('\n'):
        ln = re.sub(r'//.*$', '', ln)
        lines.append(ln)
    code = '\n'.join(lines)

    for m in BREAKPOINT_RE.finditer(code):
        n = m.group(1)
        if n in {'600', '840', '1200'} or num_ok(n) and float(n) in (600.0, 840.0, 1200.0):
            line = code[:m.start()].count('\n') + 1
            errs.append(f'{rel}:{line}: 断点手写 {n}（须经 TnBreakpoint）')
        elif not num_ok(n):
            pass

    for pat, label in PATTERNS:
        for m in pat.finditer(code):
            n = m.group(1)
            # 多值 EdgeInsets：拆开逐个判
            parts = [p.strip() for p in re.split(r'[,:]', n) if p.strip()]
            bad = [p for p in parts if not num_ok(p)]
            if bad:
                line = code[:m.start()].count('\n') + 1
                errs.append(f'{rel}:{line}: {label} {m.group(0)[:60]}（数值 {bad} 非体系值，须经 design/layout.dart）')

if errs:
    print('FAIL ui-layout-gate:')
    for e in errs[:60]:
        print('  -', e)
    if len(errs) > 60:
        print(f'  ... 其余 {len(errs)-60} 条')
    sys.exit(1)
print(f'PASS ui-layout-gate ({len(files)} files, zero raw layout literals)')
