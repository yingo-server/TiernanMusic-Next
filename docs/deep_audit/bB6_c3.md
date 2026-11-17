# B6 批 · C3 用户痛点专项 · UI / M3 / 主题 / 动画 / 动态取色 跨层复评

> 审查时间戳起：2026-11-17 08:49 LCL（Asia/Shanghai）
> 视角：阶段 B6 · C3（用户痛点主战场）
> 纪律：只读（file_read + shell ls/rg/wc）；唯一写＝本文件 append。
> 基线对照：阶段 A `docs/deep_audit/bA7_c3.md` MD3 = **40/100 fail**；`M3_BASELINE.md`；`PHASE_A_FIX_LOG.md`（P1-7 motion 令牌、P1-8 tonal pairing）。

---

## 审查进行中（逐条 append，带时间戳）

### [08:49] 基线确认：阶段 A 的 motion 令牌与 tonal pairing 确实写进了 tokens.dart
- `design/tokens.dart:67-75`：新增 `Sp.fast=200/normal=300/enter=400/screen=500ms` 四档 + `curve/standard/emphasized/decelerate/accelerate` 五个曲线常量。对齐 MD3 Standard(300)/Emphasized(400/500) 数值档。
- `design/tokens.dart:88-99`：`ColorScheme.fromSeed(seed:green).copyWith(...)` 补了 `primaryContainer=greenDim / onPrimaryContainer=text / onError=Colors.white`，并 copyWith 了五级 surfaceContainer。
- **但**：tokens.dart 文件头注释自承「Sp.bg/card 等仍为 static const，被 8 个文件 17 处 const 引用；页面 const 色值动态化留批后」。→ 阶段 A 修复是否生效，取决于页面是否消费这些令牌。下面开始量化核验。

### [08:52] 【核心证据】阶段 A 的 motion / tonal pairing 修复在页面层几乎零消费
**Motion 令牌消费**：全 surface 仅 **1 处** 页面消费 —— `pages/lyrics_page.dart:159` `_scroll.animateTo(target, duration: Sp.normal, curve: Sp.curve)`。新增的 `enter/screen/fast/standard/emphasized/decelerate/accelerate` **7 个令牌在 tokens.dart 之外零调用**（rg 全 surface 命中仅定义处 + 这 1 行）。→ 阶段 A P1-7「补 MD3 六档」停留在定义层，页面过渡动画没有一档在用。
**硬编码时长仍在**：`lyrics_page.dart:55` Timer.periodic 200ms、`login_sheet.dart:187` 1500ms（轮询，非过渡，但也不走令牌）。
**ColorScheme 消费**：`Theme.of(context).colorScheme` / `.primaryContainer` / `.onPrimaryContainer` / `.onError` / `.surfaceContainer*` 在**页面层 0 命中**；rg 全 surface 仅 2 处，都在主题构造内部（tokens.dart:110 `colorScheme: scheme`、tn_theme.dart:10）。→ 阶段 A P1-8 补的 `onPrimaryContainer/onError` 是**死令牌**，没有任何 widget 消费。
**Sp.* 静态色仍大面积绕过**：全 surface **195 处** Sp 色引用（16 文件；tokens.dart 定义处 11 处，页面/design 约 184 处）。按文件：playlist 30 / search 25 / player 23 / settings 18 / home 14 / library 13 / mv 12 / search_tile 9 / components 9 / login_account 8 / lyrics 6 / login_sheet 6 / ykg_sheet 4 / home_state_views 4 / mini_bar 3。→ 与阶段 A「主题数据建了但 UI 用 Sp.* 架空」结论一致，**本轮未改善**。

### [08:55] 【动态取色/主题切换】四档主题映射塌缩为两态，纯黑档是空壳，跟随系统失效
- 设置页 `settings_page.dart:209-220` 提供 4 个 segment：跟随系统(0)/亮(1)/暗(2)/纯黑(3)，`onSelectionChanged` → `ThemeController.setMode`（L6，持久化 `ui.themeMode`，即时 notifyListeners）。
- 但 `app_root.dart:63-68` 映射：
  ```
  // 0 系统 / 1 亮 / 2 暗 / 3 纯黑（纯黑暂用暗色板，TODO 更深色板）。
  themeMode: switch (mode) { 1 => ThemeMode.light, _ => ThemeMode.dark }
  ```
  → **mode 0「跟随系统」被强制成 ThemeMode.dark**，完全没读 `MediaQuery.platformBrightness`/`ThemeMode.system`：在系统亮色下选「跟随系统」仍是暗色，功能名实不符。
  → **mode 3「纯黑」与 mode 2「暗」落到完全相同的 ThemeMode.dark + 同一份 `Sp.theme(dark:true)`**（`scaffoldBackgroundColor=Sp.bg=#0E0F12` 非纯黑 #000000）。用户切「纯黑」**无任何视觉变化**——与 A7 发现「0/3 映射 TODO」一致，阶段 A 未修。
- 切换即时性：`ValueListenableBuilder` 包 `MaterialApp`，`setMode` 即时 notify → rebuild 即时；切换机制本身 OK，**坏在下游只有 2 种视觉结果**。
- **动态取色链 100% 断**：`core/algorithms/color_extract.dart:9-14` 文件头自承「extractDominant / fromSeed 当前版本未被任何 UI 消费方调用（原 cover_color_bridge.dart 已删除）」。`rg` 全 lib：`extractDominant`/`fromSeed`/`ThemePalette` 仅定义在 color_extract.dart，**零调用方**。L4→L6→L7 取色链彻底不存在，动态取色体验为零。seed 还落在品牌绿 #1DB954（tokens）与 fallback 品牌紫 #7C4DFF（color_extract）两套，彼此不一致。

### [08:58] 【动画细节】逐页核查：无过渡动画体系，只有业务轮询 + 两处 AnimatedBuilder + 一处 animateTo
全 surface 动画构造清点（rg）：
1. `mini_bar.dart:21` `AnimatedBuilder(animation: session)` — **监听整个 PlaybackSession**，任一快照字段变化（含播放进度 positionMs 高频 tick）都重建迷你条整条 Row。无 child 复用、无 RepaintBoundary。
2. `player_page.dart:313` `AnimatedBuilder(animation: session)` — **包住整屏 body**（TopBar + ListView + 280px 封面 + 全部控件）；播放进度每 tick 通知 → 整页 Column/ListView 重建。典型 rebuild 风暴，用户「不经看」的卡顿来源之一。
3. `settings_page.dart:156` `AnimatedBuilder` — 需单独看动画对象。
4. `lyrics_page.dart:159` `_scroll.animateTo(target, duration: Sp.normal(300ms), curve: Sp.curve(easeOutCubic))` — 全 App **唯一**使用 MD3 令牌的过渡；曲线 `Sp.curve=easeOutCubic` 与 MD3 emphasized decelerate `cubic-bezier(0.05,0.7,0.1,1)` 只是近似，非精确令牌。
5. **零** AnimatedContainer / AnimatedOpacity / AnimatedSwitcher / Hero / SlideTransition / FadeTransition / 页面转场自定义 / shared-axis / shape morphing / spring。页面切换走默认 `MaterialPageRoute`（`shell.dart:141`），无统一入场/退场曲线。
6. **业务轮询被误当动画**：`lyrics_page.dart:55` 200ms Timer 逐行定位、`login_sheet.dart:186` 1500ms QR 轮询、`:331` 1s 倒计时。这些是定时器，不是过渡动画；但 QR 状态切换（waitScan→waitConfirm→expired）、歌词切行高亮**全部瞬时跳变无缓动**。
7. 中断/重复触发治理：
   - `lyrics_page` 切歌时 `_tick` 内 `_load()`（`lyrics_page.dart:129`），200ms 周期可能重复触发 `_load`，虽有 `song.hash==_hash && _rows.isNotEmpty` 早退，但加载中 `_hash` 已更新、`_rows` 仍空 → 重复并发 `lyricsFor`（**重复触发瑕疵**）。
   - `login_sheet` `_timer` 复用同一字段承载 QR/倒计时两种 Timer，切换场景 cancel 有覆盖（`login_sheet.dart:186/331`），尚可。
   - `mini_bar`/`player_page` AnimatedBuilder **无动画中断/去抖**，高频通知下无节流。
- 对照 MD3 motion 六档：令牌定义了 4 档时长+5 曲线（数值档对），但**实际过渡动画只有 1 处**用 lowest 档；六档体系形同虚设。用户「动画也是、细节瑕疵、不经看」↔ 代码实证吻合。

### [09:01] 【文案接线】本批范围内 surface 硬编码中文总量（复用 A7 统计 + 本批 rg 复核）
- rg 复核（含注释，scope 内 6 文件 + 12 页面/弹层）：**213 处中文串命中**；A7 记为「约 212 命中 / 119 处去重文案」，一致。按文件（本批口径）：login_sheet 32 / settings 29 / home 27 / player 24 / search 22 / mv 21 / playlist 19 / library 17 / lyrics 7 / search_tile 4 / login_account 4 / mini_bar 3 / shell 2 / home_state_views 1 / components 1。
- i18n 接线：阶段 A 已复活 `S.of(context).t` 门面（`lib/surface/l10n/s.dart`），但全 surface 仅 **20 处** S.of 调用，**全部集中在新代码**：ykg_sheet（~17）、login_sheet 新增 YKG Tab（5）、player_page 新写收藏/下载反馈（~5）。存量的设置项/主题模式/歌词/空态/错误态等**仍 100% 硬编码中文**——`settings_page.dart:198-220`「主题模式/跟随系统/亮/暗/纯黑」、`lyrics_page.dart:207-224`「歌词加载失败/暂无歌词」均未接 S.of。阶段 A 自承「存量 119 处迁移列阶段 B7」，本批 B6 无改善。

### [09:01] 【无障碍】抽样：语义标签近乎为零，触控目标靠组件默认、无 48dp 保证
- 全 surface `Semantics` 显式标签 **0 处**，`semanticLabel` 0 处；仅 17 处 `tooltip`（多为 IconButton，Material 自带语义尚可覆盖）。
- 大量 `InkWell/GestureDetector/onTap`（44 处命中）无语义标签、无 `Semantics(container: true)`；列表行（SpSongTile）、封面点击等读屏仅读出拼合文本。
- 触控目标：无 `<40px` 的 SizedBox 硬编码（未发现明显过小 chip），但 `SpSongTile` 末尾 `IconButton(size:20, VisualDensity.compact)`（`components.dart:110-114`）实际点击区可能 <48dp，无 minInteractiveSize 保证。无 3 级 contrast（standard/medium/high）支持——ColorScheme 未暴露 contrast 参数。
- 对比度抽样：亮色主题下 `settings_page.dart:198` `Text('主题模式', color: Sp.text)` 用深色值 #EDEFF2，若所在容器亮色 → 白底白字；`mini_bar.dart:77/83` 图标 `color: Sp.text` 在亮色 `Sp.bgElevated=#F7F8FA` 容器上同样低对比。`Sp.textFaint=#6C737D`（深）/`#9AA0AA`（亮）用于小字 fTiny=11/fSub=12，对比度边缘。亮色主题全靠 const 色 → 页面级 ColorScheme 改造零进行。

---

## MD3 复评打分表

**目标**：Flutter App `lib/surface/`（tokens/components/mini_bar/tn_theme/app_root/shell + 12 页面/弹层）。
**评分依据**：material-3 skill `MD3 Compliance Audit` 十类，每类 0–10。
**阶段 A 基线**：`bA7_c3.md` = **40/100 fail**。
**B6 复评总分 = 42/100 fail**（pass 阈值 ≥70）。**与阶段 A 分差：+2**。

| 类别 | 阶段A | B6复评 | 分差 | 状态 | 主要证据（文件:行） |
|---|---|---|---|---|---|
| Color tokens | 2 | **3** | +1 | fail | P1-8 补 `primaryContainer=greenDim/onPrimaryContainer/onError`（tokens.dart:96-98）+ 五级 surfaceContainer（:94-96）**仅定义处**；页面 `Theme.of.colorScheme` 消费 = 0，Sp.* 静态色 195 处仍绕过；primary 仍被 `copyWith(primary: green=#1DB954)` 覆盖为非 tonal 品牌绿；亮色白底白字仍在。**令牌补全但死令牌，未接线**。 |
| Typography | 5 | 5 | 0 | warn | 仍是 `Sp.fTiny/fSub/fItem/...` 自定义字号名，非 MD3 五档角色；无 emphasized / tracking / line-height 令牌。与 A7 同。
| Shape | 6 | 6 | 0 | warn | 圆角走 `Sp.r*`、magic number 0（正面）；但非 MD3 刻度、无主题级 Shapes 组件形状不随主题变。未动。
| Elevation | 4 | 4 | 0 | warn | 五级 surfaceContainer copyWith 已在 A 存在，页面仍用 Sp.card/Sp.cardHigh 不消费；阴影 2 处。未动。
| Components | 6 | 6 | 0 | warn | 用 Flutter MD3 组件 + useMaterial3:true；自绘组件与 SpSongTile 死代码仍在。未动。
| Layout | 3 | 3 | 0 | fail | 全页面手机单列固定布局，无 window size class / 大屏限宽 / 折叠屏 hinge。未动。
| Navigation | 5 | 5 | 0 | warn | NavigationBar + hash 路由；无 rail/drawer 按尺寸切换、无 predictive back。未动。
| Motion | 2 | **3** | +1 | fail | P1-7 补 4 档时长+5 曲线令牌（tokens.dart:67-75），但**全 App 仅 1 处页面消费**（lyrics_page.dart:159 用 Sp.normal+Sp.curve）；enter/screen/fast/standard/emphasized/decelerate/accelerate 7 令牌定义外零调用；无页面转场曲线/spring/中断治理。**定义补齐、消费几乎为零**。 |
| Accessibility | 4 | 4 | 0 | warn | Semantics 0 处、无 3 级 contrast、亮色白底白字、触控目标无 48dp 保证。未动。
| Theming | 3 | 3 | 0 | fail | 两套主题构造（Sp.theme vs spLightThemeData）未合并；4 档映射塌缩为 2 态（跟随系统→dark、纯黑=暗）；动态取色链 100% 断（color_extract 零调用）。未动。
| **总分** | **40** | **42** | **+2** | **fail** | 唯一 +2 来自 Color/Motion 的"令牌定义补全"，但二者均未接入页面消费。 |

**复评结论（切题回答）**：阶段 A 的 motion 令牌与 tonal pairing **确实写进了 tokens.dart，但没有真正提升页面级合规**——它们停在定义处：motion 仅 1/7 令牌被用、pairing 令牌零消费、页面仍 195 处 `Sp.*` 硬编码绕过 ColorScheme。总分仅 40→42（+2，仍 fail），**修复未端到端生效**。根因不变：ThemeData/令牌建好但 UI 消费侧未改造（页面级 ColorScheme 改造被阶段 A 明确推迟到 B6，本批实为"欠账未还"）。

---

## 动画问题清单

| # | 位置 | 问题 | 严重度 | 与 MD3 motion 对照 |
|---|---|---|---|---|
| A1 | `player_page.dart:313` | `AnimatedBuilder(animation: session)` 包整屏 body，播放进度每 tick 通知 → 整页（含 280px 封面/ListView/全部控件）rebuild，无 child 复用 | P1（rebuild 风暴/卡顿） | 无分级动画、无局部更新 |
| A2 | `mini_bar.dart:21` | `AnimatedBuilder(animation: session)` 监听整个快照，positionMs 高频 tick 重建整条迷你栏 | P2 | 同上 |
| A3 | 全局（除 lyrics 1 处） | 无 AnimatedContainer/Opacity/Switcher/Hero/Transition，页面转场走默认 MaterialPageRoute，无统一曲线 | P1（"动画细节差"主因） | MD3 六档曲线/时长体系空白 |
| A4 | `lyrics_page.dart:159` | 唯一令牌动画，但 curve=Sp.curve(easeOutCubic) 仅近似 emphasized decelerate，非精确 cubic-bezier | P2 | 用错曲线令牌（应用 decelerate） |
| A5 | `lyrics_page.dart:55,129` | 200ms Timer 轮询；切歌时加载中重复触发 `_load()`（hash 已更新但 rows 仍空，早退失效）→ 并发 lyricsFor | P2（重复触发） | 无中断/去抖治理 |
| A6 | `login_sheet.dart:186,214-232` | QR 状态切换 waitScan→waitConfirm→expired 全部瞬时跳变无缓动；1500ms 轮询 | P2 | 无过渡动画 |
| A7 | `settings_page.dart:156` | SegmentedButton 外包 AnimatedBuilder 监听 session（本页仅需 speed），切换账号态/缓存态时无关播放通知触发重建 | P2 | setState/通知范围过大 |
| A8 | 全 App | 无 spring physics、无 shared-axis、无 shape morphing、无 enter/screen 档位实际使用 | P3（Expressive 缺失） | MD3 Expressive motion 全缺 |

**动画问题数：8 项**（P1×2、P2×5、P3×1）。

---

## 动态取色体验结论

1. **四档塌缩为两态**：设置页 4 档（跟随系统/亮/暗/纯黑），`app_root.dart:64-66` 只映射 `1→light / 其余→dark`。用户选「跟随系统」恒暗（不读 platformBrightness，功能名实不符）；选「纯黑」与「暗」视觉完全相同。
2. **纯黑不是纯黑**：暗色板 `scaffoldBackgroundColor=Sp.bg=#0E0F12`（非 #000000），无独立纯黑 ThemeData；A7 的「0/3 映射 TODO」在 app_root.dart:63 注释里原样保留，阶段 A 未修。
3. **切换即时性 OK**：ValueListenableBuilder 包 MaterialApp + setMode 即时 notify/持久化 → rebuild 即时；问题在下游只有 2 种结果。
4. **动态取色链 100% 断**：L4 `color_extract.dart` extractDominant/fromSeed/ThemePalette 全仓零调用（文件头自承桥已删）；无封面取色→主题注入；seed 品牌绿(#1DB954) 与 fallback 品牌紫(#7C4DFF) 两套并存不一致。用户「动态取色」体感为零。
5. **亮白底白字仍在**：页面级 ColorScheme 改造阶段 A 未做（明确推迟 B6，本批未还账），85 处 `color: Sp.text` 用深色常量 + 4 处 `Colors.black` 在亮色容器上 → 白底白字/黑底黑字风险依旧。

---

## 本视角结论

1. **MD3 复评 42/100 fail（较阶段 A 40 仅 +2）**：阶段 A 的 motion 令牌与 tonal pairing 修复**只在 tokens.dart 定义处落地，页面层几乎零消费**（motion 1/7 令牌被用、pairing 令牌零消费、195 处 Sp.* 静态色绕过 ColorScheme）。修复未端到端生效——这是本批对「阶段 A 修复是否真提升合规分」的直接回答：**名义提升 2 分，实质未改善用户可见合规**。
2. **动画「不经看」实锤**：无过渡动画体系（仅 1 处令牌动画），3 处 AnimatedBuilder 监听整个 session 造成 rebuild 风暴，业务轮询瞬时跳变、切歌重复触发——8 项动画问题与用户抱怨吻合。
3. **动态取色体验为零**：4 档主题塌缩为 2 态、纯黑是空壳（非 #000000）、跟随系统失效、取色链 100% 断、亮色白底白字仍在。
4. **文案接线欠账**：213 处硬编码中文，S.of 仅 20 处且全在新代码，存量未迁（阶段 A 推迟到 B7）。
5. **无障碍薄弱**：Semantics 0、无 3 级 contrast、触控目标无 48dp 保证、对比度抽样亮色白底白字。

## 未覆盖

- 运行时动画观察（真机逐帧）、精确 WCAG 对比度数值（需工具测量）、实机读屏 TalkBack。
- 12 页面逐控件 48dp 触控目标枚举（仅抽样）。
- L5/L4 更下层（playback_session positionMs 通知频率、color_extract HSL 算法正确性）未深挖——本批聚焦 L7/L6/L4 取色链消费侧。
- 10 份 arb 译文语义质量（结构/键集已由 C1 核实）。

## 76 合规小结

- **跨层接缝断链（本批核心）**：L4 取色算法（color_extract）→ L6 主题控制器（theme_controller）→ L7 主题消费（tokens/app_root）三段**彼此无调用**，ThemeController 只管明暗档位、不接色；是典型「下层能力造好、上层不接」的反向断链。
- **L7 职责**：AnimatedBuilder 直接监听 PlaybackSession 整快照（player_page/mini_bar）、页面内定时器/轮询（lyrics/login）属 L7 持有逻辑状态，违反 §0「L7 只画控件、状态来自 L6」——rebuild 风暴与重复触发的根因即层级错位。
- **主题构建在 L7 surface 合规**（ThemeData 允许在 L7）；但两套构造（Sp.theme / spLightThemeData）单一事实源分裂，属职责重复。
- i18n 常量在 L4（core）符合分层；surface 仅新代码消费属断链，非越级。

---
*报告完 · B6-C3 · 落盘 `docs/deep_audit/bB6_c3.md` · 审查时间戳 2026-11-17 08:49–09:05 LCL。*
