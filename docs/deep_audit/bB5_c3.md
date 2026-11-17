# B5 批 · C3 用户痛点专项（下载 / 收藏 / 歌单 / 缓存 跨层审查）

> 审查时间：2026-11-17（Asia/Shanghai）。视角：C3 用户痛点。
> 范围：L7 `library_page.dart`/`playlist_page.dart`；L5 download/collect/playlist(+write) logic；L4 download_store/cache_service/resource_cache。
> 纪律：只读取证（file_read + ls/rg/wc），未改源码、未跑 analyze/test、未联网。

## C3 用户痛点 · lib/surface/pages/player_page.dart:244-271 · P1 · 下载入口位置与空态指引不一致
证据：阶段A新增下载入口位于播放页 ⋮ 菜单「下载当前歌曲」(`:248`)，调 `mgr.enqueue(cur,'128')`(`:256`)，有 `downloadQueued`/`errorGeneric` SnackBar(`:259-266`)。但 `library_page.dart:303` 空态文案为「在歌曲菜单里选择下载」；library 列表项(`:307-325`)无任何 ⋮/菜单/onTap。
问题：入口确实可用（阶段A修复生效），但它藏在"播放页⋮→下载当前歌曲"，并非文案所说的"歌曲菜单"；用户空态按指引找不到入口，需先播放该曲再进 ⋮ 菜单才能下载。
建议：要么把下载入口加到 library 列表项/搜索结果项的 ⋮ 菜单，要么把空态文案改为「播放歌曲后，点播放页右上角 ⋮ →下载当前歌曲」并接 S.of。
76 合规：涉及——L7 入口文案与真实功能点错位，属跨层入口/文案接缝问题。

## C3 用户痛点 · lib/surface/pages/library_page.dart:56-59,290-326 · P0 · 下载进度/状态不刷新（onTask 从未订阅）
证据：`_loadDownloads()` 仅在 `initState` 调一次(`:34,57-59`)：`_downloads = dm.listTasks()`；`_downloadsTab()`(`:291`)无 `setState`、无订阅。L5 `DownloadManager.onTask`(download_manager.dart:58) 在整个 lib 中仅有定义与 `_emit` 调用(`:471`)，**L7/L6 零订阅**（rg 实证）。列表用 `LinearProgressIndicator(value: t.progress)`(`:321`)但无 rebuild 触发。
问题：点下载后切到「下载管理」tab，`_downloads` 是 initState 时的旧快照；下载中进度条、完成/失败状态都不会更新——用户看不到任何进度变化，可能一直显示"暂无下载任务"或卡在"下载中"。这是下载体验最致命痛点。
建议：L7 `initState` 订阅 `appGraph.downloads.onTask = (e) => setState(() => _downloads = e.tasks)`，`dispose` 取消；或 L6 用 ValueNotifier 桥接。`ListTile` 需 key=hash 保证进度条重建。
76 合规：涉及——L5 有回调契约、L6/L7 不消费，订阅职责断在跨层接缝。

## C3 用户痛点 · lib/surface/pages/library_page.dart:307-325 · P1 · 下载任务无法删除/暂停/重试/取消
证据：下载列表项(`:309-324`)只有 leading 封面、title、subtitle、trailing 进度条，**无 onTap、无删除按钮**。L5 `cancel`(download_manager.dart:154)/`pause`/`resume`/`retry`，L4 `deleteWithFile`(download_store.dart:242) 全仓无 L7 调用（rg 实证）。
问题：用户下载后无法删除任务或文件、无法暂停/重试失败项；失败任务只能干看着。管理与清理能力完全缺失。
建议：给列表项加 trailing 图标按钮（done→删除文件 `deleteWithFile`+`cancel`，running→暂停，paused→恢复，failed→重试），接 S.of tooltip。
76 合规：涉及——L4/L5 删除与控制在桥后无 L7 出口，能力浪费。

## C3 用户痛点 · lib/surface/pages/library_page.dart:313-316,download_models.dart:29-35 · P1 · 状态与错误原因对用户不可读
证据：subtitle 直接显示 `'${t.quality} · ${t.status.name}'`(`:314-315`)，`status.name` 为 pending/running/paused/done/failed 英文枚举；`t.error` 有失败原因(download_models.dart:79)但 UI 完全不展示。
问题：用户看到"128 · running/failed"这类英文技术态，既不懂状态也不知道失败原因（如 resolve:notFound / http 403），无从判断该怎么办。
建议：状态映射为本地化文案（S.of key），失败态在 subtitle 追加 `t.error` 的可读化描述。
76 合规：仅 UI 文案层，涉及硬编码/未国际化。

## C3 用户痛点 · lib/logic/download/download_manager.dart:11-13,download_store.dart:162 · P1 · 重启后「下载管理」恒为空，已完成下载只在「本地曲库」
证据：manager 注释(`:11-13`)明确"任务队列为内存态，启动不恢复"；`library_page._downloadsTab` 只读 `dm.listTasks()`(不读 `DownloadStore.listAll()`，download_store.dart:162)。已完成文件入 index.json + SongDao，显示在「本地曲库」tab(`:206-213`)。
问题：重启 App 后「下载管理」tab 永远显示"暂无下载任务"，即使已下载多首；用户会以为下载丢失。同一批文件分散在两个 tab，认知割裂。
建议：「下载管理」tab 合并展示 `DownloadStore.listAll()` 的已完成记录（含删除入口），任务表只展示进行中；空态文案区分"无进行中任务/无已下载文件"。
76 合规：涉及——L4 有持久化记录、L7 只读内存队列，跨层数据源未整合。

## C3 用户痛点 · lib/logic/player/playback_service.dart:178-196,session/playback_session.dart:264-266 · P1 · 离线播放仅本地已下载可播，普通收藏/缓存不可离线
证据：`resolvePlaySource` 先查 DownloadStore(complete + 文件存在)→localPath(playback_service.dart:188-196)，播放会话 `src.localPath ?? src.urls.first`、`_sourceKind='local'`(playback_session.dart:264-266)。
问题：只有"下载完成"的曲子可离线播放；这是设计如此，但 UI 从未告知用户"下载=可离线"，且前面进度不刷新+重启列表空，用户很难确认下载成功→离线可用。收藏/推荐缓存的曲目离线仍不可播，无明确提示。
建议：下载完成态给 SnackBar「已下载，可离线播放」；播放页/设置加"仅离线"开关或在无网时明确提示"该曲未下载，无法离线播放"。
76 合规：基本合规（L4 存储→L5 解析→L6 会话链路清晰）；仅缺 UI 告知。

## C3 用户痛点 · lib/surface/pages/player_page.dart:68-125 · P2 · 收藏真逻辑已接线但成功无正向反馈 / 取消收藏回执依赖 fileid
证据：FavoriteButton 已改真逻辑(`:79-115`)：读 `appGraph.collect.isCollected`、调 `logic.toggle`，失败/需登录有 SnackBar(`:103-108`)。但**成功无提示**（无 r.ok 分支提示）。`collect_logic.dart:134-145` 取消收藏优先用 `_fileIds[h]`；无 fileid 时回退 `album_audio_id`(`:142`)，而 `cancelCollectByHash` 要求 fileid 为合法数字且≠0(collect_endpoints.dart:200-203)，回退 `${song?.albumAudioId??0}` 常为 0 → 删歌失败。
问题：①用户点收藏后图标变色但无"已收藏"确认，取消也无"已取消"提示，弱反馈；②收藏成功若回执缺 fileid，取消收藏会静默失败（用户以为取消成功、实际仍在"我喜欢"）。
建议：成功也发 SnackBar（已收藏/已取消收藏，接 S.of）；fileid 缺失时用 mixSongId 兜底或拉取歌单曲目补锚点，失败时明确提示"取消失败，请重试"。
76 合规：涉及——收藏写链路 L7→L5→L4 通，但回执锚点(fileid)跨层衔接脆弱。

## C3 用户痛点 · lib/logic/catalog/collect_logic.dart:229-260,session/bootstrap.dart:151-157 · P2 · onChanged 未装配 + 收藏计数可能偏差
证据：CollectLogic 构造支持 `onChanged`(collect_logic.dart:36)，但 bootstrap 装配(:151-157)**未传 onChanged**；`_notify()`(`:315`)恒空操作。`library_page._favCount` 只在 initState 刷新一次(`:51-52`)，收藏后「我喜欢 N」不实时变。计数端点 `getFavoriteCount` 以空 mixsongids 请求(collect_endpoints.dart:238-240)，"待实测"，返回可能 0 → refreshCount 用镜像条数兜底(collect_logic.dart:229-233)。
问题：用户在播放页收藏后返回「我的」，"我喜欢 N"数字不更新（无 onChanged、无刷新），需重启 App 才准；计数来源不可靠。
建议：bootstrap 给 collect 注入 onChanged 通知 library 刷新；`_favCount` 用 ValueNotifier；library 每次进前台/切 tab 重刷 count。
76 合规：涉及——L5 通知契约与 L6 装配、L7 刷新三者未串起来。

## C3 用户痛点 · lib/surface/pages/library_page.dart:46-52,136-166 · P2 · 未登录整块隐藏账号卡，无登录引导
证据：`_loadProfile()` 当 `user==null && collect==null` 直接空 UserProfile，`_accountCard()`(`:135`) `if(p.isEmpty) return SizedBox.shrink()`(`:139`)整块隐藏。
问题：未登录用户进「音乐库」看不到任何账号区，也没有"登录以同步收藏"的引导（设置页有，音乐库没有）；用户无法从音乐库感知"收藏需要登录"。
建议：未登录时在账号卡位置显示"登录以同步收藏与历史"+ 跳转登录按钮（复用 settings 的 showLoginSheet）。
76 合规：仅 UI 呈现层，低层数据齐备但 L7 未给引导出口。

## C3 用户痛点 · lib/surface/pages/playlist_page.dart:全页 · P1 · 歌单"创建/删除/加歌"零 UI，我的歌单只读本地镜像
证据：`PlaylistWriteLogic.create/delete/removeSongs`(playlist_write_logic.dart:81-152) 已实现且装配(bootstrap.dart:187-189)，但**全仓 L7 零调用**（rg 实证；文件末注释 :156「待 UI 接线」）。`playlist_page._MineTab._load()`(`:157-162`)只读 `pl.listLocal()`（本地镜像），空态"还没有收藏的歌单"(`:212`)。`_MineRow`(`:433`)仅 onTap 打开详情，无删除/管理。
问题：用户无法在 App 内创建歌单、删除歌单、给歌单加歌/删歌；"我的"页只是只读镜像列表，且镜像仅由 `saveLocalMirror` 写入(playlist_logic.dart:208，L7 也无调用)——实际上"我的歌单"很可能永远为空且无法填充。创建/删除能力完全不可用。
建议：在「我的」tab 加"+"建歌单、行尾 ⋮ 删除，详情弹层加"添加到歌单/移出"；接 PlaylistWriteLogic 与 playlist_logic.addSongsToKugouPlaylist/saveLocalMirror。
76 合规：涉及——L5 写逻辑完善、L6 已装配，唯 L7 无出口，能力断在最后一层。

## C3 用户痛点 · lib/surface/pages/playlist_page.dart:152-221,playlist_logic.dart:208-240 · P1 · 本地镜像歌单无写入触发，空态误导
证据：`_MineTab` 读 `pl.listLocal()`(playlist_page.dart:160)→PlaylistDao.list()；`saveLocalMirror` 是唯一写入口(playlist_logic.dart:208)，但 L7 `PlaylistDetailSheet._load()`(`:200-222`)只调 detail+tracks，**从不调 saveLocalMirror**。收藏逻辑写的是 settings['favorites'] 镜像，不写 PlaylistDao。
问题：本地镜像表没有任何 L7 触发写入，"我的歌单"空态"还没有收藏的歌单"长期恒空且无救济路径；用户收藏歌曲/打开在线歌单后，指望"我的"出现内容，实际不会。空态文案"收藏的歌单"也不指向真实功能（无收藏歌单入口）。
建议：打开在线歌单详情时调 saveLocalMirror 落镜像；或"我的"tab 改为展示 getUserPlaylists 的在线歌单 + 收藏；空态加"去推荐页收藏歌单"引导并接 S.of。
76 合规：涉及——L4 PlaylistDao→L5 saveLocalMirror→L7 详情页未触发，跨层写入链断点。

## C3 用户痛点 · lib/surface/pages/settings_page.dart:133-143,257-276 · P1 · 清缓存只清单飞表，不清磁盘缓存——用户"清了还是旧的"
证据：`_clearCache()`(settings_page.dart:136-142)仅 `cache.invalidateSession()`；`CacheService.invalidateSession` 只做 `_client.clearInflight()`(cache_service.dart:160-165)，而 `clearInflight` 仅 `_inflight?.clear()`(kugou_client.dart:62-67)。磁盘 L2 `ResourceCache`(ttl 默认 7 天，resource_cache.dart:69) 完全未清，代码注释也承认"磁盘级清理能力尚未经桥暴露"(settings_page.dart:134-135)。
问题：用户点"清理缓存 → 清理"后，磁盘缓存仍在，"改了内容还是旧的"痛点依旧——阶段A只固化了部分（单飞表），用户感知的"缓存"是磁盘数据，清了没用。副标题"清理会话缓存与请求合并表"(`:269-270`)虽诚实但普通用户不懂，仍以为清了所有缓存。
建议：expose `ResourceCache.clearAll()/invalidateAll()` 经桥到 CacheService，清缓存时同时清磁盘 L2（可按 uid）；或把入口改名为"刷新数据"并真实强制失效相关端点缓存，副标题讲清"不会清除已下载歌曲"。
76 合规：涉及——L4 磁盘缓存能力未过桥，L7 入口能力不足，跨层接缝断。

## C3 用户痛点 · lib/core/cache/cache_service.dart:18-26,160-171 · P2 · 缓存统计恒 0，无诊断页暴露
证据：CacheServiceStats 的 hits/writes/evictions 恒 0、`exposeRealCounters=false`、`source` 注明"未接线"(cache_service.dart:44-95,165-169)；`toJson()`(`:172`)有序列化但全仓无诊断页调用。
问题：无法量化缓存是否生效；用户"还是旧的"投诉缺少可核查数据（无法看出命中了多少旧缓存）。
建议：低频端点暴露 getter 接真实计数，或在设置加"缓存诊断"页展示 stats.toJson()（注明 source）。
76 合规：基本合规（门面诚实标注未接线，值得肯定）；仅缺 L7 展示出口。

## C3 用户痛点 · lib/surface/pages/library_page.dart:225-259 · P2 · 本地曲库/最近播放无删除与离线播放入口
证据：`_list<T>`(library_page.dart:226-259)列表项 `:249-258` 仅展示 title/subtitle，无 onTap、无删除。本地曲库是已下载文件落点(SongDao)，却点击不能播放。
问题：用户在「本地曲库」看到已下载歌曲，点击无反应、不能播放、不能删除——"下载了却放不了/删不掉"的直接痛点，与下载管理同样的问题。
建议：列表项 onTap→PlaybackSession.playAll(本地记录) 或按 localPath 播；加删除入口。
76 合规：涉及——L7 展示层未接 L6 播放会话与 L4 删除能力。

## C3 用户痛点 · lib/surface/pages/playlist_page.dart:1-576 · P1 · 歌单页零分页/无下拉刷新，曲目只加载第 1 页
证据：`PlaylistDetailSheet._load()`(playlist_page.dart:207-222)调 `pl.tracks(id,1)`固定第 1 页；`_RecommendTab._load()`(`:78`) `recommend(1)`固定第 1 页。无 ScrollController 加载更多、无 RefreshIndicator。L5 `tracks` 支持 page 参数(playlist_logic.dart:120)。
问题：大歌单只显示前 30 首，用户无法翻页/加载更多；推荐歌单也只有一页。歌单内容"看不全"。
建议：详情弹层 ListView 尾部加"加载更多"或 scroll 触底翻页；推荐/我的加下拉刷新。
76 合规：涉及——L5 已支持分页，L7 只用第一页，能力未用尽。

## 下载收藏体验走查

1. **点下载有没有反应**：有。播放页 ⋮ →「下载当前歌曲」调 `enqueue`，SnackBar「已加入下载队列」(player_page.dart:256-266)。阶段A加的入口**真可用**（能入队、发给 DownloadManager）。
2. **进度是否显示**：`_downloadsTab` 有 `LinearProgressIndicator(value:t.progress)`(library_page.dart:321)，但 **`onTask` 无人订阅**、列表 initState 后不刷新 → 进度条实际不会随时间变化（P0）。
3. **下载中/完成/失败状态**：L5 状态机完整(pending/running/paused/done/failed + error)，UI 仅显示英文 `status.name`，失败原因 `t.error` 不展示（P1）。
4. **在"我的"里能否找到**：完成文件在「本地曲库」tab（SongDao 建档），「下载管理」tab 重启后恒空（内存态不恢复）。两份割裂（P1）。
5. **删除下载**：UI 零出口（P1）。L4 deleteWithFile、L5 cancel 均存在未被调。
6. **离线能否播放**：仅"下载完成"曲可离线（localPath 优先，playback_service.dart:188-196），链路通；但 UI 未告知、且因进度/列表 bug 用户难确认成功。
7. **收藏反馈**：点收藏图标变色 + 失败/需登录 SnackBar；成功无正向提示；未登录有明确「需要登录」提示(player_page.dart:102-104)。
8. **收藏持久/重启**：镜像写 settings['favorites.<uid>'] + fileid 镜像，重启仍在（collect_logic.dart:_load/_flush，合规）；但取消收藏在 fileid 未建档时静默失败（P2）。
9. **取消收藏**：有（同按钮 toggle），回执锚点脆弱（P2）。
10. **歌单创建/删除/加歌**：L5+L6 齐备，L7 零出口，完全不可用（P1）；我的歌单镜像无写入触发，恒空（P1）。
11. **清缓存**：入口在设置页，但只清单飞表不清磁盘，"改了还是旧的"仍在（P1）。

## 文案接线清单（library_page / playlist_page 硬编码中文，零 S.of）

统计：`S.of|AppLocalizations|TnStrings` 在两页 **0 命中**（rg 实证）。含用户可见文案行：

**library_page.dart**（用户可见，文件:行）：
- :86-88 Tab「本地曲库/最近播放/下载管理」
- :138「未命名用户」:161「我喜欢 N」
- :209-210「曲库还是空的 / 下载或导入歌曲后会显示在这里」
- :219-220「还没有播放记录 / 播放歌曲后会显示在这里」
- :236「数据能力未装配」:247「加载失败」:249「重试」
- :295-296「下载管理不可用 / 下载能力未装配」
- :302-303「暂无下载任务 / 在歌曲菜单里选择下载」（空态指向的"歌曲菜单"不存在，见 P1 条）
- :342 NavEntry「音乐库」

**playlist_page.dart**（用户可见，文件:行）：
- :21 NavEntry「歌单」:52-53 Tab「推荐/我的」
- :124「推荐歌单加载失败」:128「暂无推荐歌单」
- :208「我的歌单加载失败」:212「还没有收藏的歌单」（无收藏入口，见 P1 条）
- :334「歌单详情」:346「N 首」:347「本地镜像 N 首」:361「该歌单暂无曲目」
- :418「未命名歌单」:424「曲目数未知」:466「N 首」
- :499「未知歌曲」:513「专辑」:569「重试」

（注释行 1/2/3/4/13/107/206/216/226/290/333 及 playlist 各 /// 注释为开发者注释，非用户文案，仅统计时一并列出。）
建议：两页所有用户可见串改 `S.of(context).t(key)`，补 zh/en 等 arb key；空态文案必须指向真实存在的功能入口。

## MD3 局部（列表项 / 进度指示 / 空态 / Sp.* 绕过 ColorScheme 统计）

- **列表项**：library `_list`/`_downloadsTab`(library_page.dart:249-325)、playlist `_MineRow`/`_TrackRow`/`PlaylistGridCard`(playlist_page.dart:389-521) 均用标准 `ListTile`/`GestureDetector`，触摸目标靠内容撑起；未显式保证 48dp，未用 M3 `FilledTonalButton` 等状态层。属 warn（与基线 A7-C3 Components 6/10 一致）。
- **进度指示**：`LinearProgressIndicator`/`CircularProgressIndicator` 均设 `color: Sp.green`(library_page.dart:321、playlist_page.dart:105/165/238)，是品牌绿硬编码而非 `colorScheme.primary`；且 library 进度条无 trackColor/容器色角色。属 fail 局部。
- **空态**：library 用 `SpStateView`(图标+标题+副标题)，playlist 用 `PlaylistEmptyBox`(仅一行灰字 `Sp.textFaint`，playlist_page.dart:541-545)，二者形状/层级不一致；playlist 空态无图标/无引导按钮，达不到 M3 empty state 的"说明+可操作"要求。属 warn。
- **Sp.* 绕过 ColorScheme 统计**（本批范围内命中）：
  - library_page.dart：`Sp.bg`(`:67`) `Sp.text/unselectedLabelColor`(`:71-73`) `Sp.green`(`:72`) `Sp.text`(`:78,141,255`) `Sp.textSub`(`:73,150,256`) `Sp.cardHigh`(`:174`) `Sp.textFaint`(`:178,251`) `Sp.red`(经 SpStateView)；密集绕过 `Theme.of(context).colorScheme`。
  - playlist_page.dart：`Sp.bg`(`:37`) `Sp.green`(`:33,105,165,237`) `Sp.text`(`:34,338,507`) `Sp.textSub`(`:35,349,510`) `Sp.bgElevated`(`:69,163,231`) `Sp.cardHigh`(`:242,330,400,447,499`) `Sp.textFaint`(`:424,469,502,514,544`) `Sp.red`(`:563`)——**每页数十处静态色，页面层零 `Theme.of`**。
  - 结论：与基线 A7-C3 一致——ThemeData 存在，但页面用 `Sp.*` 静态色架空 ColorScheme；亮色主题下仍取深色 `Sp.text` 存在白底白字风险。本批未做精确对比度测量（见未覆盖）。

## 本视角结论

1. **下载入口（阶段A修复）真可用**：播放页 ⋮ →下载当前歌曲能入队并给 SnackBar；但藏得深、与空态文案"在歌曲菜单里选择下载"不一致。
2. **最致命痛点是进度/状态不刷新**：`DownloadManager.onTask` 全仓零订阅，library 下载列表 initState 后成死快照，用户看不到进度/完成/失败（P0）。
3. **下载管理缺删除/暂停/重试/离线确认**：L4/L5 能力齐备，L7 零出口；重启后下载管理恒空、已完成文件只在本地曲库且点击不能播。
4. **收藏真逻辑已接线且可持久**（settings 镜像+fileid，重启仍在，需登录有提示）；短板是成功无反馈、取消收藏 fileid 回执脆弱、onChanged 未装配导致计数不刷新。
5. **歌单写能力（建/删/加歌）L5+L6 齐备但 L7 完全无 UI**；本地镜像无写入触发，"我的歌单"长期恒空。
6. **清缓存只清单飞表不清磁盘**，"改了还是旧的"痛点仍在（阶段A只固化部分）。
7. **文案零接线**：两页 0 处 S.of，硬编码中文密集（library ~13 行用户可见、playlist ~20 行），空态文案指向不存在功能。
8. **MD3 局部**：进度色/静态色绕过 ColorScheme，空态不统一、无引导，符合基线"主题数据被 Sp.* 架空"的根因。

## 未覆盖

- 运行时真机观察（下载进度实际是否随时间动、离线播放实测、重启实测）——仅静态代码 + rg 取证，未跑 App/analyze/test（纪律禁止）。
- 端点端到端实测（collect getFavoriteCount / cancel_collect / 歌单写端点是否真成功），仅审代码契约与注释标注的"待实测"。
- 精确 WCAG 对比度数值、触控目标逐控件 48dp 枚举（需真机/工具，且属 B6 视角）。
- `download_song_sync.dart`/`download_paths.dart`/`download_job.dart` 的细节逻辑（仅在下载链路中旁证，未逐行深审）；`resource_cache.dart` 内部 LRU/TTL 实现细节。
- settings/login 等页面文案与收藏登录引导的其他落点（本批范围外，归 B7）。

## 76 合规小结

- **跨层接缝职责**：本批多处"能力在 L4/L5、装配在 L6、L7 无出口"——下载控制/删除、歌单写(create/delete/removeSongs)、saveLocalMirror、缓存统计展示，均违反 §0「能力应贯通到 UI」的实质要求，属职责断链（非越级，但能力浪费）。
- **L7 职责**：`library_page.dart` 持有多条 Future + 下载任务列表快照且未下沉订阅；`playlist_page.dart` 持 Future 与 `_data` 可变字段，与基线 A7-C3「L7 Widget 内持有编排/状态」判断一致。
- **L4 core 归属**：strings.dart(i18n)、download_store、cache_service、lru_cache 位于 core，层级合规；问题在消费侧（surface 不接 S.of、不消费 ColorScheme、不订阅 onTask、不清磁盘缓存）。
- **桥接**：bridge_logic 导出 DownloadManager/DownloadTask、bridge_core 导出 DownloadStore/CacheService 正确；但 onTask 回调、deleteWithFile、磁盘清缓存未过桥到 L7，是接缝薄弱点。
- **单一事实源**：收藏镜像 settings['favorites.<uid>'] 与 fileid 镜像按账号隔离、写前 forceReload 索引，符合单一真源（正面）；download_store 原子 rename、commitDownload 强制重载索引（阶段A修复）确认生效（正面）。
