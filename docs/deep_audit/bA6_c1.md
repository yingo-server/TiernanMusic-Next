# A6 批 · C1 架构合规视角 · 深度审查（只读，不改源码）

> 审查对象：lib/session/ 8 文件 + lib/bridges/ 6 文件（共 14 文件 1866 行，均已完整读取）。
> 依据：docs/DEEP_AUDIT_14_BATCH_PLAN.md §0/§2、docs/SEVEN_SIX_RULE.md §0 及 §1~§4。
> 时间戳：2026-11-16（本轮审查）。

## C1 · lib/init/main.dart:18 · P0 · 越级跨层（桥相邻关系破坏）
证据：main.dart:18 `import '../bridges/bridge_surface.dart' show SurfaceDeps, bootstrapApp, installServices, spLightThemeData;`；main.dart:112 `bootstrapApp(outcome.dep('__raw'));`。bridge_surface.dart:1 注释自称「L6 session ↔ L7 surface / L1 装配入口」，:24 installServices 先调 `session.bootstrapSession` 再调 `root.installServices`，:48 bootstrapApp 直转 surface。L1 经此桥跨过 L2~L6 五层直达 L7，且把 L2 原始结果 `__raw` 透传给 L7（dynamic duck typing）。
问题：A1 已发现「main 直连 bridge_surface 跨 5 层」仍在；bridge_surface 同时承担 L1→L6→L7 三跨层职责，违反相邻层唯一通道。
建议：L1 只经 bridge_boot 取 BootOutcome，经 bridge_session 的装配入口触发 bootstrapSession；由 L2 bootloader 或 L6 session 调用 L7 装配，bridge_surface 回归仅 L6↔L7，禁 main import。
76 合规：违反第1、4条（跨层仅经相邻桥、每层只依赖下层门面）。

## C1 · lib/bridges/bridge_boot.dart:5-7 · P1 · 桥职责越界 / 相邻关系（A1 遗留）
证据：bridge_boot.dart:5 `import '../kernel/kernel.dart' as k;`、:7 `export '../kernel/kernel.dart' show Kernel, KernelContext, Log;`、:11-18 BootBridge.assemble() 直接 `k.Kernel.assemble()`。bridge_kernel.dart:51 另有 assembleKernel()，全仓 `rg assembleKernel` 仅定义处一处、零调用。
问题：A1 已发现「bridge_boot re-export kernel 致 bridge_kernel 名存实亡」仍未修；bridge_boot(L1↔L2) 越级暴露 L3 kernel 门面，bridge_kernel(L2↔L3) 实际被绕开。
建议：移除 bridge_boot 的 kernel import/export 与 BootBridge.assemble，L2 需 kernel 能力一律经 bridge_kernel.assembleKernel/logD/logW/logE。
76 合规：违反第1、4条（桥按相邻层暴露门面、禁反依赖/越级）。

## C1 · lib/session/bootstrap.dart:220-229, 266-275 · P0 · 模块注册表占位抢占（A1 遗留，session 侧可修）
证据：bootstrap.dart:220 `const moduleIds = <String>['home','search','playlist','library','settings','player','lyrics','comment','mv','album','artist']`；:226-227 `for (final id in moduleIds) ModuleRegistry.instance.install(_PlaceholderModule(id));`；:267-275 `_PlaceholderModule extends SurfaceModule { enabled => false; }`。module_registry.dart:15-19 `install` 对重复 id 直接覆盖。mv_page.dart:14-16 `registerMvModule(){ if (reg.byId('mv') != null) return; reg.install(MvPageModule()); }` —— 因 session 已装入 id='mv' 占位，守卫恒真提前返回，真实 MV 模块永不注册。shell.dart:23-29 各页面模块在 root.installServices 中按 id 覆盖占位，但 MV 页不在其中（navEntry=null，靠播放页菜单触发注册），故独独 MV 被卡死。
问题：占位模块抢占 id 致真实 MV 模块永不注册，用户点名「MV 用不了」的架构根因之一；且 php 其余页面依赖「后装覆盖」的时序约定，无幂等保护/依赖检查。
建议：session 侧修——bootstrap 不再 install 占位模块（模块注册表应保持空，由 L7 按需 install），或为占位加 `isPlaceholder` 标记并在 install 时允许真实模块无条件覆盖、registerMvModule 守卫改为「占位可覆盖」；同时 AppGraph.modules 保留 id 清单供导航渲染，不与占位注册耦合。
76 合规：违反第5条（L6 模块经 session 注册表热插拔）——热插拔语义被占位抢占破坏。

## C1 · lib/session/playback_session.dart:64-79, 86, 116-262 · P0 · L6 职责越界（状态机/编排归属冲突）
证据：playback_session.dart:6 `import 'package:flutter/foundation.dart' show ChangeNotifier`；:64 `class PlaybackSession extends ChangeNotifier`；:69-79 持有 `_queue`(QueueState)/`_player`(PlayerState)/`_mvTriedOnce`/`_sourceKind`；:116-262 `_onEngineEvent` 把 AudioEvent 翻译为 L5 `playbackReducer(_player, ...)` 并在多个方法内直接调用 reducer（:122,:126,:130,:134,:138,:176,:188,:213 等）；:190-262 `_start` 执行 resolve→引擎 play→历史 recordPlay→通知栏 updateMetadata 全链编排。SEVEN_SIX_RULE.md §1 明确「L5 状态机数据（queue_state/player_state/reducer 保留在 L5）」、§4「L6 播放页只 ref.watch 快照 + 发意图，零状态机」；DEEP_AUDIT_PLAN §0-8「播放控制/队列/reducer 应在 L5，不在 L6；L6 只暴露状态/回调」。
问题：L6 直接持有并驱动 L5 状态机（reducer 调用点 ≥10 处）与队列变更方法（next/removeAt/insertNext/setMode 等），是任务书明令禁止的「越界持有状态机」；不过从 SEVEN_SIX_RULE §4「播放编排属 session/playback_session」看，编排位置本身合法，冲突集中在 reducer/队列状态机的持有与调用。
建议：把 reducer 调用与队列变换下沉回 L5（新增 PlaybackCoordinator 或扩展 PlaybackService.apply(action)），L6 只保留 `_queue/_player` 的只读快照缓存、意图转发与编排顺序，reducer 结果由 L5 回吐；或主会话裁决 §0-8 与 §4 的口径冲突后统一。
76 合规：违反第8条（播放控制/播放列表/reducer 不得放进 L6）与 SEVEN_SIX_RULE §4「L7 零状态机」的上游约束。

## C1 · lib/session/bootstrap.dart:198-219 · P1 · 预读执行越界（写入权归属）
证据：bootstrap.dart:205 `final cacheService = CacheService(client);`；:206-208 `PlaybackSession.instance.onQueueChanged = (hashes) { Log.d(... 'cache keeps LRU warm'); };`；:210-219 `cacheService.prefetch(<({Endpoint ep, Map<String,Object?> params})>[ (ep: EndpointRegistry.searchHot, params: {'navid':1,'plat':2}), (ep: EndpointRegistry.rankList, params: {}) ]);`。SEVEN_SIX_RULE.md §3：「预读触发（队列 upcoming 窗口）由 session 决定『预测哪些键』，但不执行写入；执行权在 L4 CacheService」。DEEP_AUDIT_PLAN §0-8：「预测哪些键可在 L6，但不执行写入（写入权在 L4 CacheService）」。
问题：L6 在装配期直接调用 `cacheService.prefetch(...)` 执行确定性写入（热搜/榜单），属 L4 写入执行动作出现在 L6；`onQueueChanged` 回调只打日志、不真正驱动 upcoming 预读，预读策略名存实亡。
建议：把「预热哪些键」表达为策略/键清单交给 L4 CacheService.prefetchPolicy（由 L4 启动时自行写入），L6 只调用 `cacheService.prefetch(keys)` 式的意图接口或在装配期由 bridge_core 注册策略；队列回调改为向 CacheService 报送 upcoming keys 由 L4 决定写入。
76 合规：违反第8条（预读/缓存不得放进 L6）与 §3 写入权在 L4 的裁定。

## C1 · lib/session/auth_session.dart:4, 50-56, 72-82 vs nav_state.dart:60-66 · P1 · 功能断点（登录态通知双轨）
证据：auth_session.dart:4「批2-F2 的 NavState.bumpAuth 未落盘…本类不臆造监听机制」、:52-53 TODO 注释「NavState.bumpAuth 落盘后改为监听…当前仅本地注册，无触发源」；但 nav_state.dart:60-66 `bumpAuth()` 实际已落盘（自增 authVersion + _notify + Log）。rg 全仓 bumpAuth 调用方：settings_page.dart:81、login_sheet.dart:79/95 —— 均只调 navState().bumpAuth()，无人调 AuthSession.notifyAuthChanged()，也无 onAuthChanged 订阅者（只有定义）。
问题：两边注释与实现错位：L6 AuthSession.onAuthChanged 的监听注册表永不触发（notifyAuthChanged 零调用、onAuthChanged 零订阅），而真实登录广播走 NavState.bumpAuth。L6 自身对外暴露的登录态订阅是死链。
建议：AuthSession 取消自建 _listeners，onAuthChanged 内部转订阅 NavState.instance.addListener，或删除该 API 统一收敛到 NavState.authVersion；同步修正陈旧 TODO 注释。
76 合规：不直接违反 76 条，但违反 L6「对外暴露状态/回调」的门面有效性。

## C1 · lib/bridges/bridge_core.dart:1-178 / bridge_logic.dart:1-145 · P1 · 桥无 try/catch+Log（纯 export 桥 vs 铁律 2 冲突）
证据：bridge_core.dart:1-4「本文件只 export，不写任何逻辑；上层禁直接 import core 内部模块」，全文件 178 行均为 `export '../core/...'`（如 :39, :51, :55, :141），零函数、零 try/catch。bridge_logic.dart:1-4「本文件只 export…跨层调用的 try/catch+Log 留痕由调用方负责」，:10-126 全部 export，唯一函数 LogicFacade.playbackSummary(:134-143) 的 try/catch 内恒返回 'idle' 占位。对照 bridge_boot/kernel/session/surface 每个桥函数均有 try/catch+Log。
问题：§0 铁律 2「每个桥函数 try/catch 捕获，失败必 Log 留痕」在两座 export-only 桥上规则不可适用/未落实（export 语句无运行期失败点）；bridge_logic 把日志责任外推给「surface 层」，与「桥承担日志系统任务」相悖；LogicFacade.playbackSummary 是零调用占位，违反不写占位逻辑的精神。
建议：主会话明确铁律 2 的适用口径（export-only 桥视为透明门面、调用方留痕），或在两桥补一个统一 `call`/`guarded` 包装供上层调用；删除 LogicFacade.playbackSummary 占位方法。
76 合规：形式上违反第2条（桥函数 try/catch+Log），需规则澄清。

## C1 · lib/bridges/bridge_boot.dart:1, 106-109 · P2 · 桥内非受控函数（bootFailure 无 try/catch）
证据：bridge_boot.dart:106-109 `Map<String,Object?> bootFailure(String reason, Object? error) => <String,Object?>{...}` 为表达式体公开函数，无 try/catch、无 Log；被调用处 :99,:136,:181 均在调用方 catch 内，但自身作为公开桥 API 无留痕。另 bridge_boot.dart:5-7 沿用「五桥」旧注释（bridge_kernel.dart:1 亦为「五桥」），与六桥 V2 不一致。
问题：桥公开函数不全符合「每个桥函数 try/catch + Log 留痕」；桥头注释陈旧（五桥）。
建议：bootFailure 改为块体并补 Log.d 留痕；全部桥头注释改「六桥」。
76 合规：轻微违反第2条；文档口径与 V2 六桥不符。

## C1 · lib/bridges/bridge_session.dart:31-66 · P2 · 桥函数 catch 后返回同一失败源（伪容错）
证据：:41-47 `moduleRegistry()` catch 中 `Log.e(...); return ModuleRegistry.instance;`；:51-57 navState()、:61-66 playbackSession() 同样在 catch 后返回同一单例；:31-38 createAppGraph() catch 后 `return AppGraph.empty()` 与 try 内返回值相同。
问题：单例 getter 本身几乎不可能抛，catch 分支返回同一表达式，属形式化 try/catch；若真抛则 catch 内再次求值会二次抛且无二次保护，留痕后仍失败。审计价值低但不构成静默吞。
建议：桥函数可直接返回单例（无失败点则无需 try/catch），或 catch 内返回明确的安全降级对象并记录可诊断上下文。
76 合规：形式符合第2条，实现冗余。

## C1 · 依赖方向 + 文件规模 + 影子桥（核 3/7/8）
证据：① session 8 文件 import 仅指向 `bridges/*` 与同层（graph↔contracts/module_registry/playback_session/bootstrap 相互 import 合法），**无任何 `import '../surface/...'`**（rg 全仓 session 目录，只 contracts.dart:14 注释提及 WidgetBuilder），无跨层非桥 import。② `rg --files lib | rg -i bridge` 仅返回 lib/bridges/ 下 6 文件，无影子桥目录。③ wc -l：session 最大 playback_session.dart 405 行，bootstrap.dart 275 行；bridges 最大 bridge_boot.dart 187 行、bridge_core.dart 178 行——全部 <1500 行，不需拆分。④ 反向依赖：bridge_boot/kernel/logic/session/surface 均 `import '../kernel/kernel.dart'`（L3）取 Log；按 §1 桥相邻关系，bridge_logic(L4↔L5)/bridge_session(L5↔L6)/bridge_surface(L6↔L7) 直连 L3 kernel 属越级依赖（全仓 core/algorithms、core/audio、core/cache 等亦直 import bridge_kernel，是 V2 刻意允许的日志例外，见 bridge_kernel.dart:2-4 注释）。
问题：L6 依赖方向与文件规模合规；但 4 座上层桥直连 L3 kernel（虽为日志例外）在严格相邻关系下仍属越级 import。
建议：保留日志例外但在桥头统一注明「仅 Log 走 bridge_kernel 直连」；若不设例外则需把 Log 逐级经相邻桥转发。
76 合规：依赖方向符合第4条；桥越级取 Log 需规则豁免说明。

## C1 · lib/session/theme_controller.dart:13-45 · P1 · L6 直接持久化 IO（职责与 §0-8 边界）
证据：:7 `import 'package:flutter/foundation.dart';`、:13-19 构造中 `KeyValueSettings.shared(StoragePaths.I).getInt(kThemeModeKey)`；:33-42 setMode 中 `.setInt(kThemeModeKey, mode)`（同步磁盘写）。ThemeController extends ValueNotifier<int>（:12），被 bridge_session.dart:26 导出。
问题：L6 主题控制器直接执行 core 设置存储 IO（读写 settings.json），虽经 bridge_core 门面取类型，但属「持有/执行 L4 IO 语义」；76 §1 L6 只暴露状态/回调，L4 才管存储。SESSION 侧 theme_controller 同时是状态容器，边界模糊。
建议：把持久化移到 L4（如由 bridge_core 暴露 ThemePrefs facade 或在 bootloader 装配时注入 persist 回调），L6 只 `value = mode` + notify，由监听方（L2/L4）负责落盘。
76 合规：擦边违反第8条精神（L6 只暴露状态/回调，执行权在 L4）。

## C1 · lib/session/graph.dart:81-147 / bootstrap.dart:6-50 · P2 · 装配图暴露 IO 句柄（L7 可达性）
证据：graph.dart:133-140 `final SongDao? songDao; final HistoryDao? historyDao; final KugouClient? client;` 注释「供 L7 取 DAO/Client（可选出口）」；bootstrap.dart:269-273 装配时把 songDao/historyDao/client 塞入 AppGraph。bridge_session.dart:15 与 bridge_surface.dart:16 均 export AppGraph，L7 可直接 `appGraph.songDao` 访问 L4 DAO。
问题：L7 surface 经装配图可直取 L4 存储/网络句柄，绕过 core 门面调用约束；「L7 只画控件，状态经 session 快照」被削弱。当前 rg 未见 surface 实际调用 `appGraph.songDao`（消费点在 L5/L6），但出口已开。
建议：移除 AppGraph 的 songDao/historyDao/client 字段（纯契约），L7 如需数据一律经 session 暴露的只读快照/意图方法。
76 合规：潜在违反第1、4条（跨层直取非桥门面）。

## C1 · 本视角结论
1. L6 8 文件均**无 Widget/BuildContext/build/setState 渲染**（Widget 只出现在 contracts.dart:14 注释），L6「不画控件」职责符合 76 §0；theme_controller/playback_session 用 flutter/foundation 的 ChangeNotifier/ValueNotifier，属 V2 允许的状态容器。
2. **最严重 P0 三条**：① bootstrap 占位模块抢占 id 致真实 MV 模块永不注册（A1 遗留，session 侧可修）；② playback_session 越界持有并驱动 L5 队列/reducer 状态机（≥10 处调用）；③ main 直连 bridge_surface 跨 5 层 + bridge_boot re-export kernel 致 bridge_kernel 名存实亡（A1 遗留，桥相邻关系破坏）。
3. 桥 try/catch+Log：bridge_boot/kernel/session/surface 的函数级留痕到位；bridge_core/bridge_logic 是 export-only 桥，铁律 2「每个桥函数 try/catch+Log」形式不适用，需主会话澄清口径；LogicFacade.playbackSummary 零调用占位。
4. 预读：bootstrap 在 L6 直接 `cacheService.prefetch(...)` 执行写入，越过「L6 只预测键、L4 执行写入」边界；onQueueChanged 仅打日志，预读策略未真正联动。
5. 登录态双轨：NavState.bumpAuth 已落盘（settings_page/login_sheet 调用），但 AuthSession.onAuthChanged 订阅/通知零调用，L6 对外回调是死链且注释陈旧。
6. 依赖方向：session → bridges → 下层，无 session→surface、无跨层非桥 import；全仓无影子桥；14 文件均 <1500 行（最大 405）。上层 4 座桥直连 kernel.Log 属 V2 日志例外但缺统一豁免声明。
7. 装配图暴露 L4 DAO/Client 给 L7 的出口存在（当前未见实际调用），建议收口。

## C1 · 未覆盖
- 未逐行审查 lib/init/、lib/bootloader/、lib/kernel/、lib/surface/、lib/core/、lib/logic/ 全量（属其他批次范围）；仅在取证 A1 遗留与跨层关系时对 main.dart、app_root.dart、shell.dart、mv_page.dart、login_sheet.dart、settings_page.dart 做定点 rg/片段读取。
- 未运行任何 dart/flutter/analyze/test/门禁（按工具纪律禁止）；未做运行期行为验证，结论基于静态 import/代码事实。
- 未核对 L5 queue_state/player_state/reducer 内部实现是否另有 session 委托接口（属 A5 批范围）；playback_session 的状态机归属结论按本批可见调用点给出。
- 未审 lib/surface/ 18 文件 M3/动画/文案（A7 批范围）。

## C1 · 76 合规小结
- 符合：第1条（session 仅经桥访问下层，无跨层非桥 import）、第3条（六桥唯一存在于 lib/bridges/，无影子桥）、第4条部分（session→下层方向正确）、第5条行数（14 文件均 <1500）、L6 不画控件（§0）。
- 违反：第1/4条（main→bridge_surface 跨 5 层；bridge_boot re-export kernel 越级；上层 4 桥直连 L3 Log 需豁免）、第2条（export-only 桥无 try/catch+Log，规则口径待澄清；bootFailure 无留痕）、第5条（占位模块抢占 id 破坏热插拔，MV 模块永不注册）、第8条（L6 持有 L5 队列/reducer 状态机、直接执行 cache.prefetch 写入、theme 直接落盘 IO）。
- 规则冲突待裁决：DEEP_AUDIT_PLAN §0-8「播放控制/队列/reducer 不在 L6」与 SEVEN_SIX_RULE §4「播放编排属 session/playback_session」对 reducer 归属口径不一，本次按任务书重点核要求判为违反第8条并提交主会话裁决。
