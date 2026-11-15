# 线B 逐功能「实现 / 待实测 / 未做」清单（2026-11-15）

口径：**实现**=代码路径已存在并可离线核验；**待实测**=代码/端点存在但未经真机三态留样，
不得冒充可用；**未做**=本次线B 未落地（含全部阶段2 修复项）。
本清单随 `docs/autonomous_lineB.md` 一起交付；阶段2 未执行，故「未做」列全量保留为 TODO。

| # | 功能 | 实现 | 待实测 | 未做（本次） |
|---|---|---|---|---|
| 1 | 本地曲库 Tab 真数据（SongDao.list） | L4 `SongDao.list({SortKey,SortOrder})` 已实现；bridge_core 已导出 | DAO 数据内容为本地库，无需网络实测 | L7 接线（AppGraph.songDao 出口 + library_page 三态文案 + initState 持有 Future） |
| 2 | 最近播放 Tab 真数据（HistoryDao.recent） | L4 `HistoryDao.recent({limit:50})` 已实现；实体已导出 | 同上 | L7 接线（AppGraph.historyDao 出口 + 列表渲染） |
| 3 | 下载管理 Tab | **已实现**：`appGraph.downloads.listTasks()`（同步），library_page 已渲染 | — | 进度刷新订阅优化（未做，非任务硬要求） |
| 4 | 账号卡 / 我喜欢计数 | 已实现：`appGraph.user.profile()` + `collect.refreshCount()` | `get_my_info` / `favorite_count` 端点未实测，空态隐藏符合纪律 | 无 |
| 5 | MV 页（mv_page.dart） | L5 `MvLogic.qualities()/playUrl()`、`MvQuality/MvBrief/MvPlayResult`、L4 `getMvBySong/getVideoQualities/getVideoUrl` 均已实现并装配 `appGraph.mv`；pubspec 含 `video_player: ^2.9.2`，L7 白名单允许 | MV downurl 常为 http 明文；清晰度档可播性、匿名音频流最低档（ld）未真机实测 | **未做**：新建 mv_page.dart、封面/档位/播放按钮、video_player 内嵌、最低档优先、三态失败提示 |
| 6 | MV 入口（播放页 ⋮ / 搜索 MV 结果） | `NavState.requestTab(id)` 已实现 | — | **未做**：player_page 菜单加「MV」项（现 3→4 项）；搜索页 MV 结果入口 |
| 7 | video_player 内嵌播放 | 依赖与白名单**已具备** | 平台明文流量/解码兼容性未真机验 | **未做**：播放器初始化、错误态、生命周期 dispose |
| 8 | 收藏加/删回执校验 | `collectSongByHash` 已走「我喜欢」listid=2 → `/v6/add_song`；`cancelCollectByHash` 走 `/v4/delete_songs`；`CollectLogic` 有登录守卫+防重锁+fileid 镜像 | 写回执 `data.info[].fileid` / `list_ver` 三态未实测（plan 批8） | **未做**：回执校验、`status=0` 不冒充成功、失败原因区分、`list_ver` 消费；FavoriteButton 仍是本地假收藏 |
| 9 | 歌单写回执 / 成功语义 | `createPlaylist/deletePlaylist/addSongsToPlaylist/removeSongsFromPlaylist` 与 `PlaylistWriteLogic` 已实现 | 写回执未实测 | **未做**：`_ok()` 改 `status==1 && error_code==0`、解析并回传 `list_ver`/`fileid`/`count`，logic 消费 |
| 10 | 评论列表 / 楼层 / 计数 | `CommentLogic.comments/floor`、`CommentPage.blockedReason`（cmtlist catch 已透传）、L4 三条端点已实现 | cmtlist 有探针留样；floor 的 `tid/childrenid/mixsongid` 口径、commentCount 的 FileHash 口径待实测 | **未做**：正常响应受限透传、floor/count 不吞成空、受限页不落缓存、评论 L7 页面 |
| 11 | 个人 FM 可见入口 | `FmLogic.start()/next()` 已实现并装配 `appGraph.fm`；player_page 已有 `requestTab('fm')` 占位 | `personalFm / fmSongs` 端点**未实测**（空批次不落缓存，显式 needs probe） | **未做**：真实可见 FM 入口/页面；占位因模块未注册仍是死链 |
| 12 | 云盘列表 | `getUserCloud` 端点封装经 bridge_core 导出 | AES 契约**未实测**（plan 批9 A） | **未做**：L7 云盘列表页 |
| 13 | 高潮（songClimax） | `getSongClimax` 端点封装经 bridge_core 导出 | **未实测**（plan 批9 A） | **未做**：无 logic 门面、无 UI |
| 14 | 歌单写 / 相似推荐 / 六类搜索 L7 触达 | L5 logic 与装配图已齐（`playlistWrite/searchTyped/artist/album/recommend`） | 部分端点待实测 | **未做**（非本线阶段2 指定文件，列此备查） |
| 15 | AppGraph DAO/Client 出口 | `SessionDeps.songDao/historyDao/client` 与 `bootstrapSession` 参数已存在；`mv/comment/fm/user` 四单例**已装配** | — | **未做**：`AppGraph` 补 `songDao/historyDao/client` 可选字段并装配同一实例 |
| 16 | 阶段3 自检 | `dart` 工具链在 `/opt/dart/bin/dart` 可用（只读核实） | — | **未做**：回读改动文件、行数 ≤500、重复类名、build 内 Future、`dart format --output=none` |

## 判定汇总

- **实现且可用（离线可验）**：下载管理 Tab、账号卡/收藏计数读取路径、L4 DAO 与 L5 logic 单例装配、
  MV/评论/FM/用户/歌单写的 logic 与端点代码路径、`video_player` 依赖与 L7 白名单。
- **待实测（禁止冒充可用）**：MV downurl 与最低清晰度音频流、收藏/歌单写回执与 `list_ver`、
  FM/云盘/高潮端点、评论楼层与计数口径、`get_my_info`/`favorite_count`。
  所有相关 UI 必须显式「未实测 / 未返回 / 加载受限」态，禁止静默空页。
- **未做（本次收尾指令前止步）**：全部阶段2 代码修复（library_page / mv_page / player_page /
  graph+bootstrap / 三个 endpoints / 四个 logic）与阶段3 自检。详见 `docs/autonomous_lineB.md` 第二节 TODO。

## 集成冲突（复述，勿遗漏）

`shell.dart` 只渲染 `navEntry != null` 的模块且会清空找不到的 tabRequest；MV 模块要求
`navEntry:null` 且 shell.dart 属禁区 → `requestTab('mv')` 单独发出不可达。后续实现须在允许文件内
「requestTab 意图 + ModuleRegistry.byId('mv').builder 的 Navigator.push」双动作，并幂等安装
`MvPageModule`；FM 入口同病（`moduleIds` 无 'fm'）。
