# A7 批 · C1 架构合规视角 · 深度审查

> 审查对象：`lib/surface/` 18 文件 + `lib/l10n/` 全部 arb + README
> 视角：76 原则架构合规（层职责 / 依赖方向 / 六桥通道 / 1500 行 / i18n 结构 / 死代码）
> 只读审查，未改任何源码；证据均带 `文件:行`。

---

## [2026-11-16 23:50] 依赖图与行数基线（只读）

- surface 18 文件共 **4828 行**；最长 `pages/playlist_page.dart` 576 行，其次 `search_page.dart` 475、`login_sheet.dart` 461、`player_page.dart` 442、`home_page.dart` 436。**无任何文件超 1500 行**（76 铁律 5 行数门禁：符合）。
- import 事实：所有跨层引用均指向 `../bridges/bridge_core.dart` / `bridge_logic.dart` / `bridge_session.dart`（均为桥文件），**未发现任何 `../logic/`、`../core/`、`../session/` 非桥直连 import**；未发现反向依赖（无 L6/L5/L4 import surface）。
- 说明：§2 定义 `bridge_core`/`bridge_logic`「供上层经白名单复用」，故 surface 直接 import 这三座桥本身不构成「越级直连非桥文件」；但「只经 bridge_surface 拿 L6 门面」的收敛度问题见下方独立条目。

---

## <视角 C1> · lib/surface/app_root.dart:5-21 · <P2> · <桥通道收敛>
证据：import `../bridges/bridge_core.dart`（KugouClient/SongDao/PlaylistDao/HistoryDao/DownloadStore/KeyValueSettings/StoragePaths）+ `../bridges/bridge_session.dart` + 同层 tokens/shell；全库 surface 18 文件无一个 import `bridge_surface.dart`（仅注释提及）。
问题：§0/§2 约定 L7 应「经 bridge_surface 拿 L6 门面」，实际所有页面绕过 bridge_surface 直接抓 bridge_core/bridge_logic/bridge_session；bridge_surface 在 surface 侧形同虚设（仅 L1 init/main.dart 使用）。
建议：由主会话评估是否把跨层门面统一收敛到 bridge_surface 单一出口（仅改设计，本代理不动代码）。
76 合规：不违反铁律 1（仍走桥文件）；但偏离 §0「surface 只经 bridge_surface」与 §2 桥职责划分，记为架构漂移。

## <视角 C1> · lib/surface/app_root.dart:24-42 · <P1> · <层职责/装配图越界>
证据：`class SurfaceDeps` 字段含 `KugouClient client / SongDao songDao / PlaylistDao playlistDao / HistoryDao historyDao / DownloadStore downloadStore / KeyValueSettings settings / StoragePaths? paths`，`pathsOrI` 直接取 `StoragePaths.I`；注释「由 L1 经 bridge_surface 注入」。
问题：L7 被 §0 明令禁止「装配图/provider 图」，此处 SurfaceDeps 实质是一张 core 层依赖装配图（DAO/Store/Settings/Client 全握住），装配职责应属 L2/L6。
建议：SurfaceDeps 仅保留 UI 渲染所需最小门面（或降级为 §6 占位），把 core 依赖装配下沉 L2 bootloader / L6 session。
76 合规：违反 §0 L7「禁止装配图」及铁律 8 精神（装配不属 UI 层）。

## <视角 C1> · lib/surface/app_root.dart:61-67 · <P2> · <TODO 占位>
证据：`// 0 系统 / 1 亮 / 2 暗 / 3 纯黑（纯黑暂用暗色板，TODO 更深色板）`，`themeMode` switch 中 `0/2/3` 全部落 `_ => ThemeMode.dark`。
问题：主题模式 0（跟随系统）被错误映射为 dark，3（纯黑）无独立色板；TODO 未落。
建议：0 应映射 `ThemeMode.system`，3 应给纯黑色板或显式降档；清 TODO。
76 合规：符合（仅 UI 逻辑），属功能/文案缺口，交 C2/C3 复核。

## <视角 C1> · lib/surface/shell.dart:20-39 · <P1> · <L7 承担模块注册装配>
证据：`registerModules()` 内 `ModuleRegistry.instance..install(HomePageModule())..install(...)..registerMvModule()`；由 app_root.dart:72 `installServices` 调用。
问题：§0 明确「模块注册表/装配图在 L6」，L7 surface 在此直接向 L6 ModuleRegistry 注册 8 个页面模块，属把装配动作放在 UI 层（虽 §6 允许 app_root 占位含 installServices，但此处是实装而非占位）。
建议：模块注册移入 L6 session（或 bridge_surface 的实现侧），surface 只消费注册结果。
76 合规：违反 §0「模块注册表属 L6」「L7 禁止装配图」。

## <视角 C1> · lib/surface/theme/tn_theme.dart:1-11 · <P2> · <缺 §6 占位头>
证据：文件仅 11 行，`ThemeData spLightThemeData()`；文件头无 `// PLACEHOLDER — 由独立 UI 模型重写，禁止在此堆逻辑`（§6 硬性要求）。经复核：函数名与 bridge_surface.dart:9,16 的 `show/export spLightThemeData` 一致，前述「命名不符」判断已撤回。
问题：缺 §6 强制占位头（命名一致性 OK）。
建议：按 §6 补占位头或由主会话确认保留实装口径。
76 合规：违反 §6 占位约定（缺 PLACEHOLDER 头）。

## <视角 C1> · 全局 · <P2> · <V2 占位约定整体偏离>
证据：§6 规定「surface 页面/组件全部不建文件，仅 app_root.dart + theme/tn_theme.dart 占位」；现状 surface 实建 18 文件 4828 行（含 pages/design 全套实装）。
问题：整层未按 V2 占位约定收敛，而是保留了一整套旧 UI 实现；这与 76 原则 V2「由独立模型从零重写」方向冲突。
建议：主会话明确本轮是「保留现有 UI 做合规修补」还是「按 §6 清空为占位」，二选一后统一口径（本代理只记录，不改）。
76 合规：违反 §6（若按 V2 严格口径）；需主会话裁定。

---

## [2026-11-16 23:53] 页面读取：home / library / login 组

## <视角 C1> · lib/surface/pages/home_page.dart:47-118 · <P1> · <L7 承担数据编排/业务编排>
证据：`_load()` 直接调用 `g.recommend?.daily(1)` / `g.playlist?.recommend(1)` / `g.rank?.rankList()`；`_openRank()` 内 `rk.rankInfo(rank.rankId).then(...).catchError(...)` 并直接 `PlaybackSession.instance.playAll(songs, 0)`；`_play()` 直接下发播放意图。
问题：页面在 initState/回调里直接编排 L5 logic（recommend/playlist/rank）与 L6 播放（playAll），实质是「数据获取+播放编排」状态机驻留 L7；§0 要求 L7 只画控件、状态与编排归 L6。
建议：把「取数→选择→播放」编排下沉 L6 session，页面只 watch 快照 + 发意图。
76 合规：违反 §0「L7 仅 UI 控件」「播放控制/队列不得进 UI 层」及铁律 8 精神。

## <视角 C1> · lib/surface/pages/library_page.dart:31-61,243-260 · <P1> · <L7 直连 core DAO>
证据：`_localSongs = appGraph.songDao?.list()`；`_recentSongs = appGraph.historyDao?.recent()`；`_reloadLists()` 内 `setState(() { _localSongs = appGraph.songDao?.list(); ... })`；`_loadDownloads()` 读 `appGraph.downloads.listTasks()`。
问题：surface 页直接持有并调用 core 层 DAO（SongDao/HistoryDao）与 DownloadManager，读写本地存储属 L4/L5 职责，UI 层不该直接触达。
建议：经 L6 session 暴露「曲库快照/最近播放/下载列表」状态，页只消费快照。
76 合规：违反 §0 层职责（UI 层直连存储/DAO），虽经 appGraph 桥对象取用、形式走桥但职责越界。

## <视角 C1> · lib/surface/pages/login_sheet.dart:127-206 · <P1> · <L7 内 QR 轮询状态机 + Timer>
证据：`class _QrTabState` 持 `QrLoginState? _qr; Timer? _timer; bool _recreatedOnce`；`_createQr()` 内 `auth.createQrLogin()` + `Timer.periodic(Duration(milliseconds:1500), (_) => _poll(st.key))`；`_poll()` 内 `switch(st.status){waitScan/waitConfirm/expired/success}` 四态状态机，含「过期自动重建一次」逻辑。
问题：完整的二维码登录状态机与定时轮询驻留 UI Widget，属 §0 明禁的「L7 塞状态机」；状态/定时器应在 L6/L5。
建议：QR 生命周期（建码/轮询/过期重建/成功）下沉 auth_session，surface 只渲染状态并发意图。
76 合规：违反 §0「L7 只有 Widget 与 ThemeData；禁止状态机」。

## <视角 C1> · lib/surface/pages/login_sheet.dart:238-320 · <P1> · <L7 内短信倒计时状态机 + 登录业务>
证据：`_SmsTabState` 持 `int _countdown; Timer? _timer`；`_sendCode()` 内 `auth.sendVerifyCode(phone)` + `Timer.periodic(Duration(seconds:1), ...)` 60s 倒计时；`_login()` 内 `auth.signInByVerifyCode(phone,code)` 并按 `res.ok/res.needsProbe/res.error` 分支。
问题：60s 防重发倒计时与登录结果分支属业务逻辑，驻留 L7。
建议：倒计时状态与登录流程下沉 L6/L5。
76 合规：违反 §0「L7 禁止状态机」。

## <视角 C1> · lib/surface/pages/login_sheet.dart:13-14 · <P2> · <死代码/未用 import>
证据：`import '../../bridges/bridge_core.dart' show AccountRecord, sendSmsCode, smsLogin, KugouApiException;` —— rg 确认 `sendSmsCode`/`smsLogin`/`KugouApiException` 在全文仅出现于 :14 import 与 :5 注释，无实际调用（实际走 `appGraph.auth.*`）。
问题：桥门面 import 冗余，疑为改造残留（旧直连端点调用遗留）。
建议：清理未用 show 项。
76 合规：符合（不违反分层），属死代码。

## <视角 C1> · lib/surface/pages/login_sheet.dart:330-355 · <P2> · <登录落库/通知写操作在 UI>
证据：`_onLoginSuccess()` 内 `await appGraph.account?.saveCurrent(); navState().bumpAuth(); widget.onAuthChanged?.call(); Navigator.of(context).pop();`；`_switchTo()`/`_removeAccount()` 直接 `appGraph.account?.switchTo/removeAccount`。
问题：账号落库、切换、移除等写操作在 surface 按钮回调内直接执行，属业务写逻辑驻留 UI 层。
建议：封装为 L6 auth_session 意图方法。
76 合规：违反 §0「L7 仅 UI 控件」。

## <视角 C1> · lib/surface/pages/home_page.dart:8, home_page.dart:5 · <P2> · <重复 import 同一桥>
证据：`import '../../bridges/bridge_session.dart' show NavState, PlaybackSession, SurfaceModule, NavEntry;` 与紧邻 `import '../../bridges/bridge_session.dart' show appGraph;` 分两条；settings_page.dart:9,11、lyrics_page.dart:12,15、search_page.dart:8,10、playlist_page.dart:7,9 同样拆两条。
问题：同一桥文件重复 import（可合并），非分层违规但属整洁缺陷。
建议：合并同桥 show 列表。
76 合规：符合（均桥文件），属代码整洁。

## [2026-11-16 23:56] 页面读取：lyrics / mv

## <视角 C1> · lib/surface/pages/mv_page.dart:12-20 · <P0> · <MV 模块注册守卫＝四重断点之一（surface 侧）>
证据：
```
void registerMvModule() {
  final reg = ModuleRegistry.instance;
  if (reg.byId('mv') != null) return;   // ← L18
  reg.install(MvPageModule());
}
```
问题：该「id 已存在即 return」守卫使 MV 模块在 L6 注册表已有 `mv` 占位（L6 预置禁用/空 builder 占位）时**永不安装真正的 MvPageModule**；A1/A6 已确认这是 MV 四重断点之一。surface 侧确认：可修——将守卫改为「存在但非启用/占位则覆盖安装」或在 L6 注册阶段提供 upsert 语义；当前幂等逻辑把「占位」误判为「已装好」，导致点 MV 进来是空壳。
建议：主会话修：区分「占位模块」与「真实模块」，守卫应覆盖占位（如 `reg.install` 本就幂等覆盖则删掉该 return，或判断 `byId('mv')?.builder` 是否为占位）。
76 合规：本守卫位于 L7 的注册动作，叠加 §0「模块注册表属 L6」越界（见 shell.dart 条目）。

## <视角 C1> · lib/surface/pages/mv_page.dart:75-130 · <P1> · <L7 承担 MV 完整取数/选档/URL 处理状态机>
证据：`_load()` 内 `logic.qualities(hash)` → 自写「ld→sd→size 最小」选档算法 → `logic.playUrl(hash, requestedId: requested)` → `r.playable` 判断 → `http://` 升级 https → `VideoPlayerController.network(url).initialize()/setLooping()/play()`；`enum _Phase{loading,empty,error,ready}` 四态。
问题：选档策略、URL 协议处理、播放器生命周期与四态机全在 Widget，属 §0 禁止的「L7 塞状态机」；video_player 是成熟库（铁律 9 允许）但编排应在 L6/L5。
建议：选档与 URL 解析下沉 L5 mv_logic，播放状态与错误态下沉 L6；surface 仅持有 controller 与渲染。
76 合规：违反 §0「L7 只有 Widget/ThemeData，禁止状态机」。

## <视角 C1> · lib/surface/pages/mv_page.dart:28-35 · <P2> · <死代码/占位入口>
证据：`MvPageModule.builder => (_) => const MvPage(songHash: '')`，songHash 恒为空串；`MvPage._load()` 首行 `if (hash.isEmpty) { _fail(empty, '缺少歌曲 hash'); return; }`。
问题：注册到 L6 的 MV 模块入口永远以空 hash 构建，即使解除 L18 守卫，从注册表点击进入也必然落到「缺少歌曲 hash」空态；真正可用路径只有 player_page.dart 直传 hash 的 `MvPage(songHash:...)`。
建议：模块 builder 改为从 NavState 路由参数取 hash，或由 player 页 push 时传参。
76 合规：符合分层，属功能可达性断点（与 P0 守卫叠加，交 C2 复核）。

## <视角 C1> · lib/surface/pages/lyrics_page.dart:47-133 · <P1> · <L7 内 200ms 轮询状态机 + 歌词解析>
证据：`_timer = Timer.periodic(Duration(milliseconds:200), (_) => _tick())`；`_load()` 内 `logic.lyricsFor(song)` + `logic.parsedFor(result)` + `trans.displayFor(result, LyricsDisplayMode.bilingual, ...)`；`_tick()` 根据 `snap.player.positionMs` 逐行比对推进 `_active`；类持 `_hash/_loading/_error/_bilingual/_hasTranslation/_rows` 六个状态字段。
问题：歌词加载、翻译组装、200ms 定位轮询与「当前行」推进状态机驻留 L7；应归 L5/L6（快照驱动），UI 只渲染。
建议：歌词行和高亮索引由 L6 快照提供，surface 用 ValueListenable/AnimatedBuilder 渲染，去掉 Timer 轮询。
76 合规：违反 §0「L7 禁止状态机」。

## <视角 C1> · lib/surface/pages/lyrics_page.dart:13-15 · <P2> · <跨桥注释承认桥缺口>
证据：`// GAP(跨桥)：逻辑单例随 AppGraph 暴露，bridge_session 暂未导出实例出口。` 紧接 `import '../../bridges/bridge_session.dart' show appGraph;`。
问题：源码自认桥出口缺口——L7 需的 logic 单例（LyricsLogic/TranslationLogic）不得不经 appGraph 间接取，而非经正规桥门面。
建议：bridge_session/bridge_surface 补齐 typed getter，消除 GAP 注释。
76 合规：桥通道不净（虽仍走桥文件），记为桥设计缺口。

## [2026-11-16 23:59] 页面读取：player / playlist / search / settings + l10n 结构

## <视角 C1> · lib/surface/pages/player_page.dart:169-206 · <P1> · <L7 直接取数并编排播放>
证据：`_openMenu()` 的「个人 FM」分支 `final songs = await appGraph.fm?.start(); if (songs != null && songs.isNotEmpty) await PlaybackSession.instance.playAll(songs, 0);`，其余分支 `navState().requestTab('lyrics')/('comment')`；「查看 MV」分支 `registerMvModule()` + `PlaybackSession.instance.snapshot.player.current.hash` + `push(MvPage(songHash: hash))`。
问题：页面菜单回调直接调 L5 FM 端点（fm.start）并触发播放编排，且直接读 session 快照拼路由，属 L7 承担业务编排。
建议：FM 启动/播放与 MV 跳转语义下沉 L6 意图方法。
76 合规：违反 §0「L7 仅 UI 控件」「播放控制/编排不得入 UI」。

## <视角 C1> · lib/surface/pages/player_page.dart:62-83 · <P1> · <L7 收藏状态机本地伪造>
证据：`class _FavoriteButtonState { bool _fav = false; ... setState(() => _fav = !_fav); }`，注释「收藏域写端点尚未经桥暴露，故不写远端」。
问题：收藏态在 UI 内用本地 bool 假装，既不落 L5/L6 状态也不写远端，是「界面假状态」，属职责越界 + 功能断点。
建议：收藏态与写入下沉 L6/L5，surface watch 真实收藏快照。
76 合规：违反 §0「L7 仅 UI 控件（无状态机）」。

## <视角 C1> · lib/surface/pages/playlist_page.dart:63-95,140-175,240-270 · <P1> · <L7 三处取数编排 + 播放>
证据：`_RecommendTabState._load()` 内 `appGraph.playlist?.recommend(1)`；`_MineTabState._load()` 内 `pl.listLocal()`；`_PlaylistDetailSheetState._load()` 内 `pl.detail(id)` → `pl.tracks(id,1,specialIdOverride:...)` 两级串行编排；`_play()` 内 `PlaybackSession.instance.playAll(_data.tracks.items,index)`。
问题：歌单推荐/本地镜像/详情+曲目分页编排与播放意图全在 Widget；属典型 L7 承担业务/数据编排。
建议：详情+曲目聚合下沉 L5，页面只消费 L6 快照。
76 合规：违反 §0「L7 只有 Widget/ThemeData」。

## <视角 C1> · lib/surface/pages/search_page.dart:67-116 · <P1> · <L7 搜索状态机 + 历史记录缓存>
证据：`_SearchPageState` 持 `_query/_segment/_resultF/_suggestF` 与 `final List<String> _history`；`_doSearch()` 内 `appGraph.search?.search(q,1)` / `appGraph.searchTyped?.typed(type,q,1)`，并 `_history..remove(q)..insert(0,q)` 自维护上限 12 条；`_onChanged()` 内 `se?.suggestions(t)`。
问题：搜索历史（L4 storage 职责）在 UI 内用内存 List 维护（不持久化），搜索/联想/分段编排驻留 L7；属状态机与缓存职责越界。
建议：搜索历史下沉 L4 storage 经 L6 暴露，搜索编排下沉 L6。
76 合规：违反 §0「缓存/存储不在 UI 层」「L7 禁止状态机」。

## <视角 C1> · lib/surface/pages/settings_page.dart:60-84 · <P1> · <L7 直接执行登出与缓存失效写操作>
证据：`_logout()` 内 `auth.logout(); appGraph.cache?.invalidateSession(); ... navState().bumpAuth();`；`_clearCache()` 内 `cache.invalidateSession()`。
问题：登出、会话缓存失效等写操作在设置页按钮回调内直接执行，属 L7 承担业务写逻辑（缓存职责属 L4）。
建议：封装为 L6 session 意图（logoutAndClear 等）。
76 合规：违反 §0「L7 仅 UI 控件；缓存不得入 UI」。

## <视角 C1> · lib/l10n/README.md:17,54,57 · <P1> · <i18n 文档自相矛盾/过时>
证据：README 表格「当前只落 3 语（简中/繁中/英），其余 7 语是计划占位」；第 54 行「TnStrings.supportedCodes 固定为这 3 语」；但第 47-57 行又称「当前 10 语全量可用」「7 语已人工级翻译并落盘」，且实测 10 份 arb 均存在、各 20 键齐全，`lib/core/l10n/strings.dart:242` 的 supportedCodes 实为 10 语。
问题：README 同一文件内并存「3 语」与「10 语」两套互斥陈述，前半（表格+说明+铁律）严重过时，误导维护者。
建议：主会话重写 README 统一为「10 语全量、各 20 键、键集一致」的现状口径，删旧的 3 语占位叙述。
76 合规：符合分层（i18n 资源无层职责违规），属文档一致性缺陷。

## <视角 C1> · lib/l10n/（10 份 arb）+ lib/surface/（全 18 文件）· <P2> · <i18n 资源与 surface 完全脱节>
证据：10 份 `app_*.arb` 均含 20 键且键集完全一致（@@locale 正确：zh/zh_Hant/en/ja/ko/es/fr/de/pt/ru）；`TnStrings` 定义于 `lib/core/l10n/strings.dart:235`（10 语 supportedCodes）。但 `rg "TnStrings|l10n_helper|AppLocalizations" lib/surface` 全部无命中，`lib/surface/l10n/` 目录不存在；surface 18 文件硬编码中文（login_sheet 54 处、settings 40 处、home 33 处、playlist 30 处、library/mv/player 各 27-28 处等，由 rg PCRE 汉字计数）。
问题：完整的多语资源齐备却零消费，surface 全部字面量硬编码中文；README 声称的 `lib/surface/l10n/l10n_helper.dart` 实际不存在（已迁 core/l10n/strings.dart）；架构上 i18n 通道未接通。
建议：surface 文案统一经 TnStrings（经桥暴露）取词；删除 README 过时 helper 引用。（文案硬编码细节由 C3 主查，此处仅记架构通道断裂）
76 合规：不违反分层（README 称 helper 属 L6 有误，实际 strings 在 L4 core 符合 §0「l10n 常量在 L4」）；记为 i18n 架构通道未接通。

## [2026-11-16 24:02] 复核 + 收口

## <视角 C1> · lib/surface/design/components.dart:44-110 · <P2> · <死代码 Widget>
证据：`SpSongTile` 定义于 components.dart:44，全 surface 仅 search_page.dart:475 注释「歌曲行（SpSongTile 风格）」提及，无实际实例化（搜索页用自造的 `SearchSongTile`，见 search_tile_widgets.dart）。
问题：共享组件 SpSongTile 无消费者，属死代码（与 SearchSongTile 功能重复）。
建议：搜索页改用 SpSongTile 或删除未用组件。
76 合规：符合分层，属死代码。

## <视角 C1> · lib/surface/player_page.dart:66 / settings_page.dart:134 / lyrics_page.dart:14 · <P2> · <多处自认桥能力缺口（GAP 注释）>
证据：player_page.dart:66「收藏域写端点尚未经桥暴露，故不写远端」；settings_page.dart:134「磁盘级缓存目录清理能力尚未经桥暴露」；lyrics_page.dart:14「bridge_session 暂未导出实例出口」。
问题：三处表明 L7 需要的门面（收藏写入/磁盘缓存清理/typed 逻辑单例）未桥接，导致 UI 层用假状态或绕道 appGraph，是桥覆盖不全的实证。
建议：bridge_core/bridge_session 补齐对应门面后，surface 改为正规取用。
76 合规：桥通道不净（根因在桥覆盖不足，surface 侧为症状）。

## <视角 C1> · 全局桥/反向依赖复核 · <符合项留证>
证据：`rg --files lib/bridges` = 6 座桥齐备（bridge_boot/kernel/core/logic/session/surface）；`rg --files | rg bridge | rg -v '^lib/bridges/'` 无输出（无影子桥）；`rg "import '../" lib/surface | rg -v bridges/|design/|pages/|theme/|shell|app_root` 无输出（无跨层非桥 import）；`rg "bridge_surface" lib/surface` 仅注释三处，无 import。
问题：依赖方向/桥文件层面合规，但 bridge_surface 在 surface 侧零 import（见首条漂移）。
76 合规：铁律 1/3 符合。

---

## 本视角结论
1. **依赖方向/桥文件合规面良好**：surface 18 文件全部只 import 桥文件（bridge_core/logic/session）+ 同层 design/pages，**零直连 logic/core/session 非桥文件，零反向依赖，零影子桥**；六桥文件齐备且只在 lib/bridges/。
2. **但桥通道收敛度差**：surface 完全不 import bridge_surface，全部绕过它直取三座下桥；bridge_surface 仅被 L1 init/main.dart 使用，L7「只经 bridge_surface 拿门面」的 §0 约定未落实。
3. **L7 职责大面积越界（最严重）**：至少 10 个页面在 Widget 内持有状态机/定时器/业务编排/存储 IO——QR 登录四态+轮询（login_sheet）、歌词 200ms 定位轮询+解析（lyrics）、MV 选档+协议处理+播放器四态（mv_page）、歌单两级取数+播放（playlist）、搜索联想/历史缓存（search）、FM 取数+播放与假收藏态（player）、DAO 直读与缓存失效（library/settings）。违反 §0「L7 只有 Widget 与 ThemeData」。
4. **MV 四重断点在 surface 侧可修**：`mv_page.dart:18` 的「id 存在即 return」守卫 + `builder => MvPage(songHash:'')` 空 hash 入口，双重导致 MV 模块即使注册成功也进不去；建议主会话改为 upsert 覆盖占位并从路由取 hash。（P0）
5. **装配越界**：app_root 的 SurfaceDeps 握全套 core 门面（装配图）、shell 的 registerModules 向 L6 注册表注册 8 模块，均属 §0 禁止 L7 持有的装配职责。
6. **1500 行门禁达标**：18 文件共 4828 行，最长 playlist_page 576 行，无超限。
7. **i18n 结构齐备但通道断裂**：10 份 arb 全在、各 20 键、键集一致、@@locale 正确；但 surface 零处使用 TnStrings/AppLocalizations，全部硬编码中文；README 自相矛盾（「3 语占位」与「10 语全量」并存）且引用的 l10n_helper.dart 已不存在。
8. **死代码/占位**：SpSongTile 无消费者；login_sheet 冗余 import（sendSmsCode/smsLogin/KugouApiException）；app_root 主题模式 0/3 映射错误 TODO；tn_theme 缺 §6 PLACEHOLDER 头。

## 未覆盖
- 未逐字节核对 10 份 arb 的**译文质量/语义准确性**（仅核结构、键集、@@locale、文件存在；译文内容属 C3 文案视角）。
- 未逐行审 `lib/core/l10n/strings.dart` 全文（仅读 TnStrings 段 235-304 用于确认 10 语 supportedCodes）。
- 未读取 bridge_surface/bridge_core/bridge_logic/bridge_session 全文（仅抽读 bridge_surface 用于契约核对；六桥内部 try/catch+Log 属 A6 C1 范围，本视角只做 surface 侧引用取证）。
- 未运行任何分析器/门禁/测试（按工具纪律禁止）。
- 全部 18 个 surface 文件均已读完（playlist_page 576 行分两段读取），无遗漏。

## 76 合规小结
- **符合**：铁律 1（无跨层直连非桥 import）、铁律 3（无影子桥，桥唯一在 lib/bridges/）、铁律 5（无文件超 1500 行）、依赖方向（无 surface↔session 反向 import）、i18n 常量归属 L4 core（strings.dart 在 core，符合 §0）。
- **违反**：§0「L7 仅 UI 控件/禁止状态机、播放控制、缓存、装配图、provider 图」——至少 10 个页面 + app_root(SurfaceDeps) + shell(registerModules) 越界；铁律 8 精神（播放编排入 UI）。
- **偏离/漂移**：§0「surface 只经 bridge_surface 拿 L6 门面」未落实（surface 零 import bridge_surface）；§6 V2 占位约定整体偏离（实建 18 文件 4828 行而非仅 2 个占位文件，且缺 PLACEHOLDER 头）。
- **桥缺口**：收藏写/磁盘缓存清理/typed 逻辑单例未桥接（GAP 注释实证），surface 以假状态或 appGraph 绕道，桥通道不净。
