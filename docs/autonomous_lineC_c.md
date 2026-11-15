# 线C · 阶段1 检查报告（缓存 + 网络专项 · 只读审计）

> 自主执行代理「线C」· 2026-11-15 · 项目根 `/var/minis/workspace/NextWorkspace/TiernanMusic-Next/`
> 本阶段**只读**，未修改任何源码。读文件仅用 file_read。
> 只读对象：`lib/core/cache/cache_service.dart`、`lib/core/storage/resource_cache.dart`、
> `lib/core/net/inflight.dart`、`lib/session/bootstrap.dart`、`lib/core/net/kugou_client.dart`、
> `docs/audit_rewritten_core_gates.md`、`docs/plan_upstream_endpoints_b.md`（含 §9 签名/参数坑汇总）。
> 辅助只读证据：`lib/bootloader/bootloader.dart`、`lib/bridges/bridge_core.dart`、
> `lib/bridges/bridge_kernel.dart`、`lib/core/net/signing.dart`、`lib/core/net/endpoint_registry.dart`、
> `lib/session/graph.dart`、`lib/logic/auth/auth_logic.dart`、`lib/surface/pages/settings_page.dart`、
> `tool/resolve_contract_test.dart`。

---

## ① CacheService 门面 vs KugouClient 内置 ResourceCache/InFlight：是否重复双栈？职责边界

**结论：不是重复双栈，是「薄策略门面 + 唯一执行栈」；但存在统计口径与预读路径两处不纯。**

| 层 | 文件:行 | 实际职责 |
|---|---|---|
| 策略层 | `cache_service.dart:34-105` | 只持有 `final KugouClient _client`（:37）与 3 个门面计数（:38-40）；`get` 调 `_client.request`（:51），`prefetch` 调 `_client.request`（:72），`invalidateSession` 调 `_client.clearInflight()`（:86），`stats`/`toJson` 只读自身计数（:92-104）。**零 ResourceCache / 零 InFlight 引用、零 dart:io、零文件 IO**。 |
| 执行层 | `kugou_client.dart:43-112` | `KugouClient(session, {ResourceCache? cache, InFlight? inflight})` 由 `bootloader.dart:121-128` 注入**唯一一份** `ResourceCache(namespace:'net')` + `InFlight<Map<String,dynamic>>()`；`request()` 内 `getJson`（:84）→ `InFlight.run`（:98）→ `putJson`（:102）是全仓唯一的 L2 读写/单飞路径。 |
| 装配层 | `bootstrap.dart:103-110,161` | `CacheService(client)` 单例，`prefetch` 预热 `searchHot`/`rankList`，挂进 `AppGraph.cache`（:161）；`graph.dart:80` 与 `settings_page.dart:136-141` 只消费该门面。 |

与 `docs/audit_rewritten_core_gates.md §5` 的既有结论一致（「无自研 ResourceCache 引用……它是 KugouClient 之上的薄门面」）。
**口径修正**：该文档称「client 内 L1 内存 + L2 磁盘 + 单飞」，实际 `KugouClient` 内并无独立 L1 缓存表；「L1」其实是 `ResourceCache._index`（`resource_cache.dart:78-79` 的内存索引）与各 logic 层的 `LruCache`（`bootstrap.dart:55-97`）。不影响结论，但诊断文档不应把 L1 归给 client。

不纯的两处（阶段2 第 1 项修复范围）：
- `cache_service.dart:4-6` 注释声称「prefetch 对预测键执行 get()」，实现却在 `:72` 直接 `_client.request`，绕过 `get` 的 try/catch+Log 与统一计数 → 预读不是「与正常请求完全同路径」。
- `CacheServiceStats`（:20-29）的 `reads/prefetched/errors` 是门面自造计数，与底层 L2 真实命中/写入/淘汰**完全脱节**；`KugouClient` 现有公开成员只有 `session`（:45）、`request`（:71）、`clearInflight`（:55）、`close`（:245），`_cache`/`_inflight` 为私有 final 且**无任何公开 getter**（:47-53）→ 门面无法反映真实缓存计数。`ResourceCache.stats()`（:376）与 `InFlight.pendingCount`（:26）虽公开，但门面拿不到这两个实例。

**职责边界定稿**：CacheService = 策略层（决定读哪些键/预读哪些键/换号失效/诊断序列化）；KugouClient = 唯一执行层（L2 磁盘 + 单飞 + HTTP）；ResourceCache = 纯 IO/索引；InFlight = 纯合并。跨层只经 `bridge_core.dart:107`（CacheService/CacheOrigin）与 `:24-25`（ResourceCache/InFlight）转出，符合 76 原则 §0。

---

## ② cacheKey 维度（body / token / uid / dfid / clienttime）是否完备

唯一真源 `kugou_client.dart:114-130`：

```
'${ep.method} ${ep.base}${ep.path}?$q$b&uid=${session.userid}&tk=${session.token.isEmpty ? 'anon' : session.token.hashCode}'
```
`q` = :117-118 排序后的 params；`b` = :119-121 `body.isEmpty ? '' : '&body=${body.hashCode}'`。

| 维度 | 现状 | 判定 |
|---|---|---|
| method + base + path | :124 | ✅ 完备 |
| query（排序） | :117-118 | ✅ 完备（排序保证参数顺序无关） |
| body | :119-121 `body.hashCode` | ⚠️ **不合格**：`Map.hashCode` 是**进程内 hash、非稳定内容摘要**，进程重启后同一 body 的键会变 → 磁盘缓存跨进程永不命中；且 64 位 hash 有碰撞可能。缺规范化 `jsonEncode(排序键)` 摘要。 |
| uid | :125 `session.userid` | ✅ 匿名/登录隔离 |
| token | :126 `anon` / `token.hashCode` | ⚠️ 只区分「有无」（合格），但登录态用 `hashCode` 同样不稳定 → 重启后旧登录缓存成为永久垃圾。 |
| dfid | **未入键** | ❌ 缺失。`:141` 注入 `dfid` 参与请求、`:186` 又设为 header，设备身份变化（重新生成/换设备）后仍复用旧缓存；`play_url` 类依赖 dfid 风控（`kugou_client.dart:24-27`、plan B §9.3）。 |
| mid | **未入键** | ❌ 缺失。`encryptKey` 端点的 `key=playKey(hash, mid, userid)`（`:157-159`）依赖 mid；`endpoint_registry.dart:231-235` 的 `videoUrl` 是 `encryptKey:true` 且 **未标 `cacheable:false`** → 换 mid 可脏命中。 |
| clienttime | 不入键 | ✅ **合理，不应入键**：`:152-153` 在 `_requestRaw` 内 putIfAbsent 生成，不在 `params` 里，故不影响键稳定性；若入键反而导致缓存永不命中。（plan B §0 的「秒/毫秒双轨」是签名正确性问题，不是键维度问题，见网络层结论 N2。） |
| rawBody | `cacheable = ep.cacheable && _cache != null && rawBody == null`（:82） | ✅ 加密载荷端点不进 L2。但 **单飞键复用 `cacheKey`**（`:98` `_inflight!.run(cacheKey, run)`）且键不含 `rawBody` → 两个不同 `rawBody` 的并发 `delete_list` 会**错误合并共享结果**，属真实缺陷。 |

**总判定：维度「基本可用、不完备」**。缺失 dfid/mid 设备维度；body/token 用不稳定 hashCode；单飞键未含 rawBody。全部落在 `kugou_client.dart`（线A范围、本线禁改）→ 阶段2 只在报告中列 GAP，标注「待线A收口」，不越界修改。

---

## ③ ResourceCache 同步 IO / 固定 tmp / cleanup 旧快照回写是否仍存在

全文 396 行，逐项核对：

| 项 | 证据 | 判定 |
|---|---|---|
| 同步 IO | 全文 IO 均为 `await`：`readAsString`(:123,266)、`exists`(:124,135,258,295)、`delete`(:136,188,211,227,296)、`create(recursive:true)`(:202,288)、`writeAsString(flush:true)`(:206)、`writeAsBytes(flush:true)`(:294)、`rename`(:209,216,299)、`readAsString`(:266)。**无任何 `*Sync` API**。 | ✅ 已清除 |
| 固定 tmp | `:204-205` `index.json.${DateTime.now().microsecondsSinceEpoch}.tmp`；`:292-293` `$path.${DateTime.now().microsecondsSinceEpoch}.tmp`。 | ✅ 已唯一命名（但同一微秒内同键并发写仍可能撞名，缺自增序号 → 阶段2 加固） |
| rename 原子替换 | `_saveIndex` `:209-217` 先 `rename` 覆盖，失败才 `delete` 目标后重试；**`putString` `:296-299` 仍是「先 `delete` 目标 → 再 `rename`」**，delete 与 rename 之间存在旧缓存文件已删、索引仍指向它的窗口，rename 失败即数据丢失，非原子。 | ⚠️ **残留**（阶段2 修） |
| 写串行链 `_writeChain` | `:84`、`:158-164` `_enqueue`、`:167-173` `_swallow`；`_ensureLoaded`(:112-120) 也经链排队。 | ✅ 串行、异常不饿死后续写 |
| cleanup 旧快照回写 | `:342-371` 进入串行链后基于「当前」`_index` 求和；`:350-353` 只取排序用键快照；`:357-363` 逐个 `_index.containsKey` 复查后 `_removeEntry`；`:368` `await _saveIndex()` 序列化**当前** `_index`（含排队中的新 put）。**不持旧 index 副本跨 await 回写**。 | ✅ 已消除 |
| 失败保留内存索引 | `:200-232` `_saveIndex` 失败返回 `false`（:230），调用方不回滚 `_index`（:301/:368 均忽略返回值）；`putString` 写文件失败时异常在更新 `_index` 之前抛出（:294 → :302），内存索引保持原状；`_removeEntry`(:177-191) 删文件失败吞掉但索引已一致。 | ✅ 符合（唯一例外：索引文件损坏时 `:129-138` 主动清空内存并删损坏文件，这是「重建」而非「写失败」，语义正确） |
| 行数 | 396 ≤ 500 | ✅ |

**结论：批4-F2 异步互斥方案整体已落地；唯一实质残留 = `putString` 的 delete-then-rename 非原子窗口**（另可加固 tmp 唯一性与 per-entry TTL 能力，见阶段2）。

---

## ④ 按端点 TTL 分级缺失

- `ResourceCache.ttl = const Duration(days: 7)`（`resource_cache.dart:58`），`bootloader.dart:123-126` 构造时**未传 ttl** → 全端点统一 7 天。
- `Endpoint` 类（`endpoint_registry.dart:8-36`）字段仅 `id/path/method/signType/router/base/clearDefaultParams/encryptKey/cacheable/tid/includeSrcappid`，**无 `ttl` / `cacheTtl` 字段**；`request()`（:101-106）调 `putJson(cacheKey, res)` 无 ttl 参数 → 传输层无按端点分级入口。
- 现状风险：`search_hot`（应分钟级）、`search_song`（小时级）、`rank_list`（小时级）、`comment_music`（分钟级）、`user_playlists`/`user_detail`/`privilege_lite`（登录态敏感，应短或不缓存）一律 7 天；短期正确的只有 `playUrlV5` / `anonymousSongUrl` 用 `cacheable:false` 排除（`endpoint_registry.dart:65,244`）。
- 实现 TTL 分级必须改 `endpoint_registry.dart`（线A范围）或 `kugou_client.dart:101-106`（线A范围、本线禁改）→ **本线不越界**；阶段2 只在可改的 `ResourceCache` 上补 `putString/putJson({Duration? ttl})` + per-entry TTL 元数据能力作为衔接预埋，实际接线列「待线A收口」。

**结论：分级缺失属实，根因在端点声明与 request 调用点，均在线A范围。**

---

## ⑤ 登出失效钩子

- `KugouClient.clearInflight()` **确实存在**（`kugou_client.dart:55-61`，`_inflight?.clear()` + Log），`InFlight.clear()` 也存在（`inflight.dart:30-37`），`CacheService.invalidateSession()` 已正确调用（`cache_service.dart:84-91`）→ 无需臆造，无 GAP。
- **但钩子未接入登出流程**：`AuthLogic.logout()`（`auth_logic.dart:379-402`）清 `session.token/userid/cookies` + settings，注释明写「缓存失效由调用方执行，这里只清凭据」；`signOut()`（:364-377）→ `logout()` 全链路**无任何 `invalidateSession()` 调用**。全仓唯一调用点是 `settings_page.dart:136-142` 的手动「清缓存」按钮。
- L2 磁盘缓存**不清除**：`invalidateSession` 只清 in-flight 等待表，注释（:83）称「磁盘键已含 uid，无需全清」。键含 uid 属实（:125），但 ② 中 `body.hashCode`/`token.hashCode` 不稳定 + 缺 dfid/mid → 旧 uid 条目在重启后无法再命中，会占用容量直到 7 天 TTL 或 LRU 淘汰（`resource_cache.dart:342-371`），且无按 uid/namespace 的清理接口。
- 挂自动钩子需改 `lib/logic/auth/**`、`lib/session/**` 或 `lib/surface/**`，三者均在本线严禁清单 → **列 GAP，待线A/主会话收口**（建议：`signOut`/`logout` 成功后经 bridge 调 `appGraph.cache?.invalidateSession()`；如需真清磁盘，须经 bridge 暴露 `ResourceCache.clearNamespace()` 之类能力）。

**结论：`clearInflight` 存在且门面调用正确；自动登出钩子缺失，越界不可修。**

---

## 阶段1 五项速览

| # | 项 | 结论 | 归属 |
|---|---|---|---|
| ① | 双栈 | 否，薄策略门面 + 唯一执行栈；统计与预读路径不纯 | 线C 修 |
| ② | cacheKey 维度 | 缺 dfid/mid；body/token hashCode 不稳定；单飞键缺 rawBody | 待线A收口 |
| ③ | ResourceCache 三旧疾 | 同步 IO/固定 tmp/旧快照回写均已清除；残留 putString 非原子替换 | 线C 修 |
| ④ | 端点 TTL 分级 | 缺失（统一 7 天，Endpoint 无 ttl 字段） | 线C 预埋能力 + 待线A接线 |
| ⑤ | 登出失效钩子 | clearInflight 存在；自动钩子未接、磁盘不清 | 待线A/主会话收口 |
