#!/usr/bin/env python3
"""布局 token 化迁移脚本（一次性）：

1. 删除各页私有布局常量（_pad/_gapS/_gapM/_gapL/_gapXL/_gapXS/_radiusS），
   全部改指 design/layout.dart 的 TnSpace/TnRadius。
2. 裸字面量 → token（按 8dp 体系就近映射）。
3. 断点手写（600/840/1200/1000）→ TnBreakpoint。

映射规则（唯一事实源 = design/layout.dart）：
  4→TnSpace.xs  8→TnSpace.sm  12→TnSpace.md  16→TnSpace.lg
  24→TnSpace.xl 32→TnSpace.xxl 48→TnSpace.xxxl 64→TnSize.miniBar(条高)
  封面占位 40→TnSize.avatarSm 48→TnSize.avatarLg
  圆角 8→TnRadius.sm 12→TnRadius.md 16→TnRadius.lg 28→TnRadius.xl
非体系值（96/120/124/140/176/200/208）→ 就近归一：
  96→96(空态高度，归 TnSize.emptyState) 120→TnSize.songCard 124→TnSize.songCard
  140→TnSpace.xxxl+92? → 归 TnSize.rankCard…（在 layout.dart 增补）
"""
import os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
PAGES = os.path.join(ROOT, 'lib/surface/pages')
SHELL = os.path.join(ROOT, 'lib/surface/shell.dart')

# 私有常量 → token 表达示
CONST_MAP = {
    '_pad': 'TnSpace.lg',
    '_gapXS': 'TnSpace.xs',
    '_gapS': 'TnSpace.sm',
    '_gapM': 'TnSpace.md',
    '_gapL': 'TnSpace.lg',
    '_gapXL': 'TnSpace.xl',
    '_radiusS': 'TnRadius.sm',
}

# 裸值 → token（仅替换 EdgeInsets/SizedBox/Radius 上下文里的数字）
VALUE_MAP = {
    '4': 'TnSpace.xs', '8': 'TnSpace.sm', '12': 'TnSpace.md', '16': 'TnSpace.lg',
    '24': 'TnSpace.xl', '32': 'TnSpace.xxl', '48': 'TnSpace.xxxl',
}

# 语义尺寸（带上下文判断）
SIZE_MAP = {
    '40': 'TnSize.avatarSm',
    '48': 'TnSize.avatarLg',
    '64': 'TnSize.miniBar',
    '120': 'TnSize.songCard',
    '124': 'TnSize.songCard',
    '176': 'TnSize.songRow',
    '96': 'TnSize.emptyState',
    '140': 'TnSize.rankCard',
    '200': 'TnSize.qrCode',
    '208': 'TnSize.qrCode',
}

RADIUS_MAP = {'8': 'TnRadius.sm', '12': 'TnRadius.md', '16': 'TnRadius.lg', '28': 'TnRadius.xl'}

IMPORT_LINE = "import '../design/layout.dart' show TnBreakpoint, TnRadius, TnSize, TnSpace;\n"

def add_import(src, path):
    if 'design/layout.dart' in src:
        return src
    # 插到 design/tokens_v2.dart 的 import 之后（同目录层级）
    for anchor in ("import 'design/tokens_v2.dart';\n",
                   "import '../design/tokens_v2.dart';\n"):
        if anchor in src:
            depth = '../' if '../design/' in anchor else ''
            return src.replace(anchor, anchor + IMPORT_LINE.replace('../design/', depth + 'design/'), 1)
    # 兜底：插在最后一个 import 后
    lines = src.split('\n')
    last = max(i for i, l in enumerate(lines) if l.startswith('import '))
    lines.insert(last + 1, IMPORT_LINE.strip('\n'))
    return '\n'.join(lines)

def convert(path, rel):
    src = open(path, encoding='utf-8').read()
    orig = src

    # 1) 删除私有常量定义行
    src = re.sub(r'^const double _(?:pad|gapXS|gapS|gapM|gapL|gapXL|radiusS) = \d+;\n', '', src, flags=re.M)

    # 2) 私有常量引用 → token
    for k, v in sorted(CONST_MAP.items(), key=lambda kv: -len(kv[0])):
        src = re.sub(r'\b%s\b' % re.escape(k), v, src)

    # 3) BorderRadius/Radius.circular(数字) → TnRadius
    def rrep(m):
        n = m.group(1)
        return 'BorderRadius.circular(%s)' % RADIUS_MAP.get(n, m.group(0) and n)
    src = re.sub(r'BorderRadius\.circular\((\d+)\)', rrep, src)

    # 4) EdgeInsets 数字 → TnSpace（保 0/1/2/3 不动）
    def rep_nums(s):
        def sub(m):
            n = m.group(1)
            return VALUE_MAP.get(n, n)
        return re.sub(r'\b(\d+)\b', sub, s)
    # 只处理 EdgeInsets(...数字...) 整体
    def erep(m):
        inner = m.group(1)
        if re.fullmatch(r'[\s0-9.,:TnSpaceMdXlLgSxXxXl]*', inner) is None and not re.search(r'\b\d+\b', inner):
            return m.group(0)
        inner2 = re.sub(r'\b(\d+)\b', lambda mm: VALUE_MAP.get(mm.group(1), mm.group(1)), inner)
        return m.group(0).replace(inner, inner2)
    src = re.sub(r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(([^()]*)\)', erep, src)

    # 5) SizedBox(height:/width: 数字) → token
    def srep(m):
        key, n = m.group(1), m.group(2)
        tok = VALUE_MAP.get(n) or SIZE_MAP.get(n)
        return 'SizedBox(%s: %s' % (key, tok) if tok else m.group(0)
    src = re.sub(r'SizedBox\(\s*(height|width):\s*(\d+)', srep, src)

    # 6) 容器尺寸 height:/width: 数字（Cover 占位等）
    def drep(m):
        key, n = m.group(1), m.group(2)
        tok = SIZE_MAP.get(n) or VALUE_MAP.get(n)
        return '%s: %s' % (key, tok) if tok else m.group(0)
    src = re.sub(r'(?<!SizedBox\()(\bheight|\bwidth):\s*(\d+)(?![.\w])', drep, src)

    # 7) 断点手写 → TnBreakpoint
    src = re.sub(r'MediaQuery\.sizeOf\((\w+)\)\.width >= 1000', r'TnBreakpoint.isExpanded(MediaQuery.sizeOf(\1).width)', src)
    src = re.sub(r'MediaQuery\.sizeOf\((\w+)\)\.width >= 1240', r'TnBreakpoint.isExpanded(MediaQuery.sizeOf(\1).width)', src)
    src = re.sub(r'MediaQuery\.sizeOf\((\w+)\)\.width >= 600\b', r'!TnBreakpoint.isCompact(MediaQuery.sizeOf(\1).width)', src)

    if src != orig:
        src = add_import(src, path)
        open(path, 'w', encoding='utf-8').write(src)
        return True
    return False

changed = []
for root, _, names in os.walk(PAGES):
    for n in sorted(names):
        if n.endswith('.dart'):
            p = os.path.join(root, n)
            rel = os.path.relpath(p, ROOT)
            if convert(p, rel):
                changed.append(rel)
if convert(SHELL, 'lib/surface/shell.dart'):
    changed.append('lib/surface/shell.dart')

print('converted:', len(changed))
for c in changed:
    print('  ', c)
