# UI 批次 A · 三页面改动说明（home / search / playlist）

批次范围：仅 `lib/surface/pages/home_page.dart`、`search_page.dart`、`playlist_page.dart` 三个文件；未触碰其它文件。

## 通用契约落地
- 每页定义 `XPageModule implements SurfaceModule`（id/route/navEntry/builder），builder 直接返回页面 Widget，供宿主按 id 覆盖 session 占位模块。
- 逻辑单例只经 `bridge_logic` 导出类型（SearchLogic / PlaylistLogic / RankLogic / RecommendLogic 等）；装配图取自 `session/bootstrap.dart` 的 `appGraph`；跨页导航只走 `NavState`（setAlbum / requestTab），播放只走 `PlaybackSession.instance.playAll`。
- 颜色/字号/间距/圆角全部使用 `Sp.*` 令牌（design/tokens.dart 唯一真源），无硬编码色值（排行榜渐变卡同样只用 Sp.green/greenDim）。
- 异步数据一律 StatefulWidget + `initState` 持有 Future；禁止 build 内新建 Future。每页均提供空态 / 错误重试 / 加载三态（M3EmptyState/M3ErrorRetry/M3Skeleton 在 design/components.dart 不存在，按规格以页面内私有 widget `_EmptyBox` / `_ErrorRetry` / `_SkeletonBox` 实现）。
- 列表全部使用 `ListView.builder` / `GridView.builder`，无全量 children。

## home_page.dart（500 行）
- SafeArea + AppBar 大标题「首页」+ 右侧搜索图标（点击 `NavState.requestTab('search')`）。
- 垂直区块流（外层 ListView.builder，4 项）：① 每日推荐横滑卡（RecommendLogic.daily，空态注明「登录后可能可见」，不臆造端点）；② 推荐歌单三列卡（PlaylistLogic.recommend）；③ 排行榜渐变卡（RankLogic.rankList，点击拉 rankInfo 后 playAll）；④ 热搜 chips（SearchLogic.hotSearch）。
- 每区块 M3SectionHeader 风格标题行；卡片点击进对应详情：歌单卡打开共享的 `PlaylistDetailSheet`（定义于 playlist_page.dart 并跨页复用），榜单卡直接起播。

## search_page.dart（476 行）
- SafeArea + 顶部大胶囊搜索框（TextField + 圆形绿色提交按钮）。
- 空闲态：热门分类 chips（前端关键词触发歌曲搜索）+ 历史记录（可清空）。
- 输入时走 `SearchLogic.suggestions` 联想下拉；提交走 `SearchLogic.search`（缓存接入）。
- 结果分五段 ChoiceChip（歌曲/歌单/专辑/歌手/歌词）；当前 logic 层仅「歌曲」有端点，其余四段显式空态说明「logic 层未开放端点」，不臆造调用。
- 结果行 `_SongTile`（SpSongTile 风格）：封面/名称/歌手/VIP 加粗/专辑跳转（NavState.setAlbum）/时长，点击行 playAll。

## playlist_page.dart（500 行）
- SafeArea + TabBar（推荐 / 我的，DefaultTabController）。
- 推荐页：3 列封面网格（PlaylistLogic.recommend），封面 + 名称 + 曲目数。
- 我的页：本地镜像列表（PlaylistLogic.listLocal，PlaylistMeta）。
- 点击任一条目弹出 `PlaylistDetailSheet`（DraggableScrollableSheet）：先 `detail` 拿 specialId，再 `tracks` 取曲目分页；曲目行点击即 `PlaybackSession.playAll`；行内专辑图标走 NavState 传 albumId。

## 已知边界
- 空结果不固化缓存已在 logic 层处理；页面层对空/错/加载三态均有 UI 兜底。
- 首页「每日推荐」依赖登录态，未登录时显示空态文案而非伪装数据。
- design/components.dart 不存在，三态组件以页面私有 widget 实现（规格允许的降级路径）。
