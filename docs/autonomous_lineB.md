# 自主线B UI 业务补全 · 最终报告（2026-11-15）

状态：**阶段1 检查完成并落盘；阶段2 修复、阶段3 自检未执行**（委派方在时间过半时要求
立即收尾、不再改大范围代码）。本报告自身即完整交付物；详细只读核实证据见
`docs/autonomous_lineB_c.md`，功能清单见 `docs/autonomous_lineB_features.md`。
本次**未修改任何代码文件**，未触碰线A范围与任何禁区文件，未提交 git。

---

## 一、完成

1. `docs/autonomous_lineB_c.md`（阶段1 检查报告，11KB）已落盘，逐项核实任务书要求的
   ①~⑤，全部基于 `file_read` 实读源码，无臆造方法名：
   - ① 三 Tab DAO 接线缺口：`AppGraph` 缺 `songDao` / `historyDao` 出口；
     `SongDao.list({SortKey,SortOrder}) → Future<List<SongRecord>>`、
     `HistoryDao.recent({int limit = 50}) → Future<List<PlayHistoryEntry>>`、
     `DownloadManager.listTasks() → List<DownloadTask>`（**同步**）均已确认真实签名与返回类型；
     桥已导出 `SongDao/HistoryDao/SongRecord/PlayHistoryEntry` 及 `appGraph`，只差 AppGraph 可选字段+装配。
   - ② MV 页/入口完全缺失（`enabled:false` 占位模块，shell 只注册 7 个真实模块）；
     `video_player: ^2.9.2` **已在 pubspec**，且 `tool/layer_audit.py L7_EXTRA` 与
     `tool/smoke_check.dart _l7Extra` **已白名单允许** `package:video_player`（L7 可用成熟库内嵌播放）；
     `bridge_logic.dart` 导出名确认为 `MvLogic`（另有 `MvQuality/MvBrief/MvPlayResult` 经 bridge_core）。
     代码事实：player_page ⋮ 菜单**实为 3 项**（歌词/评论/个人 FM），任务书「现有 4 项」与代码不符。
   - ③ `playlist_write_endpoints.dart:19-26 _ok()` 把 `status==0` 与 `error_code` 兜底 0 当成功；
     `docs/api_samples/anonymous.json` 顶层 `status:0`、`tool/field_truth_test.dart` A6-6
     失败样本 `{'status':0,'error_code':20010,'data':''}` 会被误判成功。
     实测留样 A6-2/3/4 的 `data.info.listid` / `data.info[].fileid,audio_id` /
     `data.pre_list_ver,list_ver,count` 全部被丢弃；`CollectResult` 只有 `ok/needsLogin/count/fileId`，
     所有失败态折叠成 `ok:false`，不可区分。
   - ④ FM / 云盘 / 高潮 / 评论在 L7 零接线：`FmLogic`、`CommentLogic`、
     `getSongClimax`、`getUserCloud` 均在 L5/L4 存在；player_page 的 `requestTab('fm')` /
     `requestTab('comment')` 因无真实模块注册/无 navEntry 而是死入口；
     `FavoriteButton` 是纯本地 `setState` 假收藏（源码注释自认）。
   - ⑤ `appGraph.mv / comment / fm / user` **四个 logic 单例已全部装配**（bootstrap.dart:62/69/76/80、
     128-151），无需补构造；此外 album/artist/searchTyped/recommend/verification/history/playback/
     playlistWrite/translation/account/cache/notification 也已装配但 L7 零/低消费。
     `AppGraph` 真正缺的是 `songDao` / `historyDao` / `KugouClient` 出口（已在 SessionDeps 与
     bootstrapSession 参数中，复用同一实例即可，不重复构造、不破坏 7 页）。
2. `docs/autonomous_lineB_features.md` 已落盘（逐功能「实现/待实测/未做」清单）。
3. 约束遵守：只用 `file_read` 读文件；`rg`/`ls` 类终检合计 ≤8 次；总工具调用远低于 90；
   未提交、未改 `.github/**`、`tool/local_gate.sh`、`README.md`、`docs/plan_*`、
   `docs/API_*`、`docs/autonomous_lineA*`、`docs/autonomous_lineC*` 及任务书全部禁区。

## 二、未完成（TODO，按任务书阶段2/3 原样保留给后续代理）

- [ ] `lib/surface/pages/library_page.dart`：三 Tab 接真数据（本地=appGraph.songDao.list()、
      最近=appGraph.historyDao.recent()、下载=appGraph.downloads.listTasks()）；Future 一律 initState
      持有（禁止 build 内 Future）；空态文案改为真实数据状态，删「能力尚未接入」；≤500 行。
      注意 `PlayHistoryEntry` 只有 fileName/singerName/playedAt/durationPlayedMs，无 cover，列表行勿臆造封面。
- [ ] 新建 `lib/surface/pages/mv_page.dart`（≤320 行）：`SurfaceModule(id:'mv')`、`navEntry:null` 排尾；
      展示封面/清晰度档位/播放按钮；用 `video_player` 内嵌（pubspec 与 L7 白名单均已允许）；
      清晰度链经 `bridge_logic.MvLogic.qualities()/playUrl()`，按 size 升序**最低档 ld 优先**
      （用户裁定：匿名只取音频流、音质不重要）；档位空/无地址/初始化失败三态区分，不冒充可播。
- [ ] `lib/surface/pages/player_page.dart`：⋮ 菜单加「MV」项（现 3 项 → 4 项），只接导航意图，≤500 行。
- [ ] `lib/session/{graph,bootstrap}.dart`：补 `AppGraph.songDao/historyDao/client` 最小可选字段并在
      `_graph = AppGraph(...)` 装配同一实例；`mv/comment/fm/user` 已存在，按「若缺」条件**无需补**；≤500 行。
- [ ] `lib/core/net/endpoints/playlist_write_endpoints.dart`：`_ok()` 改为**必须 status==1 且
      error_code==0**（顶层/data 双容错，`error_code` 缺失按 0 但不得把 `status=0` 当成功）；
      写回执解析 `list_ver`（以及 `data.info[].fileid/audio_id/listid/count`）并返回给调用方
      （建议新增纯数据回执类，保持旧函数签名兼容以免破坏 playlist_endpoints.dart:206 的转发）。
- [ ] `lib/core/net/endpoints/collect_endpoints.dart`：收藏加/删回执校验 `data.info[].fileid` 与
      `list_ver`，失败不冒充成功；`CollectResult` 扩 `reason`/`listVer` 字段区分失败态。
- [ ] `lib/core/net/endpoints/comment_endpoints.dart`：正常响应但 `status!=1`/非 JSON 也写
      `blockedReason`；`getCommentFloor` 受限原因透传（建议返回带 reason 的结果或新增函数）；
      `getCommentCount` 失败与「真的 0 条」区分；不吞成空页。
- [ ] `lib/logic/catalog/{collect,playlist_write,comment,fm}_logic.dart`：消费新回执字段
      （list_ver 乐观并发、fileid 校验、失败原因透传）；`comment_logic.floor()` 受限页不得落缓存；
      FM 可见入口（appGraph.fm 已装配，可在搜索页或播放页加入口，端点未实测须显式标注）。
- [ ] 阶段3 自检未执行：`file_read` 回读全部改动文件、`wc -l` 确认 ≤500 行、无重复类名、
      无 build 内 Future、`cd 项目根 && /opt/dart/bin/dart format --output=none lib/surface lib/session
      lib/logic/catalog lib/core/net/endpoints` 无 `Could not`。**本次未运行 dart format，也未运行门禁脚本。**

## 三、冲突 / 风险（必须告知后续代理与集成方）

1. **shell 渲染限制**：`lib/surface/shell.dart:_modules` 过滤 `navEntry != null` 才渲染，
   `_onNavState()` 对找不到的 tabRequest 还会 `clearTabRequest()`；而任务要求 MV 模块
   `navEntry:null` 排尾且 `shell.dart` 属禁区 → **单独 `NavState.requestTab('mv')` 无法渲染 MV 页**。
   可行解：在允许文件（player_page）里「发出 requestTab('mv') 意图 + 用 `ModuleRegistry.byId('mv')`
   注册的 builder 做 `Navigator.push`」双动作；并需某处调用 `MvPageModule` 的注册（当前
   `registerModules()` 在禁区 shell.dart，若不能改，则需在允许文件内幂等 install）。
   此冲突未解决即实现 MV 入口会变成「点了没反应」，请勿忽略。
2. **FM 入口同病**：`moduleIds` 无 `'fm'`、无 navEntry、shell 不过滤不到的模块 → 现有
   `requestTab('fm')` 已是死入口；若不加页面/路由，加第二个可见 FM 入口只会重复死链。
3. **status 语义**：`status==1 && error_code==0` 是写操作唯一成功判据；但个别端点
   （如 `getFavoriteCount`）明确「尚无实测章节、不设 status 门槛」，修 `_ok` 时不得把读端点一并收紧，
   否则会把「待实测」的空样本误判成受限。
4. **写操作不外发**：plan 批8 要求所有写操作先确认弹层、真实外发需用户确认；本次未做任何真实网络调用，
   后续实现须保留「未实测端点显式态」与凭据脱敏（token 前后 4 位掩码，禁止整 token 落日志/文档）。
5. **线A 并行**：`lib/core/net/**`（除本任务明确允许的三个 endpoints 文件）与
   `lib/logic/player/**` 归线A。本报告/后续改动**未触碰**线A文件；合并时若线A 同时改了
   bridge 导出或 AppGraph 构造，需按「复用同一实例、不重复构造」原则对齐。

## 四、结论

阶段1 检查报告与功能清单已完整落盘，关键事实（DAO 真实方法名、video_player 已允许、
status=0 误判现场、appGraph 四单例已装配、shell 导航冲突）均已实读确认；
**代码修复与自检按委派方「立即收尾」指令未执行**，全部列入 TODO。无 git 提交、无禁区改动、
无与线A的文件冲突。
