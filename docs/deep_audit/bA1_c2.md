# A1 批 · C2 实现正确性视角（只读审查，不改代码）

审查范围：lib/init/main.dart、lib/bootloader/bootloader.dart、lib/bootloader/register.dart、lib/kernel/kernel.dart、lib/bridges/bridge_boot.dart、lib/bridges/bridge_kernel.dart
只读扩展确认：lib/session/bootstrap.dart、lib/session/graph.dart、lib/core/database/db.dart、lib/core/net/database_opener.dart、lib/core/storage/settings_store.dart、lib/core/net/kugou_client.dart、lib/bridges/bridge_surface.dart、lib/surface/app_root.dart、lib/surface/shell.dart、lib/session/module_registry.dart、lib/core/cache/cache_service.dart

---

## C2 · lib/bridges/bridge_boot.dart:65-79 · P0 · 失败路径被误判为成功（boot rejected 丢失）
证据：
```dart
// bridge_boot.dart:50-66（fromAny）
if (any is Map) { ... final rejected = any['rejected'] == true; ... }
// 非 Map 分支（L2 BootResult）：
final d = any as dynamic;
return BootOutcome._(false, '', '', <String, Object?>{ ... });
```
```dart
// bootloader.dart:90-92
} catch (e, st) {
  Log.e('boot', 'core assemble failed', e, st);
  return BootResult(rejected: true, kernel: kernel);   // rejected=true
}
```
问题：`BootResult` 不是 `Map`，因此 `Bootstrap.run` 抛异常时返回的 `BootResult(rejected: true)` 走进 `fromAny` 的 dynamic 分支，被**硬编码成 `BootOutcome._(false, ...)`**——`BootOutcome.rejected` 永远为 false，真实异常只留在 `Log.e` 里，`outcome.error/detail` 为空串。`main.dart:54` 的 `if (outcome.rejected)` 分支永不命中，最终由 `main.dart:82-85` 的依赖判空兜底，报错文案变成「核心模块缺失：client, songDao, ...」，把真实启动失败原因（core 装配异常栈）替换成误导性文案。
建议：`fromAny` 的非 Map 分支改为动态读取 `d.rejected == true`（并把 `d.error/d.detail` 透传），失败时 `BootOutcome._(true, 'core assemble failed', '$e', deps)`；或在 `BootResult` 失败分支额外带 `error/detail` 字段并在 fromAny 中读取。
76 合规：违反第 2 条精神（失败必留痕且不得静默）——留痕只做到 print，未把失败原因 surface 给上层；桥未上抛。

---

## C2 · lib/init/main.dart:69-93 · P0 · DB 未打开时仍继续装配（启动竞态未 fail-fast）
证据：
```dart
// main.dart:69-93
const requiredDeps = <String>['client','songDao','playlistDao','historyDao','downloadStore','settings','paths'];
...
final dbFuture = deps['dbOpenFuture'];
if (dbFuture is Future<bool>) {
  await dbFuture;
  debugPrint('main: db ready');
}
```
```dart
// lib/core/database/db.dart:29-37
static Isar get isar {
  final i = _isar;
  if (i == null) { Log.e(_tag, 'isar accessed before open'); throw StateError('DatabaseService: isar not opened'); }
  return i;
}
```
问题：`dbOpenFuture` 不在 `requiredDeps` 名单里，且 `is Future<bool>` 判定为 false 时**静默跳过 await** 继续装配 surface。此时 DAO（`SongDao._isar` → `DatabaseService.isar`）在 UI 首访时抛 `StateError`，异常发生在启动 try 之外 → 首屏崩溃/白屏，而不是走错误页。`bridge_boot._readDbOpenFuture` 在 legacy 结果下返回 null 正是这个静默分支的入口（bridge_boot.dart:94-100）。
建议：把 `dbOpenFuture` 纳入必需依赖；`dbFuture == null || dbFuture is! Future<bool>` 一律判定为装配失败并渲染错误页（附「DB 未就绪」原因），不要静默继续。
76 合规：符合第 2 条（桥失败留痕），但 init 层对「DB 未就绪」缺少兜底分支——失败路径未真正被 surface 消费。

---

## C2 · lib/bridges/bridge_boot.dart:94-100 + lib/bootloader/bootloader.dart:108-117 · P2 · DB 打开失败 future 可能无人 await（未捕获异步错误）
证据：
```dart
// bootloader.dart:108-117
final Future<bool> dbOpenFuture = core.openDatabase(paths.db().path).then((opened){...})
  .catchError((Object e, StackTrace st) { Log.e('boot','db open failed',e,st); throw StateError('db open failed: $e'); });
```
```dart
// bridge_boot.dart:94-100
static Object? _readDbOpenFuture(Object? any) {
  try { return (any as dynamic).dbOpenFuture as Object?; }
  catch (e, st) { k.Log.d('bridge_boot', 'db open unavailable (legacy result): $e'); return null; }
}
```
问题：DB 打开失败被 `catchError` 转成 `StateError` 再抛出，只有在 main 真正 `await` 该 future 时才会被 `main.dart:105` 的 catch 捕获；若 `fromAny` 走 legacy 分支拿到 null future，这个「已经在失败」的 future 无人 await → 变成未捕获异步错误（zone error），错误页不会显示、真实原因只在 logcat。
建议：让 DB 打开失败的错误在 boot 阶段同步可观测——例如 `_assembleCore` 内改为 `await`-语义（把 openDatabase 放进一个显式的 `Future` 并把失败同时写入 BootResult 的 error 字段），而不是仅靠 future 的异常传播。
76 合规：符合第 2 条（catch + Log 留痕）；失败未上抛到 outcome，属「异常吞没」的边界情形。

---

## C2 · lib/kernel/kernel.dart:28-35 + lib/bridges/bridge_kernel.dart:51-57 · P1 · L3 kernel 是空壳：无生命周期、无模块注册表，失败兜底「成功但空」
证据：
```dart
// kernel.dart:28-35
class Kernel {
  Kernel._();
  static KernelContext assemble() {
    Log.d('kernel', 'assembling modules');
    return KernelContext(modules: const {});
  }
}
```
```dart
// bridge_kernel.dart:51-57
KernelContext assembleKernel() {
  try { return Kernel.assemble(); }
  catch (e, st) { _bridgeLog('E','assembleKernel',e,st); return const KernelContext(modules: {}); }
}
```
问题：(1) 76 原则要求 L3 负责「生命周期编排、日志、盐值校验执行」，但 kernel 没有任何 onStart/onResume/onPause/onStop 生命周期钩子、没有模块注册表、没有事件分发；`KernelContext.modules` 恒为空。(2) `assembleKernel` 的兜底是「catch 后返回空上下文」，属典型的「成功但空」——调用方无法区分「装配成功但无模块」与「装配失败」。(3) `KernelContext.get<T>`（kernel.dart:25）为无检查强转 `modules[T] as T`，modules 为空时抛 `TypeError`（信息弱于 StateError），且要求注册表键与请求类型**精确**匹配。(4) `BootResult.kernel` 字段被 `main` 完全忽略（main 只读 7 个 dep + `__raw`），kernel 上下文在启动链路上没有任何消费者。
建议：要么补齐 kernel 的生命周期方法与模块注册表并在启动流程中实际调用（onStart 由 L2/L1 触发、onPause/onStop 由 AppLifecycle 监听转发），要么在文档中明确 kernel 尚未接线并删除 `BootResult.kernel`/`assembleKernel` 死链；`assembleKernel` 失败应改为抛错或返回带 `failed` 标记的结果。
76 合规：违反第 3 条（L3 生命周期编排未实现）；符合第 2 条（桥函数有 try/catch + 留痕）。

---

## C2 · lib/bridges/bridge_kernel.dart:26-49 · P1 · bridge_kernel 三个日志门面 + assembleKernel 全库无调用方（死链）
证据：
```dart
void logD(String tag, String msg) { ... }
void logW(String tag, String msg) { ... }
void logE(String tag, String msg, [Object? err, StackTrace? st]) { ... }
KernelContext assembleKernel() { ... }
```
全库检索（`rg -n 'assembleKernel|logD\(|logW\(|logE\(' lib`）只命中 bridge_kernel.dart 的定义行；其余 30+ 处 `import '../../bridges/bridge_kernel.dart' show Log;` 只使用 `Log` 这一个符号。
问题：`bridge_kernel` 作为「L3 门面」除 `Log` re-export 外无任何实际桥函数被调用；同时 L2 bootloader 走的是 `bridge_boot.dart`（`import '../bridges/bridge_boot.dart' show KernelContext, Log;`）而不是 bridge_kernel —— 两个「L3 出口」并存，调用方各走一边，日志/内核能力没有单一门面。`bridge_boot` 自身又把 kernel 的 `Kernel/KernelContext/Log` 直接 re-export（L3 类型穿透桥），使 bridge_kernel 的门面职责被架空。
建议：确定唯一 L3 出口（要么 bootloader 改走 bridge_kernel.assembleKernel，要么删掉 bridge_kernel 的 log* 门面），避免两个桥并行导致能力分散；本次只记录事实，改法由主会话裁决。
76 合规：违反第 1/4 条（L3 能力未统一经桥暴露，kernel 类型经 bridge_boot 直接 re-export 穿透）。

---

## C2 · lib/bootloader/bootloader.dart:132-139 · P1 · 会话恢复失败被吞（启动「成功」但登录态丢失）
证据：
```dart
final auth = lg.AuthLogic(client: client, settings: settings);
try {
  final ok2 = auth.restoreSession();
  Log.d('boot', 'restoreSession ok=$ok2');
} catch (e, st) {
  Log.e('boot', 'restoreSession failed', e, st);
}
```
问题：`restoreSession` 自身也只 catch 后 `return false`（auth_logic.dart:217-220）。任何失败（settings.json 损坏、`getString` 异常、cookie 解析异常）都只进日志，启动流程继续走「成功」路径 → 用户看到的是「莫名其妙退出登录」，无任何提示，典型「catch 后只 log 不上抛 → 上层拿到成功但空的结果」。
建议：把 restore 结果（ok/失败原因）作为显式字段随 BootOutcome 上交（与 `BootResult.auth` 一起），由 surface 决定是否提示「会话恢复失败，请重新登录」；至少在 Log 级别升级为 W 并输出 userid 是否存在。
76 合规：违反第 2 条（失败必留痕且不得让上层误判为成功）；日志有留痕但语义上被吞。

---

## C2 · lib/bootloader/bootloader.dart:52,133 + lib/session/bootstrap.dart:101-105 · P1 · AuthLogic 双实例（L2 装配的 auth 被丢弃）
证据：
```dart
// bootloader.dart:52-53
/// 已 restoreSession 的 AuthLogic（会话 cookie 落在此 client.session 上）。
final lg.AuthLogic? auth;
```
```dart
// bootloader.dart:133 + session/bootstrap.dart:101-105
final auth = lg.AuthLogic(client: client, settings: settings);      // L2 装配并 restoreSession
final auth = step('AuthLogic', () => AuthLogic(client: client, settings: settings));  // L6 又 new 一个
```
问题：`BootResult.auth` 从未被 `main.dart` 消费（main 只取 7 个具名 dep），L2 装配并 `restoreSession()` 的 AuthLogic 构造完即被弃用，L6 session 又构造第二个 AuthLogic。当前两者共享同一 `client.session`（登录态实际写在 client 上），所以暂未出现「双实例互盲」；但只要 AuthLogic 自身持有任何实例字段（如 `_user`、`_isLoggedIn`），L6 的实例就会丢失 L2 恢复的会话——是典型的「多处分处构造同一依赖」的复发隐患（与 settings 历史双实例问题同型）。
建议：L2 不再构造 AuthLogic，或 L6 复用 L2 传下来的同一实例（把 `auth` 纳入 deps 传给 session），确保全进程只有一个 AuthLogic。
76 合规：符合第 8 条（不在 L6 放播放控制）；但违反「单实例装配」精神（L2/L6 重复构造同一 L5 依赖）。

---

## C2 · lib/bootloader/bootloader.dart:132 + lib/core/storage/settings_store.dart:29-44 · P2 · settings 单例成立但依赖构造器副作用登记（隐式契约）
证据：
```dart
// bootloader.dart:132
final settings = core.KeyValueSettings(paths);     // 不是 shared()
```
```dart
// settings_store.dart:41-44
KeyValueSettings(this._paths) : _file = _paths.fileIn('db','settings.json') {
  _sharedByPath[_file.path] ??= this;   // 构造副作用登记
}
```
问题：全库检索确认除 bootloader 外没有第二处 `new KeyValueSettings`，因此**当前不存在双实例互盲**（`shared()` 会命中 L2 这一份）。但该保证依赖「构造函数会把自己登记进 `_sharedByPath`」这一隐式副作用 + 「L2 恰好先构造」这一时序；若将来出现先 `shared()` 后 L2 `new` 的顺序，`??=` 仍保 L2 那份，但若路径键不同（rootDir 变化）即分叉。建议改为显式 `core.KeyValueSettings.shared(paths)`，把「单例」写进调用点而不是靠副作用。
76 合规：符合第 4 条（同层内引用合法）；单例语义目前成立，属脆弱实现。

---

## C2 · lib/init/main.dart:23-24,49 · P2 · `--bypass-integrity` / NEXT_DEBUG_BYPASS 为死参数
证据：
```dart
final debugBypass = args.contains('--bypass-integrity') || const bool.fromEnvironment('NEXT_DEBUG_BYPASS');
...
final Object? raw = runBoot(bypassIntegrity: debugBypass, rootDir: rootDir);
```
而 `bootloader.dart:69-73` 明确：运行期完整性校验已删除，`bypassIntegrity` 只被打印进日志（`Log.d('boot','bootstrap run (bypass=$bypassIntegrity)')`）。
问题：完整性校验已不存在，该开关无任何消费者；运维/开发按「带 flag 可跳过校验」理解会误判（flag 无效），同时它给「运行期有完整性校验」留下错误印象。
建议：删除该参数与 flag 解析，或在日志中明确标注 `bypassIntegrity` 已废弃（当前仅用于日志）。
76 合规：符合第 7 条方向（防篡改移交 CI）；属死代码/死参数。

---

## C2 · lib/init/main.dart:114 + 26-33 · P2 · bootstrapApp 在 try 外，异常时可能二次 runApp
证据：
```dart
// main.dart:114（在 _boot 内、try 之外）
bootstrapApp(outcome.dep('__raw'));
```
```dart
// main.dart:26-33
try { await _boot(...); } catch (e, st) { ... runApp(_BootErrorApp(message: '$e')); }
```
问题：`bootstrapApp` → `bridge_surface.bootstrapApp` → `surface/app_root.dart:93 runApp(const AppRoot())`。若 runApp 之后仍抛错（app_root 目前不会，但 bridge_surface 会 rethrow），main 的 catch 会**第二次** runApp，Flutter 直接抛 "runApp() called twice"，用户看到红屏而不是错误页。
建议：把 `bootstrapApp` 调用移入 main 的 try/catch 内，或在 main 加 `_appStarted` 标志位避免二次 runApp。
76 合规：符合第 2 条（桥失败 rethrow）；属 L1 兜底不足。

---

## C2 · lib/kernel/kernel.dart:7,13-19 · P2 · Log 缓冲只写不读（release 包内启动失败不可诊断）
证据：
```dart
static final _buf = <String>[];
static void _emit(String lvl, String tag, String msg) {
  final line = '${DateTime.now().toIso8601String()} $lvl/$tag: $msg';
  _buf.add(line);
  if (_buf.length > 2000) _buf.removeRange(0, 500);
  print(line);
}
```
问题：`_buf` 无任何读取/导出接口（全库无 `Log.` 的 dump/getter 调用），日志只经 `print` 写 stdout；release 构建下 stdout 不可见 → 启动期异常（含 `bootloader.dart:91` 的 core 装配异常）只能靠 logcat，App 内无「复制日志」路径。另外裁剪策略是「超过 2000 一次性删 500」，内存平稳但丢失最近上下文。
建议：给 Log 增加只读导出（`recentLogs()` / `dump()`）与文件落盘（写入 StoragePaths 的 logs 目录），供设置页「导出日志」与错误页展示。
76 合规：符合第 3 条（日志出口统一）；但缺「可取回」能力，削弱了「失败必留痕」的实际价值。

---

## C2 · lib/bridges/bridge_boot.dart:128-186 · P2 · 桥注册表用顶层可变变量，缺重复注册保护
证据：
```dart
dynamic Function({...})? _runBootImpl;
void setRunBootImpl(dynamic Function({...}) impl) {
  try { _runBootImpl = impl; k.Log.d('bridge_boot','runBoot impl installed'); }
  catch (e, st) { k.Log.e('bridge_boot','setRunBootImpl failed', e, st); }
}
```
问题：任何持有 bridge_boot 的层都能调用 `setRunBootImpl` 覆盖 L2 注册的实现（无 L2 所有权校验、无「已注册则拒绝重复注册」保护）；`setRunBootImpl` 内部 catch 后不重置为 null、也不上抛 → 注册失败时 `bootBridgeReady` 仍可能为 true（旧 impl 残留），`register.dart:22-24` 的 `if (!bootBridgeReady) throw` 检查形同虚设。
建议：`setRunBootImpl` 增加「已注册则抛错/拒绝」语义或加 owner token；失败时把 `_runBootImpl` 置 null。
76 合规：符合第 2 条（try/catch + Log）；注册契约偏弱。

---

## C2 · lib/bootloader/register.dart:13-27 · P2 · bootBridgeInstalled getter 无调用方（死链）
证据：
```dart
bool get bootBridgeInstalled => _BootBridgeInstallState.installed && bootBridgeReady;
void registerBootloader() { if (_BootBridgeInstallState.installed) return; ... }
```
问题：`bootBridgeInstalled` 全库无调用方；`registerBootloader()` 的幂等保护实际由 `_BootBridgeInstallState.installed` 承担（有效）。注册失败时 `registerBootloader` 抛 `StateError('boot bridge install failed: ...')`，被 `main.dart:31` 的 catch 接住并渲染错误页——这条失败路径正确。
建议：删除或接线 `bootBridgeInstalled`（如在启动日志中打印自检结果）。
76 合规：符合第 2 条（失败上抛、可见错误页）。

---

## C2 · lib/bootloader/bootloader.dart:101,122-129 · P1 · core 装配顺序依赖 StoragePaths.I 的全局单例
证据：
```dart
final paths = core.StoragePaths.init(rootDir ?? '.');      // 设置全局 _instance
...
final client = core.KugouClient(core.KugouSession(),
  cache: core.ResourceCache(rootDir: core.StoragePaths.I.cache(), namespace: 'net'),
  inflight: core.InFlight<Map<String, dynamic>>());
```
问题：`StoragePaths.init` 会**覆盖**全局 `_instance`（paths.dart:26-31），而本次装配里 `paths` 本地变量与 `StoragePaths.I` 并存使用；`init` 之后再由任何代码调用 `StoragePaths.init`（含热重启/测试）会让已装配的 client 缓存目录与 `paths.db()` 指向不同根，产生「一半旧路径一半新路径」的分裂（settings.json 键以绝对路径为 key，会分裂成两份设置）。当前全库仅 bootloader 一处调用 `init` ✓，但缺少「重复 init 的一致性」防护。
建议：`StoragePaths.init` 重复调用时若 root 不同应抛错或复用既有实例；bootloader 内统一使用本地 `paths`（不要混用 `StoragePaths.I`）。
76 合规：符合第 4 条（同层内引用合法）；单例一致性依赖调用点唯一，属脆弱设计。

---

## C2 · lib/session/bootstrap.dart:216-232 + lib/surface/pages/mv_page.dart:12-20 · P0 · MV 功能不可达：启动期占位模块抢占 id，导致真实 MV 模块永不注册（功能可达性·MV）
证据：
```dart
// session/bootstrap.dart:216-232（启动期，L6 先跑）
const moduleIds = <String>['home','search','playlist','library','settings','player','lyrics','comment','mv','album','artist'];
for (final id in moduleIds) { ModuleRegistry.instance.install(_PlaceholderModule(id)); }
```
```dart
// surface/pages/mv_page.dart:12-20（L7 随后注册真实模块）
void registerMvModule() {
  final reg = ModuleRegistry.instance;
  if (reg.byId('mv') != null) return;   // ← 占位模块已占用 'mv'，直接 return
  reg.install(MvPageModule());
}
```
```dart
// surface/shell.dart:22-30（registerModules 中调用 registerMvModule）
reg..install(HomePageModule())..install(SearchPageModule())..install(PlaylistPageModule())
   ..install(LibraryPageModule())..install(SettingsPageModule())..install(PlayerPageModule())
   ..install(LyricsPageModule());
registerMvModule();
```
问题：装配顺序是 `bridge_surface.installServices` → 先 `session.bootstrapSession`（装 11 个占位模块）→ 再 `surface.installServices` → `registerModules()`。占位模块 id 与真实模块 id 同名，而 `registerMvModule` 的幂等保护是「id 已存在就 return」——占位模块已存在 → **真实 MvPageModule 永远不会被安装**。结果：`ModuleRegistry.byId('mv')` 返回占位模块（`enabled=false`、`builder=null`），shell 渲染分支 `(current.builder as WidgetBuilder?)?.call(context) ?? const Center(child: Text('模块未提供页面'))` 会显示「模块未提供页面」；player_page.dart:192 的 `registerMvModule()` 同样因该守卫而空转 → 用户点 MV 入口得到空页/无反应，正是「MV 用不了」的启动期成因。其余模块（home/search/...）用无条件 `install` 覆盖，所以只有 MV 受影响。
建议：把幂等判定从「id 存在」改为「id 存在且已是真实实现」（例如用 `is PlaceholderModule` 判定或引入 `enabled`/builder 非空判定），让真实模块覆盖占位；或启动期不要装占位模块，改为「L6 只声明期望 id，L7 注册时再填充」。
76 合规：违反第 8 条「L6 只暴露状态/回调」的边界（占位模块是 L6 侧 UI 占位实现），并直接导致 MV 功能不可达。

---

## C2 · lib/surface/pages/mv_page.dart:30-32 · P1 · MV 模块 builder 硬编码空 songHash（即使注册成功也查不到内容）
证据：
```dart
@override
WidgetBuilder? get builder => (_) => const MvPage(songHash: '');
```
问题：模块 builder 无参数通道，songHash 恒为空串 → MV 查询键为空 → 恒空结果；用户点 MV 入口即使打开了页面也拿不到 MV 列表。`MvPage` 本身要求 `songHash`（`const MvPage({required this.songHash})`），说明真实入口应是「带当前曲 hash 打开 MV 页」，但模块级 builder 无法携带运行时参数。
建议：MV 不应作为「模块」注册，而应作为「带参路由/弹层」由播放页直接 `Navigator.push(MvPage(songHash: currentHash))`；`MvPageModule` 若保留，builder 需从当前播放会话取 hash。
76 合规：符合第 8 条（L7 只画控件）；属功能可达性缺陷。

---

## C2 · lib/session/bootstrap.dart:200-215 + lib/core/cache/cache_service.dart:113-128 · P1 · 启动期预读未 await 且异常被吞（启动「成功」但缓存全空）
证据：
```dart
// session/bootstrap.dart（bootstrapSession 内）
cacheService.prefetch(<({Endpoint ep, Map<String, Object?> params})>[
  (ep: EndpointRegistry.searchHot, params: {...}),
  (ep: EndpointRegistry.rankList, params: {}),
]);      // ← 未 await、未 .catchError
```
```dart
// core/cache/cache_service.dart:113-128
Future<Map<String, dynamic>> get(...) async {
  try { return await _client.request(ep, params, body: body); }
  catch (e, st) { _errors++; Log.e(_tag,'get failed ep=${ep.id}',e,st); return <String, dynamic>{}; }
}
```
问题：启动期预读 fire-and-forget；`CacheService.get` 失败时返回空 Map 而非抛错（典型「成功但空」），因此预读失败对上层完全不可见——首屏热搜/榜单可能空白且无任何错误提示，只能靠 logcat。
建议：预读结果纳入启动 outcome（成功数/失败端点），或至少在首屏数据源不可用时由 surface 显示可重试的错误态而非空态。
76 合规：符合第 2 条（catch + Log）；但属「异常吞没导致上层拿到成功但空」。

---

## C2 · lib/session/bootstrap.dart:216-232 · P2 · comment / album / artist 三个 id 永远停留在占位模块
证据：
```dart
const moduleIds = <String>['home','search','playlist','library','settings','player','lyrics','comment','mv','album','artist'];
for (final id in moduleIds) { ModuleRegistry.instance.install(_PlaceholderModule(id)); }
```
问题：`lib/surface/pages/` 下不存在 comment/album/artist 页面文件（目录实测只有 home/library/login/lyrics/mv/player/playlist/search/settings 系列），`registerModules()` 也只覆盖 7 个 id；这三个 id 的占位模块 `enabled=false`、`builder=null`，`appGraph.modules` 却仍把它们计入 `modules.length`（AppGraph.isReady 只判 `modules.isNotEmpty`）→ 「模块数=11」与真实可用页面不符，掩盖了 3 个功能未实现的事实。
建议：占位 id 列表与 L7 实际注册 id 对齐，或在 AppGraph 中区分「已实现 / 占位」，避免用 modules.length 冒充就绪度。
76 合规：符合第 8 条（L6 不画控件）；占位实现与实现声明不一致，属可达性缺口（跨层观察，A6/A7 复核）。

---

## C2 · lib/init/main.dart:114 + lib/surface/app_root.dart:92-94 · P2 · '__raw' 管线为空操作（BootResult 被整包丢弃）
证据：
```dart
// main.dart:114
bootstrapApp(outcome.dep('__raw'));
```
```dart
// surface/app_root.dart:92-94
void bootstrapApp(dynamic result) { runApp(const AppRoot()); }
```
问题：bridge_boot 为 '__raw' 专门保留了一个键、bootloader 为此写了注释与透传逻辑，但最终消费方完全忽略入参 → `result` 形参是死参数，BootResult 中仍存活的 `auth` 字段（已 restoreSession 的 AuthLogic）随管线被丢弃，两端都没有实际消费者。
建议：要么让 bootstrapApp 真正消费 bootResult（例如据此决定是否需要登录引导页），要么删掉 '__raw' 与 `BootResult.auth` 这条死链。
76 合规：符合第 2 条；属死代码/死参数。

---

## C2 · lib/init/main.dart:41-47 · P2 · 存储根目录失败时回落 '.'（相对路径），生产环境可能写错位置
证据：
```dart
String? rootDir;
try { rootDir = (await getApplicationSupportDirectory()).path; }
catch (e, st) { debugPrint('main: path_provider failed, fallback relative root: $e/$st'); }
```
问题：`getApplicationSupportDirectory()` 失败（罕见）时回落 `'.'`（bootloader.dart:101 `core.StoragePaths.init(rootDir ?? '.')`），相对路径在 Android 上解析为进程工作目录 → settings.json / Isar / 下载缓存可能落到不可写或非预期位置，且日志只有 debugPrint，release 下不可见。
建议：回落路径应视为启动失败（走错误页），或至少标记 `rootDirFallback=true` 并在错误页/日志中明确告警；生产构建禁用相对根。
76 合规：符合第 1 条（L1 特例取 path_provider）；失败兜底策略不当。

---

## 本视角结论
1. **P0：boot 失败分支被误判为成功。** `bridge_boot.fromAny` 的非 Map 分支硬编码 `BootOutcome._(false, ...)`（bridge_boot.dart:65-79），而 `bootloader.dart:92` 的失败返回正是 `BootResult(rejected: true)`（非 Map）→ `outcome.rejected` 永远 false，真实异常原因不上抛，main 最终显示误导性的「核心模块缺失」。
2. **P0：DB 未就绪不 fail-fast。** `main.dart:90-93` 的 `if (dbFuture is Future<bool>)` 静默跳过 await，且 `dbOpenFuture` 不在 `requiredDeps` 内；一旦 dbFuture 缺失（legacy 归一化分支 bridge_boot.dart:94-100），DAO 首访 `DatabaseService.isar` 抛 StateError（db.dart:29-37）发生在启动 try 之外 → 首屏崩溃而非错误页。
3. **P0：MV 功能不可达（启动期顺序缺陷）。** L6 启动时先装 11 个占位模块（session/bootstrap.dart:216-232），L7 的 `registerMvModule()` 用「id 已存在就 return」作幂等保护（mv_page.dart:12-20）→ 真实 MvPageModule 永不注册，MV 入口只能落到「模块未提供页面」；且其 builder 硬编码 `songHash: ''`（mv_page.dart:30-32），即使注册也查不到内容。这是「MV 用不了」在启动链路上的直接成因。
4. **P1：L3 kernel 是空壳。** `kernel.dart` 只有日志与空 `KernelContext`，无 onStart/onResume/onPause/onStop、无模块注册表；`bridge_kernel.assembleKernel` 兜底返回空上下文（「成功但空」）；`BootResult.kernel` 无任何消费者；`bridge_kernel` 的 logD/logW/logE/assembleKernel 全库零调用（死链）。76 原则第 3 条未落地。
5. **P1：异常吞没集中在三处** —— boot 的 restoreSession 失败（bootloader.dart:134-139）、bridge_kernel 的空上下文兜底、启动期未 await 的 prefetch + `CacheService.get` 返回空 Map（cache_service.dart:113-128）；三者都让上层拿到「成功但空」。
6. **P1：单例一致性目前成立但脆弱。** client / DAO / settings / paths / DatabaseService 全库各只有一处构造 ✓；settings 靠构造器副作用登记进 `_sharedByPath`（settings_store.dart:41-44）才保证不双实例；AuthLogic 却在 L2 与 L6 各 new 一个（bootloader.dart:133 / session/bootstrap.dart:101），当前因共享 client.session 未爆，但已具备历史「双实例互盲」同型隐患。
7. **P2 杂项**：bypass-integrity 死参数；bootstrapApp 可能二次 runApp；Log._buf 只写不读（release 不可诊断）；setRunBootImpl 无重复注册保护；bootBridgeInstalled 死 getter；'__raw' 空操作；rootDir 回落相对路径；comment/album/artist 三个 id 永远停在占位模块而 `modules.length` 仍计 11。
8. 启动竞态方面**已确认修复有效**的部分：DB 打开 Future 确实随 BootOutcome 上交并被 main await（bootloader.dart:88 / bridge_boot.dart:79 / main.dart:90-93），DAO 构造本身不触碰 Isar（dao.dart:24 仅 getter 惰性取 `DatabaseService.isar`），`StoragePaths.init` 先于 `StoragePaths.I.cache()` 执行（bootloader.dart:101 vs 122-129），DB 目录由 `paths.db()` 懒创建 ✓。

## 未覆盖
- 未覆盖 MV 功能本身的业务链路（L5 mv_logic / L4 mv_endpoints / L7 mv_page 内部播放实现），仅覆盖启动期「模块注册」这一环；MV 端点三态（匿名/VIP/画质）未验证。
- 未覆盖 L4 core 的 DB/缓存/网络内部正确性（Isar schema 迁移、ResourceCache 落盘键、endpoint 签名），仅确认启动期契约（open 是否 await、单例、构造是否抛）。
- 未覆盖 bridge_core / bridge_logic / bridge_session / bridge_surface 四个桥的内部实现，仅读 bridge_surface 与 bridge_core 的导出清单用于确认签名与顺序。
- 未覆盖 L7 surface 的 UI/动效/文案（属 A7），本视角只记录与启动装配直接相关的模块注册死链。
- 未做编译/分析器/测试验证（契约禁止），所有结论基于静态阅读。
- 未审 `docs/` 内其他审计报告，故不引用他人结论，避免交叉污染。

## 76 合规小结
- 第 1 条（跨层必须走桥）：**符合**。L1→L2 经 bridge_boot，L2→L3/L4 经 bridge_boot/bridge_core，未见本批文件直接 import 越层非桥文件（kernel.dart 为 L3 本体，合法）。
- 第 2 条（桥函数 try/catch + Log 留痕，不静默吞）：**部分违反**。bridge_boot/bridge_kernel 均有 try/catch + Log，但多处「失败 → 返回空/默认值」构成静默吞（bridge_kernel.assembleKernel 返回空 KernelContext、bootloader 的 restoreSession 失败继续、fromAny 把 rejected 抹成 false）。
- 第 3 条（L3 kernel：生命周期编排、日志、盐值校验执行）：**违反**。kernel 无任何生命周期方法与模块注册表，仅有日志；无盐值校验执行。
- 第 4 条（同层引用合法，反向依赖禁止）：**符合**，但 L3 能力存在两个出口（bridge_boot re-export kernel.Log/KernelContext 与 bridge_kernel），门面不唯一。
- 第 6 条（端点一模块、只连官方域名）：**本批不适用**（A1 无端点文件）。
- 第 8 条（播放控制/缓存/预读/装配图不得放 L6）：**符合**（bootloader 装配 core，session 只做编排）；但 L6 的 `_PlaceholderModule` 是 UI 侧占位实现，且与 L7 真实模块同 id 造成抢占。
- 第 10 条（子代理只读）：**符合**。全程只用 file_read / rg / ls（cat 仅用于已列明只读文件），未改动任何源码，唯一写入为本报告文件。
