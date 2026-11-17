# B7 · C1 架构合规视角 · i18n / 设置 / 导航 / 错误空态跨层审查

> 视角：76 原则架构合规（i18n 归口 / 导航状态归属 / 设置页职责 / 空态归位 / 六桥 / 1500 行门禁）
> 范围：L7 settings_page/shell/home_state_views/s.dart/components + 全页空态分支；L6 nav_state/bootstrap/theme_controller；L4 strings.dart + lib/l10n/*.arb；桥 bridge_core/bridge_session。
> 纪律：只读（file_read + rg/wc），未跑 dart/analyze/test/门禁，未改源码。

## [2026-11-17 09:46] ## <视角 C1> · lib/surface/pages/settings_page.dart:60-91,120-142 · <P1> · <设置页直接执行登出/缓存清理写操作（A7-C1 复现）>
证据：`_logout()`（:60-72）内直接 `auth.logout(); appGraph.cache?.invalidateSession(); ... navState().bumpAuth();`；`_clearCache()`（:120-131）内直接 `cache.invalidateSession(); _toast(...)`。无任何 L6/L5 门面包装。历史 `docs/deep_audit/bA7_c1.md:164-167` 已报同一问题，本批复核**仍未修**。
问题：登出、会话缓存失效等属于逻辑/缓存（L4/L5）与会话编排（L6）的写操作，仍由 L7 按钮回调直接编排执行，设置页越权承担业务写逻辑。
建议：在 L6 session（如 AuthSession 或新增 SettingsSession）封装 `logoutAndInvalidate()` / `clearSessionCache()` 意图方法，经 bridge_session 导出；设置页只发意图、显示结果。缓存失效钩子应内聚到 L5 `AuthLogic.logout()`（见 autonomous_lineC 遗留项）。
76 合规：违反 §0 分层职责「L7 仅 UI 控件」及铁律 4「每层只依赖下层门面」；状态机/写逻辑外溢 L7。

## [2026-11-17 09:47] ## <视角 C1> · lib/surface/l10n/s.dart:1-46 + 全 surface（213 处中文字面量）· <P1> · <i18n 门面覆盖率极低，取词链未单一事实源>
证据：`S.of` 实际仅 3 个页面消费（ykg_sheet.dart、login_sheet.dart、player_page.dart），`import '../l10n/s.dart'` 全 surface 仅这 3 处 + 定义处。B7 重点文件 settings_page.dart（37 处中文）、shell.dart（3）、home_state_views.dart（4）、design/components.dart（8）、home_page.dart（32）**零 S.of，全硬编码中文**（如 settings_page.dart:98 `SpSectionHeader(title: '账号')`、:172 '主题模式'、shell.dart:111 '无可用模块'、components.dart:268 `tooltip: '更多'`）。`rg` 全 surface 中文字面量共 213 行命中。
问题：虽然 L4 `strings.dart` + L7 `S.of` 门面 + 10 份 arb 结构齐备，但实际取词链未收敛——绝大多数页面绕过门面硬编码中文，i18n 单一事实源名存实亡；切语言后这些文案不会变化。A1-C3 报「i18n 通道断裂」，本批复核：门面已接通但仅覆盖 3 页，仍未达成全量归口。
建议：制定 surface 全量文案迁移清单，把 213 处硬编码逐页替换为 `S.of(context).t(key)` / `tr(key)`；为缺失文案在 TnStrings 10 语 catalog 与 arb 补键（保持键集一致）。
76 合规：不违反分层（门面在 L7、常量在 L4 均合规）；记为 i18n 取词链未达成单一事实源的架构收敛缺陷。

## [2026-11-17 09:48] ## <视角 C1> · lib/core/l10n/strings.dart:610-635 + lib/surface/app_root.dart:58-72 + settings_page.dart（无语言 UI）· <P1> · <语言切换功能缺失：saveLocale 零调用，locale 未装配 MaterialApp>
证据：`rg -n 'saveLocale' lib` 全仓**仅定义处 strings.dart:610，零调用点**；`loadLocale()` 仅被 s.dart:34,44 读取。`app_root.dart:58-72` 的 `MaterialApp(...)` 未设置 `locale` / `supportedLocales` / `localizationsDelegates`，`appLocaleCode()`（strings.dart:632）全仓零调用。设置页「外观」段（settings_page.dart:184-215）只有主题模式 SegmentedButton，无任何语言选择 UI。
问题：语言持久化写口（saveLocale）无人调用、`appLocaleCode` 无人装配到 MaterialApp、设置页无语言切换入口——多语能力对用户完全不可达；`S.of` 读到的 `loadLocale` 永远为空，只能跟随系统 locale，且系统 locale 又未注入 MaterialApp，实际恒为 zh。属 A1-C3「写了不生效」的结构性残留。
建议：① L7 设置页加语言切换 UI（跟随系统/10 语），调用经门面的 saveLocale；② 保存后触发 locale 变更通知（类似 ThemeController 的 ValueNotifier），AppRoot 监听并注入 `MaterialApp.locale`；③ 语言偏好写操作宜经 L6 session 门面（参照 ThemeController 模式）而非 L7 直调 core 静态方法。
76 合规：saveLocale/loadLocale 归 L4 core + 用 L4 KeyValueSettings 持久化本身符合 §0「l10n 常量在 L4」；但缺少 L6 装配门面与 L7 出口，语言状态链路三段断裂。

## [2026-11-17 09:49] ## <视角 C1> · lib/session/nav_state.dart:1-107 + lib/surface/shell.dart:56-118 · <符合> · <导航状态归属 L6，shell 仅消费状态>
证据：`nav_state.dart` 为纯 Dart（零 flutter import，仅 bridge_kernel Log），单例持有 albumId/artistId/tabRequest/authVersion，暴露 addListener/requestTab/setAlbum/bumpAuth；位于 L6 session 合规。经 `bridge_session.dart:20,55-62` 导出。`shell.dart:60-91` 只 `_onNavState()` 读 `NavState.instance.tabRequest` → `setState(_index)` → `clearTabRequest()`，导航选择 `onDestinationSelected: (i) => setState(() => _index = i)`（:118）为**本页局部 index**，未塞进 NavState；无 Widget 内状态机。
问题：无明显越权。唯一观察点：`_index` 局部态与 NavState.tabRequest 是两套 index 表达，跨页深链（setAlbum/artist）目前无消费者（`rg setAlbum/setArtist` 仅定义处），导航状态部分字段悬空。
建议：若保留 album/artist 深链意图，需在对应页面补消费；否则清理死字段，避免 nav_state 伪全量。
76 合规：符合 §0「导航状态归 L6 session」、铁律 1（经桥）、§4「L7 零状态机」；NavState 纯 Dart 可单测，设计正确。

## [2026-11-17 09:50] ## <视角 C1> · lib/surface/design/components.dart:232-268 + lib/surface/pages/* 空态分支（共 15+ 处）· <P2> · <三态组件双轨并存，归位不统一>
证据：存在两套三态组件——通用 `SpStateView`（components.dart:232，「空/错/受限三态统一」）被 library_page/lyrics_page/mv_page/player_page 使用（共 12 处）；首页专用 `HomeSkeletonBox/HomeEmptyBox/HomeErrorRetry`（home_state_views.dart:8,33,50）仅 home_page.dart 使用（9 处），二者样式/API 不同（HomeErrorRetry 带独立「重试」TextButton，SpStateView 用 FilledButton actionLabel）。且所有三态文案均为硬编码中文（mv_page.dart:243 '暂无 MV'/245 '重试'；lyrics_page.dart:211 '歌词加载失败'；library_page.dart:236 '数据能力未装配'）。
问题：三态 UI 未按单一组件体系收敛（通用 + 首页专用双轨），新增页面易各起炉灶；三态文案全部绕过 S.of，与 i18n 归口缺陷叠加。
建议：统一到 SpStateView  family（骨架用 SpSkeleton/SpListSkeleton 已有），Home 专用三件可降级为薄封装或直接迁移；三态文案统一走 S.of/tr，复用 TnStrings 已有 error*/empty/retry/needVip 键。
76 合规：组件均在 L7 design/，不违反分层；归位属架构收敛（同层职责一致性）缺陷，非越级。

## [2026-11-17 09:51] ## <视角 C1> · lib/surface/pages/settings_page.dart:1-15 + lib/surface/app_root.dart:1-19 · <P2> · <L7 普遍绕过 bridge_surface 直取三座下桥（A7-C1 复现）>
证据：settings_page.dart:5-12 直接 `import '../../bridges/bridge_core.dart' / bridge_logic.dart / bridge_session.dart`；app_root.dart:5-19 同样直取 bridge_core + bridge_session。全 surface 零 `import bridge_surface.dart`（A7-C1 bA7_c1.md:19 已报），bridge_surface 仅 L1 init/main.dart 使用。
问题：§0/§2「L7 经 bridge_surface 拿 L6 门面」未落实，surface 直接抓 bridge_core/bridge_logic/bridge_session；bridge_surface 在 surface 侧形同虚设。本批复核仍未修（A7-C1 同项）。
建议：主会话评估把跨层门面收敛到 bridge_surface 单一出口；至少让设置页/外壳的 nav/theme/graph 访问经 bridge_surface 转发。
76 合规：不违反铁律 1（三者均为合法桥），属桥出口收敛度偏离 §0/§2。

## [2026-11-17 09:52] ## <视角 C1> · lib/core/l10n/strings.dart:7 · <P2> · <L4 core 反向 import bridge_core 获取 KeyValueSettings/StoragePaths>
证据：`strings.dart:7 import '../../bridges/bridge_core.dart' show KeyValueSettings, StoragePaths;`，而 bridge_core.dart:35,50 又 `export '../core/storage/settings_store.dart'` 与 `paths.dart`——形成 core → bridge_core → core 的自环。全仓 core 层 import 桥共 46 文件，属既有普遍模式（theme_controller.dart:13 亦经 bridge_core 取同二者）。
问题：L4 core 经桥取本层门面，违背「依赖方向向下」的纯粹性，属架构自环；虽为全局既定做法、单点改会导致大面积改动，但就 B7 i18n 归口而言，TnStrings.saveLocale/loadLocale 的持久化实现确有层级模糊。
建议：主会话统一评估 core 层直取同层 storage（去桥）或明确「core 经桥自取同层门面」为登记例外；不在本视角单点改。
76 合规：依赖方向铁律 4 的边缘偏离（core→bridge→core 自环）；符合「i18n 常量在 L4」归属。

## [2026-11-17 09:53] ## <视角 C1> · lib/surface/pages/settings_page.dart:316 · <P2> · <NavEntry label 硬编码破坏导航文案归口>
证据：`SettingsPageModule.navEntry => const NavEntry('设置', 'settings', navOrder: 4)`（:316），label 为硬编码中文；shell.dart:129 `NavigationDestination(label: m.navEntry?.label ?? m.id)` 直接展示。全 8 个页面 Module 的 navEntry label 均为硬编码中文（settings/home/search/...）。
问题：底部导航文案经 NavEntry.label（L6 数据）传入，但源头是 L7 硬编码，切语言无效；且 i18n key `settings`/`search` 等已在 TnStrings 10 语中存在却未使用。
建议：NavEntry.label 改为存 i18n key（如 'settings'），shell 渲染时 `S.of(context).t(m.navEntry.label)`；或 Module 提供 labelKey 字段。
76 合规：NavEntry 在 L6（contracts.dart）合规；label 文案硬编码属 i18n 归口缺陷，非分层越级。

## [2026-11-17 09:54] ## <视角 C1> · lib/l10n/app_*.arb（10 份）· <P2> · <部分 arb 键数不一致（57 vs 59），与 strings.dart 声称「严格同集」有偏差>
证据：`rg -c '":' lib/l10n/app_*.arb` → app_en.arb=57、app_zh_Hant.arb=57，其余 8 份=59。而 strings.dart:2 注释「与 lib/l10n/app_*.arb 严格同集」、s.dart:5「10 语键集一致」。L4 strings.dart 各语 catalog 均为 57 键（每语自 zh 段计数），arb 多出的 2 键疑为 @@locale 元数据或自定义键（本视角不改 arb，仅记录结构差）。
问题：arb 与 core catalog 键集存在结构性不一致风险，若 CI gen-l10n 做严格键校验可能出现漂移；「单一事实源」声明与实际文件不完全吻合。
建议：主会话核对 57 vs 59 的具体差键（可能含 @@locale），统一 arb 与 strings.dart 键集并修正文档声明；属结构一致性核对，不改 arb 内容。
76 合规：arb 在 L4/lib/l10n、strings 在 L4 core，归属合规；记为资源一致性缺陷。

## 本视角结论
B7（i18n 文案 / 设置 / 导航 / 错误空态）C1 架构合规共落 **9 条**：P1 三条、P2 五条、正向符合确认一条。
- 最严重三项：① 设置页直接执行登出/缓存清理写操作（A7-C1 复现，P1）；② i18n 门面仅覆盖 3/18 页、213 处硬编码中文未归口（P1）；③ 语言切换三段断裂——saveLocale 零调用、MaterialApp 无 locale 装配、设置页无语言 UI（P1）。
- 正向确认：导航状态归属 L6、shell 只消费状态发意图、NavState 纯 Dart 可单测，无 Widget 内状态机，符合 76 原则。
- 三态组件均在 L7 design/（无跨层违规），但通用 SpStateView 与首页专用三件双轨并存，归位不统一且文案全硬编码。
- 多属「结构齐备但收敛度/接线不足」的架构漂移，非新增越级直连；A7-C1 的设置页越权、bridge_surface 绕过两项本批复现仍未修。

## 未覆盖
- 未逐行读完 lib/l10n/*.arb 全部键值（仅统计键数 + 抽查 settings 键），57 vs 59 差键未定位到具体 key。
- 未审 lib/logic 内部（auth_logic.logout 自动失效钩子、i18n 相关 logic）——超出本批跨层清单。
- 未逐页读完 lib/surface/pages 全部 18 页的每一处错误分支（仅统计 SpStateView/Home*Box 使用点与硬编码计数，未逐行核每页三态完整性）。
- 未跑任何分析器/测试/门禁（按纪律禁止），行号以静态读取为准，未做编译验证。

## 76 合规小结
- **符合**：nav_state 归 L6 session 且纯 Dart；shell 只消费状态/发意图、零 Widget 状态机；SpStateView 等三态组件在 L7 design/；TnStrings/saveLocale/loadLocale 归 L4 core + L4 KeyValueSettings 持久化；桥唯一在 lib/bridges/、无影子桥；全部重点文件 <1500 行（最大 strings.dart 676 行），无超行门禁违规。
- **违反/偏离**：设置页 L7 直接执行登出/缓存写（违反 §0「L7 仅 UI」、铁律 4）；L7 普遍绕过 bridge_surface 直取三桥（偏离 §0/§2 桥出口收敛）；L4 core import bridge_core 取同层门面形成 core→bridge→core 自环（铁律 4 边缘偏离，既有普遍模式）。
- **非分层缺陷（架构收敛）**：i18n 取词链未单一事实源（门面仅 3 页）；语言切换链路三段断裂；三态组件双轨；NavEntry.label 与部分文案硬编码；arb 键集 57/59 不一致。
