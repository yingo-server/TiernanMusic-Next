#!/usr/bin/env python3
"""bottom-bar-gate.py · 底栏不变量门禁（UI 重写后新契约版）

历史教训：
1. b50cbf4 引入 --tree-shake-icons 裁掉 iconFor() 动态映射的导航图标 → tab 全消失。
2. App 未声明系统栏样式时，MIUI 用浅灰 windowBackground 画系统导航区 → 浅色带。
3. 组件主题用局部明/暗常量与实际生效 ColorScheme 分裂 → 底栏浅、内容深。

新契约（docs/UI_REWRITE_PLAN.md §0.0 / docs/DESIGN_LANGUAGE.md）：
- 底栏一律用官方 M3 NavigationBar/NavigationRail，颜色来自 TnPalette 语义
  token（tokens_v2.dart），禁止局部明/暗常量与裸色。
- 系统栏由 app_root 的 TnSystemColors 深色常量声明。
- 构建命令禁止 --tree-shake-icons。
"""
import re, sys, os

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
shell = open(os.path.join(ROOT, 'lib/surface/shell.dart'), encoding='utf-8').read()
tokens_v2 = open(os.path.join(ROOT, 'lib/surface/design/tokens_v2.dart'), encoding='utf-8').read()
app_root = open(os.path.join(ROOT, 'lib/surface/app_root.dart'), encoding='utf-8').read()
errs = []


def check(cond, msg):
    if not cond:
        errs.append(msg)


# 1) 系统栏深色声明（真机浅色带根因；ROM 系统层，ThemeData 无效）
check('SystemChrome.setSystemUIOverlayStyle' in app_root,
      'app_root 未声明系统 UI 样式（系统导航栏可能显示浅灰带）')
check('TnSystemColors' in app_root,
      'app_root 系统栏色未用 TnSystemColors（语义 platform token）')

# 2) 底栏必须是官方 M3 NavigationBar（移动）或 NavigationRail（桌面），
#    且 shell 内不出现裸色常量（底栏颜色全部来自语义 token/scheme）
check('NavigationBar(' in shell or 'NavigationBar(' in tokens_v2,
      'shell 未使用官方 M3 NavigationBar')
for m in re.finditer(r'Color\(0x', shell):
    ctx = shell[max(0, m.start()-60):m.start()+40]
    if 'titlebar' in ctx or 'TnSystemColors' in ctx:
        continue  # 桌面标题栏/系统色是独立 token 域
    errs.append('shell 含裸色常量（底栏颜色必须来自语义 token）: …%s…' % ctx[-50:].replace('\n', ' '))

# 3) shell 必须从 tokens_v2 取主题或从 context.cs 取角色（不得自建局部深/浅常量板）
check('ThemeData(' not in shell,
      'shell 不允许自建 ThemeData（组件主题唯一来源是 tokens_v2 的 TnPalette）')

# 4) tokens_v2 必须提供 NavigationBar/Rail 主题且颜色取自语义 token
check('navigationBarTheme' in tokens_v2,
      'tokens_v2 缺 navigationBarTheme（底栏主题唯一装配点）')
check('navigationRailTheme' in tokens_v2,
      'tokens_v2 缺 navigationRailTheme（桌面导航主题装配点）')
nb = tokens_v2[tokens_v2.find('navigationBarTheme:'):tokens_v2.find('listTileTheme:')]
check(re.search(r'backgroundColor:\s*bg\w+', nb) is not None,
      'navigationBarTheme.backgroundColor 未用语义 token（bg* 字段）')
check(re.search(r'selected(Icon|Label)?\w*Theme?|\bselected\b', nb) is not None,
      'navigationBarTheme 缺选中态配色')

# 5) 构建命令禁止 --tree-shake-icons（裁掉 iconFor 动态图标 → tab 消失）
ci = open(os.path.join(ROOT, '.github/workflows/ci.yml'), encoding='utf-8').read()
check('--tree-shake-icons' not in ci,
      'CI 构建含 --tree-shake-icons：会裁掉 iconFor() 动态引用的导航图标')

if errs:
    print('FAIL bottom-bar-gate:')
    for e in errs:
        print('  -', e)
    sys.exit(1)
print('PASS bottom-bar-gate (M3 nav + semantic tokens + system bars dark + icons kept)')
