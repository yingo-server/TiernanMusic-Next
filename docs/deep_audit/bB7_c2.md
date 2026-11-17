# B7 批 · 视角 C2（实现正确性）· i18n 文案 / 设置 / 导航 / 错误空态

> 子代理：C2 实现正确性。范围：L7 settings_page.dart / shell.dart / home_state_views.dart / components.dart / 各页错误空态分支；L6 nav_state.dart / bootstrap.dart；L4 core/l10n/strings.dart；另核 surface/l10n/s.dart 门面、app_root.dart（locale 绑定实际落点）。
> 纪律：全程只读（file_read + rg/ls/wc），未改任何源码、未跑 dart/analyze/test、未联网。结论仅写本文件。

---

## [2026-11-17 09:52] ## <视角 C2> · lib/core/l10n/strings.dart:610-618 + lib/surface/pages/settings_page.dart:165-215 · <P0> · <i18n 取词链断在写入侧：saveLocale 全仓零调用者，语言状态无任何产生源>
证据：
```
lib/core/l10n/strings.dart:610  static void saveLocale(String code) {
lib/core/l10n/strings.dart:612    final s = KeyValueSettings.shared(StoragePaths.I);
lib/core/l10n/strings.dart:613    s.setString(_localeKey, normalize(code));
```
`rg -n 'saveLocale' lib tool test` 全仓结果：仅 `lib/core/l10n/strings.dart:610`（定义）、`tool/gen_i18n.py:55`（模板文本）、`lib/surface/l10n/s.dart:33`（注释提到 loadLocale）。**零个生产调用者**。
设置页 `settings_page.dart` 全文 325 行，「外观」分组只含「主题模式」SegmentedButton（:165-215），**无任何语言/语言选择控件**；全文无 `S.of`、无 `TnStrings` 引用。
问题：阶段 A 建立的 i18n 门面只能「读」，不能「写」——持久化语言值 `ui.locale` 永远为空，`S.of(context)` 永远走 `_fromLocale(locale)` 系统语言分支，整条 i18n 取词链没有入口，用户「文案没改」在写入侧即被切断。
建议：设置页「外观」组补语言选择（10 语 + 跟随系统），选择时调 `TnStrings.saveLocale(code)` 并把值注入 L6（见下条 P0-02），同时提供「跟随系统」以清除 `ui.locale`（当前设计无清除入口，见 P1-03）。
76 合规：无越级（设置页只经 bridge_core 调 L4），但 L6 无语言状态归属层 → 语言态散落在 L4 文件存储 + L7 每次 build 现读，属 §0 铁律 8「状态机归属」缺口。

---

## [2026-11-17 09:53] ## <视角 C2> · lib/surface/app_root.dart:63-73 + lib/surface/l10n/s.dart:22-37 · <P0> · <MaterialApp 未绑定 locale：无 supportedLocales/localizationsDelegates/locale，语言变更无任何刷新触发源>
证据：
```
lib/surface/app_root.dart:63      builder: (context, mode, _) => MaterialApp(
lib/surface/app_root.dart:64        title: 'TiernanMusicNext',
lib/surface/app_root.dart:67        theme: Sp.theme(dark: false),
lib/surface/app_root.dart:70        themeMode: switch (mode) { 1 => ThemeMode.light, _ => ThemeMode.dark },
lib/surface/app_root.dart:73        home: const AppShell(),
```
`rg -n 'supportedLocales|localizationsDelegates|locale:' lib` → **零命中**。
`lib/surface/l10n/s.dart:30-36`：
```
static S of(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  final saved = TnStrings.loadLocale();
  return S._(saved.isNotEmpty ? TnStrings.forCode(saved) : _fromLocale(locale));
}
```
问题：MaterialApp 既不声明 `supportedLocales`，也不声明 `localizationsDelegates`，更没有 `locale:` 注入——`Localizations.maybeLocaleOf(context)` 拿到的是**平台 locale**，应用自身的持久化语言从不进入 Flutter 的本地化体系；且 `AppRoot` 的 `ValueListenableBuilder` 只监听 `ThemeController`，**没有任何语言变更通知源**（无 `LocaleController`/无 `setState`），因此即使补上语言 UI，改完语言也不会即时刷新，必须重启进程。
建议：① 在 L6 新增 `LocaleController extends ValueNotifier<Locale>`（读 `TnStrings.loadLocale()`，写 `TnStrings.saveLocale()`），`AppRoot` 用 `ValueListenableBuilder<Locale>` 同时驱动 `MaterialApp.locale` + `supportedLocales` + `localizationsDelegates`；② `S.of` 改为读 `Localizations.localeOf(context)`（由 MaterialApp 注入），保证「文案语言」与 Flutter 内建本地化（Tooltip/文本选择菜单/日期选择器）同语言。
76 合规：`app_root.dart` 同时用了 `Sp.theme()`（L7 静态令牌）与 `ThemeController`（L6）两条主题来源，未违反依赖方向；但语言态在 L7 现读存储、无 L6 归属，属状态不同步风险。

---

## [2026-11-17 09:54] ## <视角 C2> · lib/surface/l10n/s.dart:22-37 + lib/core/l10n/strings.dart:620-630 · <P1> · <S.of 优先级写反：持久化语言优先于 Localizations，而 MaterialApp 从不消费持久化语言 → 语言分裂 + 无清除入口的死结>
证据：`s.dart:34-36` 中 `saved.isNotEmpty ? TnStrings.forCode(saved) : _fromLocale(locale)` —— **saved 优先**；`app_root.dart:63-73` 从不把 saved 注入 MaterialApp。
`strings.dart:622-628`：
```
final v = s.getString(_localeKey) ?? '';
return v.isEmpty || v == 'system' ? '' : normalize(v);
```
问题：两个后果。(a) 一旦 `ui.locale` 被写入（如未来补 UI 或用户手改 settings.json），应用文案是 saved 语言，而 Flutter 内建本地化仍是平台语言 → 同一屏里两种语言；(b) `saveLocale` 没有「清除/跟随系统」路径（`normalize('system')` 虽在 `loadLocale` 里被特殊处理为 ''，但 `saveLocale('system')` 会先被 `normalize` 归一成 `'zh'`——因为 `normalize` 白名单里没有 `'system'`，会 fallback 到 `defaultCode='zh'`）→ 用户无法通过任何调用回到「跟随系统」，只能改文件。
建议：`saveLocale` 对 `'system'`/空串走 `remove(_localeKey)` 分支；`S.of` 改为以 `Localizations.localeOf(context)` 为准（单一事实源），持久化值只用于「首次启动 MaterialApp.locale」。
76 合规：门面在 L7 只做取词、不含业务，符合「L7 只画控件」；但把「语言选择优先级」这类策略写死在门面而非 L6 控制器，属职责错位。

---

## [2026-11-17 09:55] ## <视角 C2> · lib/surface/l10n/s.dart:30-46 + lib/core/l10n/strings.dart:612,622 · <P2> · <S.of 每次调用都落磁盘：shared()→fileIn→existsSync；门面顶层 tr() 零调用者>
证据：`strings.dart:622` 每次 `loadLocale()` 都 `KeyValueSettings.shared(StoragePaths.I)` → `paths.fileIn('db','settings.json')` → `resolveSub('db')` → `_ensureDir` → `existsSync()`（`paths.dart:64-73`）。
`rg -n '\btr\(' lib` → `lib/surface/l10n/s.dart:43` 定义、`:44-46` 实现，**无任何调用者**（死代码）。
问题：每次 `S.of(context)` 至少一次同步文件系统调用（虽被 `_loaded` 缓存挡住 JSON 解析，但路径解析与 existsSync 仍发生），在列表滚动/重建密集处有 I/O 抖动；顶层 `tr()` 是阶段 A 留下的未接死口。
建议：把语言码缓存在 L6 `LocaleController` 的 `ValueNotifier` 里，`S.of` 只读内存；删除或接入 `tr()`。
76 合规：合规（无越级、无反向依赖）。

---

## [2026-11-17 09:56] ## <视角 C2> · lib/surface/app_root.dart:70 + lib/session/theme_controller.dart:31-44 · <P1> · <设置页「跟随系统」主题档位实际映射为暗色：mode 0 与 mode 3 都落 ThemeMode.dark>
证据：
```
lib/surface/app_root.dart:70        themeMode: switch (mode) {
lib/surface/app_root.dart:71          1 => ThemeMode.light,
lib/surface/app_root.dart:72          _ => ThemeMode.dark,
lib/surface/app_root.dart:73        },
```
`settings_page.dart:196-205` 的分段按钮：`ButtonSegment<int>(value: 0, label: Text('跟随系统'))`、`value:1 亮`、`value:2 暗`、`value:3 纯黑`。
`theme_controller.dart:16-19` 注释明确档位语义「0 系统 / 1 亮 / 2 暗 / 3 纯黑」。
问题：选「跟随系统」(0) → `ThemeMode.dark`，界面**不跟随系统**，且已持久化（`setMode` 写 `ui.themeMode`），重启仍错；选「纯黑」(3) 同样只是暗色板（源码 TODO 已承认）。用户看到「跟随系统」却得不到跟随系统的效果。
建议：`themeMode` 改为 `switch (mode) { 1 => light, 2 => dark, 3 => dark, _ => ThemeMode.system }`，并单独为纯黑补一套更深色板或先隐藏该档位。
76 合规：合规（ThemeController 在 L6、L7 只订阅）。

---

## [2026-11-17 09:57] ## <视角 C2> · lib/surface/pages/settings_page.dart:137-149 + lib/core/cache/cache_service.dart:155-162 · <P1> · <「清理缓存」只清 in-flight 请求合并表，不清任何缓存/文件，用户预期落空>
证据：
```
lib/surface/pages/settings_page.dart:137  void _clearCache() {
lib/surface/pages/settings_page.dart:143    cache.invalidateSession();
lib/surface/pages/settings_page.dart:144    _toast('已清理会话缓存');
lib/core/cache/cache_service.dart:155  void invalidateSession() {
lib/core/cache/cache_service.dart:157    _client.clearInflight();
```
`cache_service.dart:13-14` 注释自述：「清客户端 in-flight 等待表……磁盘键自带 uid 维度，不越权清磁盘」。
问题：按钮标题「清理缓存」、Toast「已清理会话缓存」，实际只清了去重表；L2 磁盘缓存（`ResourceCache`，`lib/core/storage/resource_cache.dart`）与下载/歌词等缓存目录**一个字节都没清**。用户点完没有任何可感知变化（除偶发重复请求），是典型的「按了没用」。
建议：要么把 L4 的磁盘缓存清理能力经 bridge_core 暴露（按 namespace/目录），要么把文案改成「重置请求队列」并明示不删磁盘文件，避免误导。
76 合规：设置页只经 `appGraph.cache` 调 L4 门面，调用链合规；缺的是能力本身未过桥。

---

## [2026-11-17 09:58] ## <视角 C2> · lib/session/playback_session.dart:378-397 + lib/session/bootstrap.dart:229 + lib/surface/pages/settings_page.dart:96-134,224-243 · <P1> · <音质/倍速设置不落盘：重启即回到 128/1.0；设置页音质副标题恒显示「128（标准）」与实际不同步>
证据：
```
lib/session/playback_session.dart:378  void setSpeed(double v) { _engine.setSpeed(v); _emit(playbackReducer(_player, SetSpeed(v))); }
lib/session/playback_session.dart:387  void setQuality(String q) { ... _quality = q; ... }   // 无任何 settings 写入
lib/session/bootstrap.dart:229        quality: settings.getString('preferred_quality') ?? '128',
```
`rg -n "preferred_quality" lib` → **只有 bootstrap 这一处读，全仓零写入**。
`settings_page.dart:224-231`：音质 ListTile 的 subtitle 是**常量** `Text('128（标准）')`（非 session 实际值），而倍速 subtitle 读的是 `session.snapshot.speed`（:238-240）。
问题：(a) 用户在设置页选 flac/2.0x，重启后分别回到 128 / 1.0x，设置项形同虚设；(b) 音质行显示的档位是硬编码字符串，与播放会话实际 `_quality` 永不同步（当前恰好都是 128 才没暴露）。
建议：`setQuality`/`setSpeed` 落盘到 settings（`preferred_quality` / `ui.speed`），并让设置页音质副标题读 `session.snapshot.quality`。
76 合规：合规。

---

## [2026-11-17 09:59] ## <视角 C2> · lib/surface/pages/settings_page.dart:100-124 + lib/logic/player/playback_service.dart:146-176 + lib/core/net/endpoints/quality_endpoints.dart:52-62 · <P1> · <设置页音质弹层对匿名用户无条件暴露 9 档 VIP 档位，而 L5 权益判定恒匿名 → 选 flac/super 必然播放失败>
证据：
```
lib/surface/pages/settings_page.dart:107            for (final AudioQuality q in vipQualities())
lib/surface/pages/settings_page.dart:112                  playbackSession().setQuality(qualityParam(q));
lib/core/net/endpoints/quality_endpoints.dart:52  List<AudioQuality> vipQualities() => [q128,q320,flac,high,qSuper,viperAtmos,viperTape,viperClear,multitrack];
lib/logic/player/playback_service.dart:146  bool get _hasRights { ... s['vip_token'] ... }
lib/logic/player/playback_service.dart:173  final start = _hasRights ? 0 : _ladder.indexOf(prefer);
```
`bootstrap.dart:118-128` 构造 `PlaybackService` 时以 **Map 快照**注入 `vip_token/vip_type`（B1 X1 已报，同一根因）。
问题：设置页不判登录态/VIP 态就摆出全部 9 档（含 flac/high/super/蝰蛇/多轨）；匿名用户选 flac 时 `_hasRights=false` → 候选链从 flac 起步（`indexOf(prefer)`）→ 请求必被服务端拒 → 播放报错，而 UI 不给任何「需会员」提示；`quality_policy.dart` 的降级策略只被死代码 `play_resolver.dart` 引用，真实播放路径根本没有策略层。
建议：设置页音质弹层按登录/权益态过滤档位（权益态由 L6 暴露，不能由 L7 自己判 settings），或至少在选择时提示「该档位需会员」；把 `quality_policy` 接入 `PlaybackService.resolvePlaySource`。
76 合规：合规（L7 只调 bridge_core 的纯数据 + bridge_session 的 session 方法）。

---

## [2026-11-17 10:00] ## <视角 C2> · lib/surface/shell.dart:84-93 + lib/surface/pages/player_page.dart:203-219 + lib/session/nav_state.dart:90-96 · <P1> · <导航 requestTab('lyrics') / ('comment') 恒无效：shell 只在「有 navEntry 的模块表」里查下标，非导航模块必然 index=-1 静默失败>
证据：
```
lib/surface/shell.dart:84    final modules = _modules;          // = active().where((m) => m.navEntry != null)
lib/surface/shell.dart:87    final i = modules.indexWhere((m) => m.id == req);
lib/surface/shell.dart:88    if (i >= 0 && mounted) setState(() => _index = i);
lib/surface/pages/player_page.dart:206      navState().requestTab('lyrics');
lib/surface/pages/player_page.dart:217      navState().requestTab('comment');
```
`player_page.dart:511` `navEntry => null`（player）、`lyrics_page.dart:279` `navEntry => null`（lyrics）、`mv_page.dart:29` `navEntry => null`（mv）。
问题：播放页 ⋮ 菜单里「歌词」「评论」两项调用 `requestTab` 后**没有任何 UI 反应**——`lyrics` 不在 nav 模块表（index=-1，请求被丢弃且 `clearTabRequest()` 已执行）；`comment` 更彻底：全仓只有 `bootstrap.dart` 的 `_PlaceholderModule('comment')`（`enabled=false`），**没有任何真实评论页**，B1/B2 提到的评论能力在 L7 根本没有出口。用户在播放页点「歌词」「评论」= 静默无响应。
建议：`requestTab` 语义应扩展为「打开模块」而非「切底栏」——shell 收到非导航模块 id 时用 `Navigator.push` 打开该模块页面（并为 comment 补真实页面或先隐藏该菜单项）；`NavState` 增 `openModule()` 事件。
76 合规：状态在 L6、L7 只消费，符合分层；但 L6 的导航事件语义只覆盖「底栏 tab」，L7 却用它做「打开页面」，属跨层契约语义错配。

---

## [2026-11-17 10:01] ## <视角 C2> · lib/logic/catalog/recommend_logic.dart:64-67 + rank_logic.dart:57-59,96-98 + lib/surface/pages/home_page.dart:192-203,228-239,269-280 · <P1> · <跨层错误态坍缩（首页）：L5 catch 后返回空列表 → L7 的 snap.hasError 永不成立 → 3 处 HomeErrorRetry 是死代码，用户只看到「暂无」>
证据：
```
lib/logic/catalog/recommend_logic.dart:64    } catch (e, st) {
lib/logic/catalog/recommend_logic.dart:65      Log.e(_tag, 'daily failed page=$page', e, st);
lib/logic/catalog/recommend_logic.dart:66      return const <SongBrief>[];
lib/logic/catalog/rank_logic.dart:57-59        catch → return const <RankBrief>[];
lib/surface/pages/home_page.dart:197      if (snap.hasError) { ... HomeErrorRetry(message: '每日推荐加载失败', onRetry: _reload) }
lib/surface/pages/home_page.dart:202      if (items.isEmpty) { ... HomeEmptyBox('暂无每日推荐（登录后可能可见）') }
```
问题：L5 把异常吞成空列表，L7 永远收不到 error → 首页「每日推荐/推荐歌单/排行榜」三段的错误分支（HomeErrorRetry + 重试按钮）**永远不可达**；网络失败与真的没内容在 UI 上完全同形（与 B2 X2「搜索错误态坍缩」同根，本次在首页链路复现）。另注 `_reload` 会把三段 Future 全部重建（`setState(_load)`），单段重试牵连全页。
建议：L5 用显式结果类型（`Result<T>{ok,data,error}`）或让异常继续上抛，由 L7 统一分派 error/empty；重试改为按段重建 Future。
76 合规：合规（异常已在 L5 留痕 Log.e）；问题是**错误语义在跨层接缝被降级**，不属越级。

---

## [2026-11-17 10:02] ## <视角 C2> · lib/surface/pages/search_page.dart:436-443 + lib/logic/catalog/search_logic.dart:63 + lib/surface/pages/search_tile_widgets.dart · <P1> · <搜索页错误态同样依赖 snap.hasError，而 L5 缓存/异常语义使失败被固化为空结果（与 B2 X1/X2 同根，B7 复核确认）>
证据：`search_page.dart:436-441` 仅在 `snap.hasError` 时渲染 `SearchErrorRetry`；`search_logic.dart:63` 无条件 `_cache.put(key,res)`（阶段 A 修复遗漏面，B2 X1）；B2 已报 L5 把 `LoginRequired` 等状态降级为 List、L7 吞成同一句空态。
问题：B7 复核确认：**搜索页的「搜索失败 + 重试」在真实链路下基本不可达**——失败被 L5 缓存固化或降级为空列表，用户看到的是「没有找到与「x」相关的歌曲」，重试按钮永不出现（阶段 A 的「只缓存成功」修复没有覆盖 search/search_typed 两个 logic）。
建议：同 P1-10；两处 logic 的 `put` 改为仅成功且非空时写入，失败抛错或返回带状态的结果。
76 合规：合规。

---

## [2026-11-17 10:03] ## <视角 C2> · lib/surface/pages/settings_page.dart:74-83 + lib/logic/auth/auth_logic.dart:386-412 + lib/session/nav_state.dart:60-67 · <P2> · <登出链路正确但不完整：忽略 logout() 失败返回值、auth 缺失时静默、登出后播放会话/收藏镜像不复位>
证据：
```
lib/surface/pages/settings_page.dart:74   void _logout() {
lib/surface/pages/settings_page.dart:76     final AuthLogic? auth = appGraph.auth;
lib/surface/pages/settings_page.dart:77     if (auth == null) return;              // 静默
lib/surface/pages/settings_page.dart:79     auth.logout();                          // 返回 bool 被丢弃
lib/surface/pages/settings_page.dart:81     appGraph.cache?.invalidateSession();
lib/surface/pages/settings_page.dart:86     navState().bumpAuth();
lib/logic/auth/auth_logic.dart:387  bool logout() { ... return ok; }   // settings 清除结果
```
问题：(a) 凭据清理本身**正确**（清 token/userid/mid/dfid/kugou_api_mid/cookie/vip_token/vip_type/t1，且用 `&` 不短路，全部执行）；但返回值被丢弃，写盘失败时用户仍看到「已登出」界面；(b) `auth == null` 时点击「登出」毫无反馈；(c) 登出**未复位播放会话**（队列/当前播放继续以旧 URL 播放），也未触发 `collect.resetLocalMirror`（B5 X2 换号/登出收藏串号同根）。
建议：检查 `logout()` 返回值，失败弹 Snackbar；登出后调用播放会话复位 + 收藏镜像复位（需 L6 装配该回调）。
76 合规：合规。

---

## [2026-11-17 10:04] ## <视角 C2> · lib/surface/pages/settings_page.dart:38-50,63-72 + lib/session/nav_state.dart:15-58 · <P2> · <登录态广播粒度过粗：NavState 任何通知（含 setAlbum/setArtist/requestTab）都会触发设置页重读账号并 setState>
证据：
```
lib/surface/pages/settings_page.dart:39    navState().addListener(_onAuthChanged);
lib/surface/pages/settings_page.dart:45   void _onAuthChanged() { _loadAccount(); }
lib/session/nav_state.dart:52-57            void setAlbum(String id) { _albumId = id; _notify(); }
lib/session/nav_state.dart:90-96            void requestTab(String moduleId) { _tabRequest = moduleId; _notify(); }
```
问题：`NavState._notify()` 不区分事件类型，设置页在「切专辑」「切歌手」「请求切 tab」时都会跑一次 `await account.activeAccount()` + `setState`（设置页 = 底部常驻页面，命中频率高）；同时 `authVersion` 字段实际无人读（`rg 'authVersion'` 仅定义与自增，无消费者），「登录态版本号」这一设计未落地。
建议：NavState 拆分为 `authChanged` / `navigation` 两类事件（或提供 `authVersion` 供 `ValueListenable` 式订阅），设置页只订阅登录态事件。
76 合规：合规。

---

## [2026-11-17 10:05] ## <视角 C2> · lib/session/nav_state.dart:90-101 + lib/surface/shell.dart:76-95 · <P2> · <导航请求可被静默吞掉：shell 未挂载时写入的 tabRequest 不会在挂载后重放>
证据：`nav_state.dart:96-101` `requestTab` 写 `_tabRequest` 后 `_notify()`；`shell.dart:76-95` 只有在**收到通知时**才消费 `tabRequest`；`shell.dart:88` 消费后立即 `clearTabRequest()`。
问题：若 `requestTab` 在 shell 尚未 build/dispose 期间发生（例如启动即请求切页、或页面重建中），请求写进了 `_tabRequest` 但没有触发者，shell 挂载后不会重放 → 一次导航被静默丢弃；同理 `clearTabRequest()` 不广播，状态残留无感知。
建议：shell `initState` 时主动消费一次 `NavState.instance.tabRequest`（pending 语义），或 NavState 改为「事件队列 + 消费确认」模型。
76 合规：合规。

---

## [2026-11-17 10:06] ## <视角 C2> · 全仓 i18n 接线精确统计 · <P1> · <阶段 A i18n 门禁虚假绿灯：门禁只做 'ui.locale' 字符串存在性检查，不校验写入者/消费者/覆盖率>
证据：`tool/feature_reachability_test.dart:224-226`
```
  check(
    'locale persisted',
    has(read('lib/core/l10n/strings.dart'), 'ui.locale'),
  );
```
精确统计（本次实测）：
- `S.of(` 真实调用点 **19 处**：`ykg_sheet.dart` 11、`player_page.dart` 6、`login_sheet.dart` 2（另有 `s.t(...)` 局部变量形式 27 处，含 ykg_sheet 17 / login_sheet 7 / player_page 6）。
- 56 键目录中**仅 22 个 key 被引用，34 个死键**（含 `search/playlist/library/settings/login/logout/theme/cache/about/empty/retry/errorNetwork/errorTimeout/errorParse/errorServer/needVerification/needVip/noPlayable/mvEmpty/mvNoSong/mvLoadingFail/ykgSourceTag/ykgValidUntil/play/pause/next/prev/player/lyrics/mv/comments/download/favorite/appTitle`）。
- `lib/surface` 中**含中文字符串字面量 196 行**（全仓 356 行）；阶段 A 记录的「119 处」为不同计数口径（去重前的字符串条数 vs 含中文字符串行数），两者不冲突但需统一口径再进 CI。
- `lib/core/l10n/strings.dart` 目录：10 语 × 56 键，与 `lib/l10n/app_*.arb` **真实键集完全一致**（各 56 个非 `@` 键）；差异仅在元数据：仅 `app_zh.arb` 带 `@appTitle` 描述键（故文件总键数 58 vs en/zh_Hant 的 57）。
问题：门禁只看源码里有没有 `'ui.locale'` 这个字符串就算「locale persisted」通过 → 一个**零写入者、零语言 UI** 的 i18n 依然全绿；覆盖率（19/196、22/56）无任何门禁。
建议：门禁改为可执行断言：① `saveLocale` 至少 1 个非测试调用者；② `MaterialApp` 存在 `locale:`/`supportedLocales`；③ `S.of(` 调用点数 ≥ 阈值或「L7 中文字符串行数 ≤ N」的收敛曲线；④ arb 真实键集一致（去掉 `@` 元数据后比较）。
76 合规：门禁形同虚设属 §0 门禁纪律违规（门禁必须能失败）。

---

## [2026-11-17 10:07] ## <视角 C2> · lib/surface/pages/library_page.dart:245-252 + lib/surface/pages/home_state_views.dart:62-74 + lib/surface/pages/search_tile_widgets.dart + lib/surface/design/components.dart:232-268 · <P2> · <三态组件四套并存、且「重试」文案硬编码；错误态把原始异常串直接抛给用户>
证据：
```
lib/surface/pages/library_page.dart:245        return SpStateView(
lib/surface/pages/library_page.dart:248          title: '加载失败',
lib/surface/pages/library_page.dart:249          subtitle: '${snap.error}',
lib/surface/pages/library_page.dart:250          actionLabel: '重试',
lib/surface/pages/home_state_views.dart:71        child: const Text('重试', ...)
lib/surface/design/components.dart:232      class SpStateView { ... }        // 空/错/受限 三态统一
```
并存四套：① `components.dart:SpStateView`（空/错/受限）；② `home_state_views.dart:HomeSkeletonBox/HomeEmptyBox/HomeErrorRetry`；③ `search_tile_widgets.dart:SearchEmptyBox/SearchErrorRetry`；④ 各页内联 `SpStateView`（mv/lyrics/player/library 共 15+ 处）。
问题：(a) 「重试」「加载失败」「暂无内容」等全部硬编码中文，**恰好是 56 键目录里已有的 `retry`/`empty`/`errorGeneric` 键**——i18n 目录已备好文案却零使用；(b) `library_page.dart:249` 把 `snap.error` 原始异常文本（如 `Exception: ...`）直接展示给用户，属内部信息外泄 + 文案不统一。
建议：收敛为单一 `SpStateView`（含 retry/empty/error/limited 四态），文案统一走 `S.of(context).t('retry'|'empty'|'errorGeneric')`；错误详情只进日志，UI 显示归一化文案。
76 合规：合规（均为 L7 组件），问题在一致性与文案治理。

---

## [2026-11-17 10:08] ## <视角 C2> · lib/surface/pages/settings_page.dart:320 + lib/surface/pages/home_page.dart:24 + search_page.dart:24 + playlist_page.dart:21 + library_page.dart:342 · <P2> · <底部导航标签全部硬编码中文，且文案放在 L6 契约里；56 键目录已有对应键却未用>
证据：`NavEntry? get navEntry => const NavEntry('设置', 'settings', navOrder: 4);`（settings_page.dart:320）；同型：`'首页'`、`'搜索'`、`'歌单'`、`'音乐库'`；`lib/session/contracts.dart:5-12` `class NavEntry { final String label; ... }`。
问题：导航栏 5 个标签是用户最显眼的文案，却零 i18n；目录中 `search/playlist/library/settings` 键已存在却未接线；且 `NavEntry.label` 位于 L6 契约，导致「UI 文案」这一层职责下沉到 L6（与 L4 i18n 单一事实源脱节）。
建议：`NavEntry` 只带 `labelKey`（如 `'settings'`），L7 渲染时 `S.of(context).t(labelKey)`；或导航标签由 L7 模块自持 key。
76 合规：L6 契约携带 UI 文案属职责错位（文案事实源应在 L4 arb）。

---

## [2026-11-17 10:09] ## <视角 C2> · lib/surface/shell.dart:107-118,136-140 + lib/session/module_registry.dart:37-58 · <P2> · <shell 兜底文案硬编码 + 底栏索引按位置而非按 id，切页后位置漂移风险>
证据：
```
lib/surface/shell.dart:114        body: Center(child: Text('无可用模块', ...)),
lib/surface/shell.dart:132            (current.builder as WidgetBuilder?)?.call(context) ?? const Center(child: Text('模块未提供页面')),
lib/surface/shell.dart:100    final safeIndex = _index.clamp(0, modules.length - 1);
lib/surface/shell.dart:131        onDestinationSelected: (i) => setState(() => _index = i),
```
问题：(a) 两处兜底文案硬编码且未走 S.of；(b) 选中态用**位置下标** `_index` 表示，模块表由 `ModuleRegistry.active()` 动态排序（navOrder → id 字典序）生成——一旦某个模块 enabled 状态变化或安装顺序变化，`_index` 会指向另一个模块（选中态与内容错位）；(c) 底栏当前页不持久化，重启永远回第 1 页。
建议：改用 `String _currentId` 表示当前模块，渲染与底栏都按 id 匹配；兜底文案接 i18n。
76 合规：合规。

---

## 本视角结论

B7 的「实现正确性」判定：**阶段 A 的 i18n 接线在写入侧完全没有闭环，在运行时也没有生效路径。**

1. **i18n 取词链断在两处（最高优先级）**：`TnStrings.saveLocale` 全仓零调用者（设置页无语言 UI）+ `MaterialApp` 未声明 `locale/supportedLocales/localizationsDelegates` 且无语言变更通知源 → 「切语言」既无入口、切了也不会即时刷新，用户必须重启进程才可能看到变化；阶段 A 门禁只检查 `'ui.locale'` 字符串存在性 → 虚假绿灯。
2. **接线覆盖率极低且统计口径需统一**：`S.of` 真实调用点 19 处（全在 ykg_sheet / player_page / login_sheet 三个页面），56 键只用 22 个（34 键死，包括 `retry`/`empty`/全部错误分类/全部导航标签），`lib/surface` 仍有 196 行含中文的字符串字面量——用户「文案没改」在 B7 得到最终定位：**不是翻译没做，是接线没做**（10 语 × 56 键的 arb 与 strings.dart 键集经核对完全一致、翻译数据本身没问题）。
3. **设置页四项功能全部有缺陷**：主题「跟随系统」实际映射为暗色（P1）；「清理缓存」只清 in-flight 去重表（P1）；音质/倍速不落盘、重启丢失且音质行显示恒定字符串（P1）；音质弹层对匿名用户暴露 9 档 VIP 档位而 L5 权益判定恒匿名（B1 X1 同根，选 flac 必失败，P1）；登出本身清凭据正确，但忽略失败返回值、auth 缺失时静默、登出不复位播放会话与收藏镜像（P2）。
4. **导航有真实死路**：播放页「歌词」「评论」用 `requestTab` 打开非导航模块，shell 只在带 navEntry 的模块表查下标 → index=-1 静默失败；`comment` 全仓无真实页面；导航请求在 shell 未挂载时会被静默丢弃。
5. **错误空态三态在跨层接缝被降级**：L5（recommend/rank/playlist/search）把异常吞成空列表或缓存固化 → L7 的 `snap.hasError` 分支永不成立，首页 3 处 `HomeErrorRetry`、搜索页 `SearchErrorRetry` 均为死代码（与 B2 X1/X2 同根，B7 在首页链路复现）；三态组件四套并存、且恰好已有 i18n 键的「重试/暂无」文案仍全部硬编码；library 错误态把原始异常串直接展示给用户。
6. **存储层双实例隐患本次未复现**：`KeyValueSettings.shared(StoragePaths.I)` 与 bootloader 的 `new KeyValueSettings(paths)` 因「构造器自注册 + 以 settings.json 绝对路径为键」确实命中同一实例（`settings_store.dart:25-38` + `bootloader.dart:132`），故 `ui.locale` 一旦有写入者即可持久化——**问题不在存储，在没有写入者**。

定级合计（本视角新增）：**P0×2、P1×9、P2×7**（其中「切语言不生效/无入口」为用户「文案没改」的直接根因）。

## 未覆盖

- 未逐行审 `mv_page.dart` / `lyrics_page.dart` / `playlist_page.dart` 的完整业务分支（仅审了三态分支与 i18n/文案相关片段）。
- 未审 `lib/l10n/*.arb` 译文质量与其余 7 语英文占位的用户可见性（C3 已覆盖）。
- 未审 `tool/gen_i18n.py` 生成逻辑与 `lib/core/l10n/strings.dart` 的**逐值**一致性（仅核对键集与抽样若干值）。
- 未审 CI 管线 `i18n_translate.yml` 是否真的会回写 arb。
- 未做运行时实测（按纪律禁止跑 dart/flutter/analyze/test）：语言切换刷新、`requestTab('lyrics')` 无反应、设置页音质失败等均为**静态代码路径推导**，建议主会话在 CI 上补一条 widget 测试固化。
- 未审 B6 主题层（`tn_theme.dart` / `tokens.dart`）的取色链与 `Sp.*` 静态令牌问题。
- 未审 L4 arb 之外的 i18n 资源（如 `docs/I18N.md` 描述的其它键集）。

## 76 合规小结

- **合规项**：L4 `core/l10n/strings.dart` 零 flutter 依赖（自研轻量 i18n，core 不依赖 UI SDK）；`lib/surface/l10n/s.dart` 门面位于 L7 且只做取词、不含业务；L6 `nav_state.dart` 状态在 L6、L7 `shell.dart` 只消费（未把状态机写进 Widget）；`bootstrap.dart` 未越层直连 L4 具体端点；设置页调凭据/缓存均经 `bridge_session`/`bridge_core` 门面；所有本报告涉及文件均无超 1500 行、无反向 import。
- **违规/风险项**：① **i18n 状态无归属层**——语言偏好既不在 L6（有 controller）、也不在 L7（有控件），而是「L4 文件 + L7 每次 build 现读」，违反「状态机归属 L5/L6」铁律；② **L6 契约 `NavEntry.label` 携带 UI 文案**，文案事实源（L4 arb）与使用地（L7）被 L6 隔断，属职责错位；③ **L7 硬编码文案 196 行**使 L4 arb 成为事实上的旁路资源（单一事实源失效）；④ **门禁只做字符串存在性检查**（`'ui.locale'`），无法失败 → 门禁纪律违规；⑤ 「跟随系统」档位与 L6 `ThemeController` 的档位契约不一致（L6 声明 0=系统，映射到 L7 变成暗色），属跨层契约被单点实现违反。
