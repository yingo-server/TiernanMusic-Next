# 批5-C3 真机验收清单（只读检查产出）

> 依据：FUNCTION_TREE.md（基准 bbe8cf2 / LTS v26.11.13.05）、docs/API_TEST_REPORT.md、README.md、lib/init/main.dart、lib/surface/app_root.dart。
> 本清单为**待执行**的真机人工验收项，不代表已通过；未实测项标注「待补测」。
> 失败排查统一入口：`adb logcat | rg 'TiernanMusicNext|Log'`（应用自建 Log 桥）；网络失败查 `lib/core/net/kugou_client.dart` 异常码（-1 网络 / -2 超时 / -3 非 JSON 解析错）。

## 1. 启动
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 1.1 | 冷启动 APK | 进入底部导航首页，无白屏/闪退 | 失败显示「无法启动」错误页 → `lib/init/main.dart` debugPrint `main: boot failure` / `core assembly incomplete` | 否 |
| 1.2 | 首次启动 DB | Isar 打开成功，日志有 `main: db ready` | `lib/core/database/db.dart` 打开失败留痕 | 否 |
| 1.3 | 底部导航项数与顺序 | 由 SurfaceRegistry 动态生成，非硬编码 | `lib/surface/registry.dart` + `Log.d('surface.app_root','services installed modules=…')` | 否 |
| 1.4 | 切换任意 tab | 页面正常渲染，异常时出现「重试」按钮 | `surface.app_root` `Log.e` / `_ModuleView` ErrorRetryBox | 否 |

## 2. 首页
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 2.1 | 每日推荐块 | 未登录应提示受限/错误，**不得显示「今日暂无推荐」空列表**（errcode=200103） | `docs/API_TEST_REPORT.md` §四-2；`user_endpoints.dart` | **需登录** |
| 2.2 | 榜单速览卡 | 展示 56 项；点击应能打开真实曲目弹层 | 若卡不可点看 `pages/home_page.dart` / `widgets/playlist_tracks_sheet.dart` | 否 |
| 2.3 | 热搜词 Chip | 点击能带关键词进入搜索 | 关键词丢失时看 `home_page.dart` onOpenSearch 调用 | 否 |
| 2.4 | 推荐歌单横滑卡 | 可点开真实曲目弹层 | `pages/playlist_tracks_sheet.dart` | 否 |

## 3. 搜索
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 3.1 | 搜「周杰伦」 | total=480、items=10，首项有 hash/歌名/歌手 | `endpoints/search_endpoints.dart`；`srcappid` 误注入会全线 20006 | 否 |
| 3.2 | 输入联想 | 300ms 防抖出联想 40 条，chip 点击可提交 | `pages/search_page.dart` `_onChanged` / search.suggestions | 否 |
| 3.3 | 热搜列表 | 270 条热词，点击填入并出结果 | `search_hot` → `group.keywords[]` | 否 |
| 3.4 | 分类段/分页 | 歌曲/歌单/专辑分段，滚到底自动分页 | `searchTyped` 六类分段 | 否 |
| 3.5 | 搜索结果点歌 | 进入播放并能出播放源 | 播放权限见第 6 组 | 否 |

## 4. 歌单
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 4.1 | 推荐歌单网格 | 下拉刷新可重载，滚动到底自动加载 | `pages/playlist_page.dart` `_loadRecommend/_loadMore` | 否 |
| 4.2 | 歌单曲目页 | 「播放全部（N首）」可播；空歌单显示「暂无曲目」且按钮不渲染 | `pages/search_detail_page.dart`；`playlistDetail/playlistTracks` | 否 |
| 4.3 | 保存镜像 | 提示保存成功，生成本地镜像歌单 | `PlaylistWriteLogic.saveLocalMirror`；`playlistDao` | **需登录**（写接口） |
| 4.4 | 我的歌单/增删 | 可新建、改名、删歌单并持久化 | `logic/playlist/` + `addSongsToPlaylist`（`/v6/add_song` + x-router） | **需登录** |

## 5. 播放
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 5.1 | 点歌播放 | MiniBar 出现、播放页可拖动进度、倍速/音质可改 | `PlayerController` / `PlaybackService`；`player_controller.dart` | 否（VIP 曲见 5.3） |
| 5.2 | 队列弹层 | 播放页⋮或封面上滑可开，可跳转/移除、当前曲高亮 | `widgets/queue_sheet.dart` | 否 |
| 5.3 | VIP 曲播放 | 非VIP 应明确报权限受限（status=2/priv_status=0），**不得静默无响应** | `endpoints/play_models.dart` privKnown/20028 判定；API 报告 §五-2 | **需 VIP** |
| 5.4 | 播放模式 | 顺序→单曲循环→随机→循环 循环生效 | `ctl.setMode` | 否 |

## 6. 收藏
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 6.1 | 收藏按钮 | 未登录点击提示「请先登录后再收藏」 | `FavoriteButton` → `CollectLogic.toggle` 登录守卫 | **需登录** |
| 6.2 | 收藏/取消收藏 | 图标切换、计数变化；连点不重复提交（防重锁） | `collect_logic.dart`、`favoriteListId`（真正歌单=listid 2） | **需登录** |
| 6.3 | 我的收藏条目 | 可列出收藏曲目 | `CollectLogic` 列表接口 | **需登录** |

## 7. 下载
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 7.1 | 歌曲操作弹层「下载」 | 进入下载管理 Tab，出现任务行（质量·状态·进度） | `widgets/song_actions_sheet.dart` → `DownloadManager` | 否 |
| 7.2 | 暂停/继续/重试/取消 | 状态与按钮随状态切换；取消后无 paused 幽灵任务 | `lib/logic/download/`；`.dlpart` 提交与曲库建档 | 否 |
| 7.3 | 下载完成后入库 | 本地曲库出现该曲，可离线播放 | `SongDao` 建档 | 否 |

## 8. 歌词
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 8.1 | 歌词页打开 | 播放页歌词按钮可进入（模块未装则不应崩溃） | `pages/lyrics_page.dart`；`SurfaceRegistry` id='lyrics' | 否 |
| 8.2 | 逐字/滚动 | KRC 逐字着色 + 200ms 轮询自动滚动 | `krcDecode`（魔数 krc1 + 异或 + zlib） | 否 |
| 8.3 | 原文/双语/译文 | 切模式即时生效；无译文回落原文 | `lyrics_logic.dart` 三级缓存 | 否 |
| 8.4 | 清理歌词缓存 | 设置项可清内存与本地歌词文件 | `settings_page.dart` `_clearCache` | 否 |

## 9. 评论
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 9.1 | 打开评论页 | 播放页评论按钮可进入 | `pages/comment_page.dart` | 否 |
| 9.2 | 评论列表 | 上游 WAF 拦截时应显示**受限提示**，不得显示「暂无评论」 | `KugouClient._requestRaw` → `KugouApiException(-3)`；API 报告 §四-1 | 列表实测样本为 VIP 态，建议 **VIP** 复测 |
| 9.3 | 楼层/楼中楼 | 有楼层时可点开 _FloorPage，可返回 | `getCommentFloor`（楼层键 tid） | 同上 |
| 9.4 | 发表/点赞/热词筛选 | **未接线**，应明确不可点，不属本轮通过项 | FUNCTION_TREE §11.2 | — |

## 10. 设置
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 10.1 | 扫码/短信登录 | 二维码 1.5s 轮询，过期自动重开；成功后提示（会话热生效不完整，建议重启） | `pages/settings_qr_dialog.dart`；`auth/login_logic.dart` | **需登录** |
| 10.2 | 多账号 | 保存当前/切换/删除账号可用并持久化 | `account_logic.dart` + `AccountDao` | **需登录** |
| 10.3 | 主题/语言 | 系统/亮/暗/纯黑即时生效；11 种语言切换后界面文案随变（免重启） | `theme_state.dart`、`TnStrings.saveLocale`、`localeRevision` | 否 |
| 10.4 | 登出 | 登录态按钮切换为「二维码登录」，收藏等入口降级 | `deps.auth.logout()` | 已登录态 |

## 11. 通知栏
| # | 验收项 | 预期结果 | 失败看哪里 | 登录/VIP |
|---|---|---|---|---|
| 11.1 | 后台播放 | 锁屏/切后台音乐继续，通知栏显示曲名/歌手/封面 | `player_controller.dart` `updateMetadata`（title/artist/artUri） | 否 |
| 11.2 | 通知栏控制键 | **next/prev/seek 未接**，不得承诺可用 | FUNCTION_TREE §11.2 `audio_service_bridge.dart` | — |
| 11.3 | 播放历史 | 播放后「最近播放」出现该曲 | `uploadPlayHistory` + `history_recorder.dart` + `historyDao` | 匿名可上报，登录态更准 |

## 风险与结论
1. 本清单全部为**待执行**项；当前仅有静态代码与 API 三态实测依据，无真机运行结论。
2. 已知会失败/不可承诺的功能点（据代码现状）：评论发表与点赞、歌词行点击 seek、音质当前档回显（硬编码 q128）、通知栏 next/prev/seek、每日推荐未登录 200103、榜单/推荐歌单旧描述的 onTap 缺失（§11.1 称已补齐，需真机确认）。
3. 高优先回归风险：播放权限三态（匿名 20028 人机验证 / 非VIP status=2 / VIP status=1）必须三账号各验一次。
4. 验收前置：安装 debug APK、开启 `adb logcat`，记录账号态（匿名/非VIP/VIP）。

*产出：批5-C3 只读检查 · 未运行分析器、未改代码、未提交*
