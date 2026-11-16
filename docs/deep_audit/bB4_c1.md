# B4 · C1 架构合规视角 · MV 播放跨层审查

> 审查时间戳：2026-11-17 07:42:41 LCL（追加块 1）
> 范围：L7 mv_page/player_page → L6 module_registry/graph/bootstrap → L5 mv_logic/playback_service → L4 mv_endpoints/mv_anonymous
> 依据：docs/DEEP_AUDIT_PHASE_B_PLAN.md §1-2、docs/SEVEN_SIX_RULE.md（76 原则 V2）
> 纪律：只读（file_read + rg/wc），未改源码、未跑分析器/门禁/网络。

---

## C1 · lib/surface/pages/mv_page.dart:14-19 + lib/session/module_registry.dart:15-23 + lib/session/bootstrap.dart:265-282 · P2 · 模块注册接缝（阶段A修复验证）
证据：L7 `registerMvModule()` 直接 `ModuleRegistry.instance.install(MvPageModule())`，无「id 存在即 return」守卫（注释明示旧守卫已删）；L6 `install(SurfaceModule m){ _modules[m.id] = m; }` 为重复 id 直接覆盖、幂等；bootstrap 占位 `_PlaceholderModule(id)`（enabled=false）在 `bootstrapSession` 内 install。时序：bridge_surface.installServices:35-44 先 `await session.bootstrapSession(...)`（装占位）再 `await root.installServices`（→registerModules→registerMvModule 覆盖真模块）。shell.dart:30、player_page.dart:229 均调用 registerMvModule（幂等）。
问题：阶段A「占位抢占」修复在 L7 守卫、L6 覆盖语义、bootstrap→register 时序三处真正配合生效，占位不会再抢占；但 L7 绕过 bridge_session 专门提供的 `moduleRegistry()` 门面（bridge_session.dart:41）直接取 `ModuleRegistry.instance`。
建议：L7 统一改走 `moduleRegistry().install(...)`，与六桥门面保持一致（只写建议，不改）。
76 合规：符合第1/4条（经桥 export 的 ModuleRegistry 属合法门面，无反向依赖）；门面函数未被使用属接缝不一致，记 P2。

## C1 · lib/session/bootstrap.dart:265-282 · P2 · 占位模块重装隐患
证据：`bootstrapSession()` 每次调用都对 11 个 moduleIds install `_PlaceholderModule`（enabled=false），注释「独立 UI 模型注册真实模块时按 id 覆盖」；正常单次启动时序为先占位后覆盖。
问题：若 bootstrapSession 被二次调用（热重启/重试），占位会以 enabled=false 覆盖已注册的真 MV 模块，导致 MV 模块失活；当前启动路径未触发，属潜在隐患。
建议：占位 install 加「仅当 id 未注册时安装」判断，或将占位注册移出可重入的 bootstrapSession（只写建议，不改）。
76 合规：符合第5条（L6 注册表热插拔）；重入覆盖属会话编排健壮性问题，非越级，记 P2。

## C1 · lib/surface/pages/mv_page.dart:115-137 + lib/logic/catalog/mv_logic.dart:89-132 · P2 · 职责错位（两段式归位）
证据：L5 `MvLogic.videoIdOfSong(aid)`→`getMvBySong`、`qualities(videoId)`→`getVideoQualities`、`playUrl(videoId,requestedId)`→`qualities`+`getVideoUrl(q.hash)`，三段封装入参均为数字 videoId，协议/签名/两段式全在 L5/L4。L7 `_load()` 只发意图（95-137）：`videoIdOfSong`→`qualities`→`playUrl`，未处理协议。但「最低档优先 ld→sd→按 size 取最小、避开 VIP 高画质档」的选档决策写在 L7（115-136）。
问题：两段式归位正确、L7 不碰协议；但选档策略属业务决策，停留在 L7，与 L5 `playUrl` 自带的降档策略（按 size 降序 + sublist 从 requestedId 起降档）两层各自决策、职责重叠（语义叠加影响属 C2 范畴，此处仅记架构边界）。
建议：把「选最低可播档」下沉为 L5 `playUrl` 的 `preferLowest` 参数/默认策略，L7 仅传意图（只写建议，不改）。
76 合规：符合第2/4条（L7 不直连协议、依赖方向正确）；L7 承载业务选档属第1条「L7 仅 UI 控件」的轻度越位，记 P2。

---

## C1 · lib/surface/pages/mv_page.dart:4-5 + 全 surface 目录 · P2 · 六桥通道（阶段A前直连修复验证）
证据：`rg 'core/net|mv_endpoints|getMvBySong|getVideoQualities|getVideoUrl|KugouClient\(|HttpClient|dart:io'` 在 mv_page.dart、player_page.dart 全部 NONE；L7 仅 `import '../../bridges/bridge_session.dart' show appGraph, ModuleRegistry, NavEntry, SurfaceModule`，数据经 `appGraph?.mv`（95）取门面。bridge_session.dart:24 `export bootstrap.appGraph`、bridge_core.dart:26-27/163-164 导出 MvBrief/MvQuality/MvPlayResult 与 getMvBySong/getVideoQualities/getVideoUrl。L5 mv_logic.dart:9-17 经 bridge_core as mv 取门面，无 core/net 直连。
问题：阶段A前「L7 直连 core/net mv_endpoints」在本批 9 文件及全 surface 页中均已消除，六桥通道合规；无新增直连。
建议：保持现状；门禁中固化「surface 不得 import core/net/endpoints」断言防回归（只写建议，不改）。
76 合规：符合第1/3/4条（唯一合法跨层通道、无影子桥、无反向依赖）。

## C1 · lib/surface/pages/mv_page.dart:3,277,283,292 · P2 · video_player 边界
证据：L7 直接 `import 'package:video_player/video_player.dart'`，Widget 树内用 `VideoPlayer(c)`、`VideoProgressIndicator`、`VideoPlayerController.network(url)`（约140-170）做 initialize/setLooping/play/pause/dispose。76 原则 §0 第9条「能用成熟库就用成熟库（video_player）」；§1 L7 职责「只有 Widget 与 ThemeData」。
问题：video_player 属成熟 UI 播放器库，控制器生命周期写在 StatefulWidget 内，符合「播放器 Widget 属 UI」边界；但网络 URL 的 http→https 升级（约143-150）与协议校验属数据处理逻辑，落在 L7 略越「仅画控件」边界（不构成 P0/P1）。
建议：URL 规范化/协议升级下沉到 L5 或 L4；保留 VideoPlayer 渲染在 L7（只写建议，不改）。
76 合规：符合第9条；第1条「L7 仅 UI」部分擦边，记 P2。

## C1 · lib/core/net/endpoints/mv_anonymous.dart:1-227 · P1 · 死代码 + 桥日志职责
证据：全仓 `rg 'registerDevice|anonymousPlayUrl|ParsedPlayUrlShim'` 除本文件自身外，仅在 endpoint_registry.dart:322/332/338/344 的注释与 Endpoint 声明出现，**无任何可执行调用点**（L5/L6/L7 均未调用）。该文件 227 行（<500），全字段容错、每函数 try/catch + `Log.e('ep.mv.anon')`（48/128/222 等）。try/catch + Log 合规。
问题：阶段A前的匿名链（registerDevice/anonymousPlayUrl/ParsedPlayUrlShim）仍是死代码——整个 227 行模块及其两个 Endpoint 声明零调用，属未接线孤岛，长期维护成本与端点契约漂移风险（platid 2 vs 上游 1 等"待实测"注释悬置）。
建议：接入 L5 匿名音质降级链或显式标注 @Deprecated 待删；接线时经 bridge_core 暴露门面，禁止上层直连（只写建议，不改）。
76 合规：try/catch+Log 符合第2条；零调用死代码不构成越级，但违背"功能可达"精神，记 P1。

## C1 · 全仓 wc -l（本批9文件）· P2 · 1500 行门禁
证据：mv_page 322 / player_page 516 / module_registry 83 / graph 151 / bootstrap 297 / mv_logic 143 / playback_service 378 / mv_endpoints 431 / mv_anonymous 227，最大 player_page.dart 516 行，全部远低于 1500。
问题：本批 9 文件均不触发按功能拆分门禁；无超标。
建议：无需动作（只记事实）。
76 合规：符合第5条（1500 行门禁）。

---

## C1 · lib/logic/player/playback_service.dart:283-334 + lib/session/playback_session.dart:223 · P2 · L5 双 MV 链职责边界
证据：存在两条 MV 取链——① L5 `MvLogic`（videoIdOfSong/qualities/playUrl，供 L7 MV 页显式查看）；② L5 `PlaybackService.resolveMvAudioFallback`（getMvBySong→getVideoQualities→getVideoUrl，由 L6 playback_session.dart:223 在播放失败兜底时调用）。两条链都从 L4 取 MV 端点，但分属两个 L5 门面，各自重复实现「ld/sd 优先选最低档」逻辑（mv_page.dart:115 / mv_logic.dart:99 降序 / playback_service.dart:305 order 列表）。
问题：同一 MV 两段式协议在 L5 有两处平行封装（MvLogic 与 PlaybackService），选档策略三处各写一遍（L7 两处 + L5 两处），违反单一职责、易漂移；属架构职责重叠，非越级（上层仍经桥、方向正确）。
建议：抽 MV 取链公共 L5 组件（如 videoIdOfSong/qualities/选档统一到 MvLogic），PlaybackService 兜底改为委托 MvLogic 门面（只写建议，不改）。
76 合规：均在第5层内、经桥，符合第4条依赖方向；重复封装属第4条"职责"软违反，记 P2。

## C1 · lib/core/net/endpoints/mv_endpoints.dart:1-431 · P2 · 端点层一模块一端点合规
证据：mv_endpoints.dart 431 行，含 mvDetail/videoDetail/videoUrl 三个 MV 相关端点的封装（getMvBySong/getVideoQualities/getVideoUrl）+ MvBrief/MvQuality/MvPlayResult 模型，每函数 try/catch+Log('ep.mv')，参数多参齐备（getVideoQualities body 含 appid/clientver/clienttime/mid/uuid/dfid/token/key/show_resolution/data），只连酷狗官方域名（openapi.kugou.com / kmr.service.kugou.com / trackermv.kugou.com），符合 §0 第6条。注意：文件头注释仍写「每端点一 dart 模块」，实际 3 端点合一文件（<500 行门禁允许，与 §0 第6条字面"一端点一文件"有出入，但为 431 行整体，不触发拆分）。
问题：端点合一与契约「每端点一 dart 模块」字面不符，但受 1500 行门禁约束（拆出 mv_anonymous 后 431 行），属可接受的历史组织方式，不构成越级。
建议：如严格遵循第6条可按端点再拆，但会新增小文件；当前不强制（只写建议，不改）。
76 合规：符合第6条（官方域名、参数齐备、try/catch+Log）；"一端点一文件"字面例外，记 P2。

---

## 本视角结论
阶段A「MV 四重断点」修复在架构合规视角下**跨层接缝基本打通**：
1. **模块注册**（重点核1）：L7 守卫已删、L6 install 为重复 id 覆盖、bootstrap 先占位后 registerMvModule 覆盖，时序（bridge_surface:35-44）正确，占位不再抢占——修复真实生效。仅余「重入 bootstrapSession 占位反覆盖」潜在隐患（P2）。
2. **两段式归位**（重点核2）：videoIdOfSong→qualities→playUrl 三段封装在 L5 MvLogic 正确，入参均数字 videoId，L7 只发意图不处理协议（95-137）——修复真实生效。选档决策残留 L7、L5 双链重复封装属职责软违反（P2）。
3. **六桥通道**（重点核3）：全 surface 无 core/net 直连，L7 经 bridge_session.appGraph.mv 取门面——阶段A前直连已消除，合规。
4. **video_player 边界**（重点核4）：成熟库 Widget 属 L7 UI，合规（URL 协议升级擦边，P2）。
5. **桥日志/死代码**（重点核5）：L4 端点 try/catch+Log('ep.mv') 齐备；mv_anonymous.dart 227 行匿名链仍是**零调用死代码**（P1，本视角最严重项）。L7 用 debugPrint 而非桥 Log 记错，属次要。
6. **1500 行门禁**（重点核6）：9 文件最大 516 行，全部达标。

发现 8 条（P1×1、P2×7），无 P0；架构无反向依赖、无影子桥、无核心越级。4 项阶段A修复验证项中，模块注册/两段式/六桥三项确认生效，死代码一项未清。

## 未覆盖
- 仅做静态跨层架构审查，未跑 dart/analyze/test/门禁/联网（按纪律禁止）；端点真实返回、video_id 实测值、播放 URL 可用性等动态正确性属 C2 视角。
- 未逐行读取 l10n/s.dart、design/components.dart(SpStateView)、KugouClient.request 内部实现（非本批跨层清单文件）。
- 未审 B4 其余可能关联文件（如 playback_session.dart 全文仅取 :223 一处证据）；该文件归 B3 播放主链路视角。
- `MvPageModule.builder` 返回 `MvPage(albumAudioId: 0)`（mv_page.dart:31）导致经模块注册表渲染时 aid=0 走空态的问题，属实现正确性（C2），本视角仅记录不展开。

## 76 合规小结
- **符合**：第1条（跨层经桥、无跨层直连非桥文件）、第2条（L4/L5/桥函数 try/catch+Log 留痕）、第3条（桥文件仅在 lib/bridges/，无影子桥）、第4条（依赖方向 surface→session→logic→core，无反向Import）、第5条（1500 行门禁全达标、L6 注册表热插拔）、第6条（端点官方域名+多参齐备+Log；"一端点一文件"字面例外但受行数门禁允许）、第8条（播放控制/装配图在 L6 session，L7 无状态机）、第9条（video_player/just_audio 成熟库）。
- **部分擦边（P2）**：第1条——L7 承载 MV 选档业务决策、URL 协议升级；L7 绕过 moduleRegistry() 门面直取单例。
- **软违反（P2）**：第4条职责——MV 两段式协议在 L5 双门面（MvLogic/PlaybackService）重复封装、选档策略多处重复。
- **未违反**：第7条（无源仓库代码复用迹象）、第10条（本子代理仅只读+report 落盘）。
