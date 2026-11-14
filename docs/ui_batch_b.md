# 批 B · UI 页面改动说明（UI-B 组）

范围：仅新增/重写 4 个 L7 surface 页面文件，未改动其它任何文件。

| 文件 | 行数 | 说明 |
|---|---|---|
| lib/surface/pages/player_page.dart | 369 | 播放页 |
| lib/surface/pages/library_page.dart | 265 | 音乐库页 |
| lib/surface/pages/lyrics_page.dart | 279 | 歌词页 |
| lib/surface/pages/settings_page.dart | 284 | 设置页 |

四文件均 ≤500 行；颜色/字号/间距/圆角一律取 `Sp.*`（design/tokens.dart，唯一真源），
共享控件复用 `design/components.dart`（SpCover / SpSongTile / SpStateView / SpListSkeleton /
SpSkeleton / SpPlayButton / SpRoundButton / SpSectionHeader），页面只做组合。

---

## 1. player_page.dart（播放页）

- 结构：顶部栏（收起箭头 `Navigator.maybePop` + `FavoriteButton` + ⋮ 菜单），中部大圆角封面
  （`SpCover`，`Sp.artHero` 尺寸，`Sp.rXL` 圆角，居中），歌名 `Sp.fPageTitle` 加粗 / 歌手
  `textSub`，进度条 + 时间行，控制行（随机 / 上一首 / 大圆播放暂停键 64px 绿底黑图标 /
  下一首 / 循环），底部倍速徽标 + 音质入口。
- **进度条合规**：自写 `StatefulWidget _SeekSlider`。
  `Slider.onChanged` 只写本地 `_preview`（setState 本地预览），**不调用 seek**；
  `onChangeEnd` 才 `playbackSession().seek(ms)`。`didUpdateWidget` 在外部位置追上预览值时
  交还真实进度。
- 控制行为全部走 `PlaybackSession` 意图方法：`toggle / prev / next / setMode`，
  随机 = `PlayMode.shuffle`，循环 = `PlayMode.loopOne`。
- 倍速徽标 → bottom sheet（0.5~2.0）→ `session.setSpeed(v)`；
  音质入口 → bottom sheet（`vipQualities()` × `qualityParam()`）→ `session.setQuality(v)`。
- 收藏按钮 `FavoriteButton`（本文件内定义，状态本地维护；收藏写域未在本批接入远端）。
- ⋮ 菜单：歌词 / 评论 / FM 通过 `navState().requestTab('lyrics'|'comment'|'fm')`，
  不直接导航其它模块。
- 模块：`PlayerPageModule implements SurfaceModule`，id `player`，route `/player`，
  **navEntry = null**（不进底部导航）。

## 2. library_page.dart（音乐库页）

- 顶部账号卡：圆形头像（`Image.network` + 占位）、昵称、ID、`我喜欢` 数。
  数据来自 `appGraph.user.profile()`（UserLogic）与 `appGraph.collect.refreshCount()/count`
  （CollectLogic）。**档案为空（未登录 / 端点未实测）时整块隐藏**，不做假数据。
- `TabBar` 三页签：本地曲库 / 最近播放 / 下载管理。
- 下载管理页签走 `appGraph.downloads.listTasks()`（DownloadManager），列表用
  `ListView.builder`，行内展示歌名/歌手/音质/状态/进度。
- 本地曲库与最近播放：`SongDao` / `HistoryDao` 实例目前只存在于 session 装配参数
  （`SessionDeps`），**未随 AppGraph / 桥暴露**，故这两个页签渲染 `SpStateView` 空态并写明
  原因，不臆造数据；待 DAO 经桥暴露后接入。
- 模块：`LibraryPageModule`，id `library`，route `/library`，navEntry `('音乐库','library_music')`
  （进底部导航）。

## 3. lyrics_page.dart（歌词页）

- 全屏歌词列表（`ListView.builder`），当前行绿色 + 粗体（`Sp.green` / `FontWeight.w700`）。
- **性能**：不每帧 rebuild 整页。用 `Timer.periodic(200ms)` 轮询
  `PlaybackSnapshot.player.positionMs` → 只更新 `ValueNotifier<int> _active`（当前行索引），
  列表项用 `ValueListenableBuilder` 局部重绘；切歌时按 hash 重载歌词。
- 数据：`appGraph.lyrics.lyricsFor(song)` → `LyricResult`；`parsedFor()` 得带时间轴的
  `LrcLine` 列表；译文用 `appGraph.translation.displayFor(result, LyricsDisplayMode.bilingual)`
  取 `DisplayLine.sub`。
- 顶部：返回 + 原文/翻译 `SegmentedButton`。**无译文数据时翻译档禁用（onSelectionChanged=null），
  只显示原文**。
- 自动滚动居中：当前行变化时 `ScrollController.animateTo`（`Sp.normal` / `Sp.curve`）。
- 模块：`LyricsPageModule`，id `lyrics`，route `/lyrics`，**navEntry = null**。

## 4. settings_page.dart（设置页）

- 分组：账号 / 外观 / 播放 / 存储 / 关于，卡片背景 `Sp.card` + `Sp.rCard`。
- 账号行：登录态（`AuthLogic.session.userid` 非空）显示昵称（`AccountLogic.activeAccount()
  .displayName`）+「登出」按钮（`auth.logout()`）；未登录显示「扫码登录」占位按钮
  （本批不接二维码 UI，点击提示「扫码登录入口待接入」）。
- 外观行：`SegmentedButton<ThemeMode>` 四档（跟随系统 / 亮 / 暗 / 纯黑），横向可滚动避免溢出。
- 播放行：音质（bottom sheet → `session.setQuality`）、倍速（bottom sheet → `session.setSpeed`），
  倍速读 `PlaybackSnapshot.speed`。
- 存储行：「清理缓存」→ `appGraph.cache.invalidateSession()`（bridge_core 的 `CacheService`）。
  **磁盘级缓存目录清理能力目前未经桥暴露**，故只调用已暴露能力，不臆造磁盘删除；
  按钮可用且在注释中标明边界。
- 关于行：版本号常量 `kAppVersion = '26.11.10+1'`（与 pubspec.yaml version 同步）。
- 模块：`SettingsPageModule`，id `settings`，route `/settings`，navEntry `('设置','settings')`。

---

## 跨层 / 桥使用说明

- L7 只消费 `PlaybackSession`（bridge_session `playbackSession()`）、`NavState`
  （bridge_session `navState()`）、`SurfaceModule` / `NavEntry`（bridge_session 出口），
  以及 logic 单例类型（bridge_core / bridge_logic）。
- **GAP（已在代码注释标注）**：`bridge_session` 只导出 `AppGraph` *类型*，未导出装配图
  *实例*；本次三处需要 logic 单例（user/collect/downloads、lyrics/translation、
  auth/account/cache），故暂从 `session/bootstrap.dart` 取 `appGraph` 实例。
  建议主会话在 bridge_session 补一个 `appGraph()` 出口后，把这 3 处 import 换回桥。
- 未臆造任何端点或假数据；缺失能力一律渲染 `SpStateView` 空态 + 文字说明。

## 未做（按批次边界）

- 未注册模块到 `ModuleRegistry`（注册由主会话/其他批次在装配层完成）。
- 未改动 app_root / theme / components / 任何 session、logic、core、bridge 文件。
- 未跑 analyzer、未提交。
