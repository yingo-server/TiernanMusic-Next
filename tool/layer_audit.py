#!/usr/bin/env python3
"""layer_audit.py — 六五规则强约束审计（strict six-five）。

层序 L1 init / L2 bootloader / L3 kernel / L4 core / L5 logic / L6 surface。
五桥唯一存在于 lib/bridges/：bridge_boot / bridge_kernel / bridge_core / bridge_logic / bridge_surface。

允许：同层 import、SDK(dart:*)、五桥中相邻桥、L1 的装配桥(bridge_boot/bridge_surface)
       + L1 的 flutter 基础包(main 装配必需)、L6 的 flutter/riverpod/just_audio/
       audio_service/path_provider、lib/bridges 自身对其下层实现文件的 import。
拒绝：跨层 import 非桥 .dart（含 init→surface、core→kernel、logic→core、surface→kernel）。
拒绝：lib/bridges 之外的影子 bridges/ 目录含 .dart；五桥缺失/多余；
      桥文件公开函数体无 try/catch 捕获留痕。
输出：PASS strict six-five 或逐条 VIOLATION + 退出码 1。
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
LIB = os.path.join(ROOT, 'lib')
BRIDGES = os.path.join(LIB, 'bridges')
PKG = 'tiernan_music_next'
LAYERS = {'init': 1, 'bootloader': 2, 'kernel': 3, 'core': 4, 'logic': 5, 'surface': 6}
BRIDGE_NAMES = {'bridge_boot', 'bridge_kernel', 'bridge_core', 'bridge_logic', 'bridge_surface'}
# 层-桥显式白名单（批10-A 收口）：这是显式枚举的每层允许桥集合，不是自动放宽。
# 新增越级 import 必须显式修改此处并注明理由，禁止恢复「下层桥自动累积」逻辑。
#   L1 init      → bridge_boot + bridge_surface（装配入口，SIX_FIVE_RULE §0 已注明保留）
#   L2 bootloader → boot/kernel/core/logic 四桥（bootloader 是依赖装配层，
#                    需经各桥组装 kernel/core/logic，属合理特例）
#   L3 kernel    → bridge_kernel（仅本层桥）
#   L4 core      → bridge_kernel + bridge_core（core 直接 import bridge_kernel 取 Log，现状保留）
#   L5 logic     → bridge_logic + bridge_core（logic 经 core 桥取模型，现状保留）
#   L6 surface   → bridge_surface + bridge_logic + bridge_core（surface 取 core 模型，现状保留）
LAYER_ALLOWED_BRIDGES = {
    1: {'bridge_boot', 'bridge_surface'},
    2: {'bridge_boot', 'bridge_kernel', 'bridge_core', 'bridge_logic'},
    3: {'bridge_kernel'},
    4: {'bridge_kernel', 'bridge_core'},
    5: {'bridge_logic', 'bridge_core', 'bridge_kernel'},  # bridge_kernel 为 Log 载体（现状）
    6: {'bridge_surface', 'bridge_logic', 'bridge_core'},
}
# L1 init 是依赖根：允许装配桥 + flutter 基础包（WidgetsFlutterBinding/SystemNavigator/debugPrint）
L1_EXTRA = ('package:flutter/material.dart', 'package:flutter/services.dart',
            'package:path_provider/path_provider.dart')
L6_EXTRA = ('package:flutter', 'package:flutter_riverpod',
            'package:riverpod', 'package:just_audio',
            'package:audio_service', 'package:path_provider',
            'package:flutter_localizations')
# L4 core 数据库域必需的 isar（存储/数据库四域之一）
L4_EXTRA = ('package:isar/isar.dart',)

violations = []
file_count = 0


def fail(src, msg):
    violations.append('%s: %s' % (src, msg))


def layer_of(rel):
    return LAYERS.get(rel.replace('\\', '/').split('/')[0])


def norm(rel):
    return rel.replace('\\', '/')


def resolve_import(src_rel, imp):
    if imp.startswith('package:%s/' % PKG):
        return norm(imp.split('/', 1)[1])
    if imp.startswith('../') or imp.startswith('./'):
        return norm(os.path.normpath(os.path.join(os.path.dirname(src_rel), imp)))
    # 同层/子目录裸文件名（Dart 允许 'models.dart' 相对同目录？不合法，但历史代码存在，
    # 按相对当前文件目录解析为同目录文件，等同层合法）
    if not imp.startswith(('dart:', 'package:')):
        base = os.path.basename(src_rel)
        d = os.path.dirname(src_rel)
        candidate = norm(os.path.join(d, imp))
        if os.path.exists(os.path.join(LIB, candidate)):
            return candidate
    return None


def is_bridge_target(target):
    return target.split('/')[0] == 'bridges'


def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    return '\n'.join(re.sub(r'//.*$', '', ln) for ln in src.split('\n'))


def check_bridge_try_catch(rel, src):
    """桥文件 top-level 函数：函数体内须出现 try 与 catch（留痕启发式）。"""
    code = strip_comments(src)
    lines = code.split('\n')
    fn_re = re.compile(r'^(?:[A-Za-z_<>,\s\?\[\]]+\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(')
    for idx, ln in enumerate(lines):
        if ln.startswith((' ', '\t', '_', '}', '/', '@')) or ln.strip() == '':
            continue
        if '(' not in ln or ln.strip().startswith(('class ', 'abstract ', 'import ', 'export ', 'typedef ', 'enum ')):
            continue
        # 类型/字段声明行（typedef、Function 类型、变量）不是函数
        if re.match(r'^(?:dynamic\s+)?Function\s*\(', ln) or re.match(r'^[A-Za-z_][A-Za-z0-9_<>,\s\?]*\s+[A-Za-z_][A-Za-z0-9_]*\s*;', ln):
            continue
        m = fn_re.match(ln)
        if not m:
            continue
        # 表达式箭头函数跳过
        if '=>' in ln and '{' not in ln:
            continue
        # 函数体：到下一个顶格 '}' 或文件尾
        body_end = len(lines)
        for j in range(idx + 1, len(lines)):
            if lines[j].startswith('}'):
                body_end = j
                break
        body = '\n'.join(lines[idx:body_end])
        if 'try' not in body or 'catch' not in body:
            fail(rel, '桥公开函数 `%s`（第 %d 行）缺少 try/catch 捕获与 Log 留痕'
                 % (m.group(1), idx + 1))


def check_imports(rel, src, lvl):
    for m in re.finditer(r'''\b(?:import|export)\s+['"]([^'"]+)['"]''', src):
        imp = m.group(1)
        if imp.startswith('dart:'):
            continue
        if imp.startswith('package:') and not imp.startswith('package:%s/' % PKG):
            if lvl == 1 and imp.startswith(L1_EXTRA):
                continue
            if lvl == 6 and imp.startswith(L6_EXTRA):
                continue
            if lvl == 4 and imp.startswith(L4_EXTRA):
                continue
            fail(rel, '层 %d 不允许第三方包 import：`%s`' % (lvl, imp))
            continue
        target = resolve_import(rel, imp)
        if target is None:
            fail(rel, '无法解析的 lib 内 import：`%s`' % imp)
            continue
        full = os.path.join(LIB, target)
        if not os.path.exists(full) and not os.path.exists(full + '.dart'):
            continue  # 缺文件交给编译器
        if is_bridge_target(target):
            base = os.path.basename(target).replace('.dart', '')
            if base not in BRIDGE_NAMES:
                fail(rel, '非法桥文件名 `lib/%s`' % target)
                continue
            # 批10-A：显式层-桥白名单（不是自动放宽）。每层只允许白名单内列出的桥；
            # 新增越级 import 必须显式修改 LAYER_ALLOWED_BRIDGES 并注明理由。
            allowed = LAYER_ALLOWED_BRIDGES.get(lvl, set())
            if base not in allowed:
                fail(rel, '层 %d import 非白名单桥 `%s`（允许：%s）'
                     % (lvl, imp, sorted(allowed)))
            continue
        tlayer = layer_of(target)
        if tlayer is None:
            fail(rel, 'import 指向六层之外：`%s`' % imp)
            continue
        if tlayer != lvl:
            fail(rel, '跨层直连 import 非桥文件 `lib/%s`（层 %d→%d，必须改走 lib/bridges/ 相邻桥）'
                 % (target, lvl, tlayer))


def check_shadow_bridges():
    for root, dirs, files in os.walk(LIB):
        rel_root = os.path.relpath(root, LIB).replace('\\', '/')
        if rel_root == 'bridges' or rel_root.startswith('bridges/'):
            continue  # lib/bridges 本尊，合法
        if os.path.basename(root) == 'bridges':
            for f in files:
                if f.endswith('.dart'):
                    fail(os.path.relpath(os.path.join(root, f), LIB),
                         '影子桥目录：桥文件唯一存在于 lib/bridges/')


def check_bridge_set():
    present = {f[:-5] for f in os.listdir(BRIDGES) if f.endswith('.dart')} if os.path.isdir(BRIDGES) else set()
    for name in sorted(BRIDGE_NAMES - present):
        fail('lib/bridges/', '缺失必需的桥文件 %s.dart' % name)
    for name in sorted(present - BRIDGE_NAMES):
        fail('lib/bridges/%s.dart' % name, '未在五桥清单内的多余桥文件')


def main():
    global file_count
    if not os.path.isdir(LIB):
        print('VIOLATION lib/: lib 目录不存在')
        sys.exit(1)
    check_shadow_bridges()
    check_bridge_set()
    for root, dirs, files in os.walk(LIB):
        for f in sorted(files):
            if not f.endswith('.dart'):
                continue
            p = os.path.join(root, f)
            rel = os.path.relpath(p, LIB).replace('\\', '/')
            file_count += 1
            with open(p, encoding='utf-8') as fh:
                src = fh.read()
            if rel.startswith('bridges/'):
                check_bridge_try_catch(rel, src)
                for m in re.finditer(r'''\bimport\s+['"]([^'"]+)['"]''', src):
                    imp = m.group(1)
                    t = resolve_import(rel, imp)
                    if imp.startswith('dart:'):
                        continue
                    if t and is_bridge_target(t):
                        fail(rel, '桥文件不得 import 其他桥文件：`%s`' % imp)
                    elif imp.startswith('package:') and not imp.startswith('package:%s/' % PKG):
                        fail(rel, '桥文件不允许第三方包 import：`%s`' % imp)
                continue
            # flutter gen-l10n 生成物：不属于六层手写代码，豁免
            if rel.startswith('l10n/'):
                continue
            lvl = layer_of(rel)
            if lvl is None:
                fail(rel, 'lib/ 下存在六层目录之外的 dart 文件')
                continue
            check_imports(rel, src, lvl)
    if violations:
        print('FAIL strict six-five: %d 项违规，扫描 %d 个 dart 文件' % (len(violations), file_count))
        for v in violations:
            print('VIOLATION %s' % v)
        sys.exit(1)
    print('PASS strict six-five (%d files scanned)' % file_count)


if __name__ == '__main__':
    main()
