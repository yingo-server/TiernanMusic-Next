#!/usr/bin/env python3
"""UI 色彩规范对比度门禁：校验 docs/DESIGN_LANGUAGE.md 的语义 Token 明暗配对与对比度。

规则（§1.6 / §7）：
- 正文 >= 4.5:1
- 大字/图标 >= 3:1
- UI 边界 >= 3:1
- Light/Dark 每个语义 token 必须成对定义
- 深色不得纯黑 #000000，浅色不得纯白 #FFFFFF（canvas 层面）
"""
import re, os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
DOC = os.path.join(ROOT, 'docs/DESIGN_LANGUAGE.md')

if not os.path.exists(DOC):
    print('FAIL ui-contrast-gate: docs/DESIGN_LANGUAGE.md 不存在')
    sys.exit(1)

text = open(DOC, encoding='utf-8').read()

# 解析语义 token 表：| `color.x` | `#RRGGBB` | `#RRGGBB` | 说明 |
PAIRS = {}
row_re = re.compile(r'^\|\s*`((?:color|titlebar)\.[\w.]+)`\s*\|\s*`(#[0-9A-Fa-f]{6})`\s*\|\s*`(#[0-9A-Fa-f]{6})`\s*\|', re.M)
for m in row_re.finditer(text):
    PAIRS[m.group(1)] = (m.group(2).upper(), m.group(3).upper())

def lum(hexcolor):
    r = int(hexcolor[1:3], 16) / 255
    g = int(hexcolor[3:5], 16) / 255
    b = int(hexcolor[5:7], 16) / 255
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    rl, gl, bl = lin(r), lin(g), lin(b)
    return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

errs = []
if len(PAIRS) < 20:
    errs.append(f'语义 token 解析到 {len(PAIRS)} 个（应 >=20），文档格式可能变了')

# 明暗成对（解析本身就是成对，这里校验 Light != Dark 的例外：secondary 允许同值）
ALLOWED_SAME = {'color.secondary', 'color.onSecondary'}

# 对比度校验组合（前景, 背景, 最低要求）
CHECKS = [
    ('color.text.primary', 'color.bg.canvas', 4.5, '正文/画布'),
    ('color.text.primary', 'color.bg.surface', 4.5, '正文/卡片'),
    ('color.text.primary', 'color.bg.container', 4.5, '正文/容器'),
    ('color.text.secondary', 'color.bg.surface', 4.5, '次要文字/卡片'),
    ('color.text.secondary', 'color.bg.canvas', 4.5, '次要文字/画布'),
    ('color.primary', 'color.bg.canvas', 3.0, '主色图标/画布'),
    ('color.primary', 'color.bg.surface', 3.0, '主色图标/卡片'),
    ('color.onPrimary', 'color.primary', 4.5, '主按钮文字'),
    ('color.onSecondary', 'color.secondary', 4.5, '次按钮文字'),
    ('color.outline', 'color.bg.surface', 3.0, '边框/卡片'),
    ('color.outline', 'color.bg.canvas', 3.0, '分割线/画布'),
    ('color.onError', 'color.error', 4.5, '错误按钮文字'),
    ('color.focus', 'color.bg.canvas', 3.0, '焦点环/画布'),
    ('color.focus', 'color.bg.surface', 3.0, '焦点环/卡片'),
    ('color.success', 'color.bg.surface', 3.0, '成功状态/卡片'),
    ('color.warning', 'color.bg.surface', 3.0, '警告状态/卡片'),
    ('color.error', 'color.bg.surface', 3.0, '错误状态/卡片'),
    ('color.info', 'color.bg.surface', 3.0, '信息状态/卡片'),
    ('color.text.disabled', 'color.bg.surface', 1.6, '禁用文字/卡片（下限，仅可读）'),
    ('titlebar.fg', 'titlebar.bg', 4.5, '标题栏文字/标题栏底'),
    ('titlebar.inactive', 'titlebar.bg', 3.0, '失活标题栏/标题栏底'),
    ('titlebar.close.hover', 'titlebar.bg', 3.0, '关闭按钮hover/标题栏底'),
    ('titlebar.button.hover', 'titlebar.bg', 1.2, '按钮hover/标题栏底（下限，仅可辨）'),
]

for idx, board in enumerate(('Light', 'Dark')):
    for fg, bg, need, label in CHECKS:
        if fg not in PAIRS or bg not in PAIRS:
            errs.append(f'{board}: token 缺失 {fg} / {bg}')
            continue
        f = PAIRS[fg][idx]
        b = PAIRS[bg][idx]
        cr = ratio(f, b)
        if cr < need:
            errs.append(f'{board}: {label} 对比 {cr:.2f} < {need} ({fg}={f} on {bg}={b})')

# 深色不得纯黑、浅色不得纯白（画布/surface 层）
if 'color.bg.canvas' in PAIRS:
    if PAIRS['color.bg.canvas'][1] == '#000000':
        errs.append('Dark: bg.canvas 不得为纯黑 #000000')
    if PAIRS['color.bg.canvas'][0] == '#FFFFFF':
        errs.append('Light: bg.canvas 不得为纯白 #FFFFFF')
if 'color.bg.surface' in PAIRS:
    if PAIRS['color.bg.surface'][1] == '#000000':
        errs.append('Dark: bg.surface 不得为纯黑 #000000')

# ── 代码真源一致性 ──────────────────────────────────────────────
# 漏洞修复：门禁原本只读文档，代码里的 token 改了而文档没改 → 门禁永远 PASS
# （文档与代码漂移）。现在从 tokens_v2.dart 解析实际色值，逐个与文档比对。
TOKENS_DART = os.path.join(ROOT, 'lib/surface/design/tokens_v2.dart')
CODE_MAP = {}  # 字段名 -> (light_hex, dark_hex)

def _parse_palette(src, name):
    """解析 TnPalette.<name> = TnPalette(...) 的字段: Color(0xAARRGGBB)"""
    m = re.search(r'static const TnPalette %s = TnPalette\((.*?)\n  \);' % name, src, re.S)
    if not m:
        return None
    out = {}
    for fm in re.finditer(r'(\w+):\s*Color\(0x([0-9A-Fa-f]{8})\)', m.group(1)):
        argb = fm.group(2).upper()
        out[fm.group(1)] = '#' + argb[2:]
    return out

if os.path.exists(TOKENS_DART):
    tsrc = open(TOKENS_DART, encoding='utf-8').read()
    light_code = _parse_palette(tsrc, 'light')
    dark_code = _parse_palette(tsrc, 'dark')
    if not light_code or not dark_code:
        errs.append('无法从 tokens_v2.dart 解析 light/dark 调色板')
    else:
        # 字段名 -> 文档 token 名
        FIELD2DOC = {
            'bgCanvas': 'color.bg.canvas', 'bgSurface': 'color.bg.surface',
            'bgContainer': 'color.bg.container',
            'bgContainerHigh': 'color.bg.containerHigh',
            'primary': 'color.primary', 'onPrimary': 'color.onPrimary',
            'secondary': 'color.secondary', 'onSecondary': 'color.onSecondary',
            'textPrimary': 'color.text.primary',
            'textSecondary': 'color.text.secondary',
            'textDisabled': 'color.text.disabled', 'outline': 'color.outline',
            'divider': 'color.divider', 'focus': 'color.focus',
            'success': 'color.success', 'warning': 'color.warning',
            'error': 'color.error', 'onError': 'color.onError', 'info': 'color.info',
            'titlebarBg': 'titlebar.bg', 'titlebarFg': 'titlebar.fg',
            'titlebarButtonHover': 'titlebar.button.hover',
            'titlebarCloseHover': 'titlebar.close.hover',
            'titlebarInactive': 'titlebar.inactive',
        }
        for field, doc_name in FIELD2DOC.items():
            if doc_name not in PAIRS:
                continue
            for idx, board in enumerate(('Light', 'Dark')):
                code_hex = (light_code if idx == 0 else dark_code).get(field)
                if code_hex is None:
                    continue
                if code_hex.upper() != PAIRS[doc_name][idx]:
                    errs.append(
                        '%s: %s 代码值 %s 与文档 %s 不一致（代码真源漂移）'
                        % (board, doc_name, code_hex, PAIRS[doc_name][idx]))

# ── 错误页主题上下文检查 ─────────────────────────────────────────
# 已知事故：错误页在 MaterialApp 的 build() 里用 Theme.of(context) 取色，
# 拿到的是 MaterialApp 生效前的外层（默认亮色）主题 → 配色割裂。
# 检查 lib/init/main.dart 的错误页不得在 MaterialApp 之外取 Theme.of(context)。
MAIN_DART = os.path.join(ROOT, 'lib/init/main.dart')
if os.path.exists(MAIN_DART):
    msrc = open(MAIN_DART, encoding='utf-8').read()
    # _BootErrorApp 的 build 方法体
    bm = re.search(r'class _BootErrorApp.*?Widget build\(BuildContext context\) \{(.*?)\n  \}\n\}', msrc, re.S)
    if bm:
        body = bm.group(1)
        # 允许：先建 theme 变量再传给 MaterialApp；禁止：直接 Theme.of(context)
        if 'Theme.of(context)' in body and 'final theme =' not in body:
            errs.append(
                'lib/init/main.dart: 错误页在 MaterialApp 之外使用 Theme.of(context)'
                '（拿到外层默认主题，配色割裂）；应先 final theme = spErrorThemeData() '
                '再传给 MaterialApp')
        if 'final theme =' not in body:
            errs.append(
                'lib/init/main.dart: 错误页未显式构造主题（应 final theme = spErrorThemeData()）')

if errs:
    print('FAIL ui-contrast-gate:')
    for e in errs:
        print('  -', e)
    sys.exit(1)
print(f'PASS ui-contrast-gate ({len(PAIRS)} semantic tokens, light/dark pairs, contrast ok, '
      f'code/doc consistent)')
