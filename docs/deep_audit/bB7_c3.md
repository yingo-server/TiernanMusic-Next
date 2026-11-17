# B7 批 · C3 用户痛点专项视角（i18n 文案 / 设置 / 导航 / 错误空态）

> 审查范围：L7 settings_page.dart / shell.dart / home_state_views.dart / l10n/s.dart / components.dart + 各页空态；L6 nav_state.dart；L4 strings.dart + lib/l10n/*.arb。
> 纪律：只读；证据均带 `文件:行`。60 分钟硬超时，收口不无限加调用。
> 基线对照：`docs/DEEP_AUDIT_PHASE_B_PLAN.md`、`docs/deep_audit/bA7_c3.md`（MD3 基线）、`docs/YKG_LINK_CRYPTO_DESIGN.md`。

---

## [2026-11-17 09:47] B7-C3-P0-01 语言切换：设置页无任何切换入口，用户「文案没改」的 UI 侧根因仍在

**痛点（用户核心诉求「相关文案也没改」）**：全 surface 搜索 `语言|language|locale|中文|English|繁体|多语言`（`rg -n -i ... lib/surface`）唯一命中是注释/账号切换，**设置页 settings_page.dart 全文 325 行没有任何语言选择项**。分组只有「账号/外观/播放/存储/关于」(`settings_page.dart:19,161,174,214,238,257`)，外观组里只有主题模式 `SegmentedButton`（`:180-207`），没有语言。

**关键断裂（三处，端到端都断）**：
1. **UI 无写入口**：`TnStrings.saveLocale(code)`（`core/l10n/strings.dart:610`）在整个 `lib/` 全仓 rg 只有定义，**零调用点**（唯一其它命中是 README 文档）。用户无法在任何界面触发语言切换。
2. **MaterialApp 不接收 locale**：`app_root.dart:56-72` 的 `MaterialApp(...)` **没有** `locale:`, `supportedLocales:`, `localizationsDelegates:`，也没有 `AppLocalizations.delegate`（全仓 `rg` 仅 `pubspec.yaml:34 generate:true`）。因此 `S.of(context)`（`surface/l10n/s.dart:31`）里 `Localizations.maybeLocaleOf(context)` 拿不到被 App 显式设置的 Locale，只能读系统 locale。
3. **无重启保持的写入**：`loadLocale()`（strings.dart:623）读 `ui.locale`，`saveLocale()`（:610）写同一键并持久化——读取链路通，但没有任何代码写入，所以「重启保持」形同虚设（永远为空→跟随系统）。

**结论**：i18n 基础设施（10 语 catalog + S 门面 + fallback）已建好，但**「设置页切换语言」这一步从未接线**。用户视角=没有任何地方能改语言，故「文案没改」在 UI 上完全成立。此为本批 P0。

## [2026-11-17 09:49] B7-C3-P0-02 「10 语里 7 语是英文占位」——部分属实，且对用户如何暴露需厘清

**事实核对**（`rg` 抽查 arb + strings.dart catalog）：
- `strings.dart:602-606` `supportedCodes` 实为 **10 语全量**：zh / zh_Hant / en / ja / ko / es / fr / de / pt / ru。注释自称「已全部达成」。
- 抽查译文质量：日语 `app_ja.arb` 基础键是真译文（`search=検索` `playlist=プレイリスト` `settings=設定` `login=ログイン`），**不是英文占位**；繁中 `app_zh_Hant.arb` 亦是真繁体（`settings=設定` `cache=快取` `login=登入`）。→ 用户关切「繁体/英文译文是否到位」：**基础键到位**。
- 但**后加的 YKG / 错误态 / 空态键在 7 语里确为英文占位**：`app_ja.arb:26 ykgTitle="YKG Link Login"`、`:32 ykgRisk` 英文整句、`:41 errorNetwork="Network error. Please retry."`、`:47 empty="Nothing here"`、`:49 needVip` 英文——与 `app_en.arb` 逐字相同；ko/es/fr/de/pt/ru 同（strings.dart 各语 map 的 ykg*/error* 段全是英文，`:400+` 各语 block 可见）。→ 「7 语英文占位」**集中在新键，不在基础键**。

**用户困惑点**：
1. 文档自相矛盾：`lib/l10n/README.md:24,50-57` 仍写「当前只落 3 语」「其余 7 语计划占位」「helper 的 supportedCodes 固定为这 3 语」「设置页展示 3/10 语可用」——而代码 reality 是 10 语全量 arb 落盘、supportedCodes=10。文档误导维护者，也解释了为什么设置页没做语言入口（以为只有 3 语/未达可切换状态）。
2. 即便切到 ja/ko 等语言，用户会看到**基础词是日文/韩文、但 YKG 弹层整段和风险提示是英文**的混杂 UI（前提是先修 P0-01 让切换可用）。这是「译文到位」的半吊子状态。
3. fallback 策略本身合理：`TnStrings.tr`（strings.dart:655-668）缺键回退 zh 再回退 keyName，并有 Log 留痕——设计无问题，问题是占位译文被当成「已支持」计入 `supportedCodes`，掩盖了 7 语新键未译。

**建议（不改码）**：设置语言入口上线前，要么把 7 语新键补齐，要么在 UI 对「部分未译」语种做标注；同步更新 README 消除 3 语/10 语矛盾。

---

## 语言切换体验走查

> 用户四问逐条回答（基于上面 P0-01/P0-02 证据）：

| 用户问题 | 结论 | 证据 |
|---|---|---|
| 设置页能否切语言？ | **不能，无任何入口** | `settings_page.dart` 全文无语言项；全 surface rg 无语言切换控件 |
| 有几种语言？ | 资源层 10 语、可达层 0 语 | strings.dart:602 支持 10 语；但无入口 + MaterialApp 未接 locale → 用户实际只能用系统语言决定 |
| 切换后是否即时生效？ | **无从谈起**（未接线）；若将来接线，S.of 走 `loadLocale` 但无全局 Locale 广播/重建，静态文案难即时刷新 | s.dart:31-35 只读持久化，无 ValueNotifier/Rebuild 机制 |
| 重启是否保持？ | 读取链路在（loadLocale 读 `ui.locale`），但无写入方，等于永远空 | strings.dart:610/623；saveLocale 全仓零调用 |
| 繁体/英文译文到位？ | 基础键到位（真译文），新键（YKG/错误/空态）7 语为英文占位 | arb 抽查 P0-02 |
| 7 语英文占位是否暴露给用户？ | 目前切换不可用故未直接暴露；一旦开入口即出现「日文界面+英文 YKG 弹层」混杂 | 同上 |

**一句话**：语言切换体验目前是**空集**——用户痛点「文案没改」的真实原因是「翻译做完了、接线没做完」，且设置页入口、MaterialApp locale、持久化写入三处同时缺失。

---

## 全仓文案接线总账

> 统计口径：`rg` 扫描 `lib/surface/**/*.dart`，CJK 落在单/双引号字符串字面量内、且非纯注释行。总量 = 各 surface 字面量出现次数（含重复）。

### 接线现状（正向）
- 真正走 `S.of(context).t(key)` 的调用点：**30 处**，仅分布在 **3 个文件**：`ykg_sheet.dart`(17)、`login_sheet.dart`(7)、`player_page.dart`(6)（player 的 6 处集中在收藏/下载的 SnackBar）。
- 门面 `S`（s.dart）+ 取词器 `TnStrings`（strings.dart）+ 10 语 arb + fallback 全部就绪；`ykg_sheet` 是接线样板（几乎全走 t()）。

### 未接线存量（负向，用户「还剩多少」）
- surface 全仓 CJK 字符串字面量 **213 处**（`rg -o`），覆盖 **15 个文件**。
- 其中已接线（同一行 S.of/t）**0 处**——30 处 t() 调用的参数都是英文 key（如 `'ykgRisk'`、`'downloadQueued'`），不是中文串。
- 结论：**213 处中文硬编码仍然 100% 未接 i18n**，与 A7 基线「约 119 处去重文案 / 212 令牌命中」量级一致（本轮 213 出现次数，含重复；去重后仍约 119 条）。

### 按文件分布（CJK 字面量行数，非注释）
| 文件 | 行数 | 代表uncaught文案（文件:行） |
|---|---|---|
| login_sheet.dart | 29 | `:356 登录失败…`、`:327 验证码已发送…`、`:318/350/431` 开发状态外露 |
| settings_page.dart | 28 | `音质档位`/`清理缓存`/`已登录`/`扫码登录`/`跟随系统` 等全页 |
| player_page.dart | 23 | `歌词`/`评论`/`查看 MV`/`下载当前歌曲`/`FM 暂无可用曲目（端点待实测）` |
| home_page.dart | 23 | `每日推荐`/`推荐歌单`/`排行榜` + 各空/错态 |
| mv_page.dart | 19 | `这首歌暂无可播 MV`/`MV 加载失败：$e`/`不支持的 MV 链接协议` |
| search_page.dart | 18 | `暂无搜索历史`/`暂无结果` + 重试 |
| playlist_page.dart | 18 | `推荐歌单加载失败`/`该歌单暂无曲目` |
| library_page.dart | 17 | `曲库还是空的`/`还没有播放记录`/`数据能力未装配` |
| lyrics_page.dart | 7 | `歌词加载失败`/`暂无歌词` |
| search_tile_widgets.dart | 4 | `重试` |
| login_account_section.dart | 4 | `暂无账号，登录后将自动保存到这里` |
| shell.dart | 2 | `无可用模块`/`模块未提供页面` |
| mini_bar.dart | 2 | 零星 |
| home_state_views.dart | 1 | `重试` |
| components.dart | 1 | `更多`(tooltip) |

### 量化结论（给用户）
> 「文案改了多少、还剩多少」：**已接线约 30 处（仅登录 YKG/收藏下载 3 页的提示），全仓约 213 处用户可见中文仍硬编码未接（≈119 条去重）**。按出现次数算接线率约 **12%（30/243）**，按中文串算接线率近 **0%**。设置/首页/播放/MV/搜索/歌单/曲库/歌词/底栏等**主体页面文案仍全部是中文硬编码**——这正是用户看到「文案没改」的直接原因。

### 跨批汇总口径说明
各批（B1 登录/YKG、B2 搜索、B3 播放、B4 MV、B5 下载收藏、B7 设置导航空态）报告的硬编码中文，均在**同一 213 处全集内按文件切分**，不应简单相加；本账以 surface 全仓 `rg` 一次性统计为准，避免重复计数。B1 已接 7（login）+17（ykg），B3 已接 6（player），其余批 0。

---

## 设置页体验走查

### 逐项状态与反馈
| 项 | 位置 | 当前状态显示 | 点击反馈 | 危险确认 | 痛点 |
|---|---|---|---|---|---|
| 登录/登出 | settings_page.dart:158-172 | `已登录`/`未登录` + 昵称或「扫码登录后同步收藏与历史」(`:162-170`) | 登出 `TextButton` 直接 `_logout()`；登录 `FilledButton` 弹层 | **无** | 登出一键生效无二次确认（轻危，可接受）；状态文字清晰 |
| 主题模式 | :180-207 | `ValueListenableBuilder` 读 ThemeController，选中态正确 | `SegmentedButton` 即时 `setMode` + 持久化（theme_controller.dart:27-44） | 不适用 | 正面项；4 档（跟随系统/亮/暗/纯黑），但 `:63` 注释「纯黑暂用暗色板 TODO」——选纯黑与暗无差别，用户困惑 |
| 音质 | :212-223 | **subtitle 恒显「128（标准）」**，与 session 实际档位脱节；点开 sheet 也**无当前档位勾选** | sheet 列表可点、点后 pop | 不适用 | 状态显示是硬编码假值，用户改了档位返回仍显示 128 |
| 倍速 | :225-239 | `AnimatedBuilder` 读 `session.snapshot.speed` 真值 `${speed}x` | sheet 内当前值有 `Icons.check` 勾选(`:115`) | 不适用 | 正面项，状态准确 |
| 清理缓存 | :242-255 | 无缓存占用量显示 | FilledButton → `_clearCache()` toast「已清理会话缓存」(`:127-138`) | 无 | subtitle 说「清理会话缓存与请求合并表」，实际只 `invalidateSession()`，注释自承磁盘缓存未清（`:132-134`）——**清缓存名不副实**，用户以为清了磁盘缓存 |
| 版本 | :258-268 | 显示 `kAppVersion='26.11.10+1'`(常量:17) | 无点击 | 不适用 | 版本号硬编码常量，与 pubspec 同步靠人工注释 |

### 发现
- **[P1] 音质档位状态造假**（settings_page.dart:218-219）：subtitle 恒为「128（标准）」，`_openQualitySheet`(:87-103) 列表项无任何当前选中标记，与倍速页形成鲜明对比（倍速有 check）。用户无法知道当前音质、也无法判断切换是否生效——印证 B 批「VIP 恒 false 提档」痛点在设置 UI 侧仍未闭环。
- **[P1] 清缓存名实不符**（:127-138, :242-255）：按钮文案「清理缓存」/「清理会话缓存与请求合并表」，实现仅 `cache.invalidateSession()`（内存会话缓存），磁盘级缓存目录未清（源码注释明说）。用户预期「释放存储空间」落空。
- **[P2] 无语言切换项**（见 P0-01）：设置页作为用户找「改语言」的唯一合理入口，缺失该项是「文案没改」投诉的直接触点。
- **[P2] 纯黑档无差异**（app_root.dart:65 注释 + theme_controller 档位3）：设置里可选「纯黑」，但 AppRoot `themeMode` 把档 2/3 都映射为 `ThemeMode.dark`，纯黑档无独立色板。
- **[P2] 危险操作无确认**：登出/清缓存均为即时执行无二次确认；此处风险低，但清缓存若将来扩展为磁盘删除需补确认。
- **[P3] 全页硬编码中文**（28 行，见文案总账）：设置页自身文案 0 接线，切语言即使可用本页也不会变。

### MD3 局部抽样（设置页/空态）
- 正面：`SegmentedButton`/`FilledButton`/`ListTile`/`NavigationBar` 均为 MD3 组件；`SpStateView`/`HomeErrorRetry` 有 icon+title+subtitle+action 四段结构，错误态带 `FilledButton` 重试（components.dart:288-310）。
- 负面（延续 A7 MD3 基线）：所有颜色走 `Sp.*` 静态常量（`Sp.bg`/`Sp.card`/`Sp.textSub`/`Sp.green`…），绕过 `ColorScheme` 语义角色；设置页 `:144,168,187` 等多处 `color: Sp.textSub`。空态文字用 `Sp.textFaint`/`Sp.red`（home_state_views.dart:44,64），亮色主题下对比度存疑（A7 已记白底白字风险）。

---

## 导航体验走查

### 底栏 Tab
- `shell.dart:118-141` 用 `NavState.instance.addListener` 订阅 `tabRequest`，`_modules` 取 `ModuleRegistry.active().where(navEntry!=null)`(`:77-80`)，`NavigationBar` 的 destinations 由模块 navEntry 生成(`:134-141`)，`selectedIndex=safeIndex` 有当前位置高亮(`:133`)。**底栏当前位置指示正常**。
- 底栏 5 项由 navOrder 排序：首页(home:0)/歌单(playlist:2)/音乐库(library_music:3)/设置(settings:4)，搜索无 navOrder 排默认——`module_registry.dart:35-46` 按 navOrder 升序、id 字典序兜底，无 navEntry 排最后。顺序由代码决定，未见用户可配置。
- **底栏 label 硬编码中文**：`NavEntry('首页'/'歌单'/'音乐库'/'搜索'/'设置')`（home_page.dart:24、playlist_page.dart:21、library_page.dart:342、search_page.dart:24、settings_page.dart:320），经 `shell.dart:139 label: m.navEntry?.label` 直接显示，**未走 i18n**——切语言底栏仍中文。

### 非底栏页面（MV / 歌词 / 播放器）返回
- Player/Lyrics/MV 三个 Module 的 `navEntry => null`（player_page.dart:511、lyrics_page.dart:279、mv_page.dart:29），不在底栏，**通过 Navigator.push 打开**：
  - 播放器：mini bar `onExpand` → `_openPlayer()` `Navigator.push(fullscreenDialog:true)`（shell.dart:141-154）。`fullscreenDialog:true` 在 iOS 会带「Cancel」关闭，Android 依赖系统返回键；`player_page.dart:404` 有 `maybePop()` 返回按钮。
  - 歌词：`player_page.dart:206` `navState().requestTab('lyrics')` 后 `Navigator.pop()` ——**这是导航断裂**：lyrics 的 navEntry=null，不在 `_modules` 里，`shell.dart:84` 的 `indexWhere(m.id==req)` 返回 -1，**requestTab('lyrics') 无效**，随后 pop 掉播放页，用户点「歌词」后可能什么都没发生或退回上一页。评论同理（`:217 requestTab('comment')`，comment 模块甚至未注册）。
  - MV：`player_page.dart:229-243` 先 `registerMvModule()` 再直接 `Navigator.push(MvPage)`，MV 页 `appBar`(mv_page.dart:213) 依赖默认 leading（Scaffold 在 push 栈里返回可用），返回路径通。

### 深链 / 返回痛点
- **[P1] 歌词/评论入口用 requestTab 指向非 Tab 模块**（player_page.dart:206,217）：`requestTab` 语义是切底栏 Tab（shell 只在 navEntry 模块里找），用来打开歌词/评论是错配；歌词最终无可靠出口，评论模块根本没注册（`registerModules` shell.dart:16-31 无 comment）。用户点这两个菜单项行为异常。
- **[P2] `navState` 的 albumId/artistId 无消费者闭环**：`setAlbum`/`setArtist`（nav_state.dart:70-86）被 search_page.dart:132、playlist_page.dart:371 调用，但全仓 rg 无页面 `addListener` 读取 `albumId/artistId` 去跳转——专辑/歌手点击后导航意图发出但无人接收，用户点歌单里的专辑无跳转。
- **[P2] 无深链入口**：Module 均有 `route`('/mv','/lyrics'…)，但 AppRoot 用 `home: AppShell()`（app_root.dart:70），**未配置 `onGenerateRoute`/`routes`**，深链（A1/A6 已记 MV 深链不可达）在 B7 复查仍未接——外部 `tiernanmusic://mv` 之类无法落到对应页。
- **[P2] 无 predictive back / 返回位置保持**：无 `PopScope`/`BackButtonListener` 治理；Tab 切换用 `KeyedSubtree(ValueKey(current.id))`（shell.dart:108），切走再切回该 Tab 状态重建（滚动位置丢失），用户从设置切到首页再回来可能回到顶部。

### MD3 局部（导航）
- 正面：用 `NavigationBar`（MD3 底栏）而非已弃用的 `BottomNavigationBar`；selectedIcon/icon 双态齐全(`:136-137`)。
- 负面（延续 A7）：无 `NavigationRail`/`Drawer` 按 window size 切换；无 predictive back 适配；深链路由未接（Navigation 维度 A7 判 5/10 warn，B7 未见改善）。

---

## 错误空态体验走查

### 三态组件现状
- 共享组件已具备三态：**骨架** `HomeSkeletonBox`(home_state_views.dart:8-29)/`SpSkeleton`/`SpListSkeleton`、`空态` `HomeEmptyBox`(:31-52)/`SpStateView`(components.dart:213-240)、**错误+重试** `HomeErrorRetry`(:54-77)/`SpErrorRetry` 各页自定义。设计上有 icon+title+subtitle+action 结构，`FilledButton` 重试，框架合格。

### 逐页文案与「是否掩盖错误/未登录」
| 页 | 空/错文案（硬编码） | 能否重试 | 痛点 |
|---|---|---|---|
| 首页 | `HomeErrorRetry('每日推荐加载失败')`(home_page.dart:198)、`HomeEmptyBox('暂无每日推荐（登录后可能可见）')`(:203)、`暂无推荐歌单`/`暂无榜单数据` | 有 `_reload` | **B2 问题复现**：`:203` 把「未登录导致无数据」和「真为空」混成一句「暂无…（登录后可能可见）」，既不引导登录也不区分网络错误；未登录用户看到空态不知要登录 |
| 歌单 | `PlaylistErrorRetry('推荐歌单加载失败')`/`('我的歌单加载失败')`(playlist_page.dart:124,208)、`暂无推荐歌单`/`该歌单暂无曲目`(:128,361) | 有 `_reload` | 错误/空分开，尚可；文案全硬编码 |
| 搜索 | `暂无搜索历史`(search_page.dart:377)、`SearchEmptyBox('暂无结果')`(:441)、`SearchErrorRetry`(:453) | 有 | 空/错分开；但空结果不提示「换个关键词」等引导 |
| 歌词 | `SpStateView(title:'歌词加载失败', subtitle:'稍后重试或切歌再试')`(lyrics_page.dart:208-214)、`暂无歌词`(:216-219) | 有 onAction | 错误给了可操作建议，正面 |
| MV | `SpStateView('暂无 MV', actionLabel:'重试')`(mv_page.dart:240-247)、`MV 加载失败：$e`(:185)、`不支持的 MV 链接协议：$url`(:157) | 有 | **把技术错误直接暴露用户**：`:157/:185` 把异常对象/URL 拼进 UI 文案，`$e` 英文栈信息对用户无意义；空态与错误态区分（_Phase.empty/error）是正面 |
| 曲库 | `曲库还是空的`/`还没有播放记录`(library_page.dart:209,219)、`数据能力未装配`(:236)、`加载失败`+`${snap.error}`(:245-248) | 部分 | `数据能力未装配`(:236) 是内部术语外露；`:248 加载失败：${snap.error}` 把原始错误塞给用户 |
| 播放器 | `FM 暂无可用曲目（端点待实测）`(player_page.dart:281)、`下载失败：$e`(:278) | 无 | **开发状态外露**（端点待实测）+ 原始异常拼接 |
| 登录 | `二维码获取失败，请重试`(:192)、`二维码已过期，请下拉重试或退出重开`(:220)、`登录失败：${...未知错误}`(:356)、`发送失败，请稍后重试`(:327) | 下拉刷新 | 「下拉重试或退出重开」指引含糊（哪里下拉？）；开发期占位（:318/350/431）仍未清（见下） |

### 发现
- **[P1] 「暂无内容」类空态掩盖错误/未登录（B2 已报，B7 确认仍在）**：首页 `home_page.dart:203` 一句「暂无每日推荐（登录后可能可见）」把「未登录」「无数据」「加载失败后 fallback」三种状态揉在一起，既不区分也不引导；登录页/曲库把「能力未装配」当空态文案。用户无法判断是没网、没登录、还是真的没内容。
- **[P1] 开发状态/技术错误直 expose 给用户**：`player_page.dart:281 FM 暂无可用曲目（端点待实测）`、`login_sheet.dart:318/350/431`（接口待实测/验证码端点待实测 needs probe/密码登录待后端就绪）、`mv_page.dart:157/185` 拼 `$url`/`$e`、`library_page.dart:248` 拼 `${snap.error}`、`player_page.dart:278 下载失败：$e`。这些直接印证 A7 基线「把开发状态暴露给用户」，且 i18n catalog 里已有 `errorNetwork/errorTimeout/errorGeneric` 等友好文案却没用。
- **[P2] 错误态重试覆盖不全**：首页/歌单/搜索/歌词/MV 有重试；曲库「数据能力未装配」态、登录「端点待实测」态无有效重试出口。
- **[P2] 空/错态文案 0 接线**：上述所有空态/错误文案全部硬编码中文（见文案总账），`strings.dart` 已有 `empty/error*/retry/mvEmpty` 等 56 键但未在 state_view 使用。

### MD3 局部（空态）
- 正面：`SpStateView` 居中 icon+标题+副标题+主按钮层级清晰，`FilledButton` 作主操作符合 MD3；骨架用 `Sp.card` 块。
- 负面：沿用 `Sp.textFaint`/`Sp.red`/`Sp.green` 静态色非 `ColorScheme` 语义色；错误态 `HomeErrorRetry` 的「重试」是 `TextButton`（home_state_views.dart:69），而 `SpStateView` 的重试用 `FilledButton`（components.dart:235）——同类操作两种强调级别，不一致。

### [2026-11-17 09:50] 补充：底栏图标 2/5 匹配失败
- `NavEntry` 签名为 `NavEntry(label, icon, {navOrder})`（contracts.dart:6-8），第 2 参数为 icon key。
- `iconFor()`（shell.dart:37-50）的 case 仅 `'home'/'search'/'library'/'music'/'settings'`，default 返回 `Icons.music_note`。
- 实际 navEntry 的 icon key：home→'home'✓、search→'search'✓、settings→'settings'✓，但 **playlist→'playlist'（playlist_page.dart:21）✗、library_music→'library_music'（library_page.dart:342）✗** ——两者都落到 default。
- 用户可见后果：**「歌单」和「音乐库」两个底栏图标显示成同一个默认音符 `Icons.music_note`**，与「首页/搜索/设置」的专属图标不一致，当前位置/功能识别变差。属命名不同步（case 用了 'library'/'music'，navEntry 用了 'library_music'/'playlist'）。

---

## 本视角结论

1. **语言切换是空集（P0）**：用户「文案没改」在 UI 侧彻底成立，根因不是没翻译，而是**三处同时断线**——设置页无切换入口、MaterialApp 未接 locale/delegate、`saveLocale()` 全仓零调用。10 语资源与 S 门面已就绪，缺的是最后一段用户可达链路。
2. **7 语英文占位部分属实**：基础键（搜索/设置/播放等 20 键）是真译文（日语/繁中已核），但后加的 YKG/错误/空态新键在 ja/ko/es/fr/de/pt/ru 全是英文占位且被计入 `supportedCodes=10`，文档 README 仍写「3 语」自相矛盾。一旦开放切换会出现「日文界面 + 英文 YKG 弹层」混杂。
3. **全仓文案账**：已接线 30 处（仅 ykg/login/player 三页提示），surface 仍有 **213 处中文硬编码（≈119 条去重）未接 i18n**；按出现次数接线率约 12%，按中文串近 0%。设置/首页/播放/MV/搜索/歌单/曲库/歌词/底栏主体文案全未接。
4. **设置页问题 5 项**：音质状态造假（恒显 128、sheet 无勾选）、清缓存名实不符（只清内存会话缓存）、无语言项、纯黑档与暗档无差异、危险操作无二次确认；正面项是倍速/主题状态准确、点击反馈到位。
5. **导航问题 5 项**：歌词/评论用 requestTab 指向非 Tab 模块（评论模块未注册）导致入口异常、albumId/artistId 无消费者（点专辑无跳转）、深链未接 `onGenerateRoute`、Tab 状态不保持、**底栏歌单/音乐库图标因 icon key 不匹配均显示默认音符**；底栏当前位置高亮正常。
6. **错误空态问题 4 项**：「暂无…（登录后可能可见）」掩盖未登录/错误/空三态（B2 复现仍在）、开发状态与技术异常直 expose 用户（端点待实测/`$e`/`$url`）、部分态无重试、空错态文案 0 接线；三态组件框架本身合格。
7. 汇总：本视角共记 **P0×2 + P1×6 + P2×9 + P3×1**（含跨节重复主题），核心矛盾贯穿一线——**基建齐、接线断**。

## 未覆盖

- 未跑 dart/analyze/test/门禁（纪律禁止）；「即时生效/重启保持」为静态代码推断，未实机验证。
- 未逐条校对 10 语 arb 全部 56 键的语义质量（仅抽查基础键 + YKG/错误/空态代表性键）。
- 未实测深链、返回键、predictive back 的运行时行为（仅静态路径分析）。
- 未枚举各页全部触控目标 48dp / WCAG 对比度数值（属 A7 MD3 基线，B7 仅抽样）。
- 各页空态仅覆盖 rg 命中样本，未逐行读完所有 18 个 surface 文件的全部 build 方法。
- 「文案总量」为 surface 层统计；logic/core 层内可能出现的用户可见文案未计入（本视角范围限 L7/L6/L4 i18n）。

## 76 合规小结

- **L4**（`core/l10n/strings.dart`）持有常量表 + 语言码归一化 + 持久化读写，零 Flutter import，归属正确（符合「i18n 常量属 L4」）。
- **L7** 门面 `surface/l10n/s.dart` 仅做 Locale→取词映射，合规；但 `settings_page.dart`（325 行）内仍持有账号读取编排、主题 sheet/音质 sheet/倍速 sheet 的状态机与业务判断（`_loadAccount`/`_logout`/`_openQualitySheet`/`_clearCache`），延续 A7「L7 Widget 内持有编排/IO」越界判断。
- **L6** `nav_state.dart` 为纯 Dart、零 Flutter 依赖、以 addListener 同形暴露，跨层接缝设计正确；问题在**消费侧缺口**（albumId/artistId 无监听者、requestTab 语义被误用于开非 Tab 页），而非层级归属。
- **接缝职责错位**：`S.of` 依赖 `Localizations.maybeLocaleOf` 但 AppRoot 未装 delegate（L7 内部接缝断）；语言持久化读写分离在 L4 但 L7 无写入点——属「能力已下沉、UI 未消费」的同类断链，与 A7 主题 `Sp.*` 架空 `ColorScheme` 同构。
- 未见新的反向依赖或越级 import（本视角范围内）。
