
## 6. 【course-correction 追加】阶段性结论汇总（2026-11-18 22:5x）

### 6.1 自己看过的图
- 用户原始照片 `/var/minis/attachments/uploads/photo-1795009516746.jpg`（3456x4608，拍摄时间 2026-11-18 21:45 本地）：底部浅米黄纯色带，无图标文字；排行榜绿卡被截断。
- 自裁 `/var/minis/workspace/bottom_crop.png`、`very_bottom.png`、`just_above_band.png`、`full_small.png`：确认色带完全无图标/文字/迷你条，深色内容被硬切断。
- 真机新抓 `/var/minis/workspace/live.png`（1080x1920，我启动 App 后 screencap）：底部 **y=1728..1919 = 192px = 64dp**（480dpi，3x）纯色 **RGB(182,182,182)**；5000~10000 点采样 uniqueColors=1，完全均匀、无任何图标/文字/分隔线。原照片的“米黄 (180,176,150)”是相机偏色，真值是中性灰 #B6B6B6。
- 对照抓 `/var/minis/workspace/other.png`（其它 App）：底部不是这条纯灰。

### 6.2 逐文件读过的代码（全文）
app_root.dart、shell.dart、design/tokens.dart、design/mini_bar.dart、pages/home_page.dart、session/theme_controller.dart、session/locale_controller.dart、surface/l10n/s.dart、init/main.dart、bridges/bridge_surface.dart、tool/bottom_bar_gate.py、tool/layer_audit.py、tool/smoke_check.dart、test/ui_preview_golden_test.dart、.github/workflows/ci.yml、preview/*、docs/FIX_BOTTOM_BAR_THEME.md。全仓 `rg 'Color\(0xFF' lib/surface` 无 #B6B6B6；`rg SystemChrome|setSystemUIOverlayStyle` 全仓 NONE。

### 6.3 决定性证据：设备根本没装过任何“修复版”
- 设备上 `dumpsys package com.tiernan.music.next.tiernan_music_next`：`versionName=26.11.18.01`、`versionCode=26113801`、`lastUpdateTime=2026-11-18 06:46:56 UTC`（= 本地 14:46），早于所有底栏修复 commit。
- `pm path` 取出设备 APK，`md5sum = c416f80c3995f0df78f554b8937760f9`，与 GitHub release **v26.11.18.01** 的 arm64-v8a APK **字节完全一致**；与 v18.02/03/04 均不同。
- v18.01 对应 commit **d4795bb**（CI run 44123172534）；该版本的 `themeMode: 0 => ThemeMode.system`，`tokens.dart` 用局部常量 `bgElevated` 给 navBar、`context.cs.*` 给页面（分裂），`navH=64`，`shell` 无 backgroundColor、`bottomNavigationBar` 是直接裸 `NavigationBar`。
- 所有所谓修复：41aca04(20:49)、0c5823c(20:54)、cdd2dd3(20:57)、eee8699(20:52)、d6ded99(21:54)、aefe268(22:19)、5b54440(22:28) 全部晚于安装时间。远端最新 release v18.04（asset 21:22 本地）对应 CI run 44311965905 / commit **2bee0eb**，仍早于 d6ded99；hard-lock 那次 CI run 44323132186 **verdict failure**，且 5b54440 未 push（origin/main=aefe268）。本地只有 tag v26.11.10.1。
- 结论：主会话“改了 N 版真机依然如此”的首要真因是 **release/安装脱节：修复从未进 APK**。

### 6.4 渲染层根因（基于打开着的 v18.01 源码 + 真机像素）
那条 64dp 纯灰带既不来自任何 `Color(0xFF...)` 常量，也不是 scheme 角色：全仓无 #B6B6B6，且轻量常量 #F7F8FA/#141519 都对不上。App 全程没有 `SystemChrome.setSystemUIOverlayStyle`，即**从未向 Android 声明导航栏/状态栏样式**。MIUI(Android 9, targetSdk 36) 在未声明时用浅灰 windowBackground 画系统导航区，这条 64dp 满宽系统带盖住/挤掉了 Flutter NavigationBar，造成“图标文字完全不可见、底栏像浅色块”。这就是 Flutter ThemeData / scheme 角色 / navH 80 全部改了也无效的第二层原因。

### 6.5 已落盘修改（未 commit / 未 push）
1. `lib/surface/app_root.dart`：新增 `package:flutter/services.dart` 导入；`_AppRootState.initState` 调 `_applySystemBarStyle()`，`SystemChrome.setSystemUIOverlayStyle` 锁 `systemNavigationBarColor=#0E0F12`、`systemNavigationBarDividerColor`、`systemNavigationBarIconBrightness=light`、`systemNavigationBarContrastEnforced=false`、statusBar 同步深色。
2. `tool/bottom_bar_gate.py`：新增读取 app_root.dart + 4 条系统栏断言（SystemChrome 调用 / systemNavigationBarColor 深色常量 / contrastEnforced=false / 文档第 6 条），防止系统层回归。

### 6.6 验证
`python3 tool/bottom_bar_gate.py` PASS；`python3 tool/layer_audit.py` PASS strict seven-six；`python3 tool/analyze_gate.py` ok；`python3 -m py_compile tool/bottom_bar_gate.py` OK。本地无 dart/flutter，`smoke_check.dart` 未跑（CI 会跑）。

### 6.7 不确定性
- 灰带“系统导航栏覆盖”是高置信推断（颜色/高度/无人机交互/ROM 行为/App 未声明），但没有直接读到此刻 Android NavigationBar 的 color 属性；另一 App 截图底部为深色，说明可能与 App 主题声明相关而非全局 ROM 设置。
- 无论如何，修复同时覆盖两层：Flutter 层已有 _buildBottomBar 硬锁深色（shell/tokens）+ 本轮新增系统层声明；真正生效仍需 **发布包含这些 commit 的新 APK 并让用户升级安装**，否则真机不会变。
