# 批1-F1 修改说明 · L6 ThemeController + 主题生效（surface/theme）

## 改动文件（共 5 个，全部在本批白名单内）

1. `lib/session/theme_controller.dart`（新建，约 56 行）
   - `class ThemeController extends ValueNotifier<int>`，私有构造 + `static final instance` 单例。
   - 构造时经 `KeyValueSettings.shared(StoragePaths.I).getInt('ui.themeMode')` 读持久化值（0 系统/1 亮/2 暗/3 纯黑，默认 2，越界回退默认）。
   - `setMode(int)`：范围校验 → 写 value → `setInt` 持久化 → `notifyListeners()`；失败 `Log.w` 留痕。
   - 全方法 try/catch + `Log`（经 bridge_kernel 的 Log）。依赖仅 flutter/foundation + bridge_core + bridge_kernel，符合 L6 白名单（LAYER_ALLOWED_BRIDGES[6] 含 bridge_core）。
   - 持久化键常量 `kThemeModeKey = 'ui.themeMode'`。

2. `lib/bridges/bridge_session.dart`
   - 只追加一行：`export '../session/theme_controller.dart' show ThemeController;`（L7 白名单含 bridge_session，放行）。

3. `lib/surface/app_root.dart`
   - `AppRoot` StatelessWidget → StatefulWidget（`_AppRootState`）。
   - build 用 `ValueListenableBuilder<int>(valueListenable: ThemeController.instance)` 包 MaterialApp。
   - 补齐三参：`theme: Sp.theme(dark: false)`、`darkTheme: Sp.theme(dark: true)`、`themeMode: mode==1 ? light : dark`（mode==3 纯黑暂用暗色板，**TODO：更深色板留批后**；mode 0 系统暂落 dark，后续可接 platform dispatcher——本批不做，见 C2 折中结论）。
   - `installServices` / `bootstrapApp` 签名未动。

4. `lib/surface/pages/settings_page.dart`
   - 删除 L37-38 本地 `int _themeMode = 2` 及注释；删除 L183-184 的 `setState(() => _themeMode = s.first)`。
   - SegmentedButton 外包 `ValueListenableBuilder<int>`（读 ThemeController.instance）；`onSelectionChanged` 改调 `ThemeController.instance.setMode(s.first)`，持久化+全局生效。
   - 导入合并：`bridge_session.dart show appGraph, ThemeController`。

5. `lib/surface/design/tokens.dart`（166 → 184 行，≤500 达标）
   - `static ThemeData theme({bool dark = true})` 抽参；**保留 `ColorScheme.fromSeed` 字符串锚点**（feature_reachability ⑦）。
   - 新增私有亮色常量：`_bgLight=Colors.white`、`_cardLight=#F2F2F2`、`_cardHighLight=#E8EAEE`、`_dividerLight=#DCDFE4`、`_textLight=#111111`、`_textSubLight=#5F646D`、`_textFaintLight=#9AA0AA`、`_bgElevatedLight=#F7F8FA`。
   - 工厂内部按 dark 分流 surface/onSurface/onSurfaceVariant/container 系与 appBar/navBar/listTile/chip/snackBar 文案色；`_text()` 加 `dark` 参数。
   - 深色分支值与原实现完全一致（const 令牌 12 色未动）。
   - 文件头注释写明：**Sp.bg/Sp.card 等 static const 被 8 文件 17 处 const 直引，页面 const 色值动态化留批后，亮色页面视觉允许暂不完美**。

## 未做 / 留批后
- mode==3 纯黑深色板（app_root 标 TODO）。
- mode==0 跟随系统的 platform brightness 监听（本批 themeMode 固定映射）。
- 8 个页面文件 17 处 `Sp.bg/card` const 直引的动态化（C2 §4 折中）。
- layer_audit.py / smoke_check.dart 白名单无需改动（本次未新增桥路径，7→bridge_session、6→bridge_core 均已放行）。

## 验收自检（file_read 回读确认）
- theme_controller.dart：单例 `instance` ✓、持久化键 `ui.themeMode` ✓、setMode 持久化+notify ✓、全方法 try/catch+Log ✓、≤120 行 ✓。
- app_root.dart：StatefulWidget + `darkTheme:` + `themeMode:` ✓、`theme: Sp.theme(dark:false)` ✓、installServices/bootstrapApp 签名不变 ✓。
- settings_page.dart：无 `_themeMode` 本地 state、无该处 setState ✓、经 ThemeController 读写 ✓。
- tokens.dart：`theme({bool dark = true})` ✓、`ColorScheme.fromSeed` 锚点在 ✓、文件头遗留注释 ✓、184 行 ≤500 ✓。
- 同名类查重：`ThemeController` 全仓唯一（仅新建文件定义）。
