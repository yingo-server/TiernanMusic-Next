# B2 批 · C2 实现正确性视角 · 搜索/联想/热搜/榜单/推荐 跨层审查

> 视角：C2 实现正确性（跨层链路是否真通）。纪律：只读；证据带 `文件:行`。
> 基线：阶段 A 已修 srcappid 默认不注入、mid 默认注入、kugou_client 成功缓存判定、
> rank/recommend 空结果不固化；bA2/bA3 已知单点（search 缺 mid、suggest=RecordDatas[].HintInfo、
> hot=group{name,keywords[]}、缓存固化底层已修）不重复报。
> 审查时间：2026-11-17。范围：L7(search_page/search_tile_widgets/home_page/home_state_views) →
> L6(graph/bootstrap) → L5(search/search_typed/rank/recommend logic) →
> L4(search/search_typed/misc(rank)/recommend endpoints)。

---

## 视角 C2 · lib/logic/catalog/search_logic.dart:63 · P1 · 缓存语义/失败固化
证据：`search_logic.search()` 命中缓存直接返回，未命中 `final res = await searchSongs(...); _cache.put(key, res);` —— **无条件 put**，注释无"成功判定"。对照同批 `rank_logic.dart:54,93`（`if (items.isNotEmpty) _cache.put`）与 `recommend_logic.dart:61`（`if (res.cacheable && res.isNotEmpty)`）阶段A已修；`searchSongs(search_endpoints.dart:33-50)` 无业务成功码判定，HTTP200+status!=1/error_code!=0（如 20006/限流）或异常 catch 均返回 `const SearchResult()`（空 items）。LruCache.get(lru_cache.dart:124-134) 命中即 return，不再打网。
问题：搜索失败/空结果被写进 LruCache 并在 TTL 内固化——用户搜到一次限流空结果后，反复点搜索/重试都命中同一空缓存，永不自愈，须重启或登出；与已修的 rank/recommend 同链路行为不一致（阶段A缓存修复在搜索链路未生效）。
建议：`searchSongs` 返回带 state/成功码的结果（参 `DailyRecommendResult` 分态模式），仅在成功且非空时 `put`；或至少 `if (res.items.isNotEmpty) _cache.put(...)`，失败与空都不落缓存。
76 合规：L5 职责内（缓存策略属 logic）；但跨层接缝处 L4 未暴露成败语义，导致 L5 无法区分——属"成功/失败语义跨层丢失"，非越级依赖。

---

## 视角 C2 · lib/logic/catalog/search_typed_logic.dart:68,108 · P1 · 缓存语义/失败固化
证据：`typed()` L68 `_cache.put(key, res);`，注释明写"空结果也落缓存防重复打网"；`complex()` L108 同样无条件 put。二者调用的 `ep.searchTyped`（search_typed_endpoints.dart:66-91）与 `searchComplexV6`（降级薄委托，L100-114）均无业务成功码判定，异常/business fail 统一 `const SearchResult()`。对照 rank/recommend 已改为不固化空。
问题：分类搜索（歌单/专辑/歌手/歌词）与综合搜索把失败当空结果固化进 LruCache，形成"一次失败、长期空"；注释把该反模式当作设计意图，阶段A缓存修复在此完全未覆盖。
建议：与 search_logic 统一分态；`typed/complex` 仅在成功非空时 put；删除"空结果也落缓存防重复打网"的误导注释（失败应允许重试而非防网）。
76 合规：L5 缓存职责内；跨层接缝成败语义缺失（同前条），未越级。

---

## 视角 C2 · lib/surface/pages/search_page.dart:104-115,224-249 · P1 · 联想 Future 竞态（A7-C2 旧问题跨层复核）
证据：`_onChanged` 每次输入 `setState(() => _suggestF = se?.suggestions(t) ?? ...)`（L113），无请求序号/节流/取消；`_suggestBox` 的 `FutureBuilder(future: f)`（L226-230）直接消费该 Future。`SearchLogic.suggestions`(search_logic.dart:82-92) 直通、无 merge/版本校验；`searchSuggest`(search_endpoints.dart:52-101) 逐字符发请求、无去重。A7-C2 报的 search_page:74-97 竞态，行号漂移后（现 104-115/224-249）**机制未变**。
问题：快速连续输入时，旧关键词的联想请求若晚于新请求返回，其 Future 已被 `_suggestF` 替换——因 FutureBuilder 只绑定最新 `f`，旧结果实际不会覆盖 UI（这点比 A7-C2 描述略好）；但**每次按键都立即发一条网络请求、无节流无取消**，旧请求仍全部打网并可能因 LruCache/服务端限流挤占新请求，属真实竞态/资源浪费；且 `_doSearch`(L81-99) 只置 `_suggestF=null` 不取消在飞联想，提交后旧联想回包虽不显示但已消耗配额。
建议：`_onChanged` 加 debounce（如 250ms）+ 单调递增 requestId，FutureBuilder 内校验 id 再展示；L5 `suggestions` 增"仅最新关键词生效"的门控或取消令牌。
76 合规：竞态治理应在 L7(UI 生命周期)+L5(逻辑门控) 分层处理；当前 L7 直接裸持 Future、L5 无状态，属 UI 态管理职责未落地（非依赖越级）。

---

## 视角 C2 · lib/surface/pages/search_page.dart:81-99,271-290,450-466 · P1 · 分页缺失/加载更多未触发
证据：`_doSearch` 固定 `se?.search(q, 1)` / `typed?.typed(type, q, 1)`（L87-88，page 恒 1）；`_resultBody` 的 ListView `itemCount: items.length`（L463）无 `ScrollController`、无 onEndReached/加载更多分支；端点层 `searchSongs(search_endpoints.dart:12-14)` 与 `searchTyped(search_typed_endpoints.dart:48-51)` 均支持 page 参数，L5 缓存键含 page（search_logic.dart:42-46）——**能力具备但 L7 从不翻页**。
问题：搜索/分类搜索只展示第 1 页（30 条）；`SearchResult.total`（如实测 480）已解析返回却无任何 UI 消费，用户无法加载更多结果，长尾结果不可达。榜单详情 rankInfo 支持 page（rank_logic.dart:70-72）但首页 `_openRank`(home_page.dart:97) 只取 page=1 用于播放，也不翻页。
建议：L7 结果列表加 ScrollController，触底时 `_doSearch(q, page+1)` 追加（区分替换/累加）；或在明确产品口径前，至少展示"共 total 条，仅显示前 30 条"提示，避免误导。
76 合规：分页编排属 L7+L5；L4/L5 已就绪，缺 L7 触发——职责断在展示层，非越级。

---

## 视角 C2 · lib/surface/pages/search_page.dart:277-290,450-456 · P1 · 三态坍缩/错误态不可达
证据：三条链路全部"错误坍缩为空"：① L4 `searchSongs/searchTyped` 异常 catch 返回 `const SearchResult()`（空，非抛错）；② L5 `search_logic.search()` catch 同样返回空；③ L7 `_resultBody` 仅 `snap.hasError` 分支显示 `SearchErrorRetry`（L450-451），而上游永不抛 error，故**错误重试 UI 是死代码**——真实失败一律走到 `items.isEmpty` 的"没有找到与「x」相关的歌曲"（L456）。对照 hasError 分支与 SearchErrorRetry 定义（search_tile_widgets.dart:103-120）完整实现却无触发源。
问题：搜索失败（网络/限流/20006）被显示成"没找到结果"，用户无法区分"真没结果"与"加载失败"，重试按钮永远不出现；三态从 L4→L5→L7 中途坍缩为二态（done+空 / loading）。
建议：L4/L5 保留成败语义（见前分态建议）并向上抛或传 state；L7 据 state 分别渲染 empty/error；让 `snap.hasError` 真正可达或改用结果对象 state。
76 合规：三态语义需 L4→L5→L7 一致传递，属跨层接缝核心问题；当前坍缩源于各层只传裸列表，无越级依赖但职责链断裂。

---

## 视角 C2 · lib/core/net/endpoints/search_typed_endpoints.dart:135-152 · P1 · 字段解析错位（歌手/歌词段）
证据：`parseSearchItems` 仅对 `special`/`album` 配专用映射，`author`/`lyric`/`song` 一律落到 default=`SongBrief.fromSearchList`（L143-147）。`fromSearchList`（song_models.dart:43-77）读 `FileName/SingerName/FileHash/MixSongID`。而实测契约：歌手搜索 A1-4（TRUTH:49-52）键为大写驼峰 `AuthorName/AuthorId/Avatar`（无 FileName/SingerName/FileHash）；歌词搜索 A1-6（TRUTH:66-70）名称在 `SongName`/`Lyric` 而非仅 FileName。过滤门槛 `if (s.name.isNotEmpty)`（L150）会把歌手项全部丢弃。
问题：L7「歌手」段（`kSearchSegmentTypes` 第4项=SearchType.author）与「歌词」段走分类搜索时，歌手结果 100% 被过滤为空、歌词结果名称/字段大量错配；L7 显示"没有找到相关歌曲"，实为字段映射缺失（A1-4/A1-6 契约虽已固化在文档，但端点层未落地专用映射）。
建议：为 `author` 加 `songBriefFromSearchAuthor`（name←AuthorName、mixSongId←AuthorId、singer 留空/固定"歌手"），`lyric` 加 `songBriefFromSearchLyric`（name←SongName/FileName 兜底、hash←FileHash、时长←TimeLength）；或 L7 歌手段改走 ArtistBrief 专用模型与展示。
76 合规：字段解析属 L4 端点职责；L7 暴露了无模型支撑的分类段（职责落在端点却未实现），非越级但契约未闭环。

---

## 视角 C2 · lib/session/bootstrap.dart:216-228 · P2 · 预热形同虚设（跨层缓存键不匹配）
证据：`bootstrapSession` 里 `cacheService.prefetch([(ep: searchHot, params:{'navid':1,'plat':2}), (ep: rankList, params:{})])`（L216-226）。`CacheService.get`(cache_service.dart:113-125) 转发 `_client.request` 并落入 KugouClient 磁盘缓存，键由 `_cacheKeyOf`(kugou_client.dart:149-169) = method+base+path+`_stable(params)`+uid/token/dfid/mid 构成。而真正消费热搜/榜单的是 L5 `SearchLogic.hotSearch()`（直通 searchHot，不经缓存）与 `RankLogic.rankList()`（LruCache 内存缓存，键为 `buildKey(ns:'rank',path,pagesize...)`）——与预热的磁盘键体系完全不同。
问题：预热的磁盘结果没有任何上层读取路径：热搜 L5 明确"直通不缓存"，榜单 L5 用内存 LruCache 另起键；`CacheService` 的 hits/writes 恒 0（文件头自认未接真实计数）。故启动预热纯属额外打网，不加速热搜/榜单首屏（阶段A"缓存⊃预读统一服务"接线在本功能域未真正闭环）。
建议：让 L5 `hotSearch/rankList` 优先读 CacheService（统一键），或让 bootstrap 预热改为调用 `appGraph.rank.rankList()` / `search.hotSearch()` 写入 L5 各自的缓存；否则去掉无效预热。
76 合规：缓存归属 L4/L5，L6 只决定预测键——当前 L6 预热键与 L5 消费键分属两套体系，属跨层接缝"缓存键不一致"，非依赖越级。

---

## 视角 C2 · lib/core/net/endpoints/recommend_endpoints.dart:122-135 · P2 · 错误码键/成功码判定偏窄
证据：推荐实测（TRUTH/API_TEST_REPORT §四.2）未登录为 `errcode=200103` 且 **data 为字符串**；端点读 `errCode = safeInt(res['errcode'] ?? data['errcode'], 0)`（L122）。`dataOf`（models_util.dart:57-66）在 data 为字符串时返回空 Map，故事实上只能读顶层 `res['errcode']`——本例恰好正确。但若服务端把通用失败放在 `error_code`（搜索/榜单系惯用键，见 TRUTH §通用响应形态），本处只读 `errcode` 会漏判；且 `errMsg = safeStr(res['error'] ?? data['error'] ?? data['errmsg'])`（L123）未覆盖 `errmsg` 顶层键。
问题：推荐错误判定仅认 `errcode` 单一键，与搜索/榜单系的 `error_code` 口径不统一；若上游换键或返回 `error_code:200103`，会误当成功空列表（虽 items 空→ok(empty) 态，UI 显示"暂无推荐"而非"需登录"），三态判定不稳。属契约健壮性问题，非必然在线 bug。
建议：`errCode` 兼容 `errcode ?? error_code`；`errMsg` 兼容 `errmsg/error_msg`；保持 data 为字符串时按未登录/错误处理而非空列表。
76 合规：错误码归一化属端点层职责，合理；仅跨端点键口径不统一（接缝一致性），无越级。

---

## 视角 C2 · lib/surface/pages/search_page.dart:45-56,315-362 · P1 · 热搜功能跨层断链（端点/L5 就绪但 L7 无入口）
证据：全仓 `rg '.hotSearch('` 零调用——`SearchLogic.hotSearch()`（search_logic.dart:92-102）与 `searchHot()` 端点（search_endpoints.dart:106-140，字段解析符合实测 `data.list[].keywords[].keyword`）均实现完整却无任何消费者。搜索页空闲态 `_idleBody`（L315-362）只渲染 `_hotCategories()`，其数据源是**硬编码的 8 个前端分类词** `kHotCategories`（L45-56：华语/流行/摇滚…），并在注释里自认"前端关键词触发对应歌曲搜索；不臆造服务端分类端点"。bootstrap 还专门预热了 searchHot（bootstrap.dart:218-221），却无人读取。
问题：真实热搜榜（实测 270 条、三态可用）整条链路 L4→L5→预热都通，唯独 L7 没接——用户永远看不到真实热搜，只看到写死的 8 个通用分类词，点它们是搜"华语/流行"等宽泛词而非热搜词。这是功能断链而非字段错误（字段解析经核实正确），属"实现未接线"。
建议：搜索页空闲态增加真实热搜区块，调 `appGraph.search.hotSearch()` 展示 `data.list[].name/keywords[].keyword`，_hotCategories 作为补充或移除；让已预热的 searchHot 结果真正被消费。
76 合规：L7 展示未消费 L5 已就绪能力，属接缝断链（职责在 L7 编排）；无依赖越级。

---

## 视角 C2 · lib/surface/pages/home_page.dart:53,185-208 · P1 · 推荐三态传到 L7 后坍塌（loginRequired/error 不可辨）
证据：端点层精心定义了 `DailyRecommendState {ok, loginRequired, empty, error}` 与 `DailyRecommendResult`（recommend_endpoints.dart:24-89），L5 `recommend_logic.daily()` 返回 `Future<List<SongBrief>>` 但实际回传 `res` 对象（L67，运行时是 DailyRecommendResult）。然而 L7 `home_page.dart`：`_dailyF` 声明为 `Future<List<SongBrief>>`（L45），消费时仅 `final List<SongBrief> items = snap.data ?? const <SongBrief>[]`（L202），**全仓 L7/L6 无任何 `.state` / `.loginRequired` 读取**（rg 确认零命中）。三态分支只有 `snap.hasError`（上游不抛，死代码，同搜索页问题）+ `items.isEmpty`。
问题：分态结果对象一路传到 UI 却被当作裸 List 消费，`loginRequired`（未登录 200103）与 `error`（网络失败）与 `empty`（真空）在 UI 全部坍缩为同一句"暂无每日推荐（登录后可能可见）"（L205）。用户无法得到明确的"请登录"引导，与端点层"不再冒充空推荐"的设计意图相悖——阶段A分态修复在 L7 末端失效。
建议：L7 将 `_dailyF` 改为 `Future<DailyRecommendResult>`，`_dailySection` 按 `.state` 分别渲染（loginRequired→引导登录、error→重试、empty→空态、ok→列表），让端点分态真正端到端可见。
76 合规：三态需 L4→L5→L7 一致传递；此处 L4/L5 已分态，L7 未消费属接缝坍塌，非越级依赖。

---

## 视角 C2 · lib/surface/pages/search_page.dart:64,81-99 · P2 · 搜索历史仅内存、跨会话/账号不隔离
证据：`final List<String> _history = <String>[];`（L64）纯 State 内存，`_doSearch` 写入（L94-96）无持久化（无 settings/DAO 注入，L7 只经 appGraph 取 logic）；Page 重建/App 重启即清空，注释与 UI 却以"历史记录/清空"呈现（L370-410）。搜索缓存 L5 用 `buildKey(userid:)` 做了账号隔离（search_logic.dart:42-46），历史则无。
问题：用户搜索历史重启即丢，且换账号后仍可能在同一进程看到前账号历史（若页面未重建）——与"历史记录"语义不符。属实现层状态管理缺失（非分层违规）。
建议：历史经 settings/DAO 持久化并按 userid 隔离，登出时清（复用 logic.invalidatePrefix 模式）；或明确降级为"本次会话历史"文案。
76 合规：持久化应走 L4 storage + L5 logic，L7 只管展示；当前 L7 自持可变历史数据，略偏"UI 持有业务态"，非硬性越级但职责错位。

---

## 视角 C2 · lib/surface/pages/search_page.dart:461-466 + lib/core/net/endpoints/search_typed_endpoints.dart:164-192 · P1 · 非歌曲段点击播放必失败（模型/UI 错配）
证据：L7 五个结果分段（歌曲/歌单/专辑/歌手/歌词）统一用 `SearchSongTile`，onTap 一律 `_play(items, i)` → `PlaybackSession.instance.playAll(songs, index)`（L125-131）。但 `songBriefFromSearchSpecial`（L164-176）/`songBriefFromSearchAlbum`（L179-192）构造的 `SongBrief` **不设置 hash**（默认空），`durationSec` 塞的是曲目数（song_count/songcount），语义被偷换。
问题：用户在「歌单」「专辑」段点击任一结果，会用空 hash 调用 playAll，播放必然失败（或静默无效）；且 tile 副标题把"曲目数"显示成"Ns"时长（search_tile_widgets.dart:64-67）。分类搜索结果根本没有对应的歌单/专辑详情跳转（onAlbum 依赖 albumId，歌单段为空）。这是把异质实体硬塞进 SongBrief 模型 + 单一 tile 的跨层错配。
建议：分段结果改用各自模型（PlaylistBrief/AlbumBrief/ArtistBrief/SongBrief）与各自 tile；歌单段点击打开歌单详情、专辑段打开专辑详情，仅「歌曲/歌词」段可播放；勿用 durationSec 冒充计数。
76 合规：模型选型应在 L4 端点正确产出、L7 按类型分发 UI；当前 L4 为兼容而滥用 SongBrief、L7 一刀切播放，属跨层职责错配，非依赖越级。

---

## 视角 C2 · lib/core/net/kugou_client.dart:202-210 + lib/core/net/endpoints/search_typed_endpoints.dart:71-80 · 核查结论（非问题）· 缺参/20006
证据：历史 search 缺 mid→20006 已在网络层修复：`request()` 对非 clearDefaultParams 端点默认 `putIfAbsent('mid', session.mid.isEmpty ? '0' : session.mid)`（L208）且 `srcappid` 默认不注入（L203-205，仅 includeSrcappid 开启）。searchSong/searchSuggest/searchHot/rankList/rankAudio/recommend 声明均未设 clearDefaultParams/includeSrcappid（endpoint_registry.dart:46-65,155-171,255-260），故 mid 全程携带、srcappid 不注入；本地 Endpoint（search_typed_endpoints.dart:71-79，仅设 id/path/router）同样走默认注入。
问题：无——缺参/20006 在本批链路已真正端到端生效，不重复报单点。
建议：无需改动（保留回归断言防止 includeSrcappid 被误开）。
76 合规：默认参数注入归 L4 网络层，端点只声明差异，分层正确。

---

## 视角 C2 · lib/core/net/endpoints/search_endpoints.dart:106-140 + lib/logic/catalog/search_logic.dart:92-102 · 核查结论（非问题）· 联想/热搜字段契约
证据：searchSuggest 直接遍历 `res['data']` 数组分组、取 `RecordDatas[].HintInfo`（L77-89），与实测 TRUTH §R1-A-8（`data[]{RecordDatas[],RecordCount,LableName}`、词条在 HintInfo）一致；searchHot 取 `data.list[].{name,keywords[].keyword}`（L116-133），与实测 `data.list[]` 分组契约一致。二者类型安全用 `is Map<String,dynamic>` 守卫 + listOf（防数组当 Map）。
问题：无字段解析错误（bA2 已知底线的字段口径在本链路正确落地，不重复报）。仅 searchSuggest 的 `LableName` 作 type 直传（如 'MV'/'专辑'），L7 未据此分类型展示——轻微信息未用，非 bug。
建议：无需改字段解析；(可选) L7 按 type 给联想项加分类图标。
76 合规：字段解析归 L4，正确。

---

## 本视角结论

B2「搜索/联想/热搜/榜单/推荐」C2 实现正确性跨层审查完成，落盘 **12 条结论（含 2 条核查通过）**。核心判断：**L4 端点字段解析与 L4 网络层缺参修复（mid/srcappid）基本正确且底层缓存修复已生效；但阶段A的多项修复在 L5→L7 接缝处未闭环，本功能域"半通"。**

严重度分布：
- **P1×8**：搜索/分类搜索失败固化进 LruCache（search_logic:63 / search_typed_logic:68,108，与已修的 rank/recommend 不一致）；联想 Future 无节流无版本门控（search_page:104-115）；搜索/榜单分页 L7 从不翻页（search_page:81-99,463）；搜索三态坍缩致错误重试成死代码（search_page:450）；歌手/歌词段字段映射缺失致结果恒空（search_typed_endpoints:135-152）；热搜全链就绪但 L7 零接线、用硬编码分类词替代（search_page:45-56,315-362）；推荐四态结果传到 UI 被当裸 List 消费而坍塌（home_page:53,202）；非歌曲段套 SongBrief+统一 tile 致点击播放必失败（search_page:461-466）。
- **P2×4**：bootstrap 预热键与 L5 消费键两套体系、预热无效（bootstrap:216-228）；推荐错误码只读 errcode 未兼容 error_code/errmsg（recommend_endpoints:122-135）；搜索历史仅内存不持久化不隔离（search_page:64）；(核查通过不计) 实际 P2 为 3 条 + 2 条核查通过条目。

跨层模式归纳（供主会话比对）：
1. **失败语义跨层丢失**是本批最大系统性问题：L4/L5 普遍用 catch→空结果代替分态，导致 L7 无法区分 error/empty，三态一致性与阶段A分态修复在搜索/推荐末端双双失效（对应 P1: 缓存固化、三态坍缩、推荐坍塌）。
2. **L7 编排缺位**是第二大类：热搜、分页、分段差异化 UI 三项均为"下层能力就绪、L7 未消费/未分发"（对应 P1: 热搜断链、分页、播放错配）。
3. **阶段A缓存修复覆盖不均**：rank/recommend 已正确"空不落缓存"，search/searchTyped 仍无条件 put（同域不同实现）。
4. 底层已修项（mid/srcappid 20006、kugou_client 成功缓存判定、suggest/hot 字段口径）经核实**确实生效**，未重复报。

## 未覆盖

- 未跑 dart/analyze/test/门禁（工具纪律禁止），所有结论为静态代码+契约文档交叉取证，未做运行时验证；"错误态 UI 死代码""播放必失败"等为逻辑推导，建议主会话修复时补最小回归。
- 未逐行审 `search_tile_widgets.dart` 全部叶子样式、`home_state_views.dart` 三态组件实现（仅确认存在与语义，属纯展示、无数据逻辑，MD3/视觉归 B6/C1）。
- 未审 `graph.dart` 全量（仅确认 search/rank/recommend/searchTyped 单例字段装配齐全，bootstrap 已注入，无缺失）。
- 分类搜索使用本地 `Endpoint`（router complexsearch.kugou.com）的签名/默认参数端到端是否真的成功（A1-4/A1-6 段实测不可达 caveat），受"禁止联网"限制未验证，仅按文档口径静态判断。
- 榜单 `rankInfo` 的 `SongBrief.fromRankAudio` 字段映射未逐字段复核（归 A3 端点域，本视角只审到 L5/L7 分页与三态）。

## 76 合规小结

- **依赖方向/层归属**：本批 L4 端点、L5 logic、L6 session、L7 surface 依赖方向均单向向下，无 Flutter import 下沉、无反向依赖、无 IO 直连越级；端点一文件一模块、域名白名单守住——架构主干合规。
- **职责错位（非越级）集中 3 处**：① L7 自持搜索历史可变业务态（应下沉 L5+L4 持久化）；② L4 为兼容把歌单/专辑/歌手硬塞 SongBrief，L7 再一刀切播放，模型职责错配；③ 三态/失败语义在 L4→L5→L7 逐级坍缩，属"各层只传裸列表、无人持有状态契约"的接缝职责缺失。
- **接缝一致性**：阶段A修复在本功能域覆盖不均（rank/recommend 修了、search/typed 未修；端点分态了、UI 未消费；预热键与消费键不一致）——是本批 76 视角下最需注意的"跨层接缝不闭合"。
- 结论：**无硬性越级/反向依赖（0 架构级 P0/P1）**，问题集中在实现正确性与接缝闭合，非分层结构违规。

## 计数更正（append，不覆盖上文）

上文「本视角结论」开头的条目计数有笔误，以本条为准：正文共 **14 个小节 = 问题 12 条 + 核查通过 2 条**；其中问题 **P1×9、P2×3**。
- P1×9 = 缓存固化(2: search_logic / search_typed_logic) + 联想竞态 + 分页缺失 + 三态坍缩 + 字段错位(歌手/歌词) + 热搜断链 + 推荐三态坍塌 + 非歌曲段播放错配。
- P2×3 = 预热失效 + 推荐错误码偏窄 + 搜索历史不持久化。
- 核查通过×2 = mid/srcappid 20006 已修复、联想/热搜字段契约正确。
上文 P1/P2 分类条目本身均有效，仅总数描述需按此更正。
