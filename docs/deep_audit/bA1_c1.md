# bA1_c1.md · A1 批 · 视角 C1（架构合规 / 76 原则）

审查范围：lib/init/main.dart、lib/bootloader/bootloader.dart、lib/bootloader/register.dart、lib/kernel/kernel.dart、lib/bridges/bridge_boot.dart、lib/bridges/bridge_kernel.dart
只读扩展：lib/bridges/{bridge_core,bridge_logic,bridge_session,bridge_surface}.dart、lib/session/{graph,bootstrap}.dart（仅用于建立 import 依赖图与层归属确认）
权威契约：docs/DEEP_AUDIT_14_BATCH_PLAN.md §0、docs/SEVEN_SIX_RULE.md

---

## 视角 C1 · lib/init/main.dart:18 · P1 · 跨层越级 import（L1 → bridge_surface）

证据：
```dart
// lib/init/main.dart:18-19
import '../bridges/bridge_surface.dart'
    show SurfaceDeps, bootstrapApp, installServices, spLightThemeData;
```
`bridge_surface` 按 docs/SEVEN_SIX_RULE.md §2 定义为 **L6↔L7** 桥；L1 直接经它取 `SurfaceDeps/installServices/bootstrapApp`（L6/L7 装配物），跨过 L2–L6 共 5 层。项目自有门禁把该越级**显式放行**：`tool/layer_audit.py:33` → `1: {'bridge_boot', 'bridge_surface'}`，`tool/smoke_check.dart:172` 同值（注释自称「显式白名单，新增越级必须注明理由」，但此处未写理由，也未登记进 `LAYER_EXCEPTIONS`（layer_audit.py:45-47 只登记了 `init/main.dart → bootloader/register.dart`）。

问题：L1 init 的依赖面直达 L6/L7 装配入口，破坏「相邻层各一桥、每层只依赖其下层门面」的铁律 4，且绕过 L2→L6 的正规通道（L2 BootResult → L1 → bridge_surface → session.bootstrapSession）。

建议：把 surface 装配入口下沉到 `bridge_boot`（如 `runBoot` 返回后由 `bridge_boot.installSurface(deps)` 或 L1 只调 `bridge_boot` 新增的 `bootstrapSurface`），或若坚持现状，则在 `tool/layer_audit.py:LAYER_EXCEPTIONS` 显式登记 `('init/main.dart','bridges/bridge_surface.dart')` 并写明理由（与既有 register 例外并列），使越级可追溯。

76 合规：违反铁律 4（每层只依赖其下层经桥暴露的门面）+ 铁律 1（相邻层桥）；同时**符合** §1「L1 = main / runBoot 触发 / 错误页」——main.dart 内不含业务逻辑，仅完整性校验与装配触发。

---

## 视角 C1 · lib/bootloader/bootloader.dart:11-14 · P1 · L2↔L3 通道错配（未走 bridge_kernel）

证据：
```dart
// lib/bootloader/bootloader.dart:11-14
import '../bridges/bridge_boot.dart' as bb;
import '../bridges/bridge_boot.dart' show KernelContext, Log;   // ← 日志与 kernel 类型经 L1↔L2 桥取得
import '../bridges/bridge_core.dart' as core;
import '../bridges/bridge_logic.dart' as lg;
```
全仓检索：**`lib/bootloader/` 下无任何 `import '../bridges/bridge_kernel.dart'`**。L2 的日志出口是 `bridge_boot`（L1↔L2 桥）转出的 `Log`（bootloader.dart:69, 102, 107, 111, 115, 136, 138 全用它），而 `bridge_kernel`（唯一合法的 L2↔L3 通道，SEVEN_SIX §2「bridge_kernel | L2↔L3 | Log」）在 bootloader 里**完全没被引用**。后果：L2→L3 的实际数据路径是 `bootloader → bridge_boot → kernel`，把 L1↔L2 的桥当成了 L2↔L3 的通道，bridge_kernel 被架空。

问题：L2 与 L3 之间的合法唯一通道 bridge_kernel 在启动序列中未被使用，kernel 能力经错误桥取得。

建议：bootloader.dart 改为 `import '../bridges/bridge_kernel.dart' show Log, assembleKernel;`，把 `bb.BootBridge.assemble()` 换成 `assembleKernel()`；`bridge_boot` 只保留 `KernelContext` 类型导出或干脆由 bridge_kernel 独家导出。

76 合规：违反铁律 1/4（相邻层唯一桥通道）与 §1「bridge_kernel = L2↔L3」；**符合**铁律 3（桥文件唯一在 lib/bridges/）。

---

## 视角 C1 · lib/bridges/bridge_boot.dart:5,7 · P1 · 桥越界暴露非相邻下层（re-export kernel）+ kernel 双通道

证据：
```dart
// lib/bridges/bridge_boot.dart:5,7
import '../kernel/kernel.dart' as k;
export '../kernel/kernel.dart' show Kernel, KernelContext, Log;
```
`bridge_boot` 是 L1↔L2 桥，却直接 import 并 **re-export L3 kernel 的 Log / Kernel / KernelContext**；于是 L1 只要 `import bridge_boot` 就能拿到 L3 的日志与内核 API，完全绕过 bridge_kernel。同型扩散存在于其余桥：`bridge_logic.dart:7`、`bridge_session.dart:7`、`bridge_surface.dart:6` 均 `import '../kernel/kernel.dart' show Log;`（即 kernel 的日志出口从 bridge_kernel 扩散到 5 座桥）。

问题：kernel 作为 L3 的门面被 5 座桥各自直连，bridge_kernel 的「唯一 L3 出口」名存实亡；L1 亦可经 bridge_boot 直接调 L3。

建议：把 `Log` 的唯一 re-export 收敛到 `bridge_kernel`；其余桥需要留痕时改为 import `bridge_kernel`（同层桥之间互引是否允许需在 §2 补一句，或由 kernel 侧提供纯 `dart:developer`/`print` 注入）。至少把 bridge_boot 的 kernel re-export 去掉，只留 `BootOutcome` 等本层契约。

76 合规：违反铁律 4（桥只暴露其下层门面）+ §2 桥邻接表（bridge_boot=L1↔L2）；**符合**铁律 2（每个桥函数 try/catch + Log 留痕，见下）。

---

## 视角 C1 · lib/bridges/bridge_kernel.dart:51-56 · P1 · 死代码 + kernel 装配双实现

证据：
```dart
// lib/bridges/bridge_kernel.dart:51-56
KernelContext assembleKernel() {
  try { return Kernel.assemble(); }
  catch (e, st) { _bridgeLog('E', 'assembleKernel', e, st); return const KernelContext(modules: {}); }
}
```
全仓检索 `assembleKernel`：**只有定义处一个命中，零调用者**。bootloader 走的是 `bb.BootBridge.assemble()`（bootloader.dart:73 → bridge_boot.dart:13-21，直接调 `k.Kernel.assemble()`）。于是同一个「kernel 装配」动作在两座桥里各实现一次，且真正该用的那座没人用。

问题：bridge_kernel 沦为空壳；kernel 装配入口二义。

建议：删 `bridge_kernel.assembleKernel` 或改由 bootloader 唯一调用它，并删 `bridge_boot.BootBridge.assemble`（避免同一能力两个入口）。

76 合规：违反铁律 3 的精神（桥的唯一性/唯一通道）与 §2 桥邻接表（bootloader→bridge_kernel）；**符合**铁律 2（assembleKernel 有 try/catch + 留痕）。

---

## 视角 C1 · lib/bridges/bridge_kernel.dart:51-56 · P2 · 桥失败静默降级为「空上下文」

证据：`catch → return const KernelContext(modules: {})`，无 error 标志、无异常上抛。
问题：调用方无法区分「装配成功但无模块」与「装配失败」，属铁律 2「不静默吞」的边缘形态（虽已 `_bridgeLog` 留痕，但语义降级无显式信号）。
建议：失败时抛 `StateError('assembleKernel failed: $e')` 或返回带 `failed: true` 标志的结果对象。

76 合规：违反铁律 2（失败必须显式暴露，语义默认值不得掩盖失败）；**符合**「失败必 Log 留痕」部分。

---

## 视角 C1 · lib/bootloader/bootloader.dart:101 · P2 · 依赖装配静默降级（rootDir 兜底 '.' 无告警）

证据：
```dart
// lib/bootloader/bootloader.dart:101-102
final paths = core.StoragePaths.init(rootDir ?? '.');
Log.d('boot', 'storage root=${paths.rootDir.path}');
```
`rootDir` 为空时（main.dart:42-46 path_provider 失败 → rootDir=null）落回相对目录 `'.'`，仅用 `Log.d` 记录，无 `Log.w`，release 包里等于把 DB/缓存写进进程 CWD。
问题：存储根解析失败在 release 下静默降级到错误目录，仅 debug 级别日志。
建议：`rootDir == null` 时 `Log.w('boot','rootDir missing, fallback to "." (debug only)')` 并在非 debug 下抛错让 L1 走错误页。

76 合规：违反铁律 2（失败须留痕且不静默降级）；**符合** §1「L2 = core/logic 单例装配、DB await」与「L2 禁 flutter」（bootloader 全文件无 flutter/BuildContext/Widget，仅 `dart:async`）。

---

## 视角 C1 · lib/bootloader/bootloader.dart:108-118 + lib/init/main.dart:89-94 · 合规确认（附 P2 提示） · P2 · 启动序列 DB await

证据：
```dart
// bootloader.dart:108-118  —— 不再 unawaited，Future 随 BootResult 上交
final Future<bool> dbOpenFuture = core.openDatabase(paths.db().path) ...
// main.dart:89-94
final dbFuture = deps['dbOpenFuture'];
if (dbFuture is Future<bool>) { await dbFuture; debugPrint('main: db ready'); }
```
问题（提示级）：DB 打开失败时 `catchError` 抛 `StateError('db open failed: $e')`，该异常在 main.dart:95-107 的 `installServices` try 块里被捕获，文案统一报成「装配失败」，DB 与装配两类故障无法区分；另外 `BootResult.rejected` 在 DB 未成功时仍是 false，失败只在 await 点暴露。
建议：DB future 失败单独 catch，报「数据库打开失败：…」并置 rejected 语义。

76 合规：**符合** §1「L2 = DB await」与铁律 1（历史 unawaited 竞态已修，deps 键 'dbOpenFuture' 经 bridge_boot.dart:88 `_readDbOpenFuture` 动态读取并保留）。

---

## 视角 C1 · lib/bootloader/bootloader.dart:132-138 · 合规确认 · 单例装配（settings 双实例 bug 已修）

证据：
```dart
final settings = core.KeyValueSettings(paths);      // 唯一实例
final auth = lg.AuthLogic(client: client, settings: settings);
try { final ok2 = auth.restoreSession(); ... }
```
该 `settings` 同时进 `_assembleCore` 返回 map（'settings' → 同一对象），经 `BootOutcome.deps['settings']` → main.dart:96 `SurfaceDeps(settings: outcome.dep('settings'))` → `session/bootstrap.dart` 复用同一实例（session/bootstrap.dart:99 `AuthLogic(client: client, settings: settings)`），未再 new 第二份 → L2 写入、L6 读取共享同一内存缓存。

76 合规：**符合**铁律 4（依赖经桥门面传递）、§1「L2 = core/logic 单例装配」；**符合**历史 bug「settings 双实例互盲」已修复。

---

## 视角 C1 · lib/bridges/bridge_boot.dart:70-92 + lib/session/bootstrap.dart:99 · P2 · BootOutcome 归一化丢键 → BootResult.auth 死字段 + 双 AuthLogic 实例

证据：
```dart
// bridge_boot.dart:70-92（成功路径 deps 只搬运这些键，无 'auth'）
'client': d.client, 'songDao': d.songDao, ..., 'paths': d.paths,
'dbOpenFuture': _readDbOpenFuture(any), '__raw': any,
```
`BootResult.auth`（bootloader.dart:53 `final lg.AuthLogic? auth;`、:86 `auth: coreSet['auth'] as lg.AuthLogic?`）经 `fromAny` 后**不在 deps 里**，L1/main 也从未取用 → 该字段及其 `restoreSession` 成果无处消费；随后 L6 在 `lib/session/bootstrap.dart:99` 又 `AuthLogic(client: client, settings: settings)` 新建第二个 AuthLogic 实例（虽共享同一 `client.session` 与同一 settings，cookie 不丢，但 L2 已 restoreSession 的那个对象被丢弃，实例与语义割裂）。

问题：L2 装配的 AuthLogic 单例被桥归一化层丢弃，L6 出现第二个 AuthLogic 实例。

建议：`fromAny` 的成功路径补 `'auth': _readField(any,'auth')`，并让 L6 bootstrap 接受已装配的 AuthLogic（或由 L2 传 auth 取代重复 new），保证「单例」语义贯穿。

76 合规：违反铁律 4（经桥暴露的门面应完整传递，丢键即门面残缺）与 §1「L2 = core/logic 单例装配」；**符合**铁律 2（fromAny 有 try/catch + Log）。

---

## 视角 C1 · lib/bridges/bridge_boot.dart:40-92 · P2 · 桥用 dynamic duck typing 读 L2 私有字段

证据：`final d = any as dynamic; return BootOutcome._(false,'','', {'client': d.client, ...})` + `_readDbOpenFuture` 内 `(any as dynamic).dbOpenFuture`。
问题：桥不得反向 import L2，于是靠动态字段名耦合；L2 字段一旦改名，桥静默产出 null（当前有 L1 兜底：main.dart:78-86 判 missing → 错误页）。
建议：给 L2 的 BootResult 加稳定的 `Map<String,Object?> toDeps()` 契约（或在 L2 侧即产出 Map），桥只读 Map，彻底去掉 dynamic 字段探测。

76 合规：**符合**铁律 1（桥不反向 import L2）；但以「dynamic 探测」替代类型化契约，与「消除 duck typing」的注释目标（bridge_boot.dart:20-21 自述）不一致。

---

## 视角 C1 · lib/init/main.dart:49-52 · P2 · 死分支

证据：
```dart
final Object? raw = runBoot(bypassIntegrity: debugBypass, rootDir: rootDir);
final BootOutcome outcome = raw is BootOutcome ? raw : BootOutcome.fromAny(raw);
```
`runBoot` 的静态返回类型就是 `BootOutcome`（bridge_boot.dart:130-145），`raw is BootOutcome` 恒真，`else` 分支不可达。
问题：冗余死分支，掩盖「归一化只发生一次」的真实契约。
建议：直接 `final outcome = runBoot(...)`。

76 合规：**符合**铁律 2（runBoot 内部 try/catch + Log，失败返回 bootFailure 归一化形状）。

---

## 视角 C1 · lib/kernel/kernel.dart:5-34 · P2 · L3 占位未接线（模块表恒空 / 日志缓冲只写不读 / get<T> 必抛）

证据：
```dart
static final _buf = <String>[];                 // 只 add，无任何读取接口
...
class KernelContext { final Map<Type,Object> modules; T get<T extends Object>() => modules[T] as T; }
static KernelContext assemble() { ...; return KernelContext(modules: const {}); }
```
问题：① `Log._buf` 环形缓冲（>2000 截断 500）无读取方，等于死存储；② `Kernel.assemble()` 恒返回空模块表，L3「生命周期编排、模块注册表」职责为空实现；③ `KernelContext.get<T>()` 对任何 T 都会因 null cast 抛错，无调用者也无防御；④ 全仓 `KernelContext` 除桥转发外无消费者。
建议：`_buf` 增 `static List<String> dump()` 或删除；模块表至少接入真实模块注册；`get<T>` 增 `T? tryGet<T>()`。

76 合规：违反 §1「L3 = 生命周期编排 / 模块注册表」职责定义（实现为空壳）；**符合**「L3 不得碰 UI」（kernel.dart 无任何 flutter import / Widget / BuildContext）。

---

## 视角 C1 · lib/bootloader/register.dart:13-14 · P2 · 公开符号无消费者

证据：`bool get bootBridgeInstalled => _BootBridgeInstallState.installed && bootBridgeReady;` —— 全仓检索仅定义处命中，无调用者。
问题：公开 getter 无人使用（register 自身已用 `bootBridgeReady` 自检）。
建议：删除或改为私有，或让 L1 启动日志打印一次。

76 合规：**符合**铁律 3（桥安装入口唯一在 lib/bootloader/，无影子注册点）。

---

## 视角 C1 · lib/bootloader/register.dart:16-27 · P2 · 失败无 Log 留痕

证据：
```dart
try { installBootBridge(); } catch (e, st) { throw StateError('boot bridge install failed: $e\n$st'); }
if (!bootBridgeReady) { throw StateError('boot bridge install failed: impl not registered'); }
```
问题：注册失败只抛异常，不经任何桥 Log 留痕（异常最终被 main.dart:31 的 debugPrint 兜住，但 kernel 日志系统里没有记录）。
建议：捕获后先经 `bridge_boot`/kernel Log 记 E 级再抛。

76 合规：违反铁律 2（失败必 Log 留痕，虽本文件非桥，但属启动关键路径）；**符合**「不静默吞」（异常上抛，最终落到 L1 错误页）。

---

## 视角 C1 · lib/init/main.dart:48 + tool/layer_audit.py:46 · 合规确认 · 例外登记仍在使用且合理

证据：`main.dart:48 registerBootloader();`；`tool/layer_audit.py:45-47` → `LAYER_EXCEPTIONS = {('init/main.dart','bootloader/register.dart')}`；SEVEN_SIX_RULE.md §1「允许登记例外：init/main.dart → bootloader/register.dart（语言层装配必需）」。
问题：无。该例外被真实使用（唯一调用点 main.dart:48），且 register.dart 只做「装桥 + 零副作用自检」，不含业务、不反向 import L3/L4。
建议：保留；在 §1 例外清单旁补一句「仍生效，调用点 init/main.dart:48」。

76 合规：**符合** §1 例外登记条款 + 铁律 3（注册点唯一）。

---

## 视角 C1 · 全仓只读 ls/rg · 合规确认 · 无影子桥

证据：`rg --files | rg -i 'bridge|adapter|gateway|facade'` 命中仅 6 个 `lib/bridges/bridge_*.dart` 与 `lib/core/audio/{audio_gateway,notification_gateway}.dart`（L4 内部的音频引擎适配，非跨层桥）；`ls -d lib/*/` 仅 bootloader/bridges/core/init/kernel/l10n/logic/session/surface 九个目录，无 `lib/bridge/`、`lib/adapter/`、`lib/gateway/` 等影子目录。
问题：无影子桥。
76 合规：**符合**铁律 3（桥文件唯一存在于 lib/bridges/）。

---

## 视角 C1 · lib/bootloader/bootloader.dart:13-14 · P2 · L2 直取 L5 能力（跨 3 层，经桥但非相邻）

证据：`import '../bridges/bridge_core.dart' as core;`（L2→L4 门面）、`import '../bridges/bridge_logic.dart' as lg;`（L2→L5 门面）。门禁白名单明确允许（tool/layer_audit.py:34 `2: {'bridge_boot','bridge_kernel','bridge_core','bridge_logic'}`），但 SEVEN_SIX §2 定义 bridge_logic 为 L4↔L5、bridge_core 为 L3↔L4。
问题：L2 跳过 L3 直取 L5 的 AuthLogic，架构上 L2 只应组装 L3 提供的「已就绪能力」，否则 L3 的编排职责被架空（与上条 bridge_kernel 被架空同源）。
建议：要么把 L2 的 core/logic 组装下沉到 bridge_kernel 背后的 L3 编排，要么在 §2 明确写「bridge_core/bridge_logic 供上层经白名单复用」（该说法仅出现在文档表格备注，契约正文未定义白名单机制）。

76 合规：符合铁律 1（跨层经桥，未直接 import 非桥文件）；**不符合** §1「bridge 相邻关系（L2↔L3）」的相邻性精神。

---

## 视角 C1 · 桥 try/catch + Log 逐函数核查表 · 合规确认（含 2 处 P2）

证据（bridge_boot.dart 全部公开函数）：
| 函数 | 行 | try/catch | Log | 结论 |
|---|---|---|---|---|
| `BootBridge.assemble` | 12-21 | ✔ | `k.Log.e` | 合规 |
| `BootOutcome.fromAny` | 47-92 | ✔ | `k.Log.e` | 合规 |
| `BootOutcome._readDbOpenFuture` | 95-101 | ✔ | `k.Log.d` | 合规（降级为 d 级，属 legacy 兼容路径） |
| `bootFailure` | 108-113 | 无（纯 Map 构造，无可失败操作） | — | 合规 |
| `runBoot` | 117-137 | ✔ | `k.Log.e` | 合规 |
| `setRunBootImpl` | 146-160 | ✔ | `k.Log.e` / `k.Log.d` | 合规 |
| `bootBridgeReady` | 164 | 无（纯判空） | — | 合规 |
| `runBootImpl` | 166-187 | ✔ | `k.Log.e` | 合规（失败以返回值 bootFailure 表达） |

证据（bridge_kernel.dart 全部公开函数）：
| `logD` | 26-32 | ✔ | `Log.d` + `_bridgeLog` 兜底 | 合规 |
| `logW` | 34-40 | ✔ | 同上 | 合规 |
| `logE` | 42-48 | ✔ | 同上 | 合规 |
| `assembleKernel` | 51-56 | ✔ | `_bridgeLog` | 见上条 P2（失败静默降级为空上下文）+ P1（零调用者） |

问题：无静默吞异常者（桥内 catch 全部留痕或显式降级并告警）；唯一例外是 bridge_kernel 的 `assembleKernel` 把失败降级为「空上下文」而无错误标志（已在 P2 条目单列）。
建议：见上；`_bridgeLog` 的兜底 catch（bridge_kernel.dart:22-24 注释「静默终止」）可接受，属防递归的合理例外。

76 合规：**符合**铁律 2（每个桥函数 try/catch + 失败 Log 留痕，无静默吞）。

---

## 视角 C1 · 层归属逐文件判定 · 合规确认

证据：
- `lib/init/main.dart`：仅 `package:flutter/material.dart`、`path_provider`（L1 特例，已在 layer_audit.py:49-50 的 L1_EXTRA 登记）+ 3 个 import：`../bridges/bridge_boot.dart`、`../bootloader/register.dart`（已登记例外）、`../bridges/bridge_surface.dart`（见 P1）。文件内是完整性校验（requiredDeps）+ 装配触发 + 错误页 Widget，**无业务逻辑**（无 endpoint、无 DAO 查询、无播放/登录逻辑）。
- `lib/bootloader/bootloader.dart`：无 flutter import、无 Widget/BuildContext（`rg "flutter|Widget|BuildContext"` 全文仅 :61 注释里出现「禁 flutter」字样）；只做 core/logic 单例装配 + DB future 上交 + 桥 impl 注册。
- `lib/bootloader/register.dart`：只做桥安装 + 自检，无业务。
- `lib/kernel/kernel.dart`：无 flutter import，只有 Log/KernelContext/Kernel 三个纯 Dart 类。

76 合规：**符合** §1「L1 = main/runBoot 触发/错误页」「L2 不得持有 Widget」「L3 = Log/生命周期，不得碰 UI」三条职责定义；**不符合** §1 中「L3 = 生命周期编排、模块注册表」的实质实现（见 kernel 空壳 P2 条）。

---

## 本视角结论

1. **无影子桥**：全仓仅 `lib/bridges/` 下 6 座桥，`core/audio/*_gateway.dart` 是 L4 内部适配器非跨层桥；铁律 3 合规。
2. **P1 最严重问题一：L2↔L3 通道错配**——bootloader 全文件不 import bridge_kernel，其日志与 kernel 类型经 `bridge_boot`（L1↔L2 桥）取得，`bridge_kernel.assembleKernel` 零调用者，kernel 装配在两桥重复实现。
3. **P1 最严重问题二：桥越界 re-export 非相邻下层**——`bridge_boot.dart:7` re-export kernel 的 Log/Kernel，`bridge_logic/bridge_session/bridge_surface` 也各自直连 kernel，bridge_kernel 的唯一出口名存实亡。
4. **P1 问题三：L1→bridge_surface 跨 5 层越级**——虽有门禁白名单放行，但未登记进 LAYER_EXCEPTIONS、无理由说明，破坏相邻桥原则。
5. **启动序列主体正确**：DB 打开已由 `dbOpenFuture` 随 BootResult 上交并在 main.dart:90-93 await（历史 unawaited 竞态已修）；settings 已单实例贯穿 L2→L1→L6（历史双实例互盲 bug 已修）；任一必需依赖缺失走可见错误页而非崩（main.dart:78-86）。
6. **桥 try/catch + Log 基本达标**：bridge_boot 8 个公开函数、bridge_kernel 4 个公开函数全部有 try/catch 与失败留痕，无静默吞；唯一瑕疵是 bridge_kernel.assembleKernel 把失败降级为空上下文无错误标志。
7. **死代码/占位**：kernel 模块表恒空且 `Log._buf` 只写不读、`KernelContext.get<T>()` 必抛；register.dart:13 `bootBridgeInstalled` 无消费者；main.dart:50 恒真分支；BootResult.auth 经 bridge_boot 归一化被丢弃并导致 L6 出现第二个 AuthLogic 实例。
8. **例外登记合规**：`init/main.dart → bootloader/register.dart` 仍被 main.dart:48 实际使用，仅做语言层装桥，登记在 tool/layer_audit.py:46 与 §1 中，判定合理可保留。

## 未覆盖

- 未审 `lib/surface/**`（L7）与 `lib/session/**` 其余文件的业务逻辑（仅读 graph.dart / bootstrap.dart 用于确认层归属与装配链）。
- 未审 `lib/core/**`、`lib/logic/**` 内部实现（仅在只读扩展中确认它们经 bridge_kernel 取 Log，不涉及其自身分层合规）。
- 未审 `tool/layer_audit.py` / `tool/smoke_check.dart` 门禁脚本本身的实现正确性（仅引为白名单事实）。
- 未审 `lib/surface/app_root.dart`、`lib/surface/theme/tn_theme.dart`（main.dart 依赖的 `bootstrapApp/installServices/spLightThemeData` 实现体），故「L1→bridge_surface」是否真能收敛到 bridge_boot 未验证。
- 未审 A6/A7 批次文件中 bridge_session / bridge_surface / 六桥其余部分的分层细节（除 kernel 直连一项）。
- 未审 i18n、动画、M3（属 C3 视角）。

## 76 合规小结

| 铁律 | 结论 | 依据 |
|---|---|---|
| 1 不同层间必须经桥、禁跨层直接 import 非桥文件 | **合规**（无一处直接 import 非桥的跨层文件；所有跨层访问均经 lib/bridges/*.dart） | 全批 import 清单 |
| 2 桥函数 try/catch + 失败必 Log、不静默吞 | **基本合规**，1 处 P2 降级瑕疵（bridge_kernel.assembleKernel 失败返空上下文无标志） | 核查表 |
| 3 桥文件唯一在 lib/bridges/、禁影子桥 | **合规** | rg --files 全仓确认 |
| 4 每层只依赖其下层经桥门面、反向依赖禁止 | **违规**（P1×3）：L1→bridge_surface 跨 5 层；L2 经 bridge_boot 取 L3；bridge_boot re-export L3，5 座桥直连 kernel | 见 P1 条目 |
| 5 单文件 ≤1500 行；L6 模块经注册表热插拔 | **合规**（本批最长 bridge_boot.dart 187 行；main 161 / bootloader 171 / kernel 35 / bridge_kernel 58） | wc -l |
| 6 网络层端点分文件、只连酷狗官方域名 | **不适用**（本批无网络代码） | — |
| 7 零源仓库代码复用 | **合规**（未见归档项目代码搬运痕迹） | 抽样 |
| 8 播放控制/列表/缓存/预读/装配图不得进 L6 | **合规**（本批不含 L6 业务；L2 仅做单例装配） | 读 bootstrap.dart |
| 9 用成熟库 | **合规**（本批无引擎/播放代码；main 用官方 path_provider） | — |
| 10 子代理只读、不跑分析器 | **合规**（全程只用 file_read / rg / ls / wc；唯一写入为本报告） | — |
| §1 L1 = main/runBoot 触发/错误页，禁业务 | **合规** | main.dart 无业务逻辑 |
| §1 L2 = core/logic 单例装配 + DB await，禁持 Widget | **合规**（无 flutter import；DB future 上交并在 main await） | bootloader.dart |
| §1 L3 = Log/生命周期，禁 UI | **合规（无 UI）但职责空壳**（模块表恒空，_buf 只写不读） | kernel.dart |
| §1 例外 init/main.dart → bootloader/register.dart | **合规**（仍在使用、登记完整、用途合理） | main.dart:48 / layer_audit.py:46 |
| §2 六桥邻接表 | **违规**（bridge_boot 兼作 L1↔L2 又透出 L3；bridge_kernel 被架空） | 见 P1 条目 |
