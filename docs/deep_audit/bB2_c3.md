# B2 批 · C3 用户痛点专项（搜索 / 榜单 / 推荐 跨层）

> 视角：C3 用户痛点。范围：L7 `search_page.dart`/`search_tile_widgets.dart`/`home_page.dart`/`home_state_views.dart`；L5 `search_logic.dart`/`search_typed_logic.dart`/`rank_logic.dart`/`recommend_logic.dart`；L4 `search_endpoints.dart`/`search_typed_endpoints.dart`/`recommend_endpoints.dart`/`misc_endpoints.dart`。
> 纪律：只读采样（file_read + rg/wc），未改源码、未跑 analyze/test。基线：`docs/DEEP_AUDIT_PHASE_B_PLAN.md`、`docs/deep_audit/bA7_c3.md`（MD3 40/100 + 文案基线）。
> 说明：每条结论取证后 append，带时间戳。

---
[2026-11-17 07:18:42] 第一批：搜索体验走查

## C3 · search_page.dart:64-98,188 · P1 · 搜索触发与历史持久化
证据：`_history = <String>[]` 纯内存 List；`_doSearch` 内 `insert(0,q)`/上限12；无 shared_preferences / cache / DB 写入；搜索框 `onSubmitted: _doSearch` + 圆形按钮 `onTap: () => _doSearch(_ctrl.text)`。
问题：搜索历史重启即丢失，用户每次打开都要重输；且输入后必须点右侧箭头或回车才搜索（联想不会自动搜），符合预期但无历史留存是硬伤。
建议：历史落本地持久化（L4/L5 storage），进入页面时 load、变更时 save；保持"点选/回车才搜"的克制交互。

## C3 · search_page.dart:44-53,338-369 · P1 · 热搜功能未接线（前端伪造分类）
证据：L5 `search_logic.dart:88-99` 有 `hotSearch()` 真实热搜端点封装，但全仓 `rg hotSearch` 无 L7 调用；`search_page.dart` 只用前端常量 `kHotCategories`（华语/流行/摇滚…）当"热门分类"，标题写死"热门分类"。
问题：任务要求的热搜在 UI 零入口；用户看到的是编造的分类词，不是真实热搜榜，点"华语"只是拿这个词去搜歌。
建议：idle 态增设"热搜榜"区，调用 `appGraph.search.hotSearch()` 并接三态；把伪造分类降级或合并。

## C3 · search_logic.dart:63 / search_typed_logic.dart:35,68,108 · P1 · 搜索失败被吞成空结果并落缓存（缓存固化残留）
证据：`search_logic.dart` `catch → return const SearchResult()`，成功路径 `:63 _cache.put(key,res)` 无条件；`search_typed_logic.dart:35` 注释明写"空结果也落缓存防重复打网"，`:68/:108` 无条件 put。对照 `rank_logic.dart:54,93` / `recommend_logic.dart:61` 已是"空结果/失败不落缓存"。
问题：网络失败/风控被 catch 吞成空 SearchResult，再被固化进 LRU → L7 `snap.hasError` 永不触发，错误重试 UI（`search_page.dart:450-454`）形同虚设；用户看到"没有找到…"而非"搜索失败"，且反复搜同一词长期命中空缓存（阶段A修了 rank/recommend，搜索域未修）。
建议：与 rank/recommend 对齐——失败/空结果不 put；catch 不要吞成空结果，抛错或返回带 state 的结果让 L7 能显示错误态。

## C3 · search_page.dart:82-97,100-114 · P2 · 联想 Future 竞态（旧结果覆盖新结果）
证据：`_onChanged` 每次输入把 `_suggestF` 覆盖为新 Future，无 requestId/取消；`_suggestBox` 的 FutureBuilder 只认最后一个 future，但多个 Future 并发完成时序不确定。基线 `bA7_c3.md:75` 已记此竞态。
问题：快速输入时慢的旧请求可能后返回，联想框闪现与当前输入不符的词，用户困惑"为什么联想对不上我打的字"。
建议：加单调 requestSeq，FutureBuilder 里比对 seq 再渲染；或 debounce + 取消旧请求（sendable/Completer）。

---
[2026-11-17 07:18:42] 第二批：分区/MV/分页/功能可达性

## C3 · search_page.dart:33-41 · P1 · "MV"分区缺失（分类段与端点能力不一致）
证据：`kSearchSegments = [歌曲,歌单,专辑,歌手,歌词]`（5 段），`kSearchSegmentTypes = [song,special,album,author,lyric]`；而 L4 `search_typed_endpoints.dart:22 enum SearchType{song,special,lyric,album,author,mv}` 与 `:38-39 /v1/search/mv` 端点都存在。A2-C3 曾报"kSearchSegments 无 MV 段"，至今未补。
问题：端点支持 MV 分类搜索，但 UI 无 MV 入口，用户无法在搜索里找 MV。
建议：`kSearchSegments`/`kSearchSegmentTypes` 增 "MV"↔`SearchType.mv`，并给 `parseSearchItems` 补 MV 映射（当前 default 全用 `SongBrief.fromSearchList`，MV 字段对错）。

## C3 · search_typed_endpoints.dart:134-144 · P1 · 歌手/歌词/MV 三类搜索结果映射错位或丢失
证据：`parseSearchItems` switch 只特化 `special`(歌单) / `album`，`author`(歌手)/`lyric`(歌词)/`mv` 全走 `default: SongBrief.fromSearchList`（歌曲映射）；而 `songBriefFromSearchSpecial` 把歌手名塞进 singer、曲目数塞进 durationSec，`songBriefFromSearchAlbum` 用 albumname/title。
问题：切到"歌手"段看到的是按歌曲字段解析的条目（name 取不到即被过滤 `:144 if(s.name.isNotEmpty)` → 可能整段空白），"歌词"段也无法展示歌词；搜索结果行 `SearchSongTile` 统一当歌曲渲染（点即当歌播），歌手/歌词语义丢失。
建议：为 author/lyric/mv 各写专用映射模型或专用 tile；按段类型切换渲染，避免用歌曲 tile 一统。

## C3 · search_page.dart:440-467 / home_page.dart:292-300 等 · P1 · 搜索/首页均无分页"加载更多"与下拉刷新
证据：`rg loadMore|RefreshIndicator|ScrollController|page:2` 在 4 个 L7 文件全部 0 命中；`_doSearch` 固定 `search(q,1)`；首页三个 section `_dailyF/_playlistF/_rankF` 在 `initState` 一次性持有，仅错误 retry 调 `_reload`。
问题：搜索结果只出第 1 页（30 条），无法加载更多；首页内容看完没法下拉刷新（错误态才有"重试"），榜单/推荐"永远那几条"，配合 L5 缓存命中即返回 → 用户"内容不刷新"痛点未解。
建议：搜索结果列表尾部加 loadMore（page++ 追加）；首页套 RefreshIndicator 调 `_reload` 并强制绕过缓存刷新；明确区分"重试"与"刷新"。

## C3 · home_page.dart:91-108 · P1 · 榜单点击直接播放，不进榜单详情/歌单
证据：`_openRank(rank)` 调 `rk.rankInfo(rankId).then(songs => PlaybackSession.instance.playAll(songs,0))`；`showModalBottomSheet(PlaylistDetailSheet)` 只用于 `_openPlaylist`，rank 卡无详情入口。
问题：任务要求"榜单点击是否进歌单"——当前点了榜单卡立刻从头播放整榜，用户无法查看榜单曲目列表再选歌，也无法收藏/下载，交互突兀。
建议：榜单卡点开榜单详情 sheet（列曲目、可逐首点播/收藏），与歌单详情体验一致；或明示"点击即播放榜单"避免误触。

## C3 · home_page.dart:210-298 · P2 · 阶段A缓存修复在推荐/榜单生效，但推荐分态未暴露给 UI
证据：`recommend_logic.dart:61 if(res.cacheable && res.isNotEmpty)`、`:6/60` 注释"loginRequired/error 不缓存"；端点返回带 `state(ok/empty/loginRequired/error)` 的 `DailyRecommendResult`（同时是 List），但 `daily()` 签名仍是 `Future<List<SongBrief>>`（`:53` 注释"未改造 home_page"），L7 `_dailySection` 只判 empty → 显示"暂无每日推荐（登录后可能可见）"。
问题：缓存固化已修（失败不再固化），但"需登录"和"真没有"对 UI 是同一个空列表 + 同一句模糊文案；登录后想看推荐的用户得不到引导。
建议：L7 消费 `.state` 区分 loginRequired/error/empty，给"登录后可见"加去登录入口，error 给重试，避免把开发态兜底文案抛给用户。

---
[2026-11-17 07:18:42] 第三批：文案接线清单（未接 S.of 计数）

## C3 · 4 文件硬编码中文统计 · P1 · i18n 零接线
证据：`rg S.of|AppLocalizations|TnStrings|core/l10n` 在搜索/首页 4 文件 = **0 命中**。含中文字符串的字面量行：search_page.dart **26**、home_page.dart **33**、search_tile_widgets.dart **8**、home_state_views.dart **6**，合计 **73 行**（去重用户可见文案约 40+，含标题/NavEntry/热词/空态/错误/提示）。与基线 `bA7_c3.md` "surface i18n 零使用、119 处硬编码中文"一致，本批 4 文件是大头。
问题：10 语 arb 已就绪但本批页面完全没接，切语言后搜索/首页/榜单全是中文；用户"文案没改"实锤。
建议：按 `docs/I18N.md` 用 `S.of(context)` 逐条替换；先补 zh/en 关键 key（搜索/联想/空态/错误/三态/榜单标题）。
76 合规：文案常量应归 L4（core/l10n），当前散落 L7 属职责错位（详见合规小结）。

## C3 · search_page.dart / search_tile_widgets.dart 空态错误文案 · P2 · 到位但生硬、暴露查询串
证据：搜索空态 `:441 '暂无结果'`、`:459 '没有找到与「$_query」相关的歌曲'`；错误 `:452 '搜索失败'`；重试 tile `:113 '重试'`；未知行 `:38/:48 '未知歌曲/未知歌手'`；专辑 tooltip `:58 '专辑'`。均为硬编码中文、无 i18n；空态未区分"无网络/风控/真无结果"（因为错误被吞，见 P1 缓存条）。
问题：错误态文案到位但几乎不可达；空态把用户输入原样回显，输入敏感词时体验差；无"检查网络/换个词"的引导。
建议：文案入 arb；空态加引导、错误态随 state 细化；去掉敏感词回显或截断。

## C3 · home_page.dart 空态错误文案 · P2 · 到位但含开发兜底口吻
证据：`:198 '每日推荐加载失败'`、`:203 '暂无每日推荐（登录后可能可见）'`、`:234 '歌单加载失败'`、`:239 '暂无推荐歌单'`、`:275 '榜单加载失败'`、`:280 '暂无榜单数据'`；`:343/:376/:382/:416/:426` 等兜底文案"未知歌曲/未命名歌单/曲目数未知/榜单/每周更新"。全部硬编码。
问题：三态文案齐全（骨架/空/错），但"（登录后可能可见）"是开发兜底口吻暴露给用户；且无登录引导动作。
建议：文案入 arb；loginRequired 态改"登录后查看每日推荐"并给按钮。

---
[2026-11-17 07:18:42] 第四批：MD3 局部

## C3 · search_page.dart:154-217 / home_page.dart:60-99 · P2 · 搜索框非 M3 SearchBar，触控/色值绕过 ColorScheme
证据：搜索框是自绘 `Container(height:44) + TextField` + 圆形 `InkWell(Icons.arrow_forward)`，非 M3 `SearchBar`/`SearchAnchor`；搜索按钮 `SizedBox(44x44)`、搜索框高 44（M3 search bar 高度 56dp，触控目标≥48dp）；全 4 文件 `Sp.*` 命中 search_page **67** / search_tile **23** / home_page **38** / home_state_views **14**，共 **142** 处，全部静态色绕过 `Theme.of(context).colorScheme`（基线 `bA7_c3.md`：Color token 2/10、白底白字风险）。
问题：与系统 M3 搜索模式不一致（无搜索建议锚定、无 leading 返回/trailing 清除按钮）；44dp 触控略小于 48dp；配色在亮色主题下可能白底白字。
建议：迁 M3 `SearchBar`/`SearchAnchor`，用 `colorScheme` 语义色；按钮/行高≥48dp。
76 合规：本条属 M3/配色规范，非层级越级。

## C3 · search_page.dart:250-300 / home_page.dart:340-430 · P2 · 分区 chips 与卡片用 Sp 静态色，选中态可读性依赖硬编码 Colors.black
证据：分区 `ChoiceChip` selectedColor `Sp.green`、`label color: sel ? Colors.black : Sp.text`，`backgroundColor: Sp.card`、`side: Sp.divider`；热门/历史 `ActionChip` 同；榜单卡 `LinearGradient(Sp.green, Sp.greenDim)` + 文字 `Colors.black/black87`；卡片封面/圆角全 `Sp.*`（rCard/rM）。`ChoiceChip` 高度栏 48，chip 本身 dense/compact。
问题：选中 chip 文字色写死黑，未走 `onPrimaryContainer` 语义 → 换主题/高对比度时不可读；卡片非 M3 `Card`，无 elevation/interaction state；分区 chips 是无语义角色的自绘选择。
建议：chip/card 色值改 `colorScheme` 角色（`primaryContainer/onPrimaryContainer/surfaceContainer`）；用 `FilterChip` 语义 + `Card` 组件。

## C3 · search_tile_widgets.dart:14-70 / home_page.dart:300-360 · P2 · 列表项/卡片触控目标未保证 48dp
证据：`SearchSongTile` 用 `ListTile(dense:true, visualDensity:compact)`（tile 高被压到 <48dp）；`_SongCard` 用 `GestureDetector+SizedBox(124)` 无 `Semantics`/min 48dp 约束；`HomePlaylistCard` 同；album `IconButton iconSize:18`（点击区靠默认 48dp 容器，尚可）；弃用 `SpSongTile` 死代码（基线 C1）。基线 `bA7_c3.md` 注明"触控目标靠 Sp.* 尺寸无 48dp 保证、未枚举"。
问题：dense/compact 列表项与横滑卡片在 C3 用户痛点视角下更难点准，尤其专辑小图标与歌名区。
建议：列表项去 dense 或保证 minTileHeight≥48；卡片加 `Semantics(button:true)` + 至少 48dp 命中区。

---
[2026-11-17 07:18:42] 第五批：76 合规（跨层接缝）

## C3 · search_page.dart / home_page.dart（L7 持有逻辑）· P1 · 76 合规：L7 越界持状态机/编排
证据：L7 `_SearchPageState` 持有 `_history` 增删改、`_doSearch` 组织 search/typed 分支（`:82-97`）、`_play` 直接调 `PlaybackSession.instance.playAll`（`:104-110`）、`_openRank` 内 `.then(playAll)`（`:91-108`）；`home_page.dart:_load` 在 Widget `initState` 里编排 3 路 future、`_openRank` 跨层调 playback（`:91-108`）。违反 §0 "L7 只有 Widget/ThemeData，编排归 L6/L5"（基线 `bA7_c3.md` 76 小结）。
问题：搜索历史持久化、播放动作、榜单取数播放串在页面层 → 本次"历史不持久化""榜单点击即播"等问题都源于此，难以复用/测试。
建议：新增 L6 session/编排层统一管理历史与"查看榜单/搜索结果→播放"，L7 只发意图。
76 合规：涉及（越级：L7 直接调 L5 logic 单例 + L6 session）。

## C3 · appGraph 直连 / bridge 单例 · P2 · 76 合规：L7 经全局单例跨层取数
证据：`search_page.dart:6-12`/`home_page.dart:4-9` 直接 `import bridges/... show appGraph, NavState, PlaybackSession`，页面中 `appGraph.search`/`appGraph.searchTyped`/`appGraph.rank` 直取（`:83-86`,`:45-49`）；未经 L6 装配接口注入。
问题：依赖全局单例，跨层边界模糊；与阶段B"L7→L6→L5→L4 追踪"的目标链路不符，替换/测试困难。
建议：经 L6 注入 use-case 接口给页面，避免页面 import bridges 实现细节。

## C3 · 端点层中文注释暴露 · P2 · 76 合规：L4 注释含用户态语义但无文案出口
证据：`search_typed_endpoints.dart:99-101` 注释"综合搜索降级三段组合（由 surface 组合）"写在 L4，却要求 surface 负责组合 —— 职责回流到 L7；`recommend_logic.dart:6/53` 注释"未改造 home_page"说明契约未下沉。
问题：L4/L5 把"综合搜索=三段组合""推荐分态"的编排责任推给 L7，与分层相悖，也是本次多个断点的根因。
建议：把组合/segments 定义下沉 L5/L6，L4 只做单端点解析。

---
[2026-11-17 07:18:42] 汇总小节

## 搜索体验走查（用户视角逐步）
1. 进入搜索页 → idle 态展示"热门分类"（前端伪造 8 个词）+ "暂无搜索历史"（内存，重启即空）；真实热搜 `hotSearch()`有端点但 UI 零入口。→ P1（历史不持久化、热搜未接线）
2. 输入关键字 → `onChanged` 触发联想 Future（无 debounce/无取消，竞态可错位），联想项带 history 图标；quick 输入易闪错词。→ P2（竞态）
3. 触发搜索 → 需手动点右侧箭头按钮或键盘 search（`onSubmitted`），不会自动搜；点分类/历史 chip 直接带词搜；正确但无历史持久化。→ P1/P2
4. 联想展示 → FutureBuilder 仅 done 态渲染，等待时 `SizedBox.shrink()` 无 loading；空联想直接消失无提示。→ P2
5. 分段切换 → 5 段（歌曲/歌单/专辑/歌手/歌词），切段用 `_query` 重搜；但无 MV 段（端点有）、歌手/歌词/MV 结果用歌曲映射+歌曲 tile 渲染，语义错位/整段空白风险。→ P1
6. 结果展示 → 列表 `SearchSongTile` 点即 `playAll` 播放（可达✅），专辑按钮 `NavState.setAlbum`（可达✅）；仅第 1 页、无加载更多、无下拉刷新。→ P1（分页/刷新）
7. 空/错反馈 → 空态"没有找到与「query」相关歌曲"，错误态 `SearchErrorRetry` 存在但 L5 把失败吞成空结果并落缓存 → 错误 UI 几乎不可达，缓存固化残留。→ P1
8. 历史记录 → 只存内存、上限 12、"清空"可用但重启清零。→ P1

## 文案接线清单（本批 4 文件，未接 S.of 计数）
| 文件 | 含中文字符串行 | S.of/AppLocalizations 命中 |
|---|---|---|
| search_page.dart | 26 | 0 |
| home_page.dart | 33 | 0 |
| search_tile_widgets.dart | 8 | 0 |
| home_state_views.dart | 6 | 0 |
| **合计** | **73 行** | **0** |

代表文案：搜索框 hint"搜索歌曲、歌单、歌手"(:188)；分区/热词 :33/:46-53；空态 :377/:441/:459；错误 :452；重试 tile :113；首页标题 :130；三区块标题/空错态 :192-284；卡片兜底 :343/:376/:382/:416/:426。联想/空态/错误文案"有"但全硬编码、且错误态因缓存吞错不可达。

---
[2026-11-17 07:18:42] 收口

## 本视角结论（C3 用户痛点）
- **搜索体验问题 8 项**：历史不持久化(P1)、热搜零入口(P1)、联想竞态(P2)、MV 段缺失(P1)、歌手/歌词/MV 映射错位(P1)、无分页/无下拉刷新(P1)、错误态被缓存吞掉不可达(P1)、联想无 loading(P2)。
- **功能断点**：① 榜单点击只播放不进详情/歌单；② 搜索/首页均无加载更多与下拉刷新，内容固定第 1 页；③ 阶段A缓存修复覆盖 rank/recommend，但 **search/search_typed 仍空结果落缓存+吞错**（缓存固化残留）；④ 推荐 `state` 未暴露 UI，"需登录/失败/真空"混淆；⑤ 热搜端点有、UI 无。
- **功能可达性（正面）**：搜索结果点歌能播（playAll✅）、专辑按钮进专辑页（setAlbum✅）、推荐歌单点击开歌单详情 sheet✅、榜单取数 rankInfo 有数据✅。
- **文案接线**：4 文件 **73 行中文、S.of 零接线**，与基线"surface i18n 零使用"一致。
- **MD3 局部**：搜索框非 M3 SearchBar（44dp<48/56），Sp.* 共 **142 处**绕过 ColorScheme，chip/卡片选中态写死 Colors.black，列表项 dense/compact 触控偏小。延续 A7-C3 的 40/100 判断，本批无改善。
- **76 合规**：L7 持有历史/播放/取数编排、直连 appGraph 单例；L4/L5 把"综合搜索三段组合/推荐分态"责任推给 L7，跨层接缝多处职责错位。

## 未覆盖
- 未实机运行/未看渲染与动画（工具纪律禁 dart/flutter）；联想竞态为静态代码推断。
- 未逐一核对各分类端点真实返回字段（歌手/歌词/MV 映射为基于代码 default 分支的推断，需联调验证）。
- 未跑 WCAG 对比度实测、TalkBack 读屏（沿用 A7-C3 未覆盖项）。
- 未覆盖 lib/surface 其余 14 页、L6 编排层实现（本批限 B2 范围文件）。
- 榜单 rankInfo 分页：L5 已支持 page/pageSize 透传，但 L7 只取第 1 页（已在"无分页"条覆盖）。

## 76 合规小结
- 越级：L7 直接调 L5 logic（appGraph.search/searchTyped/rank）与 L6 session（PlaybackSession/NavState），未经 L6 编排接口 → 违反 §0 分层。
- 职责错位：搜索历史持久化（应 L5/L6 storage）、综合搜索分段组合（L4 注释要求 surface 组合）、推荐分态消费（L5 契约未下沉）都堆在页面 Widget。
- 合规面：L4 端点只做单端点解析、L5 logic 门面 try/catch + Log + 缓存键 buildKey 符合分层；i18n 常量归 core/l10n 的归属正确，问题在 surface 不消费。
- 与 A7-C3 76 小结一致：主题构建在 L7 合规、消费侧 Sp.* 架空；本批补充"编排/状态/历史"在 L7 的越界证据。

---
*本文件为 B2-C3 视角完整报告， append 写入，未覆盖源码改动。*
