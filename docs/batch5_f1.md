# 批5-F1 · 最终 app_root 主题收口（最小风险版）

日期：2026-11-14
范围：仅 2 个文件
- `lib/surface/ui/spotify_tokens.dart`
- `lib/surface/app_root.dart`

## 背景（C1 结论）
`Sp.*` 硬编码色被 21 页消费，但 app_root 用的是 `tnThemeWithPalette`（M3），两套主题混搭：
页面用 `Sp.card/Sp.text/Sp.green` 硬色，控件框架色却来自另一套 ThemeData，导致层级/容器色不一致。
本批**不做全套重排**，只做最小对齐：让 app_root 的 theme/darkTheme 与 Sp 同源。

## 改动 1 · spotify_tokens.dart
- `Sp.theme()` 签名由 `theme()` 改为 `theme({ThemePalette? palette, bool pitchBlack = false})`。
  - `ThemePalette` 来自 `../theme/color_extract.dart`（已 file_read 确认定义：`primary/onPrimary/primaryContainer/surface/dark`），
    只 `show ThemePalette`，不形成循环 import（app_root 不被 spotify_tokens 引用）。
  - `Log` 走既有唯一通道 `../../bridges/bridge_logic.dart`（不新增桥、不直连 core/logic 内部）。
- `useMaterial3: false` → `true`：21 页使用 `colorScheme.surfaceContainer*`，M3 下必须可用。
- `ColorScheme.dark(...)` → `ColorScheme.fromSeed(seedColor: Sp.green, brightness: Brightness.dark)`，
  再 `copyWith` 覆盖：
  - `surface = #0E0F12`（原 Sp.bg 为 #121212，按批5-F1 规格取 #0E0F12 为基准面）
  - `surfaceContainerLowest/surfaceContainerLow/surfaceContainer/surfaceContainerHigh/surfaceContainerHighest`
    = 卡片层（`Sp.card` / `Sp.cardHigh`）
  - `primary=Sp.green, onPrimary=black, secondary=Sp.textSub, onSecondary=Sp.text, error=Sp.red`
- `palette` 非空时由 `_applyPalette` 覆盖 `primary/onPrimary/primaryContainer`（surface 族不动，
  避免动态取色把 21 页硬编码底色冲掉）。
- `pitchBlack=true` 时 surface 家族（surface / surfaceContainer* / scaffold / canvas）全覆盖为纯黑。
- 原有 AppBar / NavigationBar / ListTile / Chip / Divider / SnackBar / ProgressIndicator 主题全部保留，
  仅底色来源改为随 surface 家族联动（chip 底色跟随卡片层）。
- 异常兜底：`theme()` 整体 try/catch + `Log.e`，失败回退 `_fallbackTheme()`（静态 M3 深色）；
  `_applyPalette` 单独 try/catch 失败则保留原 colorScheme。

## 改动 2 · app_root.dart
- import 改为 `import 'ui/spotify_tokens.dart' show Sp;`；
  删除 `theme/tn_theme.dart` 的整行 import（`tnThemeWithPalette` / `tnPitchBlackThemeData` /
  `tnPadL` / `tnPadS` / `TnText` 逐项 file_read 复核：本文件内除上述两个 theme 工厂外均未再使用）。
- `_buildMaterialApp`：
  - `theme: Sp.theme(palette: palette)`
  - `darkTheme: Sp.theme(palette: palette, pitchBlack: mode == 3)`
- 保持不变：
  - `themeModeProvider` 的 0/1/2/3 语义（system/light/dark/dark）与 `themeMode` switch 原样。
  - `dynamicThemeProvider` 的 watch、`applyCoverPalette(ref, cover, dark: dark)`、
    `setDark(dark)` 调用序列原样。
  - 启动错误页路径：`_buildMaterialApp` / `build` 的 try/catch → `FallbackApp(message: ...)` 原样；
    `bridge_surface` 的 `tnLightThemeData` 未动。
- 文件行数 286 → 284（≤500）。

## 未触碰（按禁令）
`bridge_surface.dart` / `init/main.dart` / `settings_page.dart` / `tn_theme.dart` / `assembly.dart` /
`home_shell.dart` / 其它 20 页 / `tool/` / `docs/`(除本文件) / CI。

## 已知取舍（诚实标注）
- `Sp.theme()` 是单一深色主题（Spotify 不提供亮色）。app_root 的 light 槽位（mode==1）现在也渲染
  同一套深色主题：这是「与 21 页硬编码 Sp 色一致」的最小风险取舍，彻底的亮色主题化留待后续批次。
- mode==3（纯黑）仅体现在 surface 家族与 scaffold/canvas；页面内 `Sp.card/Sp.cardHigh` 硬编码色
  不随 pitchBlack 变化（改这 21 页超出本批范围）。

## 验证
未跑 analyzer/未构建/未提交（按禁令）。改动仅限上述 2 文件，编译期风险点：
`ColorScheme.copyWith` 的 surfaceContainer* 参数、palette 三色覆盖、`Sp.theme` 新签名调用点唯一（app_root）。
