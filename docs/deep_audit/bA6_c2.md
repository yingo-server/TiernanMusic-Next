# A6 批 · C2 实现正确性视角 · session 全量 8 文件 + 六桥 6 文件

> 审查时间：2026-11-16。视角：C2（空安全 / 状态机断点 / 失败空路径 / 异步竞态 / 功能可达性 / 异常吞没 / 密码学）。
> 只读审查，未改任何源码。证据均带 `文件:行`。

## 背景（已知，避免重复报底层）
- A1 已知：boot 失败误判（bridge_boot.fromAny 非 Map rejected=false）、DB await 分歧、MV 占位抢占 id、AuthLogic 双实例、验证死状态机、MV 三重断点。
- 本视角聚焦 L6 session + 六桥自身的实现正确性，并对上述已知在本层的落点做「真相复核」。

---

## 视角 C2 · lib/session/theme_controller.dart:19-42 · P1 · 状态机/通知风暴
证据：
```dart
void setMode(int mode) {
  ...
  value = mode;                       // L23: ValueNotifier 赋值自身即 notifyListeners()
  final ok = KeyValueSettings.shared(StoragePaths.I).setInt(kThemeModeKey, mode);
  ...
  notifyListeners();                  // L41: 再次通知
}
```
问题：`ThemeController extends ValueNotifier<int>`，`value = mode`（第 23 行）已经触发一次 notifyListeners()；method 末尾第 41 行又显式调用一次 notifyListeners()，导致**每次切换主题广播两次重建**。AppRoot 监听方会整棵树重建两次，属于典型 rebuild 风暴；若 mode 未变化（value 相同）ValueNotifier 不通知，但末尾 notifyListeners 仍会广播一次「无变化」事件。
建议：删除末尾 `notifyListeners()`，仅靠 `value =` 触发；若需幂等，先 `if (value == mode) return;`。
76 合规：不违反（L6 允许 ValueNotifier，第 L6 允许 flutter/foundation 条款）；属实现正确性缺陷。

---

## 视角 C2 · lib/session/auth_session.dart:1-85 · P1 · AuthSession 整体死代码 + 过期 TODO（复核修正）
证据：
```dart
// auth_session.dart:4 / :52
// ⚠️ 批2-F2 的 NavState.bumpAuth 未落盘（2026-11-15 检查无此 API）——
// TODO(批2-F2): NavState.bumpAuth 落盘后改为监听 NavState.instance ...
```
```bash
# 全仓检索：唯一被 L7 使用的登录态通知是 NavState
lib/surface/pages/login_sheet.dart:79,95: navState().bumpAuth();
lib/surface/pages/settings_page.dart:39,81: navState().addListener / bumpAuth();
lib/surface/shell.dart:69: NavState.instance.addListener(_navListener);
# AuthSession.onAuthChanged / notifyAuthChanged / isLoggedIn 全仓零消费者（除自身定义与 bridge_session re-export）
```
问题：`NavState.bumpAuth()/authVersion` 现已落盘，且 L7 登录页/设置页/shell **实际全部使用 NavState** 做登录态广播；AuthSession 的注释/TODO 仍停在「F2 未落盘」旧假设，其 `onAuthChanged`/`notifyAuthChanged`/`isLoggedIn`/`userid` 及 `_listeners` 全仓零调用（只被 bridge_session re-export，无真实消费者）。这是一个**整体死的会话门面**：它宣称是登录态会话层，但真正的登录态(source of truth)是 `KugouClient.session` + NavState，AuthSession 的回调注册表永远无人触发、无人订阅。若未来有消费方按注释误用 `onAuthChanged`，将永远收不到登录变更。
建议：二选一——① 删除 AuthSession 及 bridge_session 中的 re-export，明确 NavState 为唯一登录态通知出口；② 若保留，则让其 `onAuthChanged` 委托 `NavState.instance.addListener`，并删除过期 TODO 注释，使两条管线合一。
76 合规：不违反层归属；属死代码/状态机断点。

---

## 视角 C2 · lib/session/auth_session.dart:64-83 · P2 · 监听器注册异常隔离（局部合规，记录）
证据：
```dart
void notifyAuthChanged() {
  for (final l in List<void Function()>.of(_listeners)) {
    try { l(); } catch (e, st) { Log.e(_tag, 'auth listener failed', e, st); }
  }
}
```
问题：此处逐监听器 try/catch + 拷贝列表迭代是**正确的**（一个坏监听器不影响其他），与前两条 nav/theme 形成对比，记录为合规对照。但 `_listeners` 只增不减（`onAuthChanged` 无配对 off 被 UI 调用则泄漏，需 L7 核查）。
建议：保持逐监听器隔离；确认 L7 页面 dispose 时调用 offAuthChanged。
76 合规：合规。

---

## 视角 C2 · lib/bridges/bridge_boot.dart:62-79 · P0 · boot 失败仍被误判成功（A1 X3 未修复，本视角复核确认）
证据：
```dart
// bridge_boot.dart:62-79 BootOutcome.fromAny
if (any is Map) {
  final rejected = any['rejected'] == true;   // Map 分支正确读 rejected
  ...
}
// 成功路径：L2 BootResult
final d = any as dynamic;
return BootOutcome._(false, '', '', <String, Object?>{  // L64: 硬编码 rejected=false
  'client': d.client, 'songDao': d.songDao, ...        // 从不读 d.rejected
  'dbOpenFuture': _readDbOpenFuture(any), '__raw': any,
});
```
对照 bootloader.dart:90-93 失败路径：
```dart
} catch (e, st) {
  Log.e('boot', 'core assemble failed', e, st);
  return BootResult(rejected: true, kernel: kernel);   // client/dao 全 null
}
```
问题：A1 X3 判「非 Map 分支 rejected=false」**至今仍在**。真实失败路径 `Bootstrap.run` 返回 `BootResult(rejected:true, kernel, 其余全 null)` 对象（非 Map）。调用链：`main.dart:47 runBoot()` → `bridge_boot.runBoot():122 return BootOutcome.fromAny(runBootImpl(...))` → `runBootImpl` 返回该 BootResult → `fromAny` 走 L64 成功分支硬编码 `rejected=false`、`error=''`、`detail=''`，把 null 依赖塞进 deps。`main.dart:54 if(outcome.rejected)` 因而为 false，但没有直接带着 null 进 installServices——`main.dart:71-83` 的 `requiredDeps` 判空兜底会命中，显示「核心模块缺失：client, songDao...」错误页。故**后果是误导性 UX + 真实拒绝原因被吞**（BootResult 失败时只有 rejected+kernel、无 error/detail，原因早已只在 kernel Log 缓冲里），而非空指针崩溃。但桥的 `rejected`/`error`/`detail` 归一化语义确实被破坏，Map 失败分支（bootFailure 造的）却正确读 rejected，两分支不一致。
建议：成功路径改为 `final rejected = d.rejected == true;`，并据容错读取的 d.error/d.detail 填充；或给 BootResult 增 error/detail 字段供桥读取。切勿在对象分支无条件 rejected=false。
76 合规：不违反（桥做类型归一化属其职责）；属失败路径语义丢失/异常吞没。

---

## 视角 C2 · lib/session/bootstrap.dart:53-65, 190-215 · P1 · step() 只包构造、prefetch/attach 未 await + 装配图半瘫风险
证据：
```dart
// step 只 try/catch 同步构造，成功即 Log；rethrow 正确
T step<T>(String name, T Function() build) { try { ... } catch { rethrow; } }
...
// L190-198
cacheService.prefetch(<...>);   // 返回 Future<int>，未 await、未 .catchError
// L201 PlaybackSession.instance.attach(...)  // 同步 void，内部 fire-and-forget
```
问题：① `step()` 设计本身正确（失败 rethrow，非静默），合规记录；但 `prefetch()` 是 `Future<int>`（cache_service.dart:133），此处**未 await 也未挂 catchError**，其内部虽有 try/catch（L148 Log），属异步静默：启动「成功」但热搜/榜单预热可能全部失败且无人察觉——与 A1 X6「启动期 prefetch 异常被吞」同源，本层确认。② `bootstrapSession` 的 engine 参数（L68 `Object? engine`）**从头到尾未被使用**，engine 注入实为死参数；L7/bridge_surface 传进来的 engine 被静默丢弃，PlaybackSession.attach 内部自建 JustAudioEngine，测试注入/替换能力失效。
建议：prefetch 改为 `unawaited(cacheService.prefetch(...).catchError(...Log.w))` 显式留痕或纳入启动 outcome；engine 参数要么透传 `PlaybackSession.instance.attach(engine: ...)`（需正确类型转换），要么删除死参数。
76 合规：不违反层归属；属异步异常吞没 + 死参数。

---

## 视角 C2 · lib/session/bootstrap.dart:200-215, 216-232 · P1 · 占位模块抢占 id 致真实 MV 模块永不注册（A1 X1 本层机制复核）
证据：
```dart
// bootstrap.dart:217-232
const moduleIds = <String>[..., 'comment', 'mv', 'album', 'artist'];
for (final id in moduleIds) {
  ModuleRegistry.instance.install(_PlaceholderModule(id));  // enabled=false，但 id 已存在
}
// mv_page.dart:12-16
void registerMvModule() {
  final reg = ModuleRegistry.instance;
  if (reg.byId('mv') != null) return;                        // 占位已占 id → 直接 return
  reg.install(MvPageModule());
}
```
问题：A1 X1 机制确认：bootstrap 先装占位 `_PlaceholderModule('mv')`（`enabled=false`，builder=null），L7 `registerMvModule()` 以 `byId('mv')!=null` 判重直接返回，真实 `MvPageModule`（即便其 builder 硬编码 `songHash:''`）**永不进入注册表**。且调用顺序是 bridge_surface.installServices 里 `bootstrapSession()` 先于 `root.installServices()→registerModules()→registerMvModule()`，故占位必然先落地。结果：`ModuleRegistry.byId('mv')` 永远是占位、enabled=false、`active()/navEntries()` 不含 mv、无 builder → MV 页功能可达性为 0。hot-plug 顺序依赖「占位先、真实后、真实靠覆盖」的假设，但 L7 用了「已存在即 return」的幂等策略，两者矛盾。
建议：占位安装改为「仅当 id 不存在才装」（`if (byId(id)==null) install(...)`），或让 L7 真实模块用无条件 `install()` 覆盖（去掉 `if byId != null return`），并统一 hot-plug 覆盖语义；根治应让 L7 先注册、bootstrap 不预占 id。
76 合规：不违反（L6 注册表本身职责正确）；属模块热插拔顺序/幂等语义缺陷。

---

## 视角 C2 · lib/session/bootstrap.dart:146 · P2 · CollectLogic isLoggedIn 闭包误用 auth.session.userid（语义可疑，需 L5 契约核对）
证据：
```dart
// bootstrap.dart:142-147
final collect = step('CollectLogic', () => CollectLogic(
  client: client,
  settings: settings,
  isLoggedIn: () => auth.session.userid.isNotEmpty,       // L146
));
```
问题：`auth.session.userid.isNotEmpty` 作为登录判据，未排除 bootloader 初始化时 `userid` 可能为哨兵 `'0'`（AuthSession.isLoggedIn 自身就用 `uid != '0'` 排除）。若 KugouSession.userid 在未登录时默认为 `'0'`，则 `isNotEmpty==true` 会把未登录误判为已登录，绕过 CollectLogic 的登录守卫。需 L5 契约确认 userid 默认值；若默认空串则此条不成立，记为待核。
建议：复用统一判据 `() => auth.session.userid.isNotEmpty && auth.session.userid != '0'`，或让 CollectLogic 直接依赖 AuthSession.isLoggedIn。
76 合规：不违反；属登录守卫判据不严谨（待 L5 契约确认）。

---

## 视角 C2 · lib/session/playback_session.dart:196-241 · P0 · 20028 needsVerification 只做 string.contains 误判，验证死状态机无触发（A5 X1 本层真相复核）
证据：
```dart
// playback_session.dart:196-202
final src = await _service?.resolvePlaySource(cur, _quality);
if (src == null || !src.ok) {
  final errKind = src?.error?.toString() ?? '';
  final canMv =
      errKind.contains('noPrivilege') ||
      errKind.contains('needsVerification') ||
      errKind.contains('notFound');
  // → 命中后只试 MV 音频兜底，失败则 emit ErrorAction(...)
```
对照 PlaySource.toString（playback_service.dart:92-98）：
```dart
return 'PlaySource(${toMap()})';  // toMap()['error'] = error?.name（枚举名，如 'needsVerification'）
```
问题：A5 X1 称「遇到 20028 只拼错误文案不触发验证」——本层确认**属实**：
① 错误判定用 `errKind.contains(...)` 对 `toString()` 结果做**子串匹配**（当前 `PlaySource.toString()`→`toMap()['error']=error?.name` 恰好产出 'needsVerification' 等枚举名，故 today 能命中；但这是脆弱的隐式耦合——枚举改名/序列化格式变即失效），而非直接比较 `src.error == PlaybackError.needsVerification`。
② 真正命中 `needsVerification`（匿名 20028）后，L6 **不调用 VerificationLogic**（虽 bootstrap 已装配 `graph.verification`、playback_session 根本拿不到它），而是去试 `resolveMvAudioFallback`（MV 音频兜底）。MV 兜底失败后仅 `_emit(ErrorAction(src.error...))` 拼文案，**从不触发任何验证流程** → 用户遇 20028 验证请求时永远卡在错误态，verifyLogic 的 submitVerification 恒定 false（A5 已知）更使即使触发也无解。这是「功能可达性」P0：验证流程从播放链完全断开。
建议：① 改为强类型 `switch (src.error)` 判 `needsVerification`；② 在命中 needsVerification 时经装配图拿到 VerificationLogic，拉起验证 UI/提交（L6 发意图，L7 弹验证页），而非走 MV 兜底；MV 兜底仅保留给 noPrivilege/notFound。
76 合规：不违反层归属（L6 编排验证属职责内）；属错误判定脆弱 + 验证流程死链。

---

## 视角 C2 · lib/session/playback_session.dart:1-3,118-145 · P2 · 依赖 flutter/foundation ChangeNotifier（76 §0 注释自认需豁免，存疑）
证据：
```dart
// playback_session.dart:1-3
// L6 session · 播放编排会话（... ChangeNotifier 仅作 Listenable 状态容器，
// 76 原则 §2 允许 L6 依赖 flutter/foundation）。
import 'package:flutter/foundation.dart' show ChangeNotifier;
...
class PlaybackSession extends ChangeNotifier { ... }
```
问题：文件头注释声称「76 原则 §2 允许 L6 依赖 flutter/foundation」，但 §0 前缀铁律列出 L6 为「编排会话层」，明确「L6 只暴露状态/回调」，且 contracts.dart 刻意保持「零 flutter 依赖」以可本地单测。此处 L6 直接 `extends ChangeNotifier` 并 import flutter/foundation，使 session 失去纯 Dart 可单测性，且与 contracts 的设计取向矛盾。注释所引「§2」是 DEEP_AUDIT_14_BATCH_PLAN 的审查视角小节，并非 76 原则条款——属**用不存在条款为越依赖辩护**。C1 视角将裁定是否构成违反；此处仅记录事实与可测试性损失。
建议：若坚持 76 纯 Dart，改为自带 `void Function()? onChanged` 回调列表（同 NavState 模式），去掉 flutter/foundation 依赖；或由主会话在 76 原则里显式登记 L6 可用 foundation 的例外。
76 合规：存疑——可能违反 §0「L6 只暴露状态/回调」及第 10 条纯 Dart 取向；交 C1 裁定。

---

## 视角 C2 · lib/session/playback_session.dart:76-96, 101-145 · P1 · _mvTriedOnce 永久累积不清理 + attach 重复初始化竞态
证据：
```dart
// L76
final Set<String> _mvTriedOnce = <String>{};
// L198-204: 每曲只试一次 MV 兜底，hash 永久留在 Set 中
if (canMv && !_mvTriedOnce.contains(cur.hash)) {
  _mvTriedOnce.add(cur.hash);
  ...
// L118-145 attach
void attach({...}) {
  ...
  if (engine == null && _engine is NullAudioEngine) {
    final just = JustAudioEngine(onEvent: _onEngineEvent);
    _engine = just;
    initNotification(just.rawPlayer, ...).then(...).catchError(...);  // fire-and-forget
  }
}
```
问题：① `_mvTriedOnce` 是会话级 Set，只增不减——同一首歌在会话内第二次播放（用户手动重播/切歌回来）遇到 20028 时将**不再尝试 MV 兜底**，直接进 ErrorAction。注释称「每曲只试一次」是防死循环，但 bind 到 hash 且从不清理，导致重播体验永久降级（尤其 MV 兜底本是 20028 的唯一出路）。② `attach` 若被调用两次，第一次已建 JustAudioEngine（`_engine` 非 NullAudioEngine），第二次 `if (engine==null && _engine is NullAudioEngine)` 为 false，跳过重建——但 `_service`/`_quality` 会被覆盖、`notifyListeners` 再广播；多个 `initNotification` 不会重复（幂等），但 attach 无「已装配」守卫，配置可被静默改写。属低概率竞态，记录 P2→P1（因叠加 MV 兜底死链）。
建议：① `_mvTriedOnce` 改为 LRU/按时间清理，或在 playSong/playAll 显式重播时 `remove(cur.hash)`；② attach 加 `bool _attached` 守卫，重复调用直接 return 或 Log.w。
76 合规：不违反；属状态管理/竞态。

---

## 视角 C2 · lib/session/playback_session.dart:150-165, 278-300 · P2 · 引擎事件驱动状态更新 vs 直接 emit 双源，可能状态抖动
证据：
```dart
// _onEngineEvent(L150) 收到 AudioEventType.playing/paused → _emit(playbackReducer(...))
// 而 toggle()(L278)/pause()(L288) 也直接 _emit(Playing/Paused) 不依赖引擎回执：
void toggle() { if (status==playing) { _engine.pause(); _emit(Paused()); } else { _engine.resume(); _emit(Resume()); } }
```
问题：`toggle()/pause()` 先调用引擎再**立即同步** `_emit` 状态，而引擎随后也会通过 `AudioEventType.playing/paused` 回调再次 `_emit`。若引擎事件快速返回，同一逻辑转换被 emit 两次（notifyListeners 两次 → L7 双重 rebuild）；若引擎 **不** 发回执（NullAudioEngine/桩），则状态完全依赖同步 emit（此时正确）。两条更新源无单一权威，产生潜在 rebuild 抖动与「状态与引擎实际不同步」窗口（引擎拒绝 pause 但 UI 已显示 paused）。
建议：选定单一权威——要么 UI 意图只调引擎、状态一律由引擎事件驱动 emit；要么同步 emit 后忽略对应引擎回执（加去重/版本号）。
76 合规：不违反；属状态机双源/重建抖动。

---

## 视角 C2 · lib/session/auth_session.dart:22-29 · P1 · AuthSession.attach 全仓零调用 → client 永远 null，快照恒空（死门面确证）
证据：
```dart
// auth_session.dart:22-29
KugouClient? _client;
void attach(KugouClient? client) { _client = client; ... }
String get userid {
  try { return _client?.session.userid ?? ''; } ...   // _client 恒 null → ''
}
```
```bash
# 全仓检索：除定义外无任何 AuthSession.attach(client) 调用
lib/session/auth_session.dart 以外仅在 bridge_session.dart:28 被 re-export
bootloader/bootstrap 装配的是 AuthLogic（auth.session），从不 attach 给 AuthSession
```
问题：与上条呼应——AuthSession 非但监听器无触发源，连**数据源注入 `attach()` 都全仓零调用**。因此 `_client` 永远为 null，`userid` 恒 `''`、`isLoggedIn` 恒 false。它对外宣称的「登录态快照」是一个**永远返回未登录的假快照**。任何未来经 bridge_session 误用 `AuthSession.instance.isLoggedIn` 的页面将永远判定为游客。这是死代码 + 假数据的双重问题，明确了「应删除还是应接上」的紧迫性。
建议：若保留 AuthSession，必须在 bootstrap/bootloader 装配时调用 `AuthSession.instance.attach(client)` 并统一通知出口；否则直接从 bridge_session 删除 re-export 与整个文件。
76 合规：不违反层归属；属死代码/假数据。

---

## 视角 C2 · lib/session/playback_session.dart:110-112 · P2 · 通知栏 onSeek 未接线 → 拖动进度条无响应
证据：
```dart
// playback_session.dart:110-112
initNotification(
  just.rawPlayer,
  NotificationControls(onNext: next, onPrev: prev),  // 未传 onSeek
)
```
对照 NotificationControls（notification_gateway.dart:28-33）：
```dart
const NotificationControls({this.onNext, this.onPrev, this.onSeek});
final Future<void> Function(int ms)? onSeek;
```
问题：`NotificationControls` 支持 `onSeek`，但 attach 时只接了 onNext/onPrev，onSeek 留空。若 L4 通知网关依赖该回调处理通知栏拖动进度，则通知栏 seek 控件为死链（点击无效）。需 L4 确认 notification_gateway 是否用 onSeek；若用，则此处遗漏接线属功能断点。
建议：补 `onSeek: (ms) async => seek(ms)`（注意 seek 是 void，需包一层 Future）或确认网关有独立 seek 通道后登记。
76 合规：不违反；属回调接线遗漏（待 L4 确认）。

---

## 视角 C2 · lib/session/graph.dart:33-38, 136-137 · P2 · AppGraph.notification 字段从未装配 + SessionDeps 从未被使用
证据：
```dart
// graph.dart: AppGraph 构造含 notification 字段（L137 final MusicAudioHandler? notification）
// bootstrap.dart:235-260 构造 AppGraph 时未传 notification → 恒 null
// SessionDeps（graph.dart:41-73）定义完整，但全仓除 bridge_surface re-export 外无构造点
```
问题：① `AppGraph.notification`（通知栏网关）在 bootstrap 构造时未注入，恒 null——若 L7 经 appGraph.notification 消费将拿到空；而通知实际由 PlaybackSession 内的 `_notification` 持有，两条出口不一致。② `SessionDeps` 是可空 core 依赖集合，但 bootstrapSession 用的是平铺 required 参数而非 SessionDeps，`SessionDeps` 全仓零构造——是死契约（bridge_surface re-export 的 `SessionDeps` 也无实际使用者）。均属装配图字段与真实装配路径脱节的死数据。
建议：要么在 bootstrap 构造 AppGraph 时把 PlaybackSession 的通知 handler 暴露并注入 notification 字段，要么删除未用的 notification/SessionDeps 出口，避免误导 L7。
76 合规：不违反层归属；属死字段/装配不一致。

---

## 视角 C2 · lib/bridges/bridge_core.dart:71,175-178 + bridge_logic.dart:60-67 · P2 · comment_endpoints 双桥出口（re-export 制造多出口）
证据：
```dart
// bridge_core.dart:177-178
export '../core/net/endpoints/comment_endpoints.dart' show getMusicComments, getCommentFloor, getCommentCount;
// bridge_logic.dart:60-67 又从同一文件导出 CommentItem/CommentPage/getMusicComments/getCommentFloor/getCommentCount
```
问题：注释（bridge_core.dart:175）自认「comment_endpoints 经 bridge_core 与 bridge_logic 双桥出口，存在重复符号，按 76 暂保留」。同一批 core 函数从两座桥暴露，违反「桥唯一通道」的精神（C1 会更权威裁定）；C2 视角关注实现后果：调用方 import 两桥时 `getMusicComments` 产生 ambiguous import 风险，且未来一侧修改签名另一侧漏改会导致行为分叉。属 re-export 制造多出口。
建议：统一收敛到单一桥（core 数据端点应只走 bridge_core，logic 门面只走 bridge_logic），删除重复 export。
76 合规：可能违反第 2 条「桥唯一合法通道」（C1 裁定）；本视角记录为多出口风险。

---

## 视角 C2 · lib/bridges/bridge_kernel.dart:20-26, 51-57 · P2 · 桥内日志用 print 兜底 + assembleKernel 失败返回空上下文（异常降级但非静默）
证据：
```dart
void _bridgeLog(...) { try { print(...); } catch (e) { /* 静默终止 */ } }
KernelContext assembleKernel() {
  try { return Kernel.assemble(); }
  catch (e, st) { _bridgeLog('E', 'assembleKernel', e, st); return const KernelContext(modules: {}); }
}
```
问题：① `_bridgeLog` 用 `print` 而非 kernel.Log（为避免递归，设计合理），但 kernel.Log 自身也是 `print`（kernel.dart:18）——若 Log 抛错的概率极低，兜底 print 一致；记录为合规降级。② `assembleKernel()` 失败返回空 `KernelContext`（非 null），但其**全仓零调用**（A1 X4 已记 bridge_kernel 空壳）——本层确认：bridge_kernel 的 logD/logW/logE 被 session 各文件广泛使用（合规出口），但 `assembleKernel` 无消费者，属桥内死函数。③ `KernelContext.get<T>()`（kernel.dart:25）`modules[T] as T` 对空表必抛 CastError，若真有调用方 get 将崩，但当前无调用。
建议：删除无消费者的 assembleKernel 或补文档说明保留理由；保留则确认无人对空上下文做 get。
76 合规：合规（桥承担日志职责、异常不静默）；死函数记录。

---

## 视角 C2 · lib/bridges/bridge_session.dart:34-66 · P2 · 桥函数 catch 后返回同一个单例（catch 分支无效，属形式化 try/catch）
证据：
```dart
ModuleRegistry moduleRegistry() {
  try { return ModuleRegistry.instance; }
  catch (e, st) { Log.e(...); return ModuleRegistry.instance; }  // catch 里返回同样的表达式
}
NavState navState() / PlaybackSession playbackSession() 同形
```
问题：`ModuleRegistry.instance`/`NavState.instance`/`PlaybackSession.instance` 是 `static final` 惰性单例，取值本身不可能抛异常；try/catch 是形式化的（catch 分支返回完全相同的表达式）。这不算错误，但属于「为满足铁律而写的空壳 try/catch」——真正的异常只会来自单例**构造**（首次访问时），而构造在 `static final` 初始化中抛错发生在进入 try 之前的语义边界（Dart 中首次访问确实在 try 内求值，能捕获），但捕获后返回同一表达式会**再次触发构造并再次抛错**，catch 形同虚设且可能二次异常。低概率，记录 P2。
建议：这些纯 getter 可去掉 try/catch（无业务异常可吞），或在 catch 里返回明确的空/降级对象而非重试同一表达式。
76 合规：合规（无越层）；属形式化异常处理。

---

## 视角 C2 · lib/session/bootstrap.dart:103 + lib/bootloader/bootloader.dart:133 · P1 · AuthLogic 双实例（A1 X7 复核确认）+ BootResult.auth 弃用
证据：
```dart
// bootloader.dart:132-133（L2 装配一份）
final settings = core.KeyValueSettings(paths);
final auth = lg.AuthLogic(client: client, settings: settings);   // → BootResult.auth
// bootstrap.dart:102-104（L6 又装一份）
final auth = step('AuthLogic', () => AuthLogic(client: client, settings: settings));
```
```bash
# BootResult.auth 全仓仅 3 处：定义(L31) + bootloader 赋值(L86) + 无消费者
# bridge_boot.BootOutcome.fromAny 的 deps 从不带 'auth' 键
# L7 登录页/设置页全部用 appGraph.auth（= bootstrap 的第二份）
```
问题：A1 X7 确认：**两份 AuthLogic**。L2 那份（`BootResult.auth`）构造后从未被任何层消费——bridge_boot 归一化时不透传 `auth` 键，main 也不取它，属**纯浪费的死实例**；真正服务 L7 的是 bootstrap 的第二份（进 AppGraph.auth）。所幸 AuthLogic 自身无可变实例字段（仅 `final _client/_settings`，session 状态委托 `_client.session`），故两份不会「互盲」到数据层面，风险低于历史 settings 双实例 bug，但仍是无意义重复构造 + 潜在 if 未来加实例态即分叉。L2 为构造这个死实例还多装了一份 `KeyValueSettings(paths)`（见下条）。
建议：删除 bootloader 的 `AuthLogic`/`auth` 装配与 BootResult.auth 字段（唯一消费点在 L6），或反过来让 L6 复用 BootResult.auth（经 BootOutcome.deps 透传）以真正单例化。二选一，别并存。
76 合规：不违反层归属；属重复装配/死实例。

---

## 视角 C2 · lib/bootloader/bootloader.dart:132 + lib/session/theme_controller.dart:15,36 · P2 · settings 实例来源不统一（new vs .shared，本层复核风险已被构造器登记缓解）
证据：
```dart
// bootloader.dart:132
final settings = core.KeyValueSettings(paths);       // 直接 new
// theme_controller.dart:15/36
KeyValueSettings.shared(StoragePaths.I).getInt(...)/setInt(...)   // 走 shared 工厂
```
```dart
// settings_store.dart:34-40（构造器已登记自身，使 shared() 命中同路径实例）
KeyValueSettings(this._paths) : _file = ... {
  _sharedByPath[_file.path] ??= this;
}
```
问题：A1 曾记「settings 双实例历史 bug」；本层复核发现**已部分修复**：`KeyValueSettings` 构造器会把自身登记进 `_sharedByPath`，只要路径相同，`shared()` 会命中 L2 new 的那份，故 bootloader 的 settings 与 theme_controller 的 shared 实例实际是同一对象（前提是 `paths` 同路径——L2 用 `StoragePaths.init(rootDir)` 的返回值，theme 用 `StoragePaths.I` 同一实例，路径一致）。**当前不构成互盲**。但两条创建风格并存是脆弱契约：若某处 new 时路径与 I 不同（如不同 rootDir），就会分裂。记录为风险而非确证 bug。
建议：统一为 `KeyValueSettings.shared(StoragePaths.I)` 单一入口，消除裸 `new`；避免依赖「构造器自登记」这一隐式约定。
76 合规：不违反；属单例来源不一致的脆弱契约。

---

## 视角 C2 · lib/session/bootstrap.dart:190-198 · P2 · cacheService.prefetch 参数用 'navid'/'plat' 硬编码，与端点真实契约待核
证据：
```dart
cacheService.prefetch(<({Endpoint ep, Map<String, Object?> params})>[
  (ep: EndpointRegistry.searchHot, params: <String, Object?>{'navid': 1, 'plat': 2}),
  (ep: EndpointRegistry.rankList, params: <String, Object?>{}),
]);
```
问题：预热 `searchHot` 传 `navid:1, plat:2`、`rankList` 传空 params。A2/A3 端点审查若发现实际端点要求不同参数名（如 `navid` 应为字符串 `'RECOMMEND_...'`、`rankList` 必传 `id`/`type`），则预热请求全部拿到错误响应但被 CacheService 吞掉（只记 Log），启动期缓存永久空。属「字段解析与真实契约对齐」待核点；本视角不重复 A2/A3 端点细节，标记为需与 `search_endpoints.searchHot`、`misc_endpoints.rankList` 签名比对。
建议：核对 `searchHot`/`rankList` 的真实必填参数并补齐；预热失败应可见（计入 CacheStats.errors，已有字段）。
76 合规：不违反；属参数契约待核。

---

## 视角 C2 · lib/session/playback_session.dart:392-395 + lib/logic/player/queue_state.dart:73-83 · P1 · loopOne（单曲循环）模式完全失效
证据：
```dart
// playback_session.dart:392-395
void onCompleted() {
  _emit(playbackReducer(_player, const Completed()));
  next();                       // 无条件切下一曲
}
// queue_state.dart:73,80-83
/// 下一曲。空队列返回 null；loopOne 也前进（单曲循环由播放器负责）。
QueueState? next() {
  if (mode == PlayMode.shuffle) return _shuffleStep(1);
  var ni = index + 1; ...        // loopOne 未做任何处理，直接前进
}
```
```bash
# 全仓 AudioEngine/JustAudioEngine 无 setLoopMode / loop / LoopMode 实现（audio_gateway.dart 无相关符号）
```
问题：`loopOne`（单曲循环）被设计为「由播放器负责」（queue_state 注释 L73），但 `AudioEngine` 接口与 `JustAudioEngine` **没有任何 loop 能力**（无 setLoopMode/LoopMode）；L6 `onCompleted()` 又无条件 `next()`，QueueState.next() 对 loopOne 直接前进到下一曲。结果：L7 player_page.dart:390-395 提供的「单曲循环」按钮能切换 UI 状态，但**实际播放到尾仍会跳下一曲，单曲循环永不生效**——这是一个用户可感知的功能假按钮（点名级「功能都用不了」类）。
建议：在 L6 `onCompleted()` 判 `_queue.mode == PlayMode.loopOne` 时改为重新 `_start(_queue.items, _queue.index)`（或 seek(0)+重播）而非 `next()`；或给 AudioEngine 增加 loop 能力并由 L6 设置。二者选一，别把责任悬空在「播放器负责」而播放器没有该能力。
76 合规：不违反层归属（L6 编排播放行为正确位置）；属状态机分支缺失/功能假按钮。

---

## 视角 C2 · lib/session/playback_session.dart:183-260 · P2 · _start 无并发守卫，快速切歌产生异步竞态（后发先至可致错曲）
证据：
```dart
Future<void> _start(List<SongBrief> songs, int start, {SongBrief? song}) async {
  ...
  final src = await _service?.resolvePlaySource(cur, _quality);   // 网络 await 点
  if (src == null || !src.ok) { ... return; }
  final target = src.localPath ?? src.urls.first;
  await _engine.play(target);                                     // 第二处 await
  _emit(playbackReducer(_player, Playing()), queue: q);           // 用入口快照 q emit
}
```
问题：`_start` 是 async 且有两次 await（解析音源 + 引擎播放），但**无请求序号/代次（generation token）守卫**。用户快速连点下一曲/切歌时，多个 `_start` 并发：先发起的请求（旧曲）若网络返回较慢，其 `await _engine.play(oldUrl)` 可能晚于后发请求完成，最终 `_emit(...Playing(), queue: 旧q)` 把队列与 playing 状态**回退到旧曲**，而引擎实际在播新曲 → 状态与音源错配。MV 兜底分支的 `await _engine.play(mvUrl)` 同样无守卫。属典型异步竞态，快速操作可复现。
建议：增加 `int _playGeneration` 计数器，每次 `_start` 入口 `final gen = ++_playGeneration`，每个 await 后检查 `if (gen != _playGeneration) return;` 再 emit；引擎播放在新请求到来时也需 stop 旧播放。
76 合规：不违反；属异步竞态。

---

## 本视角结论
1. **P0 · boot 失败误判仍在**（bridge_boot.dart:64）：A1 X3 未修复，`BootOutcome.fromAny` 对象分支硬编码 `rejected=false`，真实 BootResult 拒绝原因被吞；所幸 main.requiredDeps 判空兜住崩溃，但 UX 误导（显示「核心模块缺失」而非真实拒绝原因）。
2. **P0 · 20028 验证死链**（playback_session.dart:196-241）：A5 X1 确认——错误判定靠 `toString().contains()` 脆弱匹配，命中 needsVerification 后不触发 VerificationLogic，只做 MV 音频兜底 + 拼错误文案，用户遇验证必卡死。
3. **P0/P1 · MV 模块不可达机制复核**（bootstrap.dart:217-232 + mv_page.dart:15）：占位先装抢占 id，L7 `registerMvModule()` 见 id 存在即 return，真实 MV 模块永不注册；调用顺序保证占位必然先落地。
4. **P1 · loopOne 单曲循环失效**（playback_session.dart:392-395）：L7 有按钮、L5 状态机有枚举，但 L6 无条件 next() 且音频引擎无 loop 能力，功能假按钮。
5. **P1 · AuthSession 整体死代码**（auth_session.dart:22-29,50-83）：attach 全仓零调用 → client 恒 null → userid/isLoggedIn 恒空/假；监听器无触发源；真实登录态走 NavState。应删除或接上。
6. **P1 · AuthLogic 双实例**（bootstrap.dart:103 + bootloader.dart:133）：L2 那份纯死实例，L7 全用 AppGraph 那份；settings 双实例历史 bug 已由构造器自登记缓解（当前不互盲）。
7. **P1 · ThemeController 双次 notify**（theme_controller.dart:23,41）：`value=` 已触发一次通知，末尾又 `notifyListeners()`，每次切主题广播两次。
8. **P1 · _start 异步竞态 + prefetch/engine 死参/死配置**：`_start` 无 generation 守卫可后发先至；bootstrap 的 engine 参数未使用、prefetch 未 await、AppGraph.notification/SessionDeps 恒空死契约。
9. **P2 · 桥层多出口/形式化 try/catch**：comment_endpoints 双桥 export（潜在 ambiguous import）；bridge_session 的 getter catch 分支返回同一单例形同虚设；bridge_kernel.assembleKernel 全仓零调用。
10. **六桥日志无 token 泄漏**：Log 调用点无 token/cookie/password 明文（仅 auth_session 记录 'userid read failed' 无值），此项合规。

## 未覆盖
- 未逐行核对 A2/A3 端点真实参数契约（searchHot/rankList 预热参数 'navid'/'plat' 是否匹配），仅标记待核（bootstrap.dart:190-198）。
- 未验证 L4 notification_gateway 是否消费 onSeek（playback_session 未接线的影响面需 L4 确认）。
- 未验证 CollectLogic.isLoggedIn 判据中 userid 未登录默认值是否为 '0'（需 L5 契约确认；若为空串则该条不成立）。
- 未审查 L7 surface 文件（A7 范围），仅按 grep 核对调用点；MV 页 builder 硬编码 songHash:'' 属 A7 范围未展开。
- 未跑任何 dart/analyze/test（工具纪律禁止），全部为静态取证。

## 76 合规小结
- **层归属**：session 承载播放编排/装配图/注册表/导航状态，符合 L6 职责；六桥均在 lib/bridges/、无影子桥（合规）。
- **try/catch+Log**：绝大多数桥函数与 session 方法均有 try/catch+Log 留痕，异常不静默吞（合规）；例外：bootstrap 的 `prefetch` 未 await/未挂 catchError（异步静默）、bridge_session getter 形式化 catch（P2）。
- **桥唯一通道**：`comment_endpoints` 经 bridge_core 与 bridge_logic 双出口（P2，潜在违反第 2 条唯一通道，C1 权威裁定）。
- **反向依赖**：未发现 session 反向依赖 surface；bridge_surface import session/bootstrap 属 L1/L7 装配合法通道。
- **flutter 依赖**：`playback_session extends ChangeNotifier` 引入 flutter/foundation，与其文件头自引的「§2 允许」存在条款依据存疑；contracts.dart 保持零 flutter 依赖。交 C1 裁定是否违反 §0「L6 只暴露状态/回调」（存疑，非确证违规）。
- **单文件 1500 行**：本批最大文件 playback_session.dart 405 行，全部合规。
- **成熟库**：just_audio/audio_service 经 audio_gateway/notification_gateway 门面使用，合规（但 loop 能力缺失属实现问题非架构问题）。
