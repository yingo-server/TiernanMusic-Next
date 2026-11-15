# 线B 阶段1 检查报告（只读核实，2026-11-15）

范围：docs/research_ui_nav_features.md、docs/plan_ui_api_batches.md（批6~9）、
lib/surface/pages/library_page.dart、lib/session/{graph,bootstrap}.dart、
lib/bridges/bridge_logic.dart、lib/logic/catalog/{collect,playlist_write,comment,fm,user}_logic.dart、
lib/core/net/endpoints/{playlist_write,collect,comment}_endpoints.dart。
辅助只读：bridge_core.dart / bridge_session.dart / dao.dart / entities.dart /
download_manager.dart / player_page.dart / shell.dart / app_root.dart /
contracts.dart / nav_state.dart / module_registry.dart / mv_logic.dart /
mv_endpoints.dart / pubspec.yaml / tool/layer_audit.py / tool/smoke_check.dart（门禁白名单）。

---

## ① 本地曲库三 Tab 缺哪些 DAO 接线

| Tab | 现状（library_page.dart:201/208/215） | 真实数据方法（已 file_read 核实） | 缺口 |
|---|---|---|---|
| 本地曲库 | `_localLibrary()` 恒 `SpStateView('本地曲库暂不可用', '本地歌曲数据库能力尚未接入本页')` | `SongDao.list({SortKey sort = SortKey.addedAt, SortOrder order = SortOrder.desc}) → Future<List<SongRecord>>`（dao.dart:69-80） | `AppGraph` **无 songDao 字段**；SessionDeps 有（graph.dart:32），bootstrapSession 参数有（bootstrap.dart:29），但只用于构造 PlaybackService/HistoryRecorder/DownloadManager，未写入 `_graph = AppGraph(...)`（bootstrap.dart:128-151） |
| 最近播放 | `_recentPlays()` 恒 `SpStateView('暂无最近播放', '播放历史能力尚未接入本页')` | `HistoryDao.recent({int limit = 50}) → Future<List<PlayHistoryEntry>>`（dao.dart:~298） | 同上：`AppGraph` 无 historyDao 字段 |
| 下载管理 | 已接 `appGraph.downloads.listTasks()`（library_page.dart:57）：`DownloadManager.listTasks() → List<DownloadTask>`（**同步**，download_manager.dart:63-70） | 无需新增 | 只在 `initState` 取一次快照，进度变更不刷新；但数据接线真实存在 |

实体字段（entities.dart，确认非臆造）：`SongRecord{fileName,singerName,albumName,durationMs,hash,quality,localPath,addedAt,playCount,lastPlayedAt}`；
`PlayHistoryEntry{hash,fileName,singerName,playedAt,durationPlayedMs}`；
`DownloadTask{song:SongBrief,quality,status,progress,displayName}`（download_models.dart:29-75）。
桥通道已具备：`bridge_core.dart` 导出 `SongDao/HistoryDao/SongRecord/PlayHistoryEntry`，
`bridge_session.dart` 导出 `appGraph`（session/bootstrap.dart 的全局 getter）。故只需在 AppGraph 补两个可选字段并装配，L7 无新增跨层 import。
注：`library_page.dart` 顶部注释与 :201/:208 文案「能力尚未接入」必须改成真实数据状态文案。

## ② MV 页/入口是否完全缺失、video_player 是否在 pubspec 与 L7 白名单

- **完全缺失**：`lib/surface/` 无 `mv_page.dart`；`rg mv` 在 surface 只命中无关字符串。
  `bootstrap.dart:122` 的 moduleIds 含 `'mv'`，但装的是 `_PlaceholderModule(id)`（`enabled:false`，
  bootstrap.dart:165-170）；`shell.dart:24-34 registerModules()` 只装 7 个真实模块，无 MvPageModule。
- `player_page.dart:_openMenu():153-185` 现有菜单 **实为 3 项**（歌词 / 评论 / 个人 FM），
  无「MV」；research 文档 §5/E11 写「菜单只有歌词/评论/FM」正确，任务书「现有 4 项」与代码不符，
  按代码事实加 MV 后成为 4 项。
- **video_player 已具备**：`pubspec.yaml:20 video_player: ^2.9.2`；
  `tool/layer_audit.py` 的 `L7_EXTRA` 含 `'package:video_player'`；
  `tool/smoke_check.dart:169` 的 `_l7Extra` 含 `'package:video_player', // MV inline shell (batch R2)`。
  → 允许且应当用成熟库内嵌播放（不是「待接入」占位的前提）。
- 清晰度链：`bridge_logic.dart:35` 导出名确认为 **`MvLogic`**（`show MvLogic, kMvCacheSchemaVer`）；
  `bridge_core.dart:21` 导出 `MvBrief/MvQuality/MvPlayResult`，`:128` 导出 `getMvBySong/getVideoQualities/getVideoUrl`。
  `MvLogic.qualities(mvHash)`/`playUrl(mvHash, {requestedId,title})` 已实现（mv_logic.dart:29/72），
  `AppGraph.mv` 已装配（bootstrap.dart:69、145），**L7 零消费**。
- 关键限制（需写入冲突栏）：`shell.dart:_modules` 过滤 `navEntry != null` 才渲染，
  且 `_onNavState()` 对找不到的 tabRequest 也会 `clearTabRequest()`；而任务要求 MV 模块
  **无 navEntry 排尾**、且 `shell.dart` 属禁区。故 `NavState.requestTab('mv')` 单独发出
  **无法渲染 MV 页**；需在允许文件内（player_page）以 ModuleRegistry 注册的 builder 追加路由 push，
  并同时发出 requestTab 意图（保持任务书要求的 NavState 入口语义）。
- 未实测纪律：MV `downurl` 常为 http 明文、清晰度档/视频轨可播性未在本环境真机实测；
  页面必须显式区分「档位为空 / 无可播地址 / 视频初始化失败」，不得冒充可播。
  匿名裁定：只取音频流、最低清晰度优先（ld 优先，按 size 升序），音质调节不影响 MV 链。

## ③ 写操作 status=0 误判现场

- `playlist_write_endpoints.dart:19-26 _ok()`：
  ```dart
  final s = safeInt(data['status'], safeInt(res['status'], safeInt(res['error_code'], -1)));
  if (s == 1 || s == 0) return true;   // ← status=0 当成功
  ...
  return s == 0;                        // ← 兜底再次把 0 当成功
  ```
  且 `error_code` 从未参与判定。`docs/api_samples/anonymous.json:15` 顶层 `status:0` 是
  「匿名无权限」样本；`tool/field_truth_test.dart:888` 的 A6-6 明文失败样本是
  `{'status':0,'error_code':20010,'data':''}` → 现状会把它判成功。
  受影响调用链：`createPlaylist` / `deletePlaylist` / `addSongsToPlaylist` /
  `removeSongsFromPlaylist` 全部用 `!_ok(res)` 判失败；`collect_endpoints.collectSongByHash`
  用 `rows.isNotEmpty` 当成功，`cancelCollectByHash` 用 `removeSongsFromPlaylist` 的 bool。
- **回执字段被丢弃**：`tool/field_truth_test.dart:857-888` A6-2/3/4 实测留样显示
  data.info.listid、`data.info[].fileid/audio_id/hash/name`、`data.pre_list_ver/list_ver/count`
  都有值；现状 `createPlaylist` 只取 listid、`addSongsToPlaylist` 只回传 info 原始 map 且
  **没解析 list_ver**、`removeSongsFromPlaylist` 只返回 bool、`deletePlaylist` 只返回 bool。
  `collect_endpoints.dart:144-154` 只从 rows.first 取 fileid/audio_id，未校验 status，
  也未消费 list_ver；`CollectResult` 只有 `ok/needsLogin/count/fileId`，
  所有失败都折叠成 `ok:false`（含「未登录」一种），**无法区分服务端拒绝/缺锚点/异常**。
- `comment_endpoints.dart`：`getMusicComments` 的 catch 已透传 `CommentPage.blockedReason`
  （:196-200，批3-F2 已修），但三条仍会吞成「空」：
  (a) 正常返回但 `status=0/error_code!=0` 或 `_raw_text` 非 JSON → 空 CommentPage 且
      blockedReason==null，UI 显示「暂无评论」；
  (b) `getCommentFloor` catch（:229）返回 `const <CommentItem>[]`，受限原因全丢；
  (c) `getCommentCount` catch（:260）返回 0，与「真的 0 条」不可区分。
  `comment_logic.dart:84-85` 把 floor 的空列表缓存成 `CommentPage(items: res)`，
  受限被固化，重试也恒空。

## ④ FM/云盘/高潮/评论在 L7 零接线清单

| 能力 | L5 logic / L6 装配 | L7 触达 | 端点状态 |
|---|---|---|---|
| FM | `FmLogic.start()/next()` 已实现并装配 `appGraph.fm`（bootstrap.dart:76、147）；bridge_logic:63 导出 | 仅 player_page `_openMenu` 的 `'fm'` 占位 `requestTab('fm')`；**moduleIds 无 'fm'**、shell 只渲染 navEntry 模块 → 死入口；无 FM 页 | `personalFm/fmSongs` 未实测（plan 批9 A），空批次不落缓存；L7 零消费 |
| 云盘 | `user_endpoints.getUserCloud` 经 bridge_core:136 导出；`UserLogic` 只暴露 `profile()` | 无页面/按钮；library_page 账号卡在 `UserProfile.isEmpty` 时整块隐藏 | AES 契约未实测（plan 批9 A） |
| 高潮 | `getSongClimax` 经 bridge_core:135 导出 | 零接线（无 UI、无 logic 门面） | 未实测（plan 批9 A） |
| 评论 | `CommentLogic.comments/floor` 装配 `appGraph.comment`（bootstrap.dart:62、146）；bridge_logic:51 导出 | 仅 player_page 菜单 `requestTab('comment')`（moduleIds 含 'comment' 但占位 `enabled:false`、无 navEntry）→ 死入口；无评论页/楼层/点赞 UI | cmtlist 有探针留样、floor 参数口径待实测 |
| 收藏写 | `CollectLogic.toggle` 已装配 `appGraph.collect`（bootstrap.dart:66、148） | `player_page.dart:FavoriteButton` 是**纯本地 setState 假收藏**（:64-82 注释自认「收藏域写端点尚未经桥暴露，故不写远端」），零调用 CollectLogic | 写回执未实测（plan 批8） |
| 歌单写 | `PlaylistWriteLogic` 装配 `appGraph.playlistWrite`（bootstrap.dart:82、149） | 零 UI | 写回执未实测 |
| MV | `MvLogic` 装配（bootstrap.dart:69、145） | 零 UI（见 ②） | 部分实测 + 待实测 |

`appGraph` 在 L7 的实际消费（rg 全量）：auth(5)、playlist(3)、search(2)、account(2)、
rank/lyrics/translation/user/collect/downloads/cache/playlistWrite? 各 1；
**fm / comment / mv / album / artist / searchTyped / recommend / history / playback 零消费**。

## ⑤ appGraph 已有但未消费的 logic 单例

`graph.dart:78-99` 字段 + `bootstrap.dart:128-151` 装配对照（已全部核实装配）：
`mv`、`comment`、`fm`、`user`（任务书点名的 4 个）**全部已装配**，无需补构造；
此外 `album / artist / searchTyped / recommend / verification / history / playback /
playlistWrite / translation / account / cache / notification` 也已装配但 L7 零/低消费。
其中 `AppGraph` 真正缺的是 **DAO 与 client 出口**（`songDao` / `historyDao` / `KugouClient`），
它们是 ① 三 Tab 与 ② MV 按歌曲解析 hash 的前置条件；均已在 SessionDeps / bootstrapSession
参数中存在，只需补「最小可选字段 + 复用同一实例装配」，不重复构造、不破坏现有 7 页。
`appGraph.mv/comment/fm/user` 的暴露形状无需改动（任务阶段2 第4项按「若缺」条件判定为无需补）。

---

## 结论 / 修复边界提示

1. 本阶段未改任何代码。阶段2 只改任务书列举文件；`shell.dart` / `app_root.dart` /
   `bridge_core.dart` / `bridge_logic.dart` / `module_registry.dart` / `tool/**` /
   `lib/core/net/endpoint_registry.dart` / `kugou_client.dart` / `play_endpoints.dart` /
   `mv_endpoints.dart` / `mv_anonymous.dart` / L4 cache/storage / surface/design 均只读。
2. 因 ② 的 shell 渲染限制，MV 入口必须「requestTab('mv') + 用已注册模块 builder 做路由 push」
   双动作；这是唯一在不碰禁区前提下让入口真实可达的做法，将在最终报告冲突栏写明。
3. 所有未实测端点（FM/云盘/高潮/MV downurl/写回执）在 UI 一律显式「待实测/未返回」态，
   禁止静默空页或假成功。
