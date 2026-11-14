# 批5-C1 · 最终 UI 残留与 app_root 主题统一方案（只读检查）

检查范围：app_root.dart / tn_theme.dart / spotify_tokens.dart / home_shell.dart / mini_bar.dart / player_page.dart / bridge_surface.dart / init/main.dart + 目录级引用扫描（未跑分析器、未改代码）。

## ① 剩余旧设计系统文件清单

当前仓库存在 **两套并行设计系统**：

- **A 系统（Spotify 系，"旧"设计系统，唯一真源自述）**：`lib/surface/ui/` 下
  - spotify_tokens.dart（令牌 + Sp.theme() 工厂，118 行）
  - spotify_states.dart（132 行）、spotify_widgets.dart（367 行）、spotify_ui.dart（15 行）
- **B 系统（M3 系，app_root 实际生效）**：`lib/surface/theme/tn_theme.dart`、`tn_motion.dart`、`dynamic_theme.dart`、`theme_state.dart`、`cover_palette.dart`、`color_extract.dart`、`tn_shader_warmup.dart`；组件层 `lib/surface/widgets/m3/`（m3_skeleton / m3_state_views / m3_section_header）与 `common_m3.dart`。

**直接消费 A 系统（`Sp.*`）的文件（21 个，须迁移）**：
playlist_tracks_sheet.dart、song_actions_sheet.dart、settings_qr_dialog.dart、player_speed_sheet.dart、queue_sheet.dart、storage_diag_page.dart、settings_page.dart、comment_page.dart、lyrics_page.dart、library_header.dart、playlist_page.dart、search_tile_widgets.dart、search_detail_page.dart、search_home_view.dart、album_page.dart、home_page.dart、artist_page.dart、home_detail_sheets.dart、（+ spotify_states/widgets/ui 三件套）。

**注释级残留（非真实 import，无 miuix 依赖）**：app_root.dart:12、settings_page.dart:5、bridge_surface.dart:13、tn_theme.dart:3。

## ② app_root 当前 ThemeData 与 Sp.theme() 的差异

| 维度 | app_root（现生效） | Sp.theme()（**全仓零调用**） |
|---|---|---|
| Material 版本 | useMaterial3: true | useMaterial3: **false** |
| 亮暗 | light + dark + pitchBlack 三态，themeMode 0/1/2/3 | **仅暗色**一套 |
| 主色 | tnPrimary #7FD3E8（可被封面调色板覆盖） | green **#1DB954**（无 palette 概念） |
| 底色/卡片 | #0E0F12 / #1C1D21 / #25272C 分层 | #121212 / #1F1F1F / #2A2A2A |
| 排版 | Typography.material2021()，body 14/16 | 手写 textTheme，条目 15 / 辅助 13 / 标题 28 w900 |
| 导航栏 | NavigationBar height 80、indicator secondaryContainer | height 64、indicator transparent、5 位 64dp |
| 组件主题 | appBar / navigationBar | 另含 listTile / chip / divider / snackBar / progressIndicator |
| 圆角 | 8/12/16（M3 网格） | 8 小圆角 + 胶囊 24 |

**结论**：A 系统（Sp 令牌）被 21 个页面大面积硬编码使用，而其配套的 `Sp.theme()` 从未被调用 —— 结果是"**M3 骨架 + Spotify 硬编码色号**"的混搭渲染（底色 #121212、卡片 #1F1F1F、绿 #1DB954 与 app_root 的 #0E0F12/#1FD3E8 青并存），主题模式/动态取色对页面基本无效。这是当前唯一且最大的 UI 不一致源。

## ③ 最小风险收口方案

原则：**不删功能、不断链、不动启动错误页与两个 provider**。

1. **保底不动**（严禁在此批改）：`theme/theme_state.dart` 的 `themeModeProvider`(0/1/2/3) 与 `theme/dynamic_theme.dart` 的 `dynamicThemeProvider`/palette 覆盖；`init/main.dart` 的 `_BootErrorApp` 启动错误页及 `bridges/bridge_surface.dart` 导出的 `tnLightThemeData`（L1→L6 经桥取主题，禁直连 surface）。
2. **选真源（需拍板，建议 A=Spotify 视觉优先）**：
   - 方案 A（推荐，视觉对齐最彻底）：把 `Sp.theme()` 升格为 app_root 的 `darkTheme`（内部改为 useMaterial3: true 以兼容现有 M3 组件），另补 `Sp.lightTheme()` 作 `theme`，并在 app_root 保留 palette 对 `colorScheme.primary` 的覆盖（动态取色不能丢）。
   - 方案 B（最保守）：保留 tn_theme 为唯一主题源，把 `Sp.theme()` 标注 `@deprecated` + `Sp.*` 颜色逐步改为 `Theme.of(context).colorScheme.*`。
   - 两者共同前置条件：**先消除页面里的硬编码色号**，否则换 theme 无效。
3. **迁移顺序（低风险、可回滚）**：
   - 步骤 1（无视觉变化）：新增 `lib/surface/theme/tn_theme.dart` 的语义别名（如 `tnSurfaceBg`/`tnCard`/`tnAccent`），保留 `Sp` 全部旧名不动。
   - 步骤 2：把 21 个消费文件的硬编码 `Sp.bg/Sp.card/Sp.green/Sp.text...` 换成 `Theme.of(context).colorScheme.*` / `TnText.of(context)`（纯局部替换，逐文件提交，单文件失败可回退）。
   - 步骤 3：切换 app_root 的 theme/darkTheme（唯一一次全局变更点），保留 palette 注入、themeMode switch、try/catch+Log 包裹。
   - 步骤 4：删除 `Sp.theme()` 与已无引用的 `Sp` 常量、`spotify_widgets/states/ui` 中失效部分；同步修正注释中的 miuix 表述。
4. **不得破坏的约束**：surface 层仍只能 import flutter/riverpod/bridge_logic/bridge_core/本层（现状合规：app_root 未 import core/logic）；每函数 try/catch + `Log`；所有改动文件 ≤500 行（现状：app_root 286、player_page 464、spotify_widgets 367，均合规）；零源仓库复用（spotify_* 为独立重写，令牌级常量，复用声明需留档）。
5. **顺手修（可选，低危）**：`home_shell.dart` 的 `FallbackApp` 与 `_ScaffoldMessage` 在崩溃路径下不在 MaterialApp 内，取 `Theme.of(context)` 落回 ThemeData.fallback（亮色），建议包一层 `MaterialApp` 保持与主题一致。

## ④ 必须最后一批改的文件及原因

| 文件 | 为何最后改 |
|---|---|
| `lib/surface/app_root.dart` | 全局主题唯一装配点；必须等页面硬编码色全部迁完再切换 theme/darkTheme，否则一改即大面积视觉回归，且难以二分定位。同时必须保留 themeModeProvider/dynamicThemeProvider 的 watch、palette 覆盖、locale 重建与 try/catch+Log + FallbackApp 兜底。 |
| `lib/surface/ui/spotify_tokens.dart` | 令牌真源；只有 21 个消费文件迁完（Sp 常量引用归零）才能安全删改/合并到 tn_theme，否则编译断裂面最大。 |
| `lib/surface/theme/tn_theme.dart` | 与 spotify_tokens 合并/互为别名时同步；同样需在消费侧迁移完成后进行。 |
| `lib/surface/pages/settings_page.dart` | 同时承载主题模式设置（0/1/2/3 切换 UI）与大量 Sp 引用，改动会同时触碰 provider 语义与视觉；须在 provider 侧稳定后最后动。 |
| `lib/bridges/bridge_surface.dart` + `lib/init/main.dart` | 桥面导出名（tnLightThemeData）一旦变更，init 的启动错误页必须同批改，否则启动失败路径无主题；两文件必须**同批**（L1 不得直连 surface，只能经桥）。 |

**最后一批 = {app_root.dart, spotify_tokens.dart, tn_theme.dart, settings_page.dart, bridge_surface.dart, init/main.dart}**，其余 21 个页面属"倒数第二批"（先行迁移）。

## 风险与遗留
- 迁移期双系统并存属正常；每文件单独提交、单独可回退。
- `Sp.theme()` 零调用意味着它是"事实死代码"，删除前必须确认无 pubspec/测试/脚本引用。
- 未运行分析器、未修改任何代码；本报告为只读结论。
