# B2 批 · C1 架构合规视角 · 搜索/联想/热搜/榜单/推荐

> 范围：L7 search_page / search_tile_widgets / home_page / home_state_views → L6 graph / bootstrap → L5 search_logic / search_typed_logic / rank_logic / recommend_logic → L4 search_endpoints / search_typed_endpoints / recommend_endpoints / misc_endpoints / endpoint_registry
> 只读审查（file_read + rg/wc），未改任何源码。时间戳见各条。

## 2026-11-17 07:2x · 首轮（完整跨层追踪）

## <视角 C1> · lib/core/net/endpoints/misc_endpoints.dart:62,85,129,38 + endpoint_registry.dart:155-171 · P0 · 端点分文件（§0-6）
证据：`lib/core/net/endpoints/` 下无 `rank_endpoints.dart`（目录清单 27 个文件，ls 全量）；`misc_endpoints.dart` 同时承载 `krcDecode`(:38)、`rankList`(:62)、`rankInfo`(:85)、`lyricSearch`(:129)、`lyricDownload`(~:198)，文件头注释自称「其他端点封装（rank / lyric / krc 解码）」；`endpoint_registry.dart` 声明 3 个 rank 端点 `rank_list`(:156)/`rank_audio`(:164)/`rank_info`(:170)；L5 `rank_logic.dart:5` 与 `:14-15` 均从 bridge_core 导出该 misc 集合取 `rankList/rankInfo`。
问题：榜单端点仍混装在 misc 模块（rank+lyric+krc 三域同文件），A3/C1 曾报的「misc 混装」未在阶段 A 修复，跨端点替换/单测粒度不可分。
建议：新建 `lib/core/net/endpoints/rank_endpoints.dart`（搬 `rankList/rankInfo` 与 RankBrief 解析），`lyric_endpoints.dart`（搬 lyricSearch/lyricDownload），`krc_codec.dart`（搬 krcDecode+kKrcXorKey）；`misc_endpoints.dart` 降为纯聚合/删除；在 `bridge_core.dart:133-134` 的导出白名单里同步改名（保持单一出口）。
76 合规：违反 §0-6「core/net/endpoints/ 每端点一 dart 模块」。

## <视角 C1> · lib/surface/pages/search_page.dart:65,68,84-115 · P0 · 状态机归属（跨层）
证据：`_history`(:65) 搜索历史、`_suggestF`(:69) 联想 future、`_resultF`(:68) 结果 future、`_segment`(:67) 分段全部是 L7 `State` 私有字段；L5 `search_logic.dart` 全文无 history/分页状态方法（只有 search/suggestions/hotSearch/invalidatePrefix）；L4 无搜索历史存储端点/DAO；L6 `graph.dart` 的 AppGraph 只有 logic 单例字段（:120-152），无 search session/状态容器。
问题：搜索历史与联想/结果/分段状态机整体驻留在 L7 Widget，既不持久化（进程重启即丢），也无 L5/L6 状态归属；与「session 是 surface 的底层、surface 只能消费快照」的契约相悖。
建议：新增 L5 `SearchHistoryLogic`（或复用 settings/DAO 持久化，参照 `lib/core/database` 既有 DAO 模式）+ L6 `SearchSession`（暴露 `history`、`suggestions`、`results` 快照 + 意图方法），L7 改为 `ref.watch`/provider 消费快照，历史与分页状态不再由 Widget 自持。
76 合规：违反 §0-4「每层只依赖其下层经桥暴露的门面」与 §0-8「播放/队列/缓存类状态不得在 L6 之外自建」的同源要求；L7 自建状态机属职责越界。

## <视角 C1> · search_page.dart:87-88 / home_page.dart:54-56,96 · P1 · 跨层接缝（L5 分页能力无消费方）
证据：L4/L5 全链支持分页——`search_logic.dart:39 search(keyword,int page,{pageSize=30})`、`search_typed_logic.dart:42 typed(type,kw,int page,...)`、`rank_logic.dart:66 rankInfo(int rankId,{page=1,pageSize=30})`、`recommend_logic.dart:40 daily(int page,...)`；而 L7 调用一律写死 1：`search_page.dart:87 se?.search(q, 1)`、`:88 typed?.typed(type, q, 1)`；`home_page.dart:55 g.recommend?.daily(1)`、`:97 rk.rankInfo(rank.rankId)`（不传 page）。
问题：分页参数在 L5/L4 完整实现却在 L7 接缝处被掐断为 1，搜索/榜单/推荐永远只有第一页，分页能力跨层无效。
建议：L5 门面向上暴露分页意图（L6 session 持有当前 page），L7 列表滚动到底触发 `loadMore`，或至少将「加载更多」入口下沉到 L6 快照字段。
76 合规：违反 §0-4 门面逐层透传（同层内引用合法但接缝参数被丢弃）。

## <视角 C1> · lib/logic/catalog/recommend_logic.dart:40 + lib/core/net/endpoints/recommend_endpoints.dart:29,44-56 · P1 · 状态信息跨层丢失（三态）
证据：L4 定义 `enum DailyRecommendState { ok, loginRequired, empty, error }`(:29) 与 `DailyRecommendResult extends ListBase<SongBrief>`(:38) 带 `.state/.loginRequired/.cacheable`(:56)；L5 `recommend_logic.dart:40` 签名降级为 `Future<List<SongBrief>> daily(...)`，返回实际是 DailyRecommendResult 但静态类型被抹平，注释自称「后续 UI 可直接从结果取 .state」却未提供出口；L7 `home_page.dart:54` 消费 `Future<List<SongBrief>>`，:200 空态写死文案「暂无每日推荐（登录后可能可见）」。
问题：L4 已显式区分「需登录/真空/失败」三态，经 L5 门面降级后 L7 全部退化为同一句「暂无」文案，200103（未登录）与网络失败在首页不可区分 —— 跨层状态机在接缝处被吞。
建议：L5 `daily` 返回类型改为 `Future<DailyRecommendResult>`（或增开 `dailyDetailed()`），L6 快照携带 `state`，L7 按 state 渲染「登录后可见 / 暂无 / 加载失败+重试」三种态。
76 合规：违反 §0-4 门面契约一致性（类型信息逐层应保留或显式升级）。

## <视角 C1> · lib/session/bootstrap.dart:217-223 + lib/core/net/endpoints/misc_endpoints.dart:72 · P1 · 死预读 / 预读键不匹配
证据：`bootstrap.dart:217` `cacheService.prefetch([...])` 预读 `EndpointRegistry.searchHot`(:219, params {navid:1,plat:2}) 与 `EndpointRegistry.rankList`(:222, params `{}`)；`misc_endpoints.dart:72` 实际请求 `rankList` 用 params `{plat:2, withsong:1, parentid:0}`，键不同 → L2 缓存键不一致；L2 由 `client.request` 统一缓存（`lib/core/cache/cache_service.dart:110-129` 注释「get() 与 prefetch() 走完全相同路径」），而 L5 `rank_logic.dart:38` 用的是**独立** `LruCache<String,dynamic>`（bootstrap.dart:90 注入），两者非同一缓存表。
问题：榜单预读的请求参数为空（缺 plat/withsong/parentid，接口必参缺失），且 L5 榜单缓存与 CacheService 不共享 → 预读对首页榜单零收益；searchHot 预读更是无任何消费方。
建议：bootstrap 预读参数与 `misc_endpoints.dart` 实际请求参数对齐并从同一处导出（单一常量），或删除 rankList 预读；榜单缓存改为走 CacheService（客户端 L2）而非 logic 私有 LruCache，确保预读可被命中。
76 合规：违反 §3「预读是 CacheService 的写入策略」的前提——预读键必须与实际读键同源。

## <视角 C1> · lib/logic/catalog/search_logic.dart:89 · P1 · 零调用符号 / 功能链在 L7 断裂（热搜榜）
证据：`SearchLogic.hotSearch()`(:89) 全仓零调用方（rg 全仓仅定义处）；`search_hot` 端点（`search_endpoints.dart:113`）+ `EndpointRegistry.searchHot`(:61) 亦只被该方法与 bootstrap 预读引用；L7 `search_page.dart` 无热搜区（idle 态只有 `kHotCategories` 假分类 :45 与 `_historySection`），`home_page.dart` 三个区块为每日推荐/推荐歌单/排行榜，无热搜。
问题：本批功能清单里的「热搜」在 L7 零 UI 出口——L4/L5 已就绪但接缝断在 L7/L6，功能等于不存在。
建议：在 L7 搜索页 idle 态新增「热搜榜」区块，数据经 L6（新增或复用 search session 快照）取 `appGraph.search.hotSearch()`，并把 `kHotCategories`（前端造词）与真实热搜二选一或明确分栏。
76 合规：违反 §0-4 门面须有真实调用链（门面存在但跨层无出口）。

## <视角 C1> · lib/core/net/endpoints/search_typed_endpoints.dart:74-79 + endpoint_registry.dart:51,169-171 · P1 · 端点声明双来源 / 死声明
证据：`search_typed_endpoints.dart:74-79` 为非 song 的 5 类分类搜索**本地** `const Endpoint(id:'search_${type.name}', path:..., router:'complexsearch.kugou.com')` 声明，不在 EndpointRegistry（文件头注释自承「本文件不注册 EndpointRegistry」）；`endpoint_registry.dart:51 searchComplex`(:52) 与 `:169 rankInfo`(:170) 全仓零调用（rg 无引用），其中 `searchComplex` 对应上游已实测不可达（ec=152，见 search_typed_endpoints.dart:106 注释），`rankInfo` 已被实测判定只回 3 首预览、改走 rank_audio（endpoint_registry.dart:159-163 注释）。
问题：端点声明存在注册表与端点文件两套真源（bootstrap 预读走注册表，实际请求走端点文件），且注册表里留着 2 个已知不可用/已被替代的死声明。
建议：分类搜索 6 类端点统一在 EndpointRegistry 声明（含 router/tid），端点文件只做封装；删除 `searchComplex` 与 `rankInfo` 死声明并同步修正相关注释。
76 合规：违反 §0-6「每端点一模块、参数多参不缺参」的单一声明真源要求。

## <视角 C1> · lib/logic/catalog/rank_logic.dart:5,14-15 · P2 · 同名符号双重导入
证据：`rank_logic.dart:5` `import '../../bridges/bridge_core.dart' as misc show rankInfo, rankList;` 与 `:9-15` `import '../../bridges/bridge_core.dart' show ... rankInfo, rankList;` 同时存在；调用处 :52 `misc.rankList(_client)`、:91 `misc.rankInfo(...)`。
问题：同一 bridge 导出符号以「前缀 + 无前缀」两条 import 引入，符号解析靠前缀区分，易在后续改动中造成歧义/误用。
建议：只保留一条 import（保留 `as misc` 或统一为无前缀），调用处统一。
76 合规：符合桥通道要求，但违反「单一真源/无冗余引用」整洁性（§0-1 精神）。

## <视角 C1> · lib/surface/pages/search_page.dart:6,34-40,45 · P2 · L7 直接持有 L4 领域枚举 + 前端造词分类
证据：`search_page.dart:6` `import '../../bridges/bridge_core.dart' show SearchType;`（SearchType 定义在 L4 `search_typed_endpoints.dart:23`）；`:34-40` `kSearchSegmentTypes` 在 L7 硬编码 5 类映射（song/special/album/author/lyric），**缺 L4 枚举中的第 6 类 `SearchType.mv`**；`:45 kHotCategories` 是 8 个前端写死的「华语/流行/摇滚…」关键词，注释自承「不臆造服务端分类端点」。
问题：搜索分类的领域知识（六类 SearchType）上浮到 UI 且漏接 mv 一类；另存在「前端造词分类」与 L4 真实热搜（searchHot）两套并行的「热门」语义，来源分裂。
建议：分段与类型的映射下沉到 L5（logic 暴露 `List<SearchSegment>`，含 type+label+i18n key），L7 只渲染；`kHotCategories` 改为由 L5 热搜/分类数据驱动或明确标注为「本地标签」。
76 合规：违反 §0-4（L7 不应直接依赖 L4 端点域枚举，且经 bridge_core 越层暴露了端点域类型）。

## <视角 C1> · lib/surface/pages/home_page.dart:186-206,230-260,268-300 · P2 · 三态判定落在 L7
证据：首页三区块各自 `FutureBuilder` 自行判 `connectionState!=done → 骨架`、`hasError → 错误+重试`、`items.isEmpty → 空态`（:190/196/202 等），三态语义散在 L7；`_reload()`(:64) 一次重载全部三区块；L5/L6 未提供任何首页聚合快照或状态枚举。
问题：首页三态（loading/empty/error）与重试粒度由 L7 决定，L5/L6 无聚合编排（无 HomeSession/首页快照），每次重试都把每日推荐/歌单/榜单三块一起重打。
建议：在 L5 增加首页聚合门面（返回带 state 的三区块结果），L6 暴露 HomeSession 快照与 per-section reload 意图，L7 只按 state 渲染。
76 合规：违反 §1「L6 session 编排会话层」的职责划分（跨层编排缺位，落到 L7）。

## <视角 C1> · search_page.dart(22 处) / home_page.dart(27) / search_tile_widgets.dart(4) / home_state_views.dart(1) · P2 · i18n 归口
证据：4 个 L7 文件硬编码中文字面量合计 54 处（rg 统计，如 `search_page.dart:29 hintText:'搜索歌曲、歌单、歌手'`、`:379 '历史记录'`、`:400 '清空'`、`home_page.dart:196 '每日推荐'`、`:261 '排行榜'`、`home_state_views.dart:57 '重试'`）；`lib/surface/l10n/s.dart` 的 `S.of(ctx).t(key)` 门面存在，但这两个页面零调用（rg `S.of` 仅命中 ykg_sheet/login_sheet/player_page）；`lib/l10n/app_zh.arb` 共 57 键，其中与本批相关仅 `"search"`(:7)，无「热门分类/历史记录/每日推荐/排行榜/搜索失败/重试」等键。
问题：阶段 A「i18n 接线」成果未覆盖搜索/首页两页，本批 54 处文案绕过 S 门面直接硬编码；切语言时这两页仍固定中文，且 arb 无对应键。
建议：在 arb 补齐本批所需键（10 语）→ 重跑 `tool/gen_i18n.py` 同步 L4 `core/l10n/strings.dart` → 两页改用 `S.of(context).t(...)`（含 L7 顶部常量 `kSearchSegments`/`kHotCategories` 的标签改由 arb 驱动）。
76 合规：符合 §5「l10n 常量表在 L4」的归口方向，但当前违反 §0-9/阶段 A 接线要求（L7 绕过门面硬编码）。

## <视角 C1> · 全部目标文件 · P2 · 1500 行门禁
证据：wc 结果——search_page.dart 475、search_tile_widgets.dart 120、home_page.dart 436、home_state_views.dart 78、graph.dart 151、bootstrap.dart 297、search_logic.dart 114、search_typed_logic.dart 131、rank_logic.dart 113、recommend_logic.dart 82、search_endpoints.dart 141、search_typed_endpoints.dart 193、recommend_endpoints.dart 143、misc_endpoints.dart 237、endpoint_registry.dart 503。
问题：无。
建议：无需拆分（仅 endpoint_registry.dart 503 行最接近，注意后续新增端点声明宜分组）。
76 合规：符合 §0-5。

## <视角 C1> · 六桥通道全链路（L7→L6→L5→L4） · 合规项
证据：L7 仅经 `bridge_session`（`appGraph`：`search_page.dart:8,10`、`home_page.dart:7-8`）取 logic 单例，并从 `bridge_logic` 取模型与 Log（`search_page.dart:5-6`、`home_page.dart:5`）、从 `bridge_core` 取 `SearchType`；全仓 `rg 'net/endpoints/'` 显示端点文件**只被 bridges 导出**（bridge_core.dart:100,119,133,137,165 等），无 L5/L6/L7 直连 endpoints；L5 四个 logic 文件全部经 `bridges/bridge_core.dart` 取端点函数（search_logic.dart:10-20、rank_logic.dart:5,9-15、recommend_logic.dart:10-16、search_typed_logic.dart:10-15），无 surface/flutter import；L6 graph.dart/bootstrap.dart 经 bridge_core + bridge_logic 装配，未直接 import logic 文件路径。
问题：无（唯一注意点见「L7 直接持有 L4 SearchType」条）。
建议：保持；后续新增搜索/榜单能力一律先经 L5 门面 + L6 快照。
76 合规：符合 §0-1/§0-4/§0-3（无影子桥，桥目录唯一）。

## <视角 C1> · 桥日志与 try/catch（L4→L5→L7） · 合规项
证据：L4 端点函数全部 try/catch + Log（`search_endpoints.dart:13,52,116`、`search_typed_endpoints.dart:64,120,142,160,180`、`recommend_endpoints.dart:88,136`、`misc_endpoints.dart:41,62,85,129`）；L5 每个公开方法 try/catch + Log（`search_logic.dart:47,76,89,103`、`search_typed_logic.dart:60,94,121`、`rank_logic.dart:40,70,99`、`recommend_logic.dart:41,74`）；L7 页面回调同样包 try/catch + Log（`search_page.dart:80,95,118,126,132`、`home_page.dart:50,70,80,93,105,113`）。
问题：无（缺失的是覆盖面而非日志纪律：见「热搜榜零出口」「分页无消费方」两条）。
建议：保持现有 try/catch + Log 密度。
76 合规：符合 §0-2。

## 本视角结论
1. **P0 两项**：(a) 榜单端点仍混装 `misc_endpoints.dart`（rank+lyric+krc），`rank_endpoints.dart` 不存在，§0-6 未修复；(b) 搜索历史/联想/结果/分段状态机整体住在 L7 Widget（L65/L68），L5/L6 无归属、无持久化。
2. **P1 五项**：分页能力在 L7 接缝被掐死为 page=1；每日推荐三态（loginRequired/empty/error）在 L5 门面降级为 `List<SongBrief>` 后被 L7 吞成同一句空态文案；bootstrap 预读键与实际请求参数不一致且 logic 用独立 LruCache → 榜单预读零收益；热搜榜 L4/L5 就绪但 L7 零出口（`hotSearch()` 全仓零调用）；分类搜索端点声明双来源（注册表 vs 端点文件本地 Endpoint）+ 注册表 2 个死声明。
3. **P2 四项**：rank_logic 同名符号双 import；L7 直接持有 L4 `SearchType` 且漏接 mv 类、前端造词分类与真实热搜双源；首页三态判定在 L7 且重试粒度为全页；本批 54 处中文硬编码绕过 `S.of` 且 arb 无对应键。
4. **合规确认**：六桥通道无越级直连（端点仅经 bridge 导出）、四层 try/catch+Log 纪律到位、1500 行门禁无风险。

## 未覆盖
- 未跑 `dart analyze`/门禁脚本（按纪律），故无编译期佐证；`rank_logic` 双 import 是否触发 analyzer 歧义警告未验证。
- 未审 L4 `kugou_client.dart` 的 L2 缓存键实现细节（仅按 `cache_service.dart` 注释与调用形态推断「预读键=请求键」）。
- 未审 `lib/core/database` 是否已有可复用的搜索历史表（仅确认 `search_logic.dart` 未使用任何 DAO）。
- 未审 10 语 arb 全量键覆盖与 `tool/gen_i18n.py` 生成流程（仅统计键数与缺键）。
- 未覆盖 B2 之外的搜索相关页面（library_page/playlist_page 的搜索入口）与其他视角（C2 正确性、C3 痛点）。

## 76 合规小结
- 违反 §0-6：榜单端点仍混装 misc 模块；分类搜索端点声明双来源（1 项 P0 + 1 项 P1）。
- 违反 §0-4：L7 自建搜索历史/联想/分段状态机（P0）；L5 分页参数在接缝被丢弃、每日推荐 state 在接缝被吞（P1 ×2）；L7 直接依赖 L4 `SearchType`（P2）。
- 违反 §1（L6 编排职责）：首页三态/重试粒度落在 L7（P2）。
- 违反 §3（预读是 CacheService 写入策略）：预读键与实际读键不同源、logic 私有 LruCache 与 CacheService 不共享（P1）。
- 符合 §0-1/§0-2/§0-3/§0-5：无越层 import、无影子桥、try/catch+Log 齐备、无超 1500 行文件。
- 违反阶段 A「i18n 接线」成果延续性：54 处硬编码中文、arb 缺键（P2）。
