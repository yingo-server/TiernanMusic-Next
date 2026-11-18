#!/usr/bin/env python3
"""bottom-bar-gate.py · 底栏深色硬锁门禁（真机浅色块回归后新增）

历史教训：底栏曾被渲染成米黄/浅灰块吞掉图标文字，静态 scheme 推导与
"CI 全绿"都没抓到。本门禁从源码层面锁死以下不变量，防止回归：
  1. shell 的 bottomNavigationBar 必须走 _buildBottomBar（局部硬锁深色 Theme）
  2. shell 外壳 Scaffold 背景必须是硬编码深色常量（不依赖 ColorScheme）
  3. _buildBottomBar 内 navigationBarTheme.backgroundColor 必须是 const darkBar
  4. _buildBottomBar 内 NavigationBar 的 indicator/label/icon 必须可读（深色底+亮字）
  5. tokens.dart 的 navigationBarTheme 必须来自 scheme（供其它屏幕用，不能再用局部明/暗常量）
  6. app_root 必须显式声明系统导航栏深色（真机浅灰/米黄带根因；ROM 系统层，
     Flutter ThemeData 改色无效）
任一不满足 -> FAIL（退出码 1）。
"""
import re, sys, os
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
shell = open(os.path.join(ROOT, 'lib/surface/shell.dart'), encoding='utf-8').read()
tokens = open(os.path.join(ROOT, 'lib/surface/design/tokens.dart'), encoding='utf-8').read()
app_root = open(os.path.join(ROOT, 'lib/surface/app_root.dart'), encoding='utf-8').read()
errs = []

def check(cond, msg):
    if not cond:
        errs.append(msg)

# 0) 【真机浅灰/米黄带根因门禁】App 必须显式声明 Android 系统导航栏深色。
#    未声明时 MIUI/ROM 用浅灰 windowBackground 画系统导航区（真机 RGB≈182），
#    盖住 Flutter NavigationBar。这是 Flutter ThemeData 改色无法覆盖的一层。
check('SystemChrome.setSystemUIOverlayStyle' in app_root,
      'app_root 未声明系统 UI 样式（系统导航栏可能显示浅灰带）')
check('systemNavigationBarColor' in app_root,
      'app_root 未设置 systemNavigationBarColor（真机浅色带根因）')
check(re.search(r'systemNavigationBarColor:\s*(?:const\s+)?Color\(0xFF0[0-9A-Fa-f]{5}\)', app_root) is not None,
      'systemNavigationBarColor 不是深色常量')
check('systemNavigationBarContrastEnforced: false' in app_root,
      '未关闭 systemNavigationBarContrastEnforced（ROM 可能强制加浅色遮罩）')

# 1) bottomNavigationBar 走 _buildBottomBar
check('bottomNavigationBar: _buildBottomBar(' in shell,
      'shell bottomNavigationBar 未走 _buildBottomBar（硬锁深色）')
# 2) 外壳 Scaffold 背景硬编码深色
check(re.search(r'backgroundColor:\s*const\s+Color\(0xFF0[0-9A-Fa-f]{5}\)', shell) is not None,
      'shell Scaffold 背景不是硬编码深色常量')
# 3) _buildBottomBar 存在且背景锁 darkBar
check('Widget _buildBottomBar(' in shell,
      '缺少 _buildBottomBar 方法')
m = re.search(r'Widget _buildBottomBar\(.*?\n  \}', shell, re.S)
if m:
    body = m.group(0)
    check('const darkBar = Color(0xFF' in body,
          '_buildBottomBar 缺少 const darkBar')
    check('navigationBarTheme: NavigationBarThemeData(' in body,
          '_buildBottomBar 缺少 navigationBarTheme')
    check(re.search(r'backgroundColor:\s*darkBar', body) is not None,
          '_buildBottomBar 的 navigationBarTheme.backgroundColor 未锁 darkBar')
    check('brightness: Brightness.dark' in body,
          '_buildBottomBar 未强制 Brightness.dark')
    check('WidgetStateProperty.resolveWith' in body and 'barText' in body,
          '_buildBottomBar 的 label/icon 未按选中态设置可读文字色')
else:
    errs.append('_buildBottomBar 方法体无法解析')

# 4) tokens navigationBarTheme 来自 scheme，无局部明/暗常量
m2 = re.search(r'navigationBarTheme:\s*NavigationBarThemeData\((.*?)\),\s*listTileTheme', tokens, re.S)
if m2:
    nb = m2.group(1)
    check('backgroundColor: scheme.' in nb,
          'tokens navigationBarTheme.backgroundColor 未取 scheme')
    check(not re.search(r'backgroundColor:\s*(bg|bgElevated|_bg)', nb),
          'tokens navigationBarTheme 用了局部明/暗常量')
else:
    errs.append('tokens navigationBarTheme 无法解析')

if errs:
    print('FAIL bottom-bar-gate:')
    for e in errs:
        print('  -', e)
    sys.exit(1)
print('PASS bottom-bar-gate (dark bottom nav hard-locked, no light-block regression)')
