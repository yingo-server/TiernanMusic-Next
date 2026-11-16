# A7 批 · C3 用户痛点专项（MD3 / 动画 / 文案）

> ⚠️ **重建说明（主会话 2026-11-16）**：原子代理报告主体（分 3 次 append 的首批 theme/tokens/app_root + 第二批页面级 P0/P1/P2 + 第三批汇总/打分/结论）**因工具使用问题丢失**，文件系统只剩 676 字节尾注。以下为主会话依据子代理回调结论 + `M3_BASELINE.md` 重建的记录版；MD3 十类细分分数详情已重派 C3 补全（追加于本文件末尾）。

## 回调核心结论（主会话据子代理最终回报记录）

- **MD3 合规总分 40/100，fail**。Color / Motion / Layout / Theming 四类 ≤3 分（0–10 制）。
- **最严重 3 条**：
  1. 20 处硬编码色 + `Sp.*` 自定义静态色类绕过 `ColorScheme` 语义角色；primary 为非 tonal 的品牌绿 `#1DB954`；**亮色主题下白底白字**（对比度致命）。
  2. 约 **119 处硬编码中文**（surface 全 18 文件），`arb` / i18n 在 surface **零使用** —— 用户「文案没改」的 UI 侧实锤。
  3. **YKG 登录 UI 零入口**，YKG 相关文案 key 全缺。
- 未覆盖：运行时动画观察、精确对比度测量、实机读屏。

## 行号补正（原尾注保留）

- `login_sheet.dart:350`「验证码登录端点待实测（needs probe）」（原报告误记 :348）
- `login_sheet.dart:318`「接口待实测」
- `login_sheet.dart:431`「密码登录待后端就绪」

## 已知基线（复用 M3_BASELINE.md，主会话采样）

- `lib/surface/design/tokens.dart` 的 `Sp` 类：`Color(0xFF…)` 硬编码 20 处（bg/card/text/green 等）；无 `ColorScheme` 角色、`primary-container` 缺失、无 `surface-container` 五级、`outline` 与 `outline-variant` 不分。
- 字号/圆角已走 token（`fontSize: 裸数字` = 0 处、`BorderRadius.circular(裸数字)` = 0 处）——这两项是正面。
- `BoxShadow`/`elevation` 仅 2 处。

---
*以下为 C3 重派补全的 MD3 打分表 / 动画清单 / 硬编码文案清单 / YKG UI 落点清单（待追加）。*


---

# 补全：MD3 合规打分表 / 动画清单 / 硬编码文案清单 / YKG UI 落点清单
（主会话 2026-11-16 亲自补齐，依据 material-3 skill `MD3 Compliance Audit` 十类 + 本仓库只读采样；C3 子代理报告主体丢失，此处为权威替代版）

## MD3 合规打分表

**目标**：Flutter App，`lib/surface/` 全 18 文件。**总分 40/100 · fail**。

| 类别 | 分数 | 状态 | 主要证据（文件:行） |
|---|---|---|---|
| **Color tokens** | **2/10** | fail | `design/tokens.dart:12-33` 定义 20 个 `Color(0xFF…)` 静态常量（bg/card/text/green…）；全 surface 各页面直接用 `Sp.text`(≥7处)、`Sp.cardHigh`(6)、`Sp.green`(9)、`Sp.textSub`(≥28)，**绕过 ColorScheme 语义角色**；`primary: green = #1DB954` 是饱和品牌绿而非 tonal palette；`Theme.of(context).colorScheme` 仅 5 个文件引用（components/mini_bar/tokens/shell/tn_theme），页面层零使用。亮色主题下页面仍取深色 `Sp.text=#EDEFF2` 等静态色 → **白底白字**（对比度致命）。 |
| **Typography** | **5/10** | warn | 有自定义字号常量 `fPageTitle/fItem/fSub/fTiny` 且 `fontSize: 裸数字` = 0 处；`Sp.theme()` 里 `textTheme: _text(scheme,…)` 有构造。但**不是 MD3 五档角色**（Display/Headline/Title/Body/Label）映射，页面散用 `Sp.f*` 自定义名；无 emphasized 变体、无 tracking/line-height 令牌。 |
| **Shape** | **6/10** | warn | 圆角全走 `Sp.r*` 令牌（`BorderRadius.circular(裸数字)` = 0 处，正面）；但令牌是自定名而非 MD3 刻度（none/extra-small4/small8/medium12/large16/extra-large28/full），且 `chipTheme` 用 `rFull`、卡片用 `rCard`，无 `Shapes` 主题级刻度，组件形状不随主题变化。 |
| **Elevation** | **4/10** | warn | `Sp.theme()` copyWith 了 `surfaceContainerLowest/Low/…/Highest` 五级（正面，tokens.dart:87-91），但**页面不消费这些角色**，直接用 `Sp.card/Sp.cardHigh`；`BoxShadow/elevation` 仅 2 处且 AppBar/NavBar 显式 `elevation:0`；深度靠自定义色阶梯而非 tonal elevation 语义。 |
| **Components** | **6/10** | warn | 用了 Flutter MD3 组件（`NavigationBar`/`FilledButton`/`Chip`/`ListTile` 等主题化），`useMaterial3:true`。但 `design/components.dart` 存在一组自绘组件（SpSectionHeader/SpEmpty/SpError 等）且 `SpSongTile` 是死代码（C1）；按钮尺寸/状态层（8%/16%）、toggle/segmented button 等 M3 变体未系统使用。 |
| **Layout** | **3/10** | fail | 全 18 页面为**手机单列固定布局**：`Sp.pagePad`/`Sp.navH` 等硬编码尺寸；无 window size class / 自适应 scaffold / 大屏 maxWidth(840–1040dp) 约束 / 折叠屏 hinge 规避；`home_page.dart:436`/`playlist_page.dart:576` 等在宽屏会无限拉宽。M3 Adaptive 要求 600dp+ 切 canonical layout，完全未做。 |
| **Navigation** | **5/10** | warn | 有 `NavigationBar`（`shell.dart` + tokens 的 navigationBarTheme）与 hash/模块路由；但无 NavigationRail/Drawer 按尺寸切换，无 predictive back 适配，深链（MV）因模块注册守卫恒真不可达（A1/A6）。 |
| **Motion** | **2/10** | fail | 全 surface 仅 9 处动画相关命中；`tokens.dart:65-66` 只有 `fast=120ms`/`normal=220ms` 两档自定义时长，**无 MD3 Emphasized(500/400/200)/Standard(300/250/200) 分级、无 cubic-bezier 曲线令牌、无 spring physics**；`login_sheet.dart:182` 1500ms 轮询、`lyrics_page.dart:55` 200ms Timer.periodic 是业务轮询不是过渡动画；无 shared-axis / 容器变换 / shape morphing。用户「动画细节差、不经看」实锤。 |
| **Accessibility** | **4/10** | warn | 部分 Material 组件自带语义；但亮色主题白底白字（对比度 <4.5:1）、`Sp.textFaint=#6C737D` 小字对比度不足、无显式 `Semantics` 标签审计、触控目标靠 `Sp.*` 尺寸无 48dp 保证、无 3 级 contrast 支持。 |
| **Theming** | **3/10** | fail | **修正 C3 的理由**：`Sp.theme()`（tokens.dart:70-148）**确实** `useMaterial3:true` + `ColorScheme.fromSeed(seedColor: green)` + copyWith 五级 surfaceContainer + textTheme/appBar/navBar/listTile/chip 全套；`tn_theme.dart:7` 也有独立 fromSeed 浅色主题。问题不在"没有 ThemeData"，而在：① 主应用与错误页用**两套主题构造**（Sp.theme vs spLightThemeData）单一事实源分裂；② 各页面直接引用 `Sp.*` 静态色，**ThemeData 存在但 UI 绕过它消费**（`Theme.of` 仅 5 文件命中）；③ `ThemeController` 不接 L4 动态取色（A6 X5），无 dynamicLight/DarkColorScheme、无 3 级 contrast；④ 亮/暗切换靠 `themeMode` 但页面色不跟着换 → 破图。 |

**总分**：2+5+6+4+6+3+5+2+4+3 = **40/100**，fail（阈值 pass≥70）。
**根因一句话**：主题数据（ThemeData/ColorScheme）建了，但 UI 层用 `Sp.*` 静态常量把它架空了；同时 Motion/Layout 两套 M3 核心体系（分级动效、自适应布局）几乎空白。

## 动画清单（surface 全 18 文件，只读采样）

| 位置 | 值/类型 | 判定 |
|---|---|---|
| `design/tokens.dart:65` | `Sp.fast = Duration(ms:120)` | 偏离 MD3（应为 Standard accelerate 200 / decelerate 250） |
| `design/tokens.dart:66` | `Sp.normal = Duration(ms:220)` | 偏离（无 Emphasized 400/500 档） |
| `pages/login_sheet.dart:182` | 1500ms 轮询 | 业务轮询，非过渡；QR 状态切换无动画 |
| `pages/lyrics_page.dart:55` | `Timer.periodic(200ms)` 歌词定位 | 业务定时器；无 mounted 保护（A7-C2 P1）；无歌词滚动缓动 |
| 其余 5 处 `Animated*`/`Hero`/`PageController` | 零散 | 无统一 motion 令牌、无曲线表、无中断/重复触发治理 |

**合规度**：MD3 motion 六档 easing/duration 全缺；曲线 `cubic-bezier(0.2,0,0,1)` 等零命中；无 spring。重复触发风险：`lyrics_page` 200ms 轮询 + 切歌重入（C2）；`search_page` 联想 Future 竞态（C2:74-97）旧请求覆盖新结果。

## 硬编码文案清单（surface 全 18 文件）

`rg` 统计：用户可见中文串 **约 212 处令牌命中 / 119 处去重文案**，按页计数：

| 文件 | 计数 | 代表文案（文件:行） |
|---|---|---|
| settings_page.dart | 28 | 设置项/登出/缓存清理 |
| login_sheet.dart | 32 | `:318` 「接口待实测」、`:350` 「验证码登录端点待实测（needs probe）」、`:431` 「密码登录待后端就绪」——**把开发状态暴露给用户** |
| home_page.dart | 23 | 首页分区标题/空态 |
| player_page.dart | 20 | 播放控制/收藏提示 |
| mv_page.dart | 18 | `:104`「这首歌暂无可播 MV」等（MV 恒失败时的误导文案） |
| search_page.dart | 18 | 搜索/联想/空态 |
| playlist_page.dart | 18 | 歌单/播放 |
| library_page.dart | 17 | `:302-303`「暂无下载任务」/「在歌曲菜单里选择下载」（指向不存在的菜单，A1/A3/A7-C2） |
| lyrics_page.dart | 7 | 歌词/翻译 |
| login_account_section.dart | 4 | 账号区 |
| search_tile_widgets.dart | 4 | 搜索项 |
| mini_bar.dart / shell.dart / home_state_views.dart / components.dart | 各 1–2 | 零星 |

**i18n 通道**：`lib/l10n/` 10 份 arb（zh/zh_Hant/en/de/es/fr/ja/ko/pt/ru）结构齐、键集一致（A7-C1 核实），但 **surface 零处使用 `AppLocalizations`/`TnStrings`**（C1 + C3 双确认）；`core/l10n/strings.dart` 的 TnStrings 取词器全仓零调用（A4 X6 / A5 X8）。→ 用户「相关文案也没改」= **不是没翻译，是翻译好的资源根本没接线**。

## YKG UI 落点清单（当前零入口）

依据 `docs/YKG_LINK_CRYPTO_DESIGN.md` §3.3/§5/§9，UI 需新增：

1. `login_sheet.dart` 第 4 个 Tab 或 `login_account_section.dart` 账号区新增 **「YKG 链接登录 / 导出」** 入口。
2. **导入弹层**：粘贴 `ykg://import/…` → 明确提示「这是登录凭据链接」→ 密码输入（不预填/不缓存）→ 统一错误文案「密码错误或链接已损坏」（不区分，避免 oracle）。
3. **导出弹层**：设置/输入导出密码（≥6 位 + 强度提示）→ 生成链接 → 复制/分享/二维码（`core/algorithms/qr_codec.dart` 可复用，但 QR off-by-one 必修，A4）→ **强制风险提示**「此链接包含你的登录凭据…请勿公开分享」→ 显示有效期。
4. **新增 i18n key**（zh/zh_Hant/en 必配，按用户日常版本纪律）：YKG 入口、密码、风险提示、有效期、错误、导出成功、导入来源标记。
5. 剪贴板 60 秒自动清空（仅当内容仍等于本链接）、凭据来源标记 `ykg`、本机已导入凭据吊销入口。

## 本视角结论（主会话定稿）

1. MD3 **40/100 fail**，Color/Motion/Layout/Theming 四类 ≤3 是主拖累。
2. 主题**数据存在但 UI 不消费**（`Sp.*` 静态色架空 ColorScheme），修复方向是让页面改用 `Theme.of(context).colorScheme.*` + 统一单一主题源，**不是**重写 ThemeData 构造函数。
3. 约 119 处硬编码中文 + 10 语 arb 全仓零接线 → 文案任务的本质是「接线 + 补 YKG/错误态 key」，而非重翻译。
4. 动画体系（MD3 motion 六档 + 曲线 + spring）几乎空白，与用户「动画细节差」吻合。
5. YKG UI 零入口，需按上面 5 项补；配套 QR bug 必修。

## 未覆盖

- 运行时动画观察、精确 WCAG 对比度数值（需真机/工具测量）、实机读屏（TalkBack）。
- 10 份 arb 译文**语义质量**逐条校对（结构/键集已由 C1 核实）。
- 各页面 48dp 触控目标逐控件枚举（仅抽样）。

## 76 合规小结

- L7 职责：C1 已判大面积越界（≥10 页在 Widget 内持有状态机/定时器/取数编排/IO），违反 §0「L7 只有 Widget 与 ThemeData」——修复时应把编排下沉 L6/L5。
- i18n 常量归属 L4（strings.dart 在 core）符合；但 surface 不消费属断链。
- 主题构建在 L7 surface 合规（ThemeData 允许在 L7）；问题在消费侧而非层级。
