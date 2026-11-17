## C2 · 2026-11-17 08:01 LCL · B5 下载/收藏/歌单/缓存 实现正确性跨层审查

> 视角 C2（实现正确性）。连续读完范围文件：L7 library_page/playlist_page；L6 graph/bootstrap；L5 download 6 文件 + collect/playlist/playlist_write logic；L4 download_store/cache_service/resource_cache/dao/collect_endpoints/playlist_write_endpoints。另核 player_page 的 FavoriteButton/下载入口、bootloader 注入、auth_session/nav_state/settings 的换号通知链、KugouClient.request/message endpoints。全部静态取证，未跑 dart/analyze/test。

## <视角 C2> · <library_page.dart:36,52,56-59,291-329> · <P1> · <跨层接缝/UI与逻辑不同步>
证据：
```dart
// library_page.dart
void _loadProfile() { ... _favCount = c.refreshCount().then((_) => c.count); }
void _loadDownloads() { final dm = appGraph.downloads; if (dm == null) return; _downloads = dm.listTasks(); }
// _downloadsTab(): 显示 t.status.name / t.progress，但全文件无 onTask 订阅、无 setState 刷新
```
问题：下载管理页只在 initState 快照一次 `listTasks()`（且 `playback_session`/全仓无任何 `onTask` 订阅者，rg 仅 `onTask=null`），`DownloadManager.onTask` 这个阶段A为「进度回调」造的跨层通道**零消费者**。用户在播放页点「下载当前歌曲」→enqueue 后切到音乐库下载页，看到的是入队瞬间快照；下载进行/完成/失败不会触发 rebuild（页面在 shell 用 `KeyedSubtree(ValueKey(current.id))` 承载、TabBarView 内常驻，不重建）。阶段A「library_page 是否显示真实进度/状态」的链路**未真正打通**：真值在 DownloadTask 对象上更新，UI 看不到。另 `_favCount`（initState 一次性 refreshCount）同样无 onChanged 订阅，收藏数变更也不会在已打开的页面刷新。
建议：library_page.initState 订阅 `appGraph.downloads.onTask = (e) => mounted && setState(() => _downloads = List.of(e.tasks))`，dispose 取消订阅；收藏数同样订阅 CollectLogic.onChanged（需在 bootstrap 注入回调）；或在 shell 层统一持有事件订阅再下发。
76 合规：76 §「L7 只画控件、经桥取数」遵守；但跨层事件通道（L5→L7）建而不用，属接缝状态不同步。

## <视角 C2> · <download_manager.dart:9-11,64-79,290-329> · <P1> · <崩溃恢复/持久化承诺>
证据：
```dart
// download_manager.dart 头部注释
// 持久化策略：任务队列为内存态，启动不恢复（进程结束未完成任务自然丢弃，用户可手动 retry）
final Map<String, DownloadTask> _tasks = {};
final List<String> _order = [];
```
问题：跨层追踪下载链：L7 ⋮菜单 → L6 downloads → L5 enqueue → HttpClient 分块写 .dlpart → L5 committer → L4 download_store.commitDownload（文件+索引落盘）→ L4 SongDao 建档。这条「成功下载」链是真通且落盘的（文件与索引、曲库三处一致）。但**任务队列纯内存**：进程崩溃/重启后，进行中/已排队/失败的任务全部消失，library_page 的 `_downloadsTab` 无历史可显示，用户无法 retry——与任务书「崩溃恢复」核验点冲突。.dlpart 残留文件也会在重启后永久悬空（无启动清理：rg 全仓 `_cleanupPartByHash` 仅在 cancel 路径调用）。design 上这是"刻意不存"的取舍，但对「下载管理」功能等于无恢复能力。
建议：启动时扫描 downloads/ 目录 `*.dlpart`（孤儿分片）与未 commit 的 hash，重建为 failed/pending 任务供用户 retry；或最小限度在 initState 调 `downloadStore.listAll()` 展示已完成历史（当前连"已完成下载列表"都不显示，只显示内存任务）。
76 合规：76 §logic 不做 IO 直连——download_manager 内 dart:io/HttpClient 属阶段A登记的下载例外，符合已裁定。

## <视角 C2> · <collect_logic.dart:100-109,117-152,356-367 / bootstrap.dart:153-158 / auth_session.dart:72-83> · <P1> · <多账号隔离/换号未清镜像>
证据：
```dart
// collect_logic.dart —— resetLocalMirror 全仓零调用（rg 仅定义在自身）
void resetLocalMirror() { _favorites.clear(); _fileIds.clear(); _count=0; _load(); _notify(); }
// main bootstrap 构造 CollectLogic 未传 onChanged：
() => CollectLogic(client: client, settings: settings, isLoggedIn: () => auth.session.userid.isNotEmpty)
// login_sheet.dart:81,97 成功只 navState().bumpAuth(); settings_page.dart 只 _loadAccount()+cache.invalidateSession()
```
问题：收藏链「阶段A接了真逻辑」是否真通——写链是真通的：L7 FavoriteButton → L5 `CollectLogic.toggle` → L4 `collectSongByHash`（GET 我喜欢 listid=2 → add_song）→ 成功才 `_flush()` 写 settings 镜像；未登录 `needsLogin=true`（L7 弹 Snackbar）；重启由 constructor `_load()` 读回镜像，持久化**成立**。**但多账号隔离在换号场景断链**：持久键虽按 uid 分（`favorites.<uid>`，`collect_logic.dart:283-286`），登录/切号/登出流程**从未调用 `resetLocalMirror()`，也无任何 CollectLogic.onChanged 注入**（bootstrap 未传）。结果：账号 A 登录时用 A 的 session 初始化镜像；切到账号 B 后，`_client.session.userid` 已变成 B，但 `_favorites`（A 的残留）不清空，`_kFavoritesKey` 却指向 B 的键——`isCollected()` 继续显示 A 的收藏态；B 的首次 toggle 会把 A 的 hash 集合写进 B 的键（`_flush` 用当前 uid 键），造成**串号污染**。`refreshCount()` 的回填仅在 `_favorites.isEmpty` 时触发（`collect_logic.dart:238`），有 A 残留时永远不补 B 的真实收藏。注释声称"换号清空镜像"的接口存在却没被装配层调用，是跨层接缝缺口。
建议：bootstrap 注册 `NavState.instance`/`AuthSession.onAuthChanged` 监听，登录/切号/登出统一调 `appGraph.collect?.resetLocalMirror()` + `appGraph.playlist?.invalidatePrefix(userid:)`；并把 `onChanged` 回调注入 CollectLogic 供 UI 刷新。
76 合规：76 §「状态机/编排归 L5、装配归 L6」——L5 提供了 resetLocalMirror 但 L6 未接线，属装配失职（跨层接缝）。

## <视角 C2> · <collect_endpoints.dart:244-262 / collect_logic.dart:229-244> · <P1> · <无效端点致计数链空转>
证据：
```dart
// collect_endpoints.dart getFavoriteCount()
if (mixSongIds.isEmpty) { Log.w(_tag, 'getFavoriteCount no mixsongids -> empty query'); }
final res = await client.request(EndpointRegistry.favoriteCount,
  <String, Object?>{'mixsongids': mixSongIds, ...});
// collect_logic.dart refreshCount(): final n = await ep.getFavoriteCount(_client); // 无 ids 入参
```
问题：收藏计数链是死路——`getFavoriteCount` 签名固定无 mixsongids 入参，调用方 `refreshCount()` 传空串，端点 `favoriteCount` 实测契约要求 `data.list[]{mixsongid,count}`（注释自承"待实测"，`collect_endpoints.dart:243-249`）。空 query 下服务端返回 count=0，`refreshCount` 拿 n=0 → 不更新计数、不触发 `_backfillFromServer`（其条件 `n>0`）。结果 library_page 账号卡「我喜欢 N」永远是 **0**（或仅镜像条数），收藏数端到端**不准**。这解释了为何阶段A"收藏接真逻辑"后用户仍看不到真实收藏数。属于端点与逻辑层契约不匹配。
建议：refreshCount 先取 `listFavorites()` 对应 mixSongId 列表（镜像当前只存 hash，需在 toggle 时一并存 mixSongId）拼 `mixsongids` 传入；或直接用「我喜欢」歌单曲目总数作为计数权威（favoriteListId→playlistTracks.total），放弃该未实测端点。
76 合规：字段容错/注释诚实不臆造，合规；但跨层「端点能力缺口」未在装配/门面层兜底。

## <视角 C2> · <bootstrap.dart:217-223 / search_logic.dart:89-95 / rank_logic.dart:38-55 / misc_endpoints.dart:62-68> · <P1> · <预读未命中（键与参数不匹配）>
证据：
```dart
// bootstrap.dart 预读
cacheService.prefetch([
  (ep: EndpointRegistry.searchHot, params: {'navid':1,'plat':2}),
  (ep: EndpointRegistry.rankList, params: {}),
]);
// misc_endpoints.dart rankList() 真实请求参数
client.request(EndpointRegistry.rankList, {'plat':2, 'withsong':1, 'parentid':0});
// search_logic.hotSearch() 直通不缓存；rankList 用自己 buildKey 的 LruCache 而非 KugouClient L2
```
问题：阶段A"缓存固化"修复是否真通：`KugouClient.request` 的 L2（ResourceCache）写入链经 `_cacheableSuccess` 只固化成功非空响应（阶段A P1-2 生效，`kugou_client.dart:94-120`），L2 缓存本身正确（resource_cache.dart 全程异步、_writeChain 串行、原子 rename、写失败留痕 P1-6 生效）。但**预读是否真命中——没有**：① `bootstrap` 预读 `rankList` 传空 params，真实业务 `misc_endpoints.rankList` 传 `{plat:2,withsong:1,parentid:0}`——`_cacheKeyOf` 按排序 query 生成键（`kugou_client.dart:154+`），两键不同，预读的 L2 条目业务侧永远 miss；② `RankLogic.rankList()` 读的是自己注入的 `LruCache<String,dynamic>`（buildKey 键，ns:'rank'），与 L2 ResourceCache 是**两张不同的表**（bootstrap 注入两个独立缓存），预读写 L2、业务读 LruCache，永不相交；③ `searchHot` 业务 `hotSearch()` 注释"直通不缓存"，预读写进 L2 后无人从 L2 读。因此 `CacheService.prefetch` 的「提前发起的读」对业务命中率贡献≈0（仅完成一次真实请求、消耗一次配额）。
建议：统一缓存真源——让 RankLogic/SearchLogic 走 `client.request` 的同一 L2（去掉第二张 LruCache 或让其成为 L2 的门面），并保证 prefetch 的 (ep,params) 与业务实际请求参数逐字一致；或删除无效的 prefetch 调用避免误导。
76 合规：76 §缓存一个域——此例正是 A4 裁定「缓存实现体分散」的跨层后果（L2 ResourceCache + L5 LruCache + CacheService 门面三套），C2 确认其导致预读失效。

## <视角 C2> · <playlist_write_logic.dart:156 / playlist_logic.dart:208-237 / playlist_page.dart:全> · <P1> · <歌单写操作零 L7 入口 + 本地镜像单向死路>
证据：
```dart
// playlist_write_logic.dart:156
// create / removeSongs：歌单管理为路线图功能，待 UI 接线（勿删）。
// playlist_logic.saveLocalMirror 全仓仅定义、无调用（rg 全仓）
// playlist_page.dart 只有 _RecommendTab/_MineTab/PlaylistDetailSheet，全文件无 create/delete/reorder/收藏歌单按钮
```
问题：歌单写链「创建/删除/加歌/排序」跨层追踪：L4 端点（createPlaylist/deletePlaylist/addSongsToPlaylist/removeSongsFromPlaylist）实现完整、`_ok` 严格 status==1&&ec==0（三态收紧生效）、DAO 有 `addSong/removeSong/reorder`（dao.dart:210-256）——**但 L5 写门面 PlaylistWriteLogic 只有 create/delete/removeSongs/myPlaylists，没有 reorder（加歌在 PlaylistLogic.addSongsToKugouPlaylist）且全仓零 L7 调用**：`appGraph.playlistWrite` 仅在 bootstrap/graph 装配，任何 surface 页面都不用它。用户无法在 UI 创建/删除/加歌/排序歌单（阶段A A5 X5「歌单写空壳」未随阶段A修复，本批确认仍断）。此外本地镜像「我的」页只读（`listLocal()`），而 `saveLocalMirror` 无人调用 → `PlaylistMeta` 全仓唯一写入点就是 `saveLocalMirror` 自己（rg 确认），即**本地镜像永远是空的**，`_MineTab` 恒显「还没有收藏的歌单」。写端点成功后的 `_invalidate` 反而调 `_dao.delete(listid)`（playlist_write_logic.dart:64-73）——即使镜像曾有数据也会被删，进一步坐实"我的歌单"不可持久。幂等性：delete 端点一次提交、重复 delete 返回 true 的"幂等"只体现在逻辑不自报错（playlist_write_logic.dart:98-118），非服务端幂等，符合 PARITY 原则。
建议：① L7 歌单页补「新建/删除/加歌到歌单/排序」入口并接 PlaylistWriteLogic+PlaylistLogic；② 加歌/收藏歌单成功后调 `saveLocalMirror` 写 PlaylistMeta（type=2 自建/收藏歌单），`_invalidate` 改为重建镜像而非 delete；③ 或明确"我的歌单"改走在线 `myPlaylists()`（登录态）渲染，放弃空本地镜像。
76 合规：76 §「logic 提供能力、surface 经桥消费」——能力齐全但 L7 未接线，属功能断链（非越级）。

## <视角 C2> · <download_store.dart:116-143,175-220,242-256 / download_commit.dart:47-70> · <P1> · <阶段A原子rename修复验证 + 索引/曲库一致性残留>
证据：
```dart
// saveIndex（阶段A修复P1-5）：tmp.writeAsStringSync(flush:true) → tmp.renameSync(index) 原子覆盖，无 delete
bool saveIndex() { ... tmp.renameSync(_indexFile.path); ... }
// commitDownload 仍保留 deleteSync：
part.writeAsBytesSync(data, flush:true);
if (target.existsSync()) target.deleteSync();  // ← 目标文件先删再 rename
part.renameSync(target.path);
```
问题：逐条核验阶段A修复：① **索引原子 rename（P1-5）真生效**——`saveIndex` 去掉 deleteSync 直接 rename 覆盖（POSIX 原子），崩溃空窗消除，`upsert/remove/commitDownload` 写前均 `loadIndex(forceReload:true)` 防旧空索引覆盖（批2-F3 已有），索引不丢记录✅。② **resource_cache 写失败信号（P1-6）真生效**——`putString` 检查 `_saveIndex()` 返回值并 `logE` 留痕（`resource_cache.dart:339-372`），✅。③ 但**实体文件的 commit 仍是「先删目标再 rename」**（`commitDownload:206-208`），文件级崩溃空窗仍在：删掉同名旧文件后、rename 失败 → 旧文件丢失且索引可能指向已不存在的 target。对同一 hash 重下覆盖场景是真实数据丢失窗口。④ `deleteWithFile` 语义正确：按 relativePath 删实体文件→`remove(hash)` 同步清索引（loadIndex forceReload），文件缺失不报错；但**无调用方**（rg 全仓仅定义），UI 也无「删除下载任务/文件」入口，删除链实际不可用。
建议：实体文件用带序号的唯一临时名 + `_resolveTarget` 已生成不冲突目标名（新目标本就不存在），可直接 `part.renameSync(target.path)` 去掉 `if(target.existsSync()) target.deleteSync()`——同名冲突已由 `_resolveTarget` 追加 -N 规避，deleteSync 是多余且有害的窗口；`deleteWithFile` 补 L7 下载页删除按钮。
76 合规：76 §core/storage 管 IO——合规；索引原子性已按阶段A修复闭环。

## <视角 C2> · <collect_logic.dart:214-219,356-367 / download_song_sync.dart:32-41 / cache_service.dart:118-131> · <P2> · <异常吞没致内存/持久化不一致>
证据：
```dart
// collect_logic.dart _doToggle：先改内存镜像再 _flush()；_flush 失败仅 Log.w
_favorites.add(h); ... final flushed = _flush(); _notify();
return CollectResult(ok:true,...);  // ← 即使 flushed=false 仍向 UI 报成功
// download_song_sync.dart：catch 内 Log.e 后吞，不 rethrow → commit 对调用方仍报 done
```
问题：① 收藏 `_flush()` 返回 false（settings.setString 失败，如磁盘满）时，内存镜像已改、UI 报 ok、onChanged 触发，但重启后收藏丢失——「写成功才改镜像」的契约被持久化失败绕过，失败无回滚也无用户可见反馈。② `syncSongRecord` 吞异常后，`DownloadCommitter.commit` 仍 `_mark(done)`——文件与索引已落盘但曲库未建档，library「本地曲库」不显示该曲，用户以为下载成功却找不到。③ `CacheService.get` 失败吞成空 Map（`cache_service.dart:127-130`，阶段A4 X10 已记），上层无法区分「无数据」与「失败」，与 collect 的 needsLogin/失败态处理形成不一致的降级语义。均属异常吞没后跨层状态不一致（非崩溃）。
建议：收藏 `_flush` 失败时回滚内存镜像（`wasCollected` 分支反向操作）并把 `ok=false` 返回给 UI 提示；`syncSongRecord` 失败上抛让 committer 标记 failed（文件保留但提示重试建档）；CacheService.get 增加可选 `throwOnError` 或返回带 error 标记的载体供需要区分三态的调用方使用。
76 合规：76 §每方法 try/catch+Log 遵守（均留痕）；但"吞异常"后的状态一致性属正确性债。

## <视角 C2> · <跨层结论：阶段A四条链真通性裁定> · <—> · <裁定汇总>
证据与裁定（逐链）：
- **下载链**：L7 入口（player_page.dart:242-272 ⋮菜单→mgr.enqueue('128')）✅真接；L5 enqueue→resolvePlaySource→分块下载→committer→L4 commitDownload（文件+索引）+SongDao 建档 ✅真实落盘；但 L7 library 页无 onTask 订阅、任务内存态无恢复、deleteWithFile 无入口 → **半通**（写入通，展示/恢复/删除断）。阶段A索引原子 rename 修复✅生效；实体文件 commit 仍有 deleteSync 空窗。
- **收藏链**：L7 FavoriteButton（player_page.dart:68-123）✅真读镜像+真 toggle+needsLogin Snackbar；L5 写成功才落 settings 镜像、按 uid 分键、重启 `_load()` 可读回 ✅持久化成立；但换号不 resetLocalMirror + 无 onChanged 注入 → 多账号串号；getFavoriteCount 空 query → 计数恒不准 → **半通**（单账号正向通，换号/计数断）。
- **歌单写链**：L4 端点+DAO 完整、L5 write logic 齐全，但 L7 零入口、`saveLocalMirror` 零调用、镜像恒空 → **断**（能力在，用户用不到）。
- **缓存链**：L2 ResourceCache 固化/原子/失败信号阶段A修复✅生效（`_cacheableSuccess` 只存成功非空）；但 CacheService.prefetch 预读参数与业务不匹配 + 两张缓存表不相交 → 预读真命中≈0 → **半通**（存储正确、预读失效）。
未发现 P0（无崩溃级/数据全丢级新缺陷）；最严重为 6 条 P1（UI事件断、崩溃恢复、换号串号、计数空转、预读失效、歌单写零入口）+ 实体文件 commit 空窗。

## 本视角结论
C2 共落 8 条（P1×7、P2×1），全部证据化、带行号。阶段A在本批涉及的 4 项修复（下载索引原子 rename、resource_cache 写失败信号、收藏/下载 L7 入口）经端到端核验**单点均生效**，但暴露出跨层接缝的系统性弱点：L5 提供的事件/重置/镜像能力（onTask、resetLocalMirror、onChanged、saveLocalMirror）在 L6 装配层/L7 消费层**未被接线**，导致"能力存在≠用户可用"。下载写入链、收藏正向写链是真实可用的；歌单写链与缓存预读链实质不可达/不命中。建议主会话按 P1 优先补：①L6 统一 AuthChanged→collect.resetLocalMirror/playlist.invalidatePrefix；②library_page onTask 订阅；③歌单写 L7 入口+镜像写入；④预读键对齐或删无效 prefetch；⑤收藏计数改走歌单曲目总数。

## 未覆盖
- 未跑 dart/flutter/analyze/test/门禁（工具纪律禁止），所有结论为静态取证；端点是否真通服务端需实测。
- B2 已报的「search logic 独立缓存遗漏」本视角仅在预读键匹配处旁证，未重复展开。
- L5 download_manager 分块下载的 pause/resume/cancel 竞态细节（abort 标志、job.done 等待、_dlpart 清理）已连续读完，未发现确凿可报缺陷，但需动态并发测试确认（静态无法证伪时序）。
- AES Rcon/VIP/20028/MV 等其他批修复不在 B5 范围。
- bridge 层导出正确性仅按需核对（未逐文件审，属 B1/C1 范围）。

## 76 合规小结
- 依赖方向：本范围 L7→桥→L5→L4 方向正确，无反向 import、无 surface 反向依赖 logic 内部类；合规。
- 层职责：L4 storage/net 管 IO、L5 编排、L7 只画控件，基本合规；download_manager 内 dart:io/HttpClient 属阶段A已裁定的下载例外。
- 跨层接缝主要问题：①L6 装配层漏接 L5 提供的 resetLocalMirror/onChanged（状态机装配失职）；②缓存"一个域"未落实（L2 ResourceCache + L5 LruCache + CacheService 门面三套），直接导致预读失效——与 A4 X4 同根；③L5→L7 事件通道建而不用（onTask/onChanged 零订阅）。三者均非越级/反向依赖，而是"该接的线没接"。
- 行数门禁：范围内均 ≤500 行（download_manager 506 行为拆分后主文件，playlist_page 576 行为 A7 已知豁免），无新增违规。

## <勘误 · 2026-11-17 08:05 LCL>（追加，不覆盖上文）
上文「裁定汇总」段"最严重为 6 条 P1"计数笔误，以本节及「本视角结论」为准：本视角实为 **P1×7（发现 1–7）+ P2×1（发现 8）**，合计 8 条。7 条 P1 = 下载UI事件断 / 崩溃恢复缺失 / 换号收藏串号 / 收藏计数端点空转 / 预读键不匹配 / 歌单写零入口 / 实体文件commit删后rename空窗。
