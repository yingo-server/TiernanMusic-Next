# R2-C 端到端功能走查报告（用户视角）

走查范围：首次启动→首页四区块→搜索→播放→歌词→下载→曲库回放；QR 登录→会话恢复→收藏；语言切换；搜索六类 Tab+综合三段；下载管理；多账号隔离。

## 断点清单（共 7 处，全部已修）

| # | 链路 | 断点 | 修复 |
|---|------|------|------|
| 1 | 播放 | `player_page.dart:65` 播放页模块 builder 引用不存在的 `_PlayerPageBody`（实际类名 `PlayerPageBody`）——播放页 tab/入口 build 必然崩溃 | 改为 `PlayerPageBody`（player_page.dart） |
| 2 | 播放/歌词 | 歌词模块（id='lyrics'）已装配但全 App 无任何页面导航可达它——用户编译通过但永远看不到歌词 | 播放页 AppBar 新增歌词 IconButton，经 `SurfaceRegistry.active` 取 lyrics 模块 builder 打开（player_page.dart `_openLyrics`） |
| 3 | 播放 | MiniBar 全局迷你播放条从未被宿主挂载（modules.dart 仅 re-export，无消费方）——有歌在播但屏幕无播放控件（除手动进播放 tab，而播放页又因断点1崩溃=完全无法控制播放） | app_root `_HomeShell` 底部导航上方挂载 MiniBar；展开走已装配 player 模块 builder（保留收藏/音质/FM/评论接线），不走 mini_bar 内置裸 `PlayerPageBody`（app_root.dart） |
| 4 | 首页→搜索 | `onOpenSearch` 是 Log-only 空实现（首页搜索卡/热搜 chip/搜索图标点了无反应） | assembly 写入新 `homeTabRequest` ValueNotifier('search')；`_HomeShell` 监听并切换到搜索 tab（app_root.dart + assembly.dart） |
| 5 | 语言切换 | 设置页 `onLocaleChanged` 未接线 + app_root 只在启动时读一次 locale——切语言后 UI 不变（注释自称"持久化，重启后生效"但 MaterialApp 无重建信号） | 新增 `localeRevision` ValueNotifier；assembly 注入 onLocaleChanged 触发 ++；app_root 用 ValueListenableBuilder 重建 MaterialApp（app_root.dart + assembly.dart）。TnStrings.saveLocale/loadLocale→app_root 链路已通，切换即时生效+重启保持 |
| 6 | 搜索综合段 | 综合三段点击歌单/专辑行只触发 `_drillDown` 把歌名回填搜索框（歌手/MV/歌词 Tab 语义），歌单/专辑行点击无详情页——用户走不到歌单/专辑详情 | search_page 新增 `_SearchDetailPage`（StatefulWidget，以命中标题经 searchTypedLogic 检索曲目 + 播放全部 + 逐曲播放；不猜未实测的歌单/专辑曲目端点字段）；`_drillDown` 对 special/album 走 Navigator.push 详情页（search_page.dart） |
| 7 | 多账号 | `onAccountChanged` 只失效 search/playlist/rank/comment/mv 5 域——searchTyped/recommend/artist/album/fm/user/translation 缓存串号；收藏本地镜像（settings['favorites']）跨账号串号显示 | assembly 失效清单扩至全部 12 域 + `collectLogic.resetLocalMirror()`（新增方法：清内存镜像→重读持久层→通知，写后由服务端 refreshCount 回填新账号收藏）（assembly.dart + collect_logic.dart） |

## 走查通过项（无断点）

- **启动链**：main→runBoot→installServices(deps)→assembleAll（强制装配，兜底自装配已删）→bootstrapApp runApp；core 装配失败有可见错误页，不闪退。
- **首页四区块**：每日推荐/榜单速览/热搜词/推荐歌单均接真实 logic（recommend.daily/rank.rankList/search.hotSearch/playlist.recommend），`_FutureBlock` 三态壳互不拖垮；区块点歌 `onPlay→controller.playSong` 已接。
- **搜索六类 Tab**：assembly 传 `searchTyped: searchTypedLogic` 非空 → TabBar 显示；切换 `_onTab` 重新 `_submit`，typed 注入生效；综合三段独立 SegmentState 分页不串扰。
- **播放链**：PlayerController←modules.dart JustAudioEngine（onAction 回流）←PlaybackService.resolvePlaySource（本地 DownloadStore 优先→在线 getPlayUrlV5，20028/priv 语义映射）；匿名用户播放落 needsVerification 有明确错误显示（播放页 lastError 区）。
- **下载→曲库回放**：enqueue→分块 .dlpart→commitDownload（.part rename 防半成品）→`_upsertSong` 同步 SongDao.localPath；resolvePlaySource 先查 DownloadStore（complete+文件存在校验，悬空索引自动回退在线）→本地回放成立；暂停/继续/取消/重试按钮齐全（_TaskTile）；DownloadManager 任务队列内存态、未完成不落盘，无悬空索引风险。
- **QR 登录**：设置页 createQrLogin→QrLoginDialog 1.5s 轮询 pollQrLogin→success 落 session+持久化→restoreSession 回灌→CollectLogic isLoggedIn 接 auth.session.userid 实时读；过期自动重开。qr 渲染 QrView 纯 Dart 已接。
- **评论/MV/歌手/专辑**：assembly 已装配且回调非空；歌手页 onOpenAlbum→navState.setAlbum→Navigator.push(AlbumPage) 已接；评论入口原为 Log-only（本次修复#4 同批接通：经 registry 打开 comment 模块）。
- **FM**：播放页/设置页 onStartFm 已接 fmLogic.start→playAll；空批次不切队列（端点 needs probe，如实降级）。

## 规范核对

- 所有修改每函数 try/catch+Log（M3 规范）。
- 行数：assembly.dart 533、app_root.dart 489、search_page.dart 605→**注意 search_page.dart 超 500 行（605）**——详情页 100 行为走查新增，建议下批把 `_SearchDetailPage` 拆到 pages/search_detail_page.dart（本次未拆以免引入新文件破坏模块注册审计）。其余文件 ≤500 行。
- 模块间零直接 import：新增导航均经 app_root 全局信号/Navigator/registry builder，未新增跨模块 import；player_page→app_root 仅取同层 logicFacadeProvider（同层公共件合法，与既有 assembly→app_root 同模式）。
- 未验证未提交：未运行 flutter analyze/build（沙箱无 Flutter SDK），已做括号/结构平衡静态扫描（全部通过）。
