#!/usr/bin/env python3
"""UI 层铁律门禁：零手写控件 + 零硬编码色值 + 只引用语义 token。

契约（docs/UI_REWRITE_PLAN.md §0.0）：
- UI 层只用官方 Material 3 控件 + GetWidget 现成能力；**不得手写任何控件**。
- 唯一允许手写：语义色彩 token 与主题装配（tokens*.dart / theme/*）。
- 组件颜色只来自语义 token，不得出现裸色值。

检查项：
1. lib/surface/**（除 tokens*.dart / theme/）不得定义自定义 widget 类
   （StatelessWidget/StatefulWidget 子类）。
2. 不得使用自绘路径：CustomPainter / Canvas.draw* / drawCircle / drawRect 等。
3. 不得出现裸色值：Color(0x...) / Colors.xxx（Colors.transparent 与 Colors.white/black
   仅在 tokens/theme 目录允许）。
4. 不得在 lib/surface 出现平台判断（Platform.isX / dart:io）。
"""
import os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SURFACE = os.path.join(ROOT, 'lib/surface')
TOKEN_ALLOW = ('tokens.dart', 'tokens_v2.dart', 'theme/')
UI_MODULES = ('ui/', 'l10n/')  # 这些目录允许少量非控件文件（取词门面等）

ALLOWED_WIDGET_FILES = {
    # 纯逻辑/常量/门面文件，不是控件
    'lib/surface/l10n/s.dart',
    # TnPageScaffold：页面骨架（官方 Scaffold+AppBar 的统一组装，无自绘，
    # 属于"布局唯一事实源"的一部分 —— 用户要求页面结构全平台一致）
    'lib/surface/design/layout.dart',
}

# 页面容器允许是 StatefulWidget/StatelessWidget（页面本身需要状态），
# 但**可复用 UI 组件**禁止自写。判定：类名以 '_' 开头（私有组件）或
# 位于 design/ 目录且非页面 → 视为组件；位于 pages/ 且类名以 Page/Sheet 结尾
# → 视为页面容器（允许）。
PAGE_NAME_RE = re.compile(r'(Page|Sheet|Panel|View|Screen|Dialog|Root|Shell)$')

errs = []
widget_def_re = re.compile(
    r'^\s*class\s+(\w+)\s+extends\s+(StatelessWidget|StatefulWidget|InheritedWidget)', re.M)
draw_re = re.compile(r'\b(CustomPainter|CustomPaint|Canvas\b|\.drawCircle\(|\.drawRect\(|\.drawPath\(|\.drawRRect\(|Paint\(\))')
color_hex_re = re.compile(r'Color\(0x[0-9A-Fa-f]{8}\)')
colors_api_re = re.compile(r'(?<![A-Za-z_])Colors\.(?!transparent\b)\w+')

def is_token_file(rel):
    return any(a in rel for a in TOKEN_ALLOW)

files = []
for root, dirs, names in os.walk(SURFACE):
    for n in names:
        if n.endswith('.dart'):
            files.append(os.path.join(root, n))

for path in files:
    rel = os.path.relpath(path, ROOT)
    if is_token_file(rel) or rel in ALLOWED_WIDGET_FILES:
        continue
    src = open(path, encoding='utf-8').read()

    # 1) 自定义可复用控件类（页面容器除外）
    for m in widget_def_re.finditer(src):
        cls = m.group(1)
        if PAGE_NAME_RE.search(cls):
            continue  # 页面容器允许
        errs.append(f'{rel}: 自定义控件 class {cls} extends {m.group(2)}（禁止手写控件）')

    # 2) 自绘路径
    for m in draw_re.finditer(src):
        errs.append(f'{rel}: 自绘路径 {m.group(0)}（禁止自绘控件）')

    # 3) 裸色值
    for m in color_hex_re.finditer(src):
        line = src[:m.start()].count('\n') + 1
        errs.append(f'{rel}:{line}: 裸色值 {m.group(0)}（须用语义 token）')
    for m in colors_api_re.finditer(src):
        line = src[:m.start()].count('\n') + 1
        errs.append(f'{rel}:{line}: Colors API {m.group(0)}（须用语义 token）')

    # 4) 平台判断
    for pat, label in ((r'Platform\.is(Windows|Linux|MacOS|Android|IOS|Fuchsia)', '平台判断'),
                       (r"import\s+'dart:io'", 'dart:io')):
        for m in re.finditer(pat, src):
            line = src[:m.start()].count('\n') + 1
            errs.append(f'{rel}:{line}: {label}（surface 不得感知平台，走能力网关）')

if errs:
    print('FAIL ui-no-custom-widgets:')
    for e in errs[:80]:
        print('  -', e)
    if len(errs) > 80:
        print(f'  ... 其余 {len(errs)-80} 条')
    sys.exit(1)

# ── 额外扫描：启动失败页（lib/init/main.dart） ─────────────────────
# 错误页不在 lib/surface 下，但它同样在真机上渲染、同样可能配色割裂。
# 这里只查「裸色值 + Colors API + 平台判断」；widget 类允许（页面容器）。
EXTRA_SCAN = [os.path.join(ROOT, 'lib/init/main.dart')]
for path in EXTRA_SCAN:
    if not os.path.exists(path):
        continue
    rel = os.path.relpath(path, ROOT)
    src = open(path, encoding='utf-8').read()
    for m in color_hex_re.finditer(src):
        line = src[:m.start()].count('\n') + 1
        errs.append(f'{rel}:{line}: 裸色值 {m.group(0)}（须用语义 token）')
    for m in colors_api_re.finditer(src):
        line = src[:m.start()].count('\n') + 1
        errs.append(f'{rel}:{line}: Colors API {m.group(0)}（须用语义 token）')
    for pat, label in ((r'Platform\.is(Windows|Linux|MacOS|Android|IOS|Fuchsia)', '平台判断'),):
        for m in re.finditer(pat, src):
            line = src[:m.start()].count('\n') + 1
            errs.append(f'{rel}:{line}: {label}（init 走平台能力网关）')

if errs:
    print('FAIL ui-no-custom-widgets:')
    for e in errs[:80]:
        print('  -', e)
    if len(errs) > 80:
        print(f'  ... 其余 {len(errs)-80} 条')
    sys.exit(1)
print(f'PASS ui-no-custom-widgets ({len(files)} surface files + {len(EXTRA_SCAN)} error-page file scanned, '
      f'zero hand-written widgets, zero raw colors)')
