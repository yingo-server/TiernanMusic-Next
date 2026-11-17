# B5 批 · C1 架构合规视角 · 下载 / 收藏 / 歌单 / 缓存

> 视角：C1 架构合规。范围：L7 library_page/playlist_page → L6 graph/bootstrap → L5 logic/download(6) + catalog(collect/playlist/playlist_write) → L4 storage/download_store、cache/cache_service、storage/resource_cache、database/dao、net/endpoints/collect_endpoints、playlist_write_endpoints。
> 纪律：只读（file_read / ls / rg / wc），不改源码，不跑门禁。
> 时间戳：2026-11-17（本节为首次落盘；后续结论以 append 追加）。

## 视角 C1 · lib/logic/download/download_manager.dart:14,344-363 · P0 · IO 直连 / 层级职责
证据：`download_manager.dart:14 import 'dart:io';`；`:344 final http = HttpClient()..userAgent=...`；`:359 part = File('${(await _storeDir())}...${task.hash}.dlpart')`；`:363 sink = part.openWrite();`；`:346-370` 由 L5 自己发起 HTTP 分块读流并写 .dlpart。同族文件同病：`download_commit.dart:5 import 'dart:io'`、`:41 File(...)`、`:53 await part.readAsBytes()`；`download_paths.dart:6 import 'dart:io'`、`:22 Directory.systemTemp.path`、`:42 cleanupPartFile(File?)`。
问题：下载的网络 IO 与文件 IO 全部留在 L5 logic/，未下沉到 L4 core/storage（阶段 A A5-C1 报过 6 处，本批复核**仍在**，共 3 文件 6+ 处触点）。
建议（只写不改）：新建 `lib/core/storage/download_transport.dart`（L4）承担 HttpClient 分块下载 + .dlpart 读写/清理，暴露 `downloadToPart(url, sink, onProgress)`/`commitPart` 门面；L5 只保留任务状态机与编排，`dart:io` 从 L5 全部移除。
76 合规：**违反** §1（L5 明确禁止「IO 直连」）、§0 铁律 4（每层只依赖其下层经桥暴露的门面）。

## 视角 C1 · lib/logic/download/download_manager.dart:344 · P1 · 端点模块缺失 / §6
证据：`rg -n download lib/core/net/endpoints` 仅命中 `misc_endpoints.dart`/`lyric_models.dart` 的字面量，**无 `download_endpoints.dart`**；下载 URL 由 `PlaybackService.resolvePlaySource` 解析后，L5 自建 `HttpClient` 直取 URL 并自行设置 `Range: bytes=0-`。
问题：下载域没有「一端点一模块」的 L4 端点层封装，请求头/重试/断点策略散在 L5 的私有方法 `_downloadUrl` 内，与 core/net 的统一客户端（KugouClient + ResourceCache + InFlight）不在同一体系。
建议：把下载请求（Range、超时、UA、备用链）收进 `lib/core/net/endpoints/download_endpoints.dart` 或至少由 L4 transport 统一发出，使 L5 只做状态机。
76 合规：**违反** §0 铁律 6（core/net/endpoints 每端点一模块）+ §1（L5 禁 IO 直连）。

## 视角 C1 · lib/core/cache/cache_service.dart:1 + lib/core/storage/resource_cache.dart:1 + lib/core/memory/lru_cache.dart + lib/core/net/inflight.dart · P1 · 缓存域分散（§3 缓存⊃预读）
证据：缓存实现分布于四处 —— L1 内存 `lib/core/memory/lru_cache.dart:14 class LruCache`、L2 磁盘 `lib/core/storage/resource_cache.dart:66 class ResourceCache`、单飞合并 `lib/core/net/inflight.dart`、门面 `lib/core/cache/cache_service.dart:101 class CacheService`；`cache_service.dart:7-8` 自述「底层唯一执行者 = KugouClient.request 自带的 ResourceCache(L2 磁盘) + InFlight(单飞)」。全仓 `rg 'PrefetchEngine'` 无命中（无独立预读引擎类，符合 §3）。
问题：§3 要求「一个域 `lib/core/cache/`」，实际门面在 cache/ 而 L1/L2/单飞散在 memory/、storage/、net/，域分散问题（A4 X4）**未修**。
建议：把 LruCache/ResourceCache/InFlight 迁入 `lib/core/cache/`（如 cache_l1.dart / cache_l2.dart / cache_inflight.dart），cache/ 成为唯一域；或改写 §3 明确允许的例外清单。
76 合规：**违反** §3「一个域：lib/core/cache/」。

## 视角 C1 · lib/core/cache/cache_service.dart:104-171 · P1 · 门面契约不全 / 来源标记缺失
证据：CacheService 公开 API 仅 `get`(:123)、`prefetch`(:141)、`invalidateSession`(:166)、`stats`(:172)、`toJson`(:170)；**无 `put`、无按 key 的 `invalidate`**；`enum CacheOrigin { network, prefetch, hit }`(:40) 仅在 `bridge_core.dart:51` 被 export，全仓无使用点；`prefetch` 内部直接调 `get`，未给写入打 `prefetched` 来源标记。
问题：§3 规定的契约 `get / put / prefetch(keys) / stats / invalidate` 缺 `put` 与按 key `invalidate`；预读作为「写入策略」缺少 `prefetched` 来源标记，无法区分命中来源（诊断/失效策略都无法按来源工作）。
建议：CacheService 补 `put(ep, params, body)` 与 `invalidate(key)`；prefetch 路径在 client 落盘时写入 `source=prefetched` 元数据（ResourceCache.putString 已有 ttlMs 元数据位可扩展）。
76 合规：**违反** §3（CacheService 是唯一入口，契约五方法；预读带来源标记 `prefetched`）。

## 视角 C1 · lib/core/cache/cache_service.dart:49-100,171 · P1 · 统计口径跨层不一致 + 门面死代码
证据：`CacheServiceStats.hits/writes/evictions` 恒 0，`exposeRealCounters=false`，`source='facade-only; KugouClient has no public cache/inflight stats getter'`(:53-55, :171)；底层真实计数在 `resource_cache.dart:454 stats()` 里存在（hits/misses/evictions 内存计数），但 `KugouClient` 未暴露 getter（kugou_client.dart:56 `final ResourceCache? _cache;` 私有）。另 `rg 'cache.stats|CacheServiceStats'` 在 lib/surface 与 lib/session 均无调用，`settings_page.dart:75,142` 只调 `invalidateSession()`。
问题：L4 门面对外谎报「零命中零写入」（已诚实标注但仍是死数据），且 stats 能力无任何消费者 → 跨层缓存状态不可观测。
建议：KugouClient 暴露只读 `cacheStats`/`inflightStats` getter，CacheService 转发真实计数；settings 诊断页读 `appGraph.cache?.stats`。
76 合规：**违反** §3（stats 属门面契约）+ §0 铁律 2（桥/门面留痕与可观测）。

## 视角 C1 · lib/session/bootstrap.dart:213-224 + lib/session/playback_session.dart:75,181-184 · P1 · 预读策略未接线（队列 upcoming 窗口）
证据：`bootstrap.dart:214-216 PlaybackSession.instance.onQueueChanged = (hashes) { Log.d(...'cache keeps LRU warm'); };` —— 回调体内**只有一条 Log**，不调用 `cacheService.prefetch`；`playback_session.dart:181-184` 注释写「缓存 ⊃ 预读：队列变化即预热后续曲目」，实际只把 hash 列表抛给上面那个空回调。真正的 prefetch 只在启动时对热搜/榜单各发一次（`bootstrap.dart:217-224`）。
问题：§3 要求的「队列 upcoming 窗口预测键 → 由 CacheService 写策略执行」整条链未闭合；预读退化为启动时两个固定端点，与播放队列无关。
建议：`onQueueChanged` 回调体内构造 upcoming 键（曲名/歌手/榜单类可缓存端点）调 `cacheService.prefetch(...)`；键的预测在 session 层，写入仍只在 L4 CacheService。
76 合规：**违反** §3（预读触发由 session 决定预测键 + CacheService 执行写入）。

## 视角 C1 · lib/session/graph.dart:143-146 + lib/surface/pages/library_page.dart:7,33-34,282-283 · P1 · 六桥通道越级（L7 直取 L4 DAO）
证据：`graph.dart:143-146` AppGraph 对外暴露 `SongDao? songDao; HistoryDao? historyDao; KugouClient? client;`；`library_page.dart:33-34` `_localSongs = appGraph.songDao?.list(); _recentSongs = appGraph.historyDao?.recent();`（`:282-283` 重试用同一路径）；`library_page.dart:7 import '../../bridges/bridge_core.dart';`。门禁 `tool/layer_audit.py:40` 的 `LAYER_ALLOWED_BRIDGES[7]` 含 bridge_core/bridge_logic，故门禁不拦；但 §1 规定「L7 surface 经 bridge_surface 拿 L6 的门面」。
问题：L7 经 AppGraph 直取 L4 数据访问对象（DAO），数据查询绕过 L5/L6 门面；同一仓库两条口径并存（门禁放行 vs 76 §1）。
建议：把「本地曲库 / 最近播放」查询收进 L5（如 `library_query_logic`）或 L6 门面（`appGraph.localSongs()`/`appGraph.recentPlays()`），L7 去掉 bridge_core import；同步修订 layer_audit 的 L7 白名单或补 LAYER_EXCEPTIONS 说明。
76 合规：**违反** §1（L7 只经 bridge_surface 取 L6 门面）+ §0 铁律 1/4。

## 视角 C1 · lib/surface/pages/library_page.dart:8 + lib/surface/pages/playlist_page.dart:4-5 · P1 · L7 依赖 L4/L5 类型，桥未收敛
证据：`library_page.dart:8 import '../../bridges/bridge_logic.dart';`（DownloadTask/DownloadStatus 经 bridge_logic 直接进 L7）；`playlist_page.dart:4 import '../../bridges/bridge_core.dart' show PlaylistMeta;`、`:5-6 bridge_logic show Log, SongBrief, PlaylistBrief, PlaylistDetail, TrackPage;`。
问题：L7 直接依赖 L5 状态类型（DownloadTask/PlaylistDetail/TrackPage）与 L4 实体（PlaylistMeta），六桥未把跨层类型收敛为 L6 门面契约，跨层接缝一变签名即碎多个页面。
建议：L6 门面暴露只读视图模型（download 列表项、playlist 摘要行），L7 只依赖这些 L6 类型；`PlaylistMeta` 等 L4 类型不进 L7 import。
76 合规：**违反** §2 六桥表（L7↔L7 唯一桥为 bridge_surface）+ §0 铁律 4。

## 视角 C1 · lib/logic/download/download_manager.dart:58 + lib/surface/pages/library_page.dart:63-66,296-330 · P1 · 状态机出口断裂（onTask 零订阅）
证据：`download_manager.dart:58 void Function(DownloadEvent event)? onTask;` —— 全仓 `rg 'onTask'` 仅命中定义、`:236 onTask = null`、`:471 final cb = onTask;`，**无任何赋值订阅者**；`library_page.dart:63-66` 仅在 initState 调一次 `dm.listTasks()`，`_downloadsTab()` 直接渲染 `_downloads` 快照，**从不重取**。
问题：下载任务状态机在 L5，但事件出口无人订阅 → 下载进度/完成态无法抵达 L7；「下载管理」页签永远显示初始快照（跨层接缝断裂，阶段 A「下载零入口」修复只做了入口未做出口）。
建议：在 L6 session 订阅 `onTask` 并暴露 `Stream`/快照给 L7（surface 订阅 session 门面，不直接挂 L5 回调）；library_page 订阅后 setState。
76 合规：**违反** §1（L6 编排会话层负责暴露状态/回调）+ §0 铁律 2（事件留痕链）。

## 视角 C1 · lib/session/bootstrap.dart:180-184 + lib/logic/catalog/playlist_write_logic.dart:31-157 · P1 · 歌单写域死代码（L5 装配了但无出口）
证据：`bootstrap.dart:180-184` 装配 `PlaylistWriteLogic(client: client, playlistDao: playlistDao)` 并放进 AppGraph.playlistWrite；全仓 `rg 'myPlaylists|createPlaylist|deletePlaylist|removeSongsFromPlaylist|playlistWrite'` 在 `lib/surface` 与 `lib/session` **零调用**（仅 bootstrap 装配行）；`playlist_logic.dart:169 addSongsToKugouPlaylist`、`:210 saveLocalMirror` 亦无任何调用方。`playlist_page.dart` 只做只读（recommend/listLocal/detail/tracks）。
问题：歌单写状态机在 L5 位置正确，但缺 L7 出口，整域为死代码；阶段 A/B1 未覆盖此域。
建议：为歌单页补「新建/删除/加歌/删歌」入口，L7 → L6 门面 → appGraph.playlistWrite；或明确标注 roadmap 并从装配图中摘除以免误判为可用能力。
76 合规：**违反** §1（L7↔L6 必须有真实通路；L6 装配图不得承载无出口能力）+ §0 铁律 2。

## 视角 C1 · lib/session/bootstrap.dart:150-157 + lib/logic/catalog/collect_logic.dart:34,86-88,388-397 · P1 · 收藏镜像变更无订阅者
证据：`collect_logic.dart:34 void Function()? onChanged;`、`:386-397 _notify()` 全仓调用 `cb()`，但 `bootstrap.dart:150-157 CollectLogic(client:, settings:, isLoggedIn:)` **未注入 onChanged**；L7 侧 `library_page.dart:52` 只在首次进入调 `c.refreshCount().then((_) => c.count)`，之后不再刷新。
问题：收藏镜像变更通知链断在装配层（能力存在但未接线）；「我喜欢 N」计数与收藏状态在同页跨操作后不同步。
建议：bootstrap 注入 onChanged → 经 L6 门面通知 L7 刷新计数；或由 L7 订阅 session 暴露的收藏快照。
76 合规：**违反** §1（L6 编排会话层负责状态广播）+ §0 铁律 2。

## 视角 C1 · lib/core/storage/download_store.dart:174,236-258 · P2 · L4 门面能力与上层不对齐（死代码）
证据：`DownloadStore.listAll()`(:174) 与 `deleteWithFile(hash)`(:236) 全仓零调用；下载管理页无「已下载列表/删除」入口，L5 `DownloadManager` 只做任务队列，不查索引。
问题：L4 下载索引的读取/删除能力无消费者，「下载管理」页签只显示内存任务，不显示已落盘文件。
建议：在 L5 DownloadManager 增 `listDownloaded()`/`removeDownloaded(hash)`（经 bridge_core 的 DownloadStore），L6 暴露给 L7。
76 合规：**符合**（层级方向正确；属能力缺口而非越级）。

## 视角 C1 · lib/logic/download/download_manager.dart:6-9,58-63 · P2 · 状态机持久化缺口
证据：`download_manager.dart:6-9` 注释明写「任务队列为内存态，启动不恢复」；`_tasks/_order` 为纯内存 Map/List；落盘侧 `download_store.dart` 的 index.json 却是持久的。
问题：进程重启后，磁盘已有下载文件与索引，但 L5 下载任务态归零，两套状态可互相矛盾（「已完成文件」被当作「未下载」）。
建议：在 L4 download_store 增加 task 状态字段持久化，或在 L5 启动时以索引重建 done 态任务快照。
76 合规：**符合** §1（L5 持状态机数据），属设计缺口。

## 视角 C1 · lib/surface/pages/library_page.dart:26-30,284-287 · P2 · L7 自持状态镜像 + 日志纪律不一致
证据：`library_page.dart:26-30` L7 持有 `_downloads/_profile/_favCount/_localSongs/_recentSongs` 五个局部状态镜像（收藏计数、下载列表与 L5/L6 各自一份）；`:284-287` `_reloadLists` 的 catch 用 `debugPrint('library: reload failed: ...')` 而非 `Log.e`。
问题：状态在 L5 与 L7 双份，且 L7 错误走 debugPrint 不走统一 Log（桥/门面层留痕纪律在 L7 侧破口）。
建议：L7 只保留「当前 Future/快照句柄」，计数与列表真值由 L6 门面单点持有；L7 错误改走 `Log.e('surface.library', ...)`。
76 合规：**违反** §0 铁律 2（失败必 Log 留痕，不静默吞）——虽在 L7 而非桥文件，但同源纪律。

## 视角 C1 · lib/logic/catalog/collect_logic.dart:400-418 vs lib/logic/catalog/playlist_logic.dart:210-236 · P2 · 镜像存储源跨域不一致
证据：收藏镜像持久化在 `KeyValueSettings` 的 JSON 字符串键（`favorites.<uid>` / `favorites.fileids.<uid>`，collect_logic.dart:400-418）；歌单本地镜像持久化在 `PlaylistDao`（DB 表，playlist_logic.dart:210-236）；下载态完全不持久化（见上一条）。
问题：同一「本地镜像」概念在本批三个域用了三种介质（settings JSON / DB / 内存），跨层读取路径不一致，且收藏域无法被 SQL 统计。
建议：统一镜像介质（建议全部进 DB，settings 只留会话级凭据），或写明介质矩阵并纳入 §3/§1 的域约定。
76 合规：**符合** §1（介质均在 L4，层向正确），属职责一致性建议。

## 视角 C1 · lib/session/graph.dart:78-146 + lib/session/playback_session.dart:70-80 · P2 · 规则内部冲突（装配图/预读触发落在 L6）
证据：`graph.dart`（L6）持有并暴露全部装配图（AppGraph，含 downloads/collect/playlistWrite/cache）；`playback_session.dart:75`（L6）声明 `onQueueChanged`（注释「bootstrap 接给 CacheService 做 upcoming 预读」）。而 §0 铁律 8 明写「播放控制/播放列表/缓存/预读/装配图 一律不得放进 L6」，§1 又把「装配图/播放编排/预读触发」列为 L6 职责，§4 更把 playback_session 定为「L7 session」。
问题：76 规则自身对 L6 边界有两套说法，本批（缓存/预读/装配图全在 L6）无法单方判定合规，需用户裁定后统一。
建议：由用户裁定 L6 是否保留装配图与预读触发；若保留，修订 §0 铁律 8 文案（改为「不得放入 L7 surface」）；若不保留，graph/playback_session 下沉。
76 合规：**规则冲突待裁定**（§0 铁律 8 vs §1/§2/§4）。

## 视角 C1 · 全仓 wc · P2 · 1500 行门禁
证据：`rg --files lib | xargs wc -l | sort -rn | head` 最大文件为 `lib/core/net/crypto_aes.dart` 792 行；本批最大 `lib/surface/pages/playlist_page.dart` 576、`lib/logic/download/download_manager.dart` 506、`lib/core/storage/resource_cache.dart` 479、`lib/core/database/dao.dart` 431、`lib/core/net/endpoints/playlist_write_endpoints.dart` 371、`lib/core/net/endpoints/collect_endpoints.dart` 287、`lib/core/storage/download_store.dart` 258、`lib/core/cache/cache_service.dart` 173、`lib/logic/catalog/collect_logic.dart` 392、`playlist_logic.dart` 265、`playlist_write_logic.dart` 157。
问题：无文件接近 1500 行门禁。
建议：无。
76 合规：**符合** §0 铁律 5。

## 本视角结论
本批 C1 共 17 条：P0 1 条、L5 IO 直连（L3 条）、P1 11 条、P2 5 条。架构主干（下载/收藏/歌单写状态机归属 L5、端点与存储在 L4、桥文件唯一）方向正确，未见反向依赖与影子桥；但 **§3「缓存⊃预读一个域」在本批基本未落地**（域分散三处、CacheService 缺 put/invalidate、来源标记未接线、stats 恒 0、队列 upcoming 预读回调为空实现、启动预读与播放队列无关），**L5 下载 IO 直连未修**（dart:io + HttpClient 仍在 L5，下载域无 L4 端点模块），**六桥通道在 L7 侧两头失守**（AppGraph 对外暴露 SongDao/HistoryDao/KugouClient，L7 直取 L4 DAO 并直接依赖 L4/L5 类型；门禁 layer_audit LAYER_ALLOWED_BRIDGES[7] 放行 bridge_core/bridge_logic，与 §1「L7 只经 bridge_surface」不一致），**三个域的 L5→L7 出口均断裂**（下载 onTask 零订阅、收藏 onChanged 未注入、歌单写域全死代码）。

## 未覆盖
- `lib/core/database/dao.dart` 只读了方法签名清单，未逐行审（SongDao/PlaylistDao/HistoryDao 内部实现与事务/并发）。
- `lib/core/net/endpoints/playlist_write_endpoints.dart` 后半（getPlaylistTags/getUserPlaylists）与 `collect_endpoints.dart` 已读全文，但未逐端点核对 EndpointRegistry 的 cacheable 标注。
- `lib/session/playback_session.dart` 未读全文（仅读 70-90、170-195 段），下载/预读在播放会话内的其余耦合未查。
- `lib/surface/pages/settings_page.dart`（缓存清理入口）、`lib/bootloader/bootloader.dart`（core 单例装配全貌）、`lib/core/net/kugou_client.dart`（缓存/单飞接线全貌）仅做定向 grep 抽样。
- 未核查 `docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md` 等历史结论与本报告的冲突项。

## 76 合规小结
- **违反**：§1（L5 禁 IO 直连 ×3 条；L7 只经 bridge_surface 取 L6 门面 ×2；L6 状态广播缺失 ×2）、§3（缓存⊃预读一个域 / CacheService 五方法契约 / `prefetched` 来源标记 / 队列 upcoming 预读触发，共 4 条）、§0 铁律 1/4（越级 import）、铁律 2（事件/日志留痕链断裂）、铁律 5（符合）、铁律 6（下载域缺 L4 端点模块）、§2（L7↔bridge_surface 唯一桥被绕过）。
- **符合**：铁律 5（无文件超 1500 行）；§1 层向（状态机在 L5、端点/存储/DAO 在 L4、装配在 L6）；无反向依赖、无影子桥目录；无独立 `PrefetchEngine` 类（符合 §3 降级要求）；桥文件 try/catch+Log 覆盖良好（download/collect/playlist_write 六文件均逐方法 try/catch+Log）。
- **规则冲突待裁定**：§0 铁律 8 vs §1/§2/§4 关于 L6 是否可持有装配图/预读触发/播放编排。
