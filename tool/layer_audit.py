#!/usr/bin/env python3
"""层审计：六层五桥架构，跨层 import 即 VIOLATION。
层序（低→高）：init(1) bootloader(2) kernel(3) core(4) logic(5) surface(6)
规则：每层只许 import 严格更低层 + 本层 + 自己层的桥出口文件。
桥文件位于 lib/bridges/，每个桥归属其上层（如 bridge_surface.dart 属 surface 可用）。
"""
import os, re, sys

LIB = os.path.join(os.path.dirname(__file__), '..', 'lib')
LAYERS = {'init': 1, 'bootloader': 2, 'kernel': 3, 'core': 4, 'logic': 5, 'surface': 6}
# 桥 → 允许使用它的最低层（上层可用，低层禁用）
BRIDGE_ALLOW = {'bridge_surface': 6, 'bridge_logic': 6, 'bridge_core': 4,
                'bridge_kernel': 3, 'bridge_boot': 2}

def layer_of(path):
    rel = os.path.relpath(path, LIB)
    top = rel.split(os.sep)[0]
    if top in LAYERS:
        return LAYERS[top]
    if 'bridge' in os.path.basename(path):
        return 99  # bridges 目录，任何层不得 import 除非声明
    return None

violations = []
for root, _, files in os.walk(LIB):
    for f in files:
        if not f.endswith('.dart'):
            continue
        p = os.path.join(root, f)
        src = os.path.relpath(p, LIB)
        lvl = layer_of(p)
        if lvl is None:
            continue
        for m in re.finditer(r"import\s+'([^']+)'", open(p, encoding='utf-8').read()):
            imp = m.group(1)
            if not imp.startswith('../') and not imp.startswith('package:tiernan_music_next/'):
                continue
            target = imp.replace('package:tiernan_music_next/', '')
            target = os.path.normpath(os.path.join(os.path.dirname(src), target))
            tl = layer_of(os.path.join(LIB, target))
            if tl is None:
                continue
            base = os.path.basename(target)
            if base.startswith('bridge'):
                allowed = next((v for k, v in BRIDGE_ALLOW.items() if base.startswith(k)), None)
                if allowed is not None and lvl > allowed:
                    violations.append(f'{src}: layer {lvl} uses {imp} (needs >= {allowed})')
                continue
            if tl >= lvl:
                violations.append(f'{src}: layer {lvl} imports same/higher layer {imp}')

if violations:
    for v in violations:
        print('VIOLATION', v)
    sys.exit(1)
print('layer audit ok')
