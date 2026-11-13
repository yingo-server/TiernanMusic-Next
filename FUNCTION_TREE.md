# TiernanMusicNext 功能树

> 精确到每一个可点击按钮 / 滑块 / 输入 / 手势；以**当前代码**为准，不照抄归档文档、不美化未实现项。
> 生成基准：`bbe8cf2`（CI `completed success`，LTS `v26.11.13.05`）。
> 依据：`lib/surface/**` 逐控件抽取 + `lib/logic/**` / `lib/core/net/endpoints/**` 全函数清单 + `tool/feature_reachability_test.dart` 可达性断言。

## 状态标注约定

| 标记 | 含义 |
|---|---|
| ✅ | 已接线，按钮 → 桥 → logic → 端点链路完整 |
| ⚠️ | 按钮存在且可点，但下游为占位 / 待实测 / 未接线（逐条注明） |
| 🔒 | 需登录或会员态，匿名下禁用或降级 |
| — | 无交互（纯展示） |

功能树按「入口 → 页面 → 区域 → 控件」展开。所有模块经 `SurfaceRegistry.install` 热插拔装配，宿主 `app_root` 不硬编码页面列表。

---

## 0. 启动与装配（无 UI 交互，但决定所有页面可用性）

```
L1 init/main()
 ├─ ① runBoot（经 bridge_boot）→ BootOutcome 归一化
 │    ├─ 失败 → _BootErrorApp（启动失败页，显示真实 error/detail）
 │    └─ 成功 → ② installServices（经 bridge_surface）
 ├─ ② assembleAll(SurfaceDeps)：装配 20+ logic 域 + 唯一 PlayerController
 │    ├─ defaultModules()：三个默认模块 install（search / playlist / player）
 │    ├─ 其余模块 install：library / lyrics / settings / comment / mv / artist / album / home
 │    └─ SurfaceRegistry.setOverrides(playerProvider / playerControllerProvider)
 └─ ③ bootstrapApp → runApp(ProviderScope(AppRoot))
```

- `registerBootloader()` 幂等 + `bridge_boot.bootBridgeReady` 零副作用自检；安装失败即 `StateError`，L1 在 runBoot 前拿到真实原因。
- 全局**唯一** `PlayerController`（JustAudioEngine）；库/首页/歌词/FM 与播放页/MiniBar 共用同一实例，避免状态分裂与静音。

---

## 1. 后端能力树（六层五桥，供上面每个按钮调用）

### L4 core · 网络端点（每端点独立 dart，参数恒显式携带 dfid/mid/uuid）

| 域 | 端点函数 | 真实响应契约要点 |
|---|---|---|
| 搜索 | `searchSongs` / `searchSuggest` / `searchHot` | 全线带 `mid`；联想取 `RecordDatas[].HintInfo`；热词取 `group.keywords[]` |
| 分类搜索 | `searchTyped` / `searchTypePath` / `parseSearchItems` | 六类分段；`/v6/search/complex` 返回 152 时降级三段综合 |
| 播放 | `getPrivilegeLite` / 播放源解析 | `play_url` 的 `status/priv_status` 判权；匿名 VIP 曲 20028 |
| 音质 | `qualityParam` / `toPlayUrlQuality` / `vipQualities` / `magicQualities` / `toPref` | 128/320/flac/high/魔法音质分档 |
| 歌词 | `lyricSearch` / `lyricDownload` / `krcDecode` | 成功 `status=200`；candidates 在响应顶层；KRC `"krc1"` 魔数 + 异或 + zlib |
| 翻译 | `fetchTranslation` / `fetchTranslationFromContent` / `alignTranslation` | 原文行 / 内嵌译文 / 对齐 |
| 歌单 | `recommendPlaylists` / `playlistDetail` / `playlistTracks` / `addSongsToPlaylist` | `data` 为数组；写接口带真实 `list_ver` |
| 歌单写 | `createPlaylist` / `deletePlaylist` / `addSongsToPlaylist` / `removeSongsFromPlaylist` / `getPlaylistTags` / `getUserPlaylists` | 加歌 `/v6/add_song` + `x-router: cloudlist.service.kugou.com` |
| 榜单 | `rankList` / `rankInfo` | 56 项榜单；`rank/audio` 需 defaultParams+body 合并签名 |
| 推荐 | `getDailyRecommend` | `platform` 必须在 query |
| 专辑 | `getAlbumDetail` / `getAlbumSongs` / `getSimilarPlaylists` | — |
| 歌手 | `getArtistDetail` / `getArtistAudios` / `getArtistAlbums` / `getArtistList` | `artist_albums` 502 时降级为专辑搜索 + `album_id` 重组 |
| 评论 | `getMusicComments` / `getCommentFloor` / `getCommentCount` | 总数必须 `FileHash`；点赞 `like.count`；楼层键 `tid` |
| 收藏 | `collectSongByHash` / `cancelCollectByHash` / `favoriteListId` / `getFavoriteCount` | 真正收藏歌单 = `listid=2`「我喜欢」（`listid=1` 弃用）；删歌 `/v4/delete_songs` 传 `fileid` |
| MV | `getMvBySong` / `getVideoQualities` / `getVideoUrl` | `videoDetailKmrV2` 三态 404，如实标记未伪造 |
| FM | `getFmPlay` / `getFmSongs` | 列表在 `data.song_list[]`；clienttime 毫秒、`kguid=userid` |
| 登录 | `sendSmsCode` / `smsLogin` / `smsSignParamsKey` | 扫码/短信登录 + 20028 验证流水线 |
| 用户 | `getUserDetail` / `uploadPlayHistory` / `getSongClimax` / `getUserCloud` / `reportListen` / `rsaCryptoEncrypt` | `data` 平铺 `pic/vip_type`；裸 RSA 右补零；⚠️ 高潮片段/云盘无实测章节，不臆造 status 门槛 |

### L5 logic · 业务域（UI 只经 `bridge_logic` 触达）

| 域 | 职责 |
|---|---|
| `player/` | `PlayerController`（队列/播放状态/音质/音量/倍速）、`PlaybackService`（播放源解析）、`HistoryRecorder`（最近播放上报） |
| `catalog/` | 搜索/歌单/榜单/推荐/专辑/歌手/评论/收藏/翻译/FM/MV/歌单写/用户/六类搜索 各自 logic + LRU 缓存 |
| `lyrics/` | 三级缓存加载、LRC/KRC 解析、逐字渲染、译文对齐 |
| `download/` | 并发队列（上限 3）、分块进度、暂停/继续/重试/取消、`.dlpart` 提交与曲库建档 |
| `auth/` | 登录态、多账号切换、失效广播、验证状态 |

### L4 core · 其它

- `database/` Isar 实体与 DAO（歌曲/歌单/播放历史/账号/下载记录）
- `memory/` LRU 缓存 + 缓存键
- `storage/` `DownloadStore`（rename + 索引）、`KeyValueSettings`、`Paths`
- `net/` `KugouClient`（签名三模式：android/web/register；gateway + x-router；只连酷狗官方域名）

---

## 2. 应用外壳（`app_root.dart`）

```
AppRoot (ProviderScope → MaterialApp)
 ├─ 启动失败页 _BootErrorApp / _FallbackApp / _ScaffoldMessage
 │    └─ — 无按钮（纯文本，显示真实错误；用户只能重启）
 └─ _HomeShell（正常态）
      ├─ NavigationBar.onDestinationSelected ✅
      │    └─ setState(_index = i) 切页；失败 try/catch + Log
      ├─ NavigationDestination ×N ✅（**动态生成，非硬编码**）
      │    └─ 数量/顺序 = SurfaceRegistry.active(logic).where(navEntry != null)，按模块 id 稳定排序
      │       图标 = _iconOf(e.icon)：home / library_music / queue_music / settings → IconData，未匹配回退 music_note
      ├─ homeTabRequest 监听（跨页切页信号，非控件）
      │    └─ 按 moduleId 定位 index → setState 切 tab（onOpenSearch 等使用）
      ├─ _ModuleView（模块 builder 容器）
      │    └─ ⚠️ 异常时 ErrorRetryBox「重试」按钮 → setState(() {}) 重跑 builder
      ├─ MiniBar（无当前曲 / idle 时整体不渲染）见 §3
      └─ 全屏播放页由 MiniBar 的 onExpand 触发（MaterialPageRoute fullscreenDialog）
```

---

## 3. 全局播放组件

### 3.1 MiniBar（`mini_bar.dart`，底部悬浮，全 tab 可见）

| 控件 | 文案 / 图标 | 动作 | 条件 |
|---|---|---|---|
| ✅ `InkWell`（整条左半区：封面+歌名+歌手） | — | `onExpand(context)` → 默认 `Navigator.push(TnPageRoute(PlayerPageBody()))` | `song==null \|\| p.status==idle` 时整条隐藏 |
| ✅ `IconButton` | pause / play_arrow（按 `p.isPlaying`） | `ctl.toggle()` | 同上 |
| ✅ `IconButton` | skip_next | `ctl.next()` | 同上 |
| ⚠️ `CoverImage` | — | 非交互，但 `url: song.albumName.isEmpty ? null : null` **恒传 null** → 封面永远占位 | — |

### 3.2 通用曲目行（被首页/搜索/歌单/曲库复用）

| 组件 | 控件 | 动作 | 条件 |
|---|---|---|---|
| ✅ `M3SongTile`（`common_m3.dart`） | `ListTile.onTap` 整行 | `onTap`（调用方注入） | 为 null 时整行不可点 |
| ✅ `M3SongTile` | trailing `IconButton(play_circle_fill)` | `onPlay`（调用方注入） | `onPlay==null` 时禁用 |
| ✅ `SongTile`（`common_widgets.dart`） | `ListTile.onTap` | `_tap()` → `onPlay(song)` | `playing==true` 仅高亮 |
| ✅ `FavoriteButton`（`favorite_button.dart`） | `IconButton`：favorite / favorite_border，tooltip「取消收藏」/「收藏」 | `_tap()` → `await onToggle()`（= `CollectLogic.toggle`，内含防重锁 + 登录守卫）🔒 | **`_busy ? null : _tap`** 防连点 |
| ✅ `ErrorRetryBox`（`common_m3.dart`） | `FilledButton`「重试」 | `onRetry` | `onRetry==null` 时不渲染 |
| — `TnAppBar` | title / actions / leading 全由页面注入 | 自身无交互 | — |

---

## 4. 首页（`home_page.dart`）

```
TnAppBar「首页」
 ├─ ✅ IconButton(search) tooltip「搜索」 → _safe(onOpenSearch)
 └─ ✅ InkWell(_SearchEntry)「搜索歌曲 / 歌手 / 专辑 / MV」 → onOpenSearch

内容区（各块 _FutureBlock / FutureBuilder）
 ├─ ✅ 每日推荐 ListTile ×N（trailing play_arrow） → onPlay(items[i])
 │     └─ 空数据时显示「今日暂无推荐」
 ├─ —  榜单速览 Grid 卡片 ×N：⚠️ **无 onTap**，榜单详情未接线（纯展示）
 ├─ ⚠️ 热搜词 ActionChip ×N → onOpenSearch()（**不带关键词**，关键词丢失，半接线）
 └─ —  推荐歌单横向卡片 ×N：⚠️ **无 onTap**，未跳歌单详情
```

---

## 5. 搜索（`search_page.dart`）

```
TnAppBar「搜索」
 ├─ ✅ TabBar ×7（条件渲染：typed==null 时整个 TabBar 不显示）
 │    └─ 综合 / 歌曲 / 歌单 / 专辑 / 歌手 / MV / 歌词 → _onTab(i)（有词则重发 _submit）
 └─ 输入区
      ├─ ✅ TextField「搜歌曲 / 歌手 / 专辑」
      │    ├─ onChanged → _onChanged（300ms 防抖 → search.suggestions）
      │    └─ onSubmitted → _submit
      ├─ ✅ IconButton(clear)「清空」 → _kwCtrl.clear(); _onChanged('')
      │    └─ 条件渲染：_kwCtrl.text.isEmpty 时 suffixIcon=null
      └─ ✅ FilterChip ×N（联想关键词） → _kwCtrl.text=s.keyword; _submit(s.keyword)

默认态 / 结果态
 ├─ ✅ 热搜 ListTile ×N → _kwCtrl.text=h.keyword; _submit(h.keyword)
 │    └─ _committedKw 非空时被结果列表替换
 ├─ ✅ SegmentedButton<SearchType> ×3（歌曲/歌单/专辑）
 │    └─ _onSegmentChanged(selected) → 切段 + _segmentFirst；仅 typed!=null && _tabIndex==0 显示
 ├─ ✅ 结果 SongTile ×N → _play(d) → player.playSong(d.song)
 ├─ ✅ 结果歌单/专辑 ListTile ×N → _drillDown(d,type) → Navigator.push(SearchDetailPage)
 │    └─ id 为空 / '0' 时直接 return 不跳转
 ├— ✅ 滚动到底自动分页 _onScroll/_onSegmentScroll → _autoMore → _loadMore/_segmentMore
 └─ —  footer「上拉加载更多」/「没有更多了」/ LinearProgressIndicator：纯提示，不可点
```

### 5.1 歌单/专辑详情（`search_detail_page.dart`）

| 控件 | 动作 | 条件 |
|---|---|---|
| ✅ `FilledButton.icon`「播放全部（N首）」 | `player.playAll(_songs, 0)` | loading→进度圈；error→「加载失败」；`typed==null` 或曲目空→「暂无曲目」，按钮不渲染 |
| ✅ `SongTile` ×N | `player.playAll(_songs, i)` | 同上三态 |

> ⚠️ `refId` 传入但未使用：详情页以「标题重搜」代替真实歌单/专辑曲目接口（代码注释自认不猜未实测端点字段）。

---

## 6. 歌单（`playlist_page.dart`）

```
TnAppBar「歌单」 + TabBar ×2（推荐 / 本地）
 ├─ 推荐 Tab
 │    ├─ ✅ RefreshIndicator（下拉刷新） → _loadRecommend(reset: true)
 │    ├─ ✅ InkWell 网格卡片 ×N → _openDetail(b) → push _PlaylistTracksPage（返回后 _loadLocal）
 │    └─ ✅ 滚动到末项自动 _loadMore（_hasMore=false 时不加尾项）
 └─ 本地 Tab
      └─ ✅ ListTile ×N → _openLocalMirror(m) → push _LocalMirrorPage

_PlaylistTracksPage（歌单曲目）
 ├─ ✅ IconButton(save_alt)「保存镜像」→ _saveMirror → playlist.saveLocalMirror + SnackBar
 ├─ ✅ IconButton(play_arrow)「播放全部」→ _playAll → player.playAll(_tracks, 0)（空则 return）
 ├─ ✅ SongTile ×N → player.playAll(_tracks, i)
 └─ ✅ 滚动加载 _onScroll → _loadMore

_LocalMirrorPage（本地镜像）
 └─ ✅ SongTile ×N → player.playSong(s)（hashes 空显示「镜像歌单为空」）
```

---

## 7. 曲库（`library_page.dart`）

```
TnAppBar「曲库」 + TabBar ×3（本地曲库 / 最近播放 / 下载管理）
 ├─ 本地曲库 Tab
 │    └─ ✅ LibrarySongTile ×N → deps.onPlay(SongBrief(hash…))；空库「曲库还是空的…」
 ├─ 最近播放 Tab
 │    └─ ✅ LibrarySongTile ×N → deps.onPlay(SongBrief(hash…))；空「还没有播放记录」
 └─ 下载管理 Tab（_TaskTile，每行显示 质量·状态·错误·进度）
      ├─ ✅ IconButton(pause)「暂停」 → deps.downloads.pause(hash) 〔status ∈ running/pending〕
      ├─ ✅ IconButton(play_arrow)「继续（从头重下）」 → deps.downloads.resume(hash) 〔paused〕
      ├─ ✅ IconButton(refresh)「重试」 → deps.downloads.retry(hash) 〔failed〕
      └─ ✅ IconButton(close)「取消」 → deps.downloads.cancel(hash) 〔status != done〕
           └─ cancel 按运行句柄等待 done 后清 .dlpart，不产生 paused 幽灵事件
```

---

## 8. 全屏播放页（`player_page.dart`）

```
TnAppBar「正在播放」
 ├─ ✅ IconButton(radio)「个人 FM」 → onStartFm()〔未注入时不显示〕
 ├─ ✅ IconButton(lyrics_outlined)「歌词」 → _openLyrics(context)：查 SurfaceRegistry id='lyrics' 模块并 push〔模块未装仅 Log，不跳〕
 ├─ ✅ IconButton(comment_outlined)「评论」 → onOpenComments()〔未注入不显示〕
 ├─ ✅ IconButton(high_quality_outlined)「音质」 → _showQualitySheet(context)〔见 §10.1〕
 ├─ ✅ FavoriteButton「收藏/取消收藏」🔒 → collect.toggle(hash, mixSongId, song)；needsLogin → SnackBar「请先登录后再收藏」
 └─ ✅ IconButton(mode)「播放模式：{mode.name}」 → ctl.setMode(_nextMode(mode))：顺序 → 单曲循环 → 随机 → 循环

播放主体
 ├— ⚠️ TnPressable（大封面）→ onTap: () {}（**空回调，仅缩放动效**）；song==null 时整页「队列为空」
 ├─ ✅ Slider（进度）→ ctl.seek((v*durationMs).round())〔durationMs<=0 时 onChanged=null 不可拖〕
 ├─ ✅ IconButton(skip_previous) → ctl.prev()
 ├─ ✅ IconButton(播放/暂停) → ctl.toggle()〔loading 时显示 hourglass_top，仍可点〕
 ├─ ✅ IconButton(skip_next) → ctl.next()
 ├─ ✅ Slider（音量，volume_down/volume_up 图标）→ ctl.setVolume(v)
 └─ ✅ TnPressable 倍速徽标「{speed}x」 → _showSpeedSheet(context)〔见 §10.2〕
```

---

## 9. 内容页（歌词 / 评论 / MV / 专辑 / 歌手）

### 9.1 歌词页（`lyrics_page.dart`）

| 控件 | 动作 | 条件 |
|---|---|---|
| ✅ `ChoiceChip` ×3「原文 / 双语 / 译文」 | `_setMode(m)` → setState + `lyricsFor` 重算 `displayFor` | `translation==null` 时仍可选，但显示回落原文、行不变 |
| — `ListView` 歌词行 | 无 onTap；200ms 轮询 `_syncScroll` 自动滚动 + KRC 逐字着色 | ⚠️ 无「点歌词行 seek」交互 |

### 9.2 评论页（`comment_page.dart`）

```
TnAppBar「评论」
 ├─ ✅ BackButton → Navigator.maybePop()
 ├─ ✅ RefreshIndicator → _model.refresh()〔mixSongId<=0 时 _load 直接跳过〕
 ├─ ✅ 滚动监听（距底 400px）→ _model.loadMore()〔loading 或 mixSongId<=0 时不加载〕
 ├─ —  Chip 热词 ×N：⚠️ 纯展示，无 onTap（无筛选行为）
 ├─ ✅ 评论 ListTile ×N（昵称/内容/N楼 + thumb_up 计数）→ onTapFloor → _openFloor(c) → push _FloorPage
 │    └─ 条件：hasFloor（floor>0 且 id 非空）才可点；⚠️ 点赞图标无点击事件
 └─ _FloorPage（楼中楼）
      ├─ ✅ BackButton → Navigator.maybePop()
      └─ ⚠️ _CommentTile 回复项 onTapFloor: () {}（空回调）；⚠️ 无分页/刷新（_load 仅 initState 一次）
```

> ⚠️ 评论页**只读浏览**：无发表评论 / 回复输入框。字段锚点见 `tool/field_truth_test.dart` N3-A 组（文档无评论域实测章节）。

### 9.3 MV 页（`mv_page.dart`）

| 控件 | 动作 | 条件 |
|---|---|---|
| ✅ `BackButton` | `Navigator.maybePop()` | — |
| ⚠️ `IconButton`「收藏 MV / 取消收藏」 | `_toggleFavorite()` → `onToggleFavorite?(hash)` | 回调未注入时点击无效果、状态不变 |
| ✅ `RefreshIndicator` | `_load()` 重拉清晰度列表 | hash 为空时不包裹，显示「无 MV 提示」 |
| ⚠️ `InkWell`（封面 64px 播放图标） | `_play()`：`logic.playUrl(h, requestedId)` → `onExternalPlay?(urls.first)`；不可播 → SnackBar「暂无可播放的清晰度」 | `_loading` 时 onTap=null；**外部播放器意图占位，无内嵌播放壳** |
| ✅ `ChoiceChip` ×N（清晰度 q.label/q.id） | `setState(_selectedQualityId = q.id)`（默认选第一个） | — |
| ⚠️ `FilledButton.icon`「播放（外部播放器占位）」 | 同上 `_play()` | `_loading` 时 null |

### 9.4 专辑页（`album_page.dart`）

| 控件 | 动作 | 条件 |
|---|---|---|
| ✅ `SongTile` ×N | `widget.onPlay(s)` | `_loading` 时显示 LinearProgress，不渲染列表 |
| —  相似歌单横滑项 ×N | ⚠️ **无 onTap / InkWell**，未接打开歌单 | — |
| —  页面级 | ⚠️ 无下拉刷新入口 | — |

### 9.5 歌手页（`artist_page.dart`）

```
TnAppBar「{歌手名}」
 ├─ ✅ IconButton(refresh)「刷新」 → _loadFirst()（并发重拉 详情/歌曲/专辑）〔_initialLoading 时 null〕
 └─ ✅ TabBar ×2「热门歌曲 / 专辑」 → DefaultTabController 切换 TabBarView

热门歌曲 Tab
 ├─ ✅ SongTile ×N（带序号） → _play(song) → widget.onPlay(song)
 └─ ✅ 列表尾哨兵 CircularProgress → addPostFrameCallback → _loadMore(songs:true)〔_loading 或 !_audioMore 时不加载〕

专辑 Tab
 ├─ ✅ ListTile ×N（专辑名/日期·曲数） → _openAlbum(a)：有 onOpenAlbum 则回调，否则 SnackBar 提示专辑名
 └─ ✅ 列表尾哨兵 → _loadMore(songs:false)〔!_albumMore 时不加载〕
```

---

## 10. 设置页与弹层

### 10.1 设置页（`settings_page.dart`）

| 控件 | 文案 | 动作 | 条件 |
|---|---|---|---|
| ✅ `TextButton`「登出」/「二维码登录」 | 按登录态二选一 | `_logout()` → `deps.auth.logout()` / `_showQrLoginDialog()` → `createQrLogin()` + showDialog | 按登录态二选一显示 |
| ✅ `AccountSection`「账号管理」 | — | 见 §10.4 | `deps.accounts==null` 不显示 |
| —  `ListTile`「我的收藏（N 首）」 | — | ⚠️ 无 onTap（纯展示） | `deps.collect==null` 不显示 |
| ✅ `ListTile`「个人 FM」 | — | `deps.onStartFm!()` | `onStartFm==null` 不显示 |
| —  `ListTile`「验证状态」 | `verificationState()` 文本 | ⚠️ 无 onTap（展示） | `verificationState==null` 不显示 |
| ✅ `SegmentedButton` ×4「系统 / 亮 / 暗 / 纯黑」 | — | `ref.read(themeModeProvider.notifier).set(s.first)` | — |
| ✅ `DropdownButton` ×11「跟随系统 / zh / 繁 / en / ja / ko / es / fr / de / pt / ru」 | — | `_pickLocale(v)`：`TnStrings.saveLocale` + `onLocaleChanged` 回调（AppRoot 重建） | — |
| ✅ `ListTile`「清理歌词缓存」 | 「内存缓存 + 本地歌词文件」 | `_clearCache()`：逐 hash `lyrics.clearFileCache` + `clearLyricCache()` | — |
| —  `ListTile`「关于」 | `TiernanMusicNext v{kAppVersion}` | 无 onTap | — |

### 10.2 音质弹层（`quality_sheet.dart`）

| 控件 | 动作 | 条件 |
|---|---|---|
| ✅ `ChoiceChip` ×15（4 组：标准 128 / 320 / flac / high / 魔法音质，label · `toPref(q)`） | `_pick(q)` → `onSelected(q)`；播放页内 `Navigator.pop` + 回调；`showQualitySheet` 内 `pop(q)` | 当前档高亮；⚠️ 播放页 `_showQualitySheet` 硬编码 `selected: q128`，**不反映真实当前档** |
| ✅ `showModalBottomSheet` 取消/异常 | `pop(null)` | — |

### 10.3 倍速弹层（`player_speed_sheet.dart`）

| 控件 | 动作 | 条件 |
|---|---|---|
| ✅ `ChoiceChip` ×4「0.5x / 1.0x / 1.5x / 2.0x」 | `read(playerProvider.notifier).setSpeed(s)` → `Navigator.pop` | 当前速度高亮；⚠️ 无 SnackBar 回执（仅 try/catch + Log） |

### 10.4 扫码登录对话框 + 多账号（`settings_qr_dialog.dart`）

| 控件 | 动作 | 条件 |
|---|---|---|
| ✅ `AlertDialog` + `TextButton`「取消」 | `Navigator.pop()` | `barrierDismissible: false`（只能点取消） |
| ✅ 二维码区 `QrView` / `Image.memory` | 自动生成；1.5s 轮询 `pollQrLogin`；过期自动 `createQrLogin` 重开；成功 → `restoreSession` + pop | ⚠️ 无「手动刷新二维码」按钮；会话热生效不完整（提示建议重启 App） |
| ✅ `TextButton.icon`「保存当前」 | `_save()` → `accounts.saveCurrent()` → `_load()` | 未登录时 SnackBar「未登录，无法保存账号」 |
| ✅ 账号 `ListTile` ×N（displayName / accountId） | `_switch(r)` → `accounts.switchTo(accountId)` → `_load()` | — |
| ✅ `IconButton(delete_outline)` | `accounts.removeAccount(r.accountId)` → `_load()` | — |

---

## 11. 未接线 / 占位清单（诚实标注，不写成已完成）

| 项 | 位置 | 现状 |
|---|---|---|
| 首页榜单速览卡片 | `home_page.dart:216` | 无 onTap，纯展示，榜单详情未接线 |
| 首页推荐歌单卡片 | `home_page.dart:315` | 无 onTap，未跳歌单详情 |
| 首页热搜 ActionChip | `home_page.dart:247` | 仅 `onOpenSearch()`，**关键词丢失**（半接线） |
| 歌单/专辑详情 refId | `search_detail_page.dart` | 传入未用，以「标题重搜」代替真实曲目接口 |
| MiniBar 封面 | `mini_bar.dart:50` | `CoverImage(url: … ? null : null)` 恒 null → 永远占位图标 |
| MV 播放 | `mv_page.dart:255/293` | 外部播放器意图占位，无内嵌播放壳；`onExternalPlay` 未注入则无响应 |
| MV 收藏 | `mv_page.dart:223` | `onToggleFavorite` / `isFavorite` 可空注入，未装配时点击无效果 |
| 播放页大封面 | `player_page.dart:296` | `onTap: () {}` 空回调，仅动效 |
| 音质当前档 | `player_page.dart` `_showQualitySheet` | `selected` 硬编码 `q128`，不读真实偏好 |
| 评论点赞 / 热词 Chip | `comment_page.dart` | 纯展示，无点击事件 |
| 楼中楼 | `comment_page.dart:388` | 回复项 `onTapFloor: () {}`；无分页加载 / 刷新 |
| 评论发表 / 回复 | `comment_page.dart` | 无输入入口，只读浏览 |
| 歌词行 seek | `lyrics_page.dart` | 无点击跳转，仅自动滚动 + 逐字着色 |
| 专辑页相似歌单 / 下拉刷新 | `album_page.dart:166` | 横滑项无 onTap；页面无刷新入口 |
| 设置「我的收藏」/「验证状态」/「关于」 | `settings_page.dart` | 纯展示，无 onTap |
| 二维码刷新 | `settings_qr_dialog.dart` | 仅过期自动重建，无手动按钮；提示建议重启 App |
| 动态主题取色 | `theme/dynamic_theme.dart` + `color_extract.dart` | ⚠️ **整链路未接线**：`cover_color_bridge.dart` 已删，`dynamicThemeProvider` 无 UI 消费方；纯 L6 内部状态容器，不影响运行 |
| 通知栏桥 | `audio/audio_service_bridge.dart` | ⚠️ 系统事件 seek/next/prev 未接队列控制；封面 artUrl 未接（SongBrief 无封面字段映射）；lifecycle 由宿主负责 |
| 高潮片段 / 云盘 / 评论计数路径 | `user_endpoints.dart` / `comment_endpoints.dart` | ⚠️ `API_FIELDS_TRUTH.md` 无实测章节 → 容错读取 + 注释「待实测」，不臆造 status 门槛 |
| 启动失败页 / 无模块页 | `app_root.dart` `_BootErrorApp` / `_ScaffoldMessage` | 无重试按钮，用户只能重启（可接 `ErrorRetryBox`） |

> 这些不是"缺陷隐瞒"，而是**按实测驱动原则**主动留白：契约未实测就不伪造成功，能力未接线就不假称可用。

---

## 12. 核对方式（如何复现本功能树）

```bash
# 1) 控件清单（按文件抽取 onPressed/onTap/Chip/Slider/…）
rg -n "onPressed|onTap|onChanged|IconButton|ChoiceChip|SegmentedButton|Slider|ListTile" lib/surface

# 2) 后端能力清单
ls lib/core/net/endpoints/*_endpoints.dart
rg -n "^Future<" lib/core/net/endpoints/

# 3) 六五原则与可达性门禁（CI 同款）
bash tool/local_gate.sh            # 本地 → FINAL-OK
python3 tool/layer_audit.py         # PASS strict six-five
dart run tool/feature_reachability_test.dart   # FEATURE-REACHABILITY-OK
```

**架构约束提醒**：所有 UI 模块经 `SurfaceRegistry.install` 热插拔，模块间零直接 import；跨层调用只经五桥；每个桥函数 try/catch + Log；单文件 ≤500 行。

---

*文档结束 · 生成于 CI `bbe8cf2` / LTS `v26.11.13.05` 后，按当前代码逐控件核对*

## 13. R2 新增交互（M3 重构后）

### 13.1 播放队列弹层（`widgets/queue_sheet.dart`）
| 控件 | 动作 | 条件 |
|---|---|---|
| 队列项 | `ctl.playAt(i)` 跳转播放 | 当前曲高亮（`graphic_eq` 图标 + 主色底） |
| `IconButton(close)`「从队列移除」 | `ctl.removeFromQueue(i)` | 删当前曲时索引自动修正到下一首 |
| 入口 | 播放页 ⋮ 菜单「播放队列」/ 封面上滑（velocity < -220） | 队列空显示 M3EmptyState |

### 13.2 歌曲操作弹层（`widgets/song_actions_sheet.dart`）
| 控件 | 动作 |
|---|---|
| 「下一首播放」 | `ctl.insertNext(song)`（队列当前曲之后插入） |
| 「收藏 / 取消收藏」 | `collectLogic.toggle(hash, mixSongId)` |
| 「下载」 | `downloads.enqueue(song, quality)` |
| 「歌曲信息」 | 展示 hash / mixsongid / album_audio_id / 时长 / bitrate |

> 入口：首页「每日推荐」行尾 ⋮；歌单曲目弹层行尾 ⋮。

### 13.3 歌单曲目弹层（`widgets/playlist_tracks_sheet.dart`）
通用实现，首页推荐歌单与音乐库「我的歌单」共用：封面 + 名称 + 曲目数 + 曲目列表（骨架屏 → 错误重试 → 空态三态），点击播放，行尾 ⋮ 打开歌曲操作弹层。

### 13.4 存储诊断页（`pages/storage_diag_page.dart`）
| 区块 | 数据源 |
|---|---|
| 本地曲库 | `SongDao.list()` 计数 |
| 下载任务 | `DownloadManager.listTasks()` 计数 |
| 我的歌单 | `PlaylistWriteLogic.myPlaylists()`（登录态才有） |
| 歌单条目 | 点击打开通用歌单曲目弹层（`PlaylistLogic.tracks`） |

入口：音乐库 → 「存储诊断」。

### 13.5 音乐库账号卡（`pages/library_header.dart`）
头像（`UserProfile.avatar`）/ 昵称 / `ID: userid` / 「我喜欢」计数（`CollectLogic.refreshCount`）/ ⋮ → 设置 tab。

### 13.6 搜索页（`pages/search_home_view.dart`）
搜索历史（`KeyValueSettings` 持久化，10 条，可单删/清空）+ 热门分类 chips（来自热搜分组 `SearchSuggestItem.type`）+ 热门搜索列表（Top3 主色）。

---
