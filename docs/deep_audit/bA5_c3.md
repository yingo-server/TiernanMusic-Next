# A5 批 · C3 用户痛点专项视角 · L5 logic 全量 34 文件

> 子代理：A5-C3｜视角：用户痛点（功能可达性 / YKG 落点 / 播放体验 / 文案泄漏 / MV 三态）
> 契约：`docs/DEEP_AUDIT_14_BATCH_PLAN.md` §0 76 原则；只读审查，唯一写入本文件（append）。

---
## 2026-11-16 · L5 auth 组（3 文件）通读结论

### 视角 C3 · lib/logic/auth/verification_logic.dart:67-125 · P0 · 20028 验证空壳 / 播放体验
证据：文件首注释「验证链路未接线，待 play_url 20028 通知接入」；`getVerifyInfo()`(:69-89) 只 `Log.w('...needs probe...')` 后 `return false`，**不发任何网络请求**；`submitVerification()`(:93-123) 只把 `_state` 置 `solving` 后 `return false`，**不外发、不自动重试原请求**；`markSolved()`(:127) 无任何调用方推进。全仓 `rg 'onVerificationRequired|VerificationLogic'` 命中仅在自身/session 装配，无真实 20028 闭环。
问题：VIP 曲目命中 errcode 20028 时，用户走完验证 UI 也永远回到失败态——「点了没反应/切歌失败」的直接原因之一；状态机 `solving` 是**终态黑洞**（无出口）。
建议：接通 get/verify/info + submit 端点（L4 一文件一模块），提交成功后由 `VerificationLogic` 回调原播放请求并重放；`solving` 必须设超时回落 `failed` 并给 UI 可重试文案；端点未实测前状态机不应暴露 `solving` 假进度。
76 合规：涉及 —— 验证端点若落在 L5 直连即违反 §0 第1/6条（须经 bridge_core + endpoints 分文件）。

### 视角 C3 · lib/logic/auth/account_logic.dart:50-60, 83-100 · P1 · YKG 导出素材 / 文案
证据：`saveCurrent()` 把 `token/mid/dfid/cookieBlob(=auth.cookie)` 全量写入 `AccountRecord`；`switchTo()` 反向把 cookieBlob 拆回 `session.cookies` 并全量回写 settings。**导出素材（cookie/token/mid/dfid）在 L5 已现成**，但 `AccountLogic` 无任何 `export*`/`share`/序列化出口。
问题：YKG 导出编排缺 L5 落点；`account_logic.dart:54` 的 `'酷狗用户 ${s.userid}'` 是**从 L5 漏出的展示文案**（且裸 userid 上屏，A1-C3 已点名）。
建议：新增 `lib/logic/auth/ykg_logic.dart` 作为 L5 唯一 YKG 编排（读 AccountRecord/session → 调 L4 crypto 封装 → 返回链接字符串）；昵称回退文案改由 L4 l10n `TnStrings.tr('accountDefaultName', args:[uid])` 提供，L5 只传占位参数。
76 合规：新增 ykg_logic 属 L5 合法；当前 `:54` 展示文案出现在 L5，违反 §0 L4-l10n 归口（铁律4/层职责）。

### 视角 C3 · lib/logic/auth/auth_logic.dart:322-345, 388-425 · P1 · 幂等/会话恢复
证据：`_tryRefreshToken()`(:322) 异步 fire-and-forget，`.catchError` 只 `Log.w('refresh degraded (exception)')` 不更新 UI；`_applyCredentials()`(:388) 每次登录把 session.cookies **全量序列化**回 `auth.cookie`，但 `logout()`(:351) 只 `cookies.clear()` 与 settings 删除。
问题：token 自动续期失败时用户无感知，VIP 权限静默降级为匿名；登录态与 cookie 快照可能不一致（cookie 未清前序列化残留）。
建议：续期失败暴露状态给 L6（`AuthState.degraded`），由 UI 给「登录态失效，请重新登录」可行动提示。
76 合规：不涉及（状态应经 bridge_logic 上报）。
## 2026-11-16 · L5 player 组核心（play_resolver / quality_policy / url_health / playback_service）通读

### 视角 C3 · lib/logic/player/play_resolver.dart:85-190 + quality_policy.dart:110-141 · P1 · 播放体验 / 三态
证据：`resolve()` 在 20028 / priv_status=0 时**立即 return**（`:127-143`），不继续降级、不触发 `VerificationLogic`；`decide()` 中 `status==2 && hasUrl` 落入兜底 `downgrade`（quality_policy.dart:135-141），但顶层注释声明「status=2 + 20028 → needVerify」——**有 URL 的验证响应被静默降档**，用户看到切歌失败而非验证提示。`PlayResolver` 构造默认 `checkHealth=false`（:65），`url_health` 整条探测默认不参与。
问题：两套播放解析（`PlayResolver` 与 `PlaybackService.resolvePlaySource`）**并存且语义不一致**：前者 20028 立即返回 needVerify 但不接验证、后者 `break` 后映射 needsVerification 但也不上报 `VerificationLogic`（playback_service.dart:336-340 只注释「上报状态」）。用户在 VIP/匿名场景必现「点了没反应」。
建议：单一事实源：把 `PlayResolver` 的 verdict 直接喂 `VerificationLogic.onVerificationRequired(errcode, ssaCode)` + `PlaybackSession` 错误码；修正 `decide()` 让 status=2 无论有无 url 都返回 needVerify（除非明确 noPrivilege）。
76 合规：不涉及。

### 视角 C3 · lib/logic/player/playback_service.dart:150-265 · P1 · VIP 权益判定 / 降级
证据：`_hasRights`(:150) 从 `Object? session` 动态取 `vip_token/vip_type`（`:163-180`），注入失败/异常一律按匿名；`_qualityCandidates`(:185) 无权益时**从 prefer 档起降**，不尝试 flac；`resolvePlaySource` 对每个失败档 `if (pr.errcode == 20028) break;`(:229)——匿名对任意档都会拿到 20028，第一档即 break，**从不降级到 128 试听**。
问题：匿名/VIP 失效用户点播 → 首档 20028 → 立即失败，没有「免费试听/最低码率兜底」路径；与 A1-C3「匿名必落 20028」一致，用户感知即「什么歌都放不了」。
建议：20028 不应终止所有档位：先上报 `needsVerification` 给 UI，同时继续尝试最低档 128 或 `isFreePart` 试听链；失败后再展示可行动文案（登录后重试 / 完成验证）。
76 合规：不涉及。

### 视角 C3 · lib/logic/player/playback_service.dart:275-340 · P1 · MV 音频兜底 / 能力重复
证据：`resolveMvAudioFallback()`(:277) 完整实现 `albumAudioId → getMvBySong → getVideoQualities → getVideoUrl` 两段式（:290-325）；但 `MvLogic`（lib/logic/catalog/mv_logic.dart:32,67）**不含这段链路**，MV 页把歌曲 hash 当 video_id 用。兜底入口由 L6 session 调用，MV 页面完全绕开。
问题：能力已实现却放错文件——「MV 音频兜底」存在，但「MV 视频播放」页面仍不可用；两段式应抽到 `MvLogic` 做唯一实现，避免双份漂移。
建议：见 MV 三态结论（文末）；把本方法迁至 `MvLogic.resolveVideoSource(song)`，PlaybackService 改为调用它。
76 合规：不涉及。

### 视角 C3 · lib/logic/player/url_health.dart:80-115 · P2 · 探测误判 / 播放体验
证据：`_probe()` 对 HEAD 阶段任意异常都降级 GET+Range（:94-103），但 `firstHealthy()` 只认 `health == UrlHealth.healthy`（2xx），**把 206 Partial Content 判为 dead**（:163-166）——GET+Range 正常响应恰是 206，被判失败导致 `PlayResolver` 全链 unhealthy → 降档或 exhausted。
问题：健康检查会把可播 URL 误杀，用户歌能放但解析层说「全断链」，切歌失败率被放大。
建议：`healthy` 判定加 `status == 206`（Range 探测的合法成功码），或专门区分 `partial` 状态。
76 合规：不涉及（L5 纯逻辑，用 dart:io 属 IO 直连——见 76 小结）。

### 视角 C3 · lib/logic/player/play_source_parser.dart / player_state.dart / playback_reducer.dart / queue_state.dart / history_recorder.dart · P1 · 播放链路能力盘点
证据：待下文逐文件读取（本条为占位，读后更新）。
问题：待补。
建议：待补。
76 合规：待补。
## 2026-11-16 · player 余下 5 文件 + 死代码交叉核验

### 视角 C3 · lib/logic/player/play_resolver.dart + quality_policy.dart + url_health.dart + play_source_parser.dart · P0 · 整套解析能力死代码
证据：`rg -l 'PlayResolver|PlayResolveResult|PlayDecision|downgradeChain|UrlHealthChecker|firstHealthy|ParsedPlayUrl' lib -g '*.dart'` → **命中仅这 4 个 L5 文件自身**；`lib/bridges/bridge_logic.dart` **未 export** 任一（`rg 'play_resolver|quality_policy|url_health|play_source_parser' lib/bridges lib/session` → 零命中）；L6 `playback_session.dart:195` 实际只调 `PlaybackService.resolvePlaySource`。
问题：4 个文件共 **693 行**（play_resolver 196 + quality_policy 143 + url_health 203 + play_source_parser 139）构成的「三态解析 + 降级 + 健康检查」旗舰能力**全部是死代码**，桥未导出、session 未接；用户「点了没反应」不是策略没写，而是策略根本没跑。
建议：要么在 `bridge_logic.dart` 导出并由 `PlaybackSession` 改用 `PlayResolver` 作为唯一解析入口（与 VerificationLogic 联动），要么删除死代码避免维护幻觉；二选一需主会话定夺。
76 合规：涉及 —— `url_health.dart:5-8` 在 **L5 logic 直接 import `dart:io` 并发起 HttpClient 网络探测**（§0 第5条「L5 仅后端逻辑、无 IO 直连」、第1条网络应经 L4/桥）；应由 L4 `core/net` 提供探测器，L5 只编排。

### 视角 C3 · lib/logic/player/history_recorder.dart:14-64 · P1 · 历史记录 / 漏斗
证据：`recordPlay()` 实现完整（建档 → `HistoryDao.record` → `SongDao.markPlayed`）；`lib/session/playback_session.dart:216,250` 调用时**传 `playedMs=0`**（两处都是常量 0）。
问题：历史记录三条链路接通，但**实际播放时长恒为 0**——「最近播放」只记了「点过」，累计时长/播放进度统计永远为空，用户感知「历史记录没内容」。
建议：`PlaybackSession` 在暂停/切歌/完成回调里用真实 `positionMs` 差值传 `playedMs`，并去重防重复上报。
76 合规：不涉及。

### 视角 C3 · lib/logic/player/playback_reducer.dart:54,191-195 + player_state.dart:26 · P1 · 文案泄漏 / L5 错误码化
证据：`ErrorAction(String message)` 直接收中文串；`playback_reducer.dart:199` catch 写 `lastError: 'reducer crash: $e'`（英文内部异常直出）；`PlayerState.lastError` 是 `String`，L6 `playback_session.dart:149/239` 又塞 `'引擎播放失败'/'播放源不可播或需登录'`（A1-C3 已点名）。
问题：L5 状态机用**字符串承载用户文案**，无法 i18n、无法分类重试动作；reducer 的英文崩溃文本若上屏就是黑话。
建议：`PlayerState.lastError` 改 `PlaybackError? errorCode`（`PlaybackError` 已在 playback_service.dart:26 定义），L5 只传码；UI 用 `TnStrings.tr('error.<code>')` 映射中文/多语。
76 合规：涉及 —— l10n 常量归 L4（§0 层职责），L5 不应产出面向用户文案。
## 2026-11-16 · L5 MV + download 组通读

### 视角 C3 · lib/logic/catalog/mv_logic.dart:27-125 · P0 · MV 逻辑三态 / 端点恒 null
证据：`MvLogic` 只有 3 个能力：`qualities(mvHash)`、`playUrl(mvHash)`、`invalidatePrefix()`；**没有** `resolveVideoSource(song)` / `getMvBySong` / 匿名端点 / VIP 判定 / 错误三态枚举。`playUrl()` 的「降级」仅是**同曲按 size 降清晰度**（:90-112），全档失败返回空 `MvPlayResult()`（:114）——与「无 MV / 需会员 / 网络失败」三态无关。`lib/core/net/endpoints/mv_anonymous.dart`（227 行 `registerDevice`/`anonymousPlayUrl`）**零 import**（A1-C3 已确认）。
问题：MV 逻辑层**不具备三态能力**：① 不区分「需 VIP / 匿名可看低清 / 无版权」；② 端点返回恒 null 或未授权时一律塌缩成空结果，UI 只能显示「暂无 MV」；③ 歌曲 hash↔MV hash 两段式不在这里，导致 MV 页面用错 hash（A1-C3 P0）。用户点名「MV 用不了」在 L5 无解。
建议：在 `MvLogic` 新增 `resolveVideoSource(SongBrief)`：`albumAudioId → getMvBySong → getMvBrief.hash → qualities → playUrl`，并返回 `MvAvailability {available|needVip|anonymousDegraded|notFound|network}` 三态以上结果；接入 `mv_anonymous` 作为未登录可看低清的降级分支；错误态带 `errorCode` 给 UI 映射 i18n 文案，禁止返回裸空对象。
76 合规：不涉及（新增仍落 L5，经 bridge_logic 暴露）。

### 视角 C3 · lib/logic/download/download_manager.dart:82-124 + 全仓引用 · P0 · 下载能力完整但无入口（呼应 A1-C3）
证据：`enqueue()`(:82) / `pause` / `resume` / `cancel` / `retry` / `listTasks` 实现完整（506 行，含并发调度、分块、断点临时文件、幂等收尾）；但 `rg -n 'enqueue\(' lib -g '*.dart'` 仅命中本文件定义（A1-C3 已确认）；L7 无「下载」按钮，`library_page.dart:303` 空态写「在歌曲菜单里选择下载」。
问题：用户点不到下载——整条 L5 下载链是「已实现、未接线」；这是用户「什么功能都用不了」的直接样本。
建议：L7 歌曲 ⋮ 菜单加入下载项 → `appGraph.downloads?.enqueue(song, quality)`；L6 暴露 `onTask` 订阅给下载管理页（当前 `onTask` 只由 manager 持有，桥是否导出见 A6 复核）。
76 合规：不涉及。

### 视角 C3 · lib/logic/download/download_manager.dart:15-22, 362-430 + url_health.dart:5-8 · P2 · L5 IO 直连（76）
证据：`download_manager.dart:14` `import 'dart:io'`，`:378` 直接 `HttpClient()` 发 GET+Range；`download_commit.dart:5` `import 'dart:io'` + `File.readAsBytes/rename`；`download_paths.dart:6` `dart:io`；`url_health.dart:8` `dart:io` + `HttpClient`。§0 定义 L5「仅后端逻辑（无 UI、无 IO 直连）」，IO/网络应经 L4 core 门面。
问题：4 个 L5 文件直接做文件/网络 IO，层职责越界；虽然注释称「经 core 桥访问存储」，但下载流与探测实际绕过 L4。
建议：长线把 HttpClient 探测/分块下载下沉为 L4 `core/net`/`core/io` 门面，L5 只保留队列/状态编排；短期至少在报告标注例外并登记白名单。
76 合规：**违反 §0 第5条（L5 无 IO 直连）与第1条（跨层须经桥）**。

### 视角 C3 · lib/logic/download/download_models.dart:68-75 · P2 · 展示文案从 L5 漏出
证据：`displayName` getter 拼 `'${song.singer} - ${song.name}'`；注释写「展示名」。
问题：拼接格式是展示决策（中文全角/半角、歌手在前与否应可本地化），放 L5 模型里使 i18n 无法覆盖。
建议：L5 只给 `song`/`name`/`singer` 字段，L7 用 `TnStrings.tr('download.displayName', args:[singer,name])` 组装。
76 合规：涉及（l10n 归 L4，展示归 L7）。
## 2026-11-16 · catalog 组（16 文件）+ lyrics 组（3 文件）通读 + 全 L5 能力-消费交叉核验

### 视角 C3 · lib/logic/catalog/comment_logic.dart:81 · P1 · 文案泄漏 / L5 错误硬编码
证据：`return const CommentPage(blockedReason: '评论门面异常，请稍后重试');`（catch 分支），「评论门面」为内部术语；A1-C3 已记 `comment_endpoints.dart:174-194` 同类硬编码。
问题：L5 直接产出面向用户的中文错误串（不是错误码），UI 直出黑话且无法 i18n。
建议：改为 `blockedReason: 'comment.facadeError'` 错误码，L7 用 `TnStrings.tr` 映射；L5 只记录 Log.e 原文。
76 合规：涉及（l10n 归 L4、展示归 L7，§0 层职责）。

### 视角 C3 · lib/logic/catalog/fm_logic.dart:6-14, 136-160 · P0 · FM 空壳（端点 needs probe）
证据：文件头明确「personalFm/fmSongs 均 needs probe → 恒空批次」；`_load()` 空结果不落缓存并 `Log.w('...needs probe?')`；L7 `player_page.dart:209` 有「个人 FM」入口 → `appGraph.fm?.start()`，返回空后 `player_page.dart:215` 显示「FM 暂无可用曲目（端点待实测）」。
问题：用户能点到「个人 FM」但**永远拿不到一首歌**——L5 逻辑完整（批次/跳过/过滤/缓存），但底层端点未实测导致恒空，且研发词「端点待实测」直达 UI。
建议：端点实测前隐藏入口或给明确空态「功能即将上线」；端点接通后 L5 无需改动即可生效。
76 合规：不涉及。

### 视角 C3 · lib/logic/catalog/collect_logic.dart:118-192 · P0 · 收藏逻辑完整但上层假按钮（呼应 A1-C3）
证据：`toggle()` 实现登录守卫、并发去重、成功才写镜像、fileid 建档、按账号隔离键（`favorites.<uid>`）、服务端回填（`refreshCount`/`_backfillFromServer`）；但全仓 `rg '\.toggle\(' lib` 仅命中 `playback_session.dart:381` 的 **playbackSession().toggle()**（播放/暂停，非收藏）；`CollectLogic.toggle` 零调用，L7 `player_page.dart:81-88` 收藏按钮仅 `setState(_fav)`。`library_page.dart:41,51` 只读 `refreshCount()` 显示计数。
问题：收藏能力是 L5 最完整的模块之一，但用户点收藏只翻图标、重启即丢——「功能用不了」的典型；并且服务端回填只在 library 页触发，播放页收藏态永远与镜像不同步。
建议：L7 收藏按钮接 `appGraph.collect?.toggle(song.hash, song.mixSongId, song: song)`，成功后同步 `isCollected()`；`isCollected` 状态经 L6 通知到所有页面。
76 合规：不涉及。

### 视角 C3 · lib/logic/catalog/playlist_write_logic.dart:52-157 + comment_logic.dart / album_logic.dart / artist_logic.dart · P1 · 多域 logic 已实现但零 UI 消费
证据（全仓消费核验）：
- `PlaylistWriteLogic`（157 行：create/delete/removeSongs/myPlaylists）：仅 bootstrap/graph/bridge 装配，`rg 'appGraph\?\.playlistWrite|appGraph\.playlistWrite' lib/surface` **零命中**；文件尾注释「待 UI 接线」。
- `CommentLogic`（140 行）：仅装配，`rg 'appGraph.*comment|CommentLogic' lib/surface` **零命中**（评论按钮在 player_page 有入口但无数据链）。
- `AlbumLogic.detail/songs/similarPlaylists`（120 行）、`ArtistLogic.detail/audios/albums/list`（191 行）：`rg 'appGraph.*album|appGraph.*artist' lib/surface` **零命中**。
- `SearchTypedLogic.complex()`（v6 综合搜索）：`search_page.dart:81` 仅用 `searchTyped`，`complex()` 零调用。
问题：至少 **5 个 catalog logic 模块（≈688 行）实现完整但 L7 无消费**；用户点评论/专辑/歌手/建歌单看不到数据或无法操作，与「什么功能都用不了」一致。
建议：阶段 B 跨层核验优先级：评论→`CommentLogic.comments`、歌单写→`PlaylistWriteLogic.create/delete`、专辑/歌手页入口；`complex()` 明确接搜索综合 Tab 或删。
76 合规：不涉及（均经 bridge_logic 暴露，装配合法）。

### 视角 C3 · lib/logic/lyrics/translation_logic.dart:18-21 · P1 · 翻译空壳 / 文案
证据：文件头「译文端点未实测（fetchTranslation 恒返回空）」；`displayFor()` 只从**本地 KRC 内嵌翻译轨**抽取（`:44-54`），无外链翻译端点；无轨时 `bilingual/translation` 模式退化为原文并只 Log.w。
问题：用户切「翻译」模式，绝大多数歌曲**看到的还是原文**——L5 没有真正翻译能力，且没有状态告知用户「这首歌没有译文」（只有 Log）。
建议：`displayFor` 返回附带 `translationAvailable` 标记，UI 显示「暂无译文」状态；翻译端点实测前不要提供「翻译」Tab 的假承诺。
76 合规：不涉及。

### 视角 C3 · lib/logic/lyrics/lyrics_logic.dart:5-9, 120-160 · P2 · L5 文件 IO / 功能可达性
证据：`import 'dart:io' show File`（:6），`_writeFile/_readFile/clearFileCache` 直接 `File.writeAsStringSync/readAsStringSync/deleteSync`（:38,55,157）；文件缓存三级链完整；L7 `lyrics_page.dart:88-96` 确实调用 `lyricsFor/parsedFor/displayFor`。
问题：歌词链是五大功能中**接通度最高**的一条（L5→L7 消费存在），但 L5 直接文件 IO 违反 §0「L5 无 IO 直连」。
建议：文件缓存下沉 L4 `core/cache` 门面，L5 只编排；短期标注例外。
76 合规：**违反 §0 第5条**（L5 文件 IO 直连）。
## 2026-11-16 · YKG 落点结论（L5 边界建议，不改代码）

### 视角 C3 · lib/logic/auth/ + 全仓 · P0 · YKG 在 L5 零落点
证据：
- `rg -ni 'ykg' lib -g '*.dart'` → **零命中**（`lib/logic/auth/ykg_logic.dart` **不存在**；A1-C3 已确认全仓 YKG 未实现）。
- 导出素材在 L5 已现成：`account_logic.dart:50-60` `saveCurrent()` 写 `token/mid/dfid/cookieBlob(=auth.cookie)`；`:83-100` `switchTo()` 反向拆 cookie 并回写 settings；`auth_logic.dart:388-425` `_applyCredentials()` 另存 `vip_token/vip_type/t1`（YKG 设计稿 §2 明文 JSON 字段 7 项**全部有来源**）。
- `docs/YKG_LINK_CRYPTO_DESIGN.md:7` 指定「导出/导入编排落 L5 `lib/logic/auth/ykg_logic.dart`」。
问题：YKG 编排**没有 L5 宿主**；若在 L7 登录页直接拼链接/解密，将违反 76（l10n/UI 混编排、 crypto 越层直连）。
建议（封装边界，不写代码）：
- **L5 `ykg_logic.dart` 职责**：仅编排——导出时注入 `AccountDao/KugouSession/KeyValueSettings` 读凭据 → 调 L4 crypto 门面加密 → 返回 `ykg://import/...` 字符串；导入时解析链接 → 调 L4 crypto 校验密码 → 成功后经 `bridge_logic` 回调 L6 `auth_session` 写 session；**不得**含 Widget、`Clipboard`、中文字面量、密码弹层。
- **L4 职责**：payload 编解码、PBKDF2/AES-GCM（用成熟库 `cryptography`，见设计稿 §8）、base64url、MD5 兼容字段 `m`、exp/指纹校验；一文件一模块。
- **L7 职责**：导出按钮/密码输入弹层/风险提示文案（走 `TnStrings`）；登录页第 4 个 Tab。
- **复用边界**：`Md5.hex`（signing.dart:266）只用于兼容字段 `m`；`AesCbc` 不用于 YKG（设计稿 §3.2）；不复用 `AccountLogic` 的展示名 `'酷狗用户 $uid'`（改 l10n）。
- **验收口径**（交给主会话）：导出必须有密码；错密码/篡改密文/过期链接一律失败；导入成功后 `AccountLogic.saveCurrent` 可建档 `source=ykg`。
76 合规：现状不涉及；新增须严守 §0 第1/6条——crypto 在 L4、编排在 L5、经 bridge_logic 到 L6。
## 2026-11-16 · 功能 logic 能力清单（五大功能 × L5）

### auth 组（3 文件，733 行）
| 模块 | L5 实现 | 上层消费 | 判定 |
|---|---|---|---|
| AuthLogic | 二维码登录/轮询/密码登录/短信/token 续期/登出/凭据持久化（完整） | L7 登录页接通；但密码/验证码端点标注待实测 | ⚠️ 接通但质量存疑 |
| AccountLogic | saveCurrent/switchTo/list/active/remove（完整，YKG 素材现成） | settings/account_section 只 `activeAccount`；saveCurrent/switchTo 有 L7 调用 | ✅ 接通；❌ 无导出 API |
| VerificationLogic | 状态机 idle→required→solving（终态） | 仅装配；`getVerifyInfo`/`submitVerification` 恒 false | ❌ **空壳**（20028 闭环断裂） |
| YKG logic | 不存在 | — | ❌ **零落点** |

### player 组（10 文件，1833 行）
| 模块 | L5 实现 | 上层消费 | 判定 |
|---|---|---|---|
| PlaybackService | 本地优先/在线降级/三态映射/MV 音频兜底（完整） | L6 `playback_session.dart:195,207` | ✅ 接通；⚠️ 20028 首档 break 不降级 |
| **PlayResolver + quality_policy + url_health + play_source_parser** | 693 行完整策略 | **零导出/零调用**，且 `:163` 206 误判 | ❌ **整套死代码** |
| QueueState/PlayerState/playback_reducer | 不可变状态机完整 | L6 正常使用（引用稳定优化到位） | ✅ 接通 |
| HistoryRecorder | 记录完整 | L6 两处调用**恒传 playedMs=0** | ⚠️ 接通但数据失真 |

### download 组（6 文件，832 行）
| 模块 | L5 实现 | 上层消费 | 判定 |
|---|---|---|---|
| DownloadManager + 5 辅助 | enqueue/pause/resume/cancel/retry/分块/并发/收尾（完整，832 行） | L7 `library_page.dart:59` 只 `listTasks()`；`enqueue` 零调用 | ❌ **完整实现但无入口** |

### catalog 组（16 文件，2306 行）
| 模块 | L5 实现 | 上层消费 | 判定 |
|---|---|---|---|
| SearchLogic / searchTyped.typed | 缓存/联想/热搜完整 | L7 search_page 接通 | ✅（缺 MV 段，typed.complex 零用） |
| RankLogic / RecommendLogic / PlaylistLogic | 缓存三态完整 | L7 home_page 接通 | ✅ |
| CollectLogic | toggle/镜像/回填/账号隔离完整 | **toggle 零调用**（假按钮） | ❌ **完整但断链** |
| FmLogic | 批次/跳过/缓存完整 | L7 player_page:209 接通，但端点 needs probe 恒空 | ❌ **功能空壳** |
| MvLogic | qualities/playUrl 有基本降档 | L7 mv_page 用错 hash；无三态；匿名端点零用 | ❌ **核心不可用**（见 MV 专项） |
| CommentLogic | comments/floor/缓存完整 | L7 零消费 | ❌ **已实现无入口** |
| PlaylistWriteLogic | create/delete/removeSongs 完整 | L7 零消费（注释「待 UI 接线」） | ❌ **已实现无入口** |
| AlbumLogic / ArtistLogic | detail/songs/audios/albums/list 完整 | L7 零消费 | ❌ **已实现无入口** |
| UserLogic | profile 完整 | library_page:40 消费（显示昵称） | ✅（端点未实测可能空） |
| searchTyped.complex | v6 综合搜索 | 零调用 | ❌ 死代码 |

### lyrics 组（3 文件，525 行）
| 模块 | L5 实现 | 上层消费 | 判定 |
|---|---|---|---|
| LyricsLogic | 内存→文件→网络三级 + KRC/LRC 解析 + offset（完整） | L7 lyrics_page:88-96 接通 | ✅ 本批接通度最高 |
| TranslationLogic | 本地 KRC 内嵌翻译轨提取 + 三模式 | L7 接通；**无外部翻译端点**，恒退原文 | ⚠️ 半空壳 |
| lyrics_parser | 纯函数完整 | 被 LyricsLogic 调用 | ✅ |

**汇总：34 文件中判定为「空壳/恒空/死代码」= 10 个**（VerificationLogic、PlayResolver、quality_policy、url_health、play_source_parser、FmLogic、MvLogic 三态缺失、CommentLogic、PlaylistWriteLogic、AlbumLogic+ArtistLogic 无消费、searchTyped.complex 等；严格按文件计：**VerificationLogic / play_resolver / quality_policy / url_health / play_source_parser / fm_logic / mv_logic / comment_logic / playlist_write_logic / album_logic / artist_logic / translation_logic = 12 个文件存在空壳或零消费问题**）。
## 2026-11-16 · MV 逻辑三态专项结论（用户点名）

### 视角 C3 · lib/logic/catalog/mv_logic.dart:27-125 · P0 · MV 三态能力缺失（确认 A3 P0）
证据链：
1. **匿名降级**：`mv_logic.dart` 全文件零 `getMvBySong`、零 `mv_anonymous`、零 `registerDevice`/`anonymousPlayUrl`；`lib/core/net/endpoints/mv_anonymous.dart:57,144` 两个函数零调用（A1-C3 已确认死代码）。
2. **VIP 降级**：`playUrl()` 的「降级」只是 `quals.sort((a,b) => b.size.compareTo(a.size))` 后逐档试 URL（:91-111），**不读 errcode / vip 状态**；VIP 档被权限挡下与网络失败被同等对待，最终都返回空 `MvPlayResult(title: title)`（:114）。
3. **端点恒 null**：`qualities()` 空结果不落缓存（:49-50，正确做法），但返回 `const []`；`playUrl()` 在 `quals.isEmpty` 时也返回空对象——调用方 `mv_page.dart:104` 统一显示「这首歌暂无可播 MV」，用户无法区分「需会员 / 匿名可看低清 / 端点挂了」。
4. **hash 语义错配**：`MvLogic` API 入参是 `mvHash`，但 `mv_page.dart:95-101` 把 `songHash`（歌曲 hash）直接传入；两段式 `song.albumAudioId → getMvBySong → mvBrief.hash` **只存在于 playback_service.dart:290-295**（MV 音频兜底），MV 页面链路完全绕开。
问题：L5 MV 逻辑**只实现了档位切换，没有实现三态**；端点恒 null 与 VIP 拦截被塌缩为同一个空结果；加上 hash 错配，「查看 MV」必现失败（A3 P0 在 L5 侧的根因确认）。
建议（MvLogic 归口）：
- 新增 `resolveVideoSource(SongBrief)` 做两段式 hash 解析（复用 `playback_service.dart:277-340` 逻辑并迁来，作为唯一实现）。
- 返回 `MvAvailability` 结果对象：`available(urls)| needVip | anonymousDegraded(urlsLow)| notFound | network`，携带 `errorCode`（非中文）。
- 接入 `mv_anonymous.dart`：未登录时先 `registerDevice` 取 dfid → `anonymousPlayUrl` 走低清可看分支；失败再判 `needVip`。
- `qualities()` 的缓存 key 已含 userid（:35-40），注意匿名/VIP 切换时 `invalidatePrefix` 正确失效（现有实现已具备，:118-124）。
- L7 只按 `errorCode` 取 i18n 文案，禁止 `$e` 原文直出（A1-C3 已点名 mv_page 黑话）。
76 合规：现状不涉及；新增保持 L5 编排 + L4 端点，经 bridge_logic 暴露。

## 2026-11-16 · 文案泄漏清单（L5 logic 中的用户可见中文 / 内部黑话）

### 视角 C3 · 汇总 · P1 · 文案应从 L5 迁出
证据（`rg` 全量命中，去注释后共 **12 处字符串字面量含中文**，其中面向用户 **7 处**）：

| 文件:行 | 原文 | 性质 | 是否面向用户 |
|---|---|---|---|
| `lib/logic/catalog/comment_logic.dart:81` | `'评论门面异常，请稍后重试'` | 错误文案直出 `blockedReason` | **是（P1）** |
| `lib/logic/auth/account_logic.dart:54` | `'酷狗用户 ${s.userid}'` | 默认昵称上屏（裸 uid） | **是（P1）** |
| `lib/logic/auth/verification_logic.dart:77-78` | `'getVerifyInfo needs probe: ...端点 docs 零留样...'` | Log 内部黑话（不直出） | 否（Log） |
| `lib/logic/auth/verification_logic.dart:102-103` | `'submitVerification needs probe: 提交端点未实测...'` | Log 内部黑话 | 否（Log） |
| `lib/logic/player/playback_service.dart:315` | `'(mp4 音轨属推断，直接喂引擎)'` | Log 研发口径 | 否（Log） |
| `lib/logic/download/download_commit.dart:75` | `'commit ... 已完成落盘但收到取消，保留文件不入曲库'` | Log 中文 | 否（Log） |
| `lib/logic/catalog/collect_logic.dart:171,207` | `'cancel fileid 未建档...'` / `'collect 无 fileid 回执...'` | Log 中文 | 否（Log） |
| `lib/logic/download/download_models.dart:68` | 注释「展示名："歌手 - 标题"」 | 展示格式决策藏在 L5 | **是（间接，P2）** |
| `lib/logic/player/playback_reducer.dart:199` | `'reducer crash: $e'` | 英文内部异常写 `lastError` | 潜在（若上屏） |
| `lib/logic/player/player_state.dart:26` | `lastError` 为 `String` | 结构性问题：L5 状态机无法错误码化 | 结构性（P1） |

补充：`lib/core/l10n/strings.dart` 仅 20 业务键、无错误/空态/账号/YKG 类键；`rg -n 'TnStrings' lib -g '*.dart'` 除 export 外**零调用**（A1-C3 已确认整套 i18n 死代码）。
问题：L5 漏出的 2 处用户文案 + 1 处展示格式 + 1 个字符串型错误字段，导致「相关文案没改」在 logic 层同样成立；错误码化缺失使 i18n 无法介入。
建议：① 上表 3 处用户可见串改为 `TnStrings.tr(key, args)` 或错误码，L5 只传码；② `PlayerState.lastError`→错误码枚举；③ 新增 arb 键 `error.commentFacade` / `account.defaultName` / `error.verificationRequired` / `ykg.*` 等（详见 A1-C3《文案缺口清单》）；④ Log 中文允许保留（不面向用户）但建议统一英文便于检索。
76 合规：涉及 —— §0 L4 持 l10n 常量、L7 负责展示；L5 产出中文用户文案/展示拼接属层职责越界。
## 2026-11-16 · 76 合规小结（A5 / L5 logic）

### 视角 C3 · 全层 · P1 · 层职责越界汇总
证据：
1. **L5 IO 直连（§0 第5条「L5 仅后端逻辑、无 IO 直连」）**：
   - `lib/logic/player/url_health.dart:8` `import 'dart:io'` + `HttpClient()` 直接网络探测；
   - `lib/logic/download/download_manager.dart:14,378` `HttpClient()` 分块下载；
   - `lib/logic/download/download_commit.dart:5,60` `File.readAsBytes` / `rename` 落盘；
   - `lib/logic/lyrics/lyrics_logic.dart:6,38,55` `File.writeAsStringSync/readAsStringSync` 文件缓存。
2. **l10n 归口（§0 层职责 + L4 core/l10n）**：`comment_logic.dart:81`、`account_logic.dart:54`、`download_models.dart:68`（展示格式）、`playback_reducer.dart:199`（英文 error 上屏）；L5 无一处调用 `TnStrings`（A1-C3 确认 i18n 整套死代码）。
3. **桥纪律（§0 第1/2条）**：34 个 L5 文件的跨层访问**全部**经 `bridge_core`/`bridge_kernel`（`rg '^import' lib/logic` 核验），**无影子桥、无 surface/session 反向 import**——这是本批合规的正面结论。
4. **同层引用合法**：`download_manager.dart:17`→`../player/playback_service.dart`、`account_logic.dart:9`→`auth_logic.dart` 等均为 L5 同层，符合铁律4。
5. **1500 行限制**：全层最大文件 `download_manager.dart` 506 行、`auth_logic.dart` 463 行，远低于阈值 ✅。
6. **文件数/目录**：无 `lib/logic/bridges/` 之类影子桥目录 ✅。
问题：L5 层在「IO 直连」和「文案归口」两类上有系统性越界；架构桥接纪律本身合规。
建议：主会话修 A 阶段时按本报告「IO 下沉 L4 / 文案码化」两轴统一处理；不要在 L5 新增任何 `dart:io` 或中文字面量。

## 本视角结论
1. **空壳/半空壳/死代码 12 个文件**（34 中约 35%）：VerificationLogic（20028 闭环断裂）、PlayResolver+quality_policy+url_health+play_source_parser（693 行整套死代码）、FmLogic（端点 needs probe 恒空）、MvLogic（三态缺失+hash 错配）、CommentLogic/PlaylistWriteLogic/AlbumLogic/ArtistLogic（实现完整零 UI 消费）、TranslationLogic（无外链翻译恒退原文）。
2. **「实现完整但上层没接」是主矛盾**：DownloadManager（832 行，enqueue 零调用）、CollectLogic.toggle（假按钮）、playlist_write/comment/album/artist——用户「什么功能都用不了」在 L5 的证据是**能力已经写好，L7/L6 没接或接错**。
3. **YKG 落点**：`lib/logic/auth/ykg_logic.dart` 不存在；L5 已有 YKG 导出素材（AccountLogic: token/mid/dfid/cookieBlob + AuthLogic: vip_token/vip_type/t1）；封装边界 = L5 只做编排（读凭据→调 L4 crypto→出链/写 session），L4 做 PBKDF2/AES-GCM/报文，L7 做密码弹层+i18n 文案。
4. **播放体验**：20028 在 VerificationLogic 是 solving 终态黑洞、在 PlaybackService 首档 break 不降级；PlayResolver 整套策略未被桥导出；206 被 url_health 判 dead——四个独立缺陷叠加造成「点了没反应/切歌失败」。
5. **MV 三态**：L5 完全没有匿名/VIP 降级与恒 null 分态，`mv_anonymous` 零调用，两段式 hash 解析只在 MV **音频**兜底里，MV 视频页绕开——A3 P0 在 L5 确认。
6. **文案泄漏**：L5 中 7 处中文字符串字面量（3 处面向用户/Log 4 处）+ 1 处英文 error 上屏 + `PlayerState.lastError` 字符串结构性问题；`TnStrings` 全仓零调用，建议错误码化后由 L4 l10n + L7 映射。
7. **76 合规**：全部逻辑跨层经桥、无影子桥、文件长度达标；不合规集中在 L5 直接 `dart:io`（4 文件）与 L5 产出用户文案（l10n 归口）。

## 未覆盖
1. L6 session/bridges 的消费细节仅按本次检索所需读取（`bootstrap.dart`/`graph.dart`/`bridge_logic.dart` 只做 import/export 与消费点 grep，未逐行通读）——归 A6 批。
2. L7 surface 页面（登录/播放/MV/设置/搜索等）只按 A1-C3 已有结论与本批交叉验证所需读取片段，未全量通读——归 A7/B 批。
3. L4 endpoints 内部实现（auth/mv/play/quality 端点具体参数与响应解析）未在本批逐行审查——归 A2/A3 批。
4. 未跑任何 dart/flutter/analyze/test/门禁，未联网，未做动态验证（按契约禁止）。
5. YKG 密码学参数安全性（PBKDF2 迭代数、GCM nonce 重用策略等）按设计稿 review 未做密码学审计——仅确认落位与素材可复用性。

## 76 合规小结
- ✅ 依赖方向：L5 仅 import `bridge_core`/`bridge_kernel` + 同层 logic + `dart:*`，无 surface/session/core 非桥文件直连；无影子桥；最大 506 行 < 1500。
- ❌ §0 第5条 L5「无 IO 直连」：`url_health.dart`、`download_manager.dart`、`download_commit.dart`、`lyrics_logic.dart` 四文件直接 HttpClient/File IO。
- ❌ §0 层职责（l10n 归 L4）：`comment_logic.dart:81`、`account_logic.dart:54`、`download_models.dart:68`、`playback_reducer.dart:199`。
- ⚠️ 设计稿新增 YKG 时须严守：crypto 在 L4（第1/6条）、编排在 L5、密码弹层在 L7、经 bridge_logic 上报 L6。
---

## 勘误（追加）
上文「player 组核心」中的占位条目（play_source_parser / player_state / reducer / queue_state / history_recorder）已由后续「player 余下 5 文件」小节实测结论取代，占位行作废。

## YKG落点结论
L5 无 `ykg_logic.dart`，YKG 在 lib 中零命中；导出素材已现成（`account_logic.dart:50-60` cookieBlob/token/mid/dfid，`auth_logic.dart:388-425` vip_token/vip_type/t1）。建议新建 `lib/logic/auth/ykg_logic.dart` 仅做编排（读凭据→调 L4 crypto→出链/写 session），crypto 与报文落 L4、密码弹层与 i18n 文案落 L7。

## 功能logic能力清单
空壳/恒空/零消费 12 文件：verification_logic、play_resolver、quality_policy、url_health、play_source_parser、fm_logic、mv_logic、comment_logic、playlist_write_logic、album_logic、artist_logic、translation_logic；实现完整但上层未接：download_manager（enqueue 零调用）、collect_logic.toggle（假按钮）、searchTyped.complex；已接通：auth、playback_service、queue/reducer、search、rank/recommend/playlist、lyrics。

## 文案泄漏清单
面向用户：`comment_logic.dart:81`、`account_logic.dart:54`、`download_models.dart:68`、`playback_reducer.dart:199`；Log 内部黑话：`verification_logic.dart:77-78,102-103`、`playback_service.dart:315`、`download_commit.dart:75`、`collect_logic.dart:171,207`。共 12 处中文/英文串，其中用户可见 4 处；`TnStrings` 全仓零调用。
