# 线C · 缓存专项 + 网络传输层只读审计（自主执行）

> 2026-11-15 · 项目根 `/var/minis/workspace/NextWorkspace/TiernanMusic-Next/`
> 线C 范围：批11/批12 中不与线A冲突的部分。**kugou_client.dart / endpoint_registry.dart 全程只读，零改动**。
> 后 5 项（网络传输层）为**只读审计**，不合格项一律列「待线A收口」，不越界修改。
> 证据格式 `文件:行`，行号以本次审计时的工作树为准。

---

## A. 缓存专项 5 项结论

### C1 · CacheService 门面是否为重复双栈（缓存 ⊃ 预读深度融合）

**结论：不是双栈；已收口为「单一策略门面 + 唯一执行栈」。**

- 真实执行者唯一：`lib/bootloader/bootloader.dart:121-128` 构造 `KugouClient(session, cache: ResourceCache(namespace:'net'), inflight: InFlight<Map<String,dynamic>>())`；`lib/core/net/kugou_client.dart:82-106` 的 `getJson → InFlight.run → putJson` 是全仓唯一 L2 读写/单飞路径。
- 门面不再造异步读写：改后 `lib/core/cache/cache_service.dart` 全文零 `dart:io`、零 `ResourceCache`、零 `InFlight` 引用，只有 `final KugouClient _client` + `get/prefetch/invalidateSession/stats`。
- 预读归缓存：`cache_service.dart` 的 `prefetch()` **只构造 (ep, params) 并调用本类 `get()`**，`get()` 转发 `_client.request(ep, params, body: body)`；与正常读完全同路径，无第二套状态（改动前 `prefetch` 直接调 `_client.request`，绕过 `get` 的统一 try/catch+Log 与计数）。
- `invalidateSession()` 调 `_client.clearInflight()`：`lib/core/net/kugou_client.dart:55-61` **确证存在**，无需臆造，无 GAP。
- 口径澄清：`docs/audit_rewritten_core_gates.md §5` 称「client 内 L1 内存 + L2 磁盘」略误——client 内无独立 L1 表，L1 实为 `lib/core/storage/resource_cache.dart:78-79` 的 `_index` 内存索引与 `lib/session/bootstrap.dart:55-97` 各 logic 的 `LruCache`。不影响「薄门面」定性。

### C2 · cacheKey 维度是否完备

**结论：基本可用但**不完备**，全部缺口在 `kugou_client.dart`（线A范围）→ 待线A收口。**

唯一真源 `lib/core/net/kugou_client.dart:114-130`：
`'${ep.method} ${ep.base}${ep.path}?$q$b&uid=${session.userid}&tk=${session.token.isEmpty ? 'anon' : session.token.hashCode}'`。

| 维度 | 证据 | 判定 |
|---|---|---|
| method+base+path+排序 query | `:117-118,124` | ✅ |
| body | `:119-121` `&body=${body.hashCode}` | ❌ `Map.hashCode` 进程内不稳定 → 重启后同 body 磁盘缓存永不命中；非内容摘要、有碰撞风险。应改 `jsonEncode(排序键)` 稳定摘要。 |
| uid | `:125` | ✅ 匿名/登录隔离 |
| token | `:126` `anon`/`hashCode` | ⚠️ 只区分有无（合格），但登录态 hashCode 不稳定 → 旧登录条目成永久垃圾。 |
| dfid | **缺** | ❌ `:142` 注入 q、`:186` 设 header；换设备/重生成后仍复用旧缓存。 |
| mid | **缺** | ❌ `:157-159` `key=playKey(hash,mid,userid)` 依赖 mid；`endpoint_registry.dart:231-235` `videoUrl` 为 `encryptKey:true` 且**未标 cacheable:false** → 换 mid 可脏命中。 |
| clienttime | 不入键 | ✅ **不应入键**：`:152-153` 在 `_requestRaw` 内 `putIfAbsent` 生成，不在 params 里；入键反致永不命中。 |
| rawBody | `:82` 排除 L2，`_cacheKeyOf` 不含 rawBody | ❌ `:98` `_inflight!.run(cacheKey, run)` 复用同键 → 两个不同 `rawBody` 的并发 `delete_list` 会错误合并共享结果。 |

**待线A收口**：键增加 dfid/mid 维度；body/token 改稳定摘要；单飞键补 rawBody 摘要。

### C3 · ResourceCache 同步 IO / 固定 tmp / cleanup 旧快照回写

**结论：批4-F2 异步互斥方案已整体落地，阶段2 补完最后一个原子性缺口。**

- 同步 IO：全文 IO 均 `await`（`:123,124,135,188,202-206,209,216,258,266,294-299`），**零 `*Sync`** ✅
- 固定 tmp：原 `:204-205`/`:292-293` 用微秒时间戳已唯一；阶段2 加固为 `微秒 + 实例 hashCode + 单调自增序号`（`_tmpPath`），杜绝同微秒同键并发撞名 ✅
- 写串行链：`resource_cache.dart:84` `_writeChain` + `:158-164` `_enqueue` + `:167-173` `_swallow`，异常不饿死后续写；`_ensureLoaded` 也经链排队 ✅
- rename 原子替换：原 `putString` 是「先 `delete` 目标 → 再 `rename`」（旧 :296-299），存在旧文件已删、rename 失败即数据丢失且索引悬空的窗口 ❌ → 阶段2 新增 `_renameAtomic()`：`rename` 覆盖优先，仅平台不支持时才退化「删后改名」，且失败保留旧文件 + 旧内存索引 ✅
- cleanup 旧快照回写：`:342-371` 基于「当前」`_index` 求和，`:350-353` 只取排序用键快照，`:357-363` 逐个 `containsKey` 复查后删，`:368` 以当前 `_index` 落盘（含已排队的新 put）——**不持旧副本跨 await** ✅
- 失败保留内存索引：`_saveIndex` 失败返回 false 而不回滚 `_index`；`putString` 仅在数据文件替换成功后才更新 `_index`；索引损坏时 `:129-138` 主动清空重建（语义为「重建」而非「写失败」）✅
- 行数 ≤500 ✅

### C4 · 按端点 TTL 分级

**结论：缺失，属实；本线只做能力预埋，接线点在线A。**

- `lib/core/storage/resource_cache.dart:58` `ttl = const Duration(days: 7)`；`lib/bootloader/bootloader.dart:123-126` 未传 ttl → 全端点统一 7 天。
- `lib/core/net/endpoint_registry.dart:8-36` `Endpoint` 无 `ttl`/`cacheTtl` 字段；`lib/core/net/kugou_client.dart:101-106` `putJson(cacheKey, res)` 无 ttl 参数 → 传输层无分级入口。
- 风险：`search_hot`/`search_song`/`rank_list`/`comment_music`/`user_playlists`/`privilege_lite` 一律 7 天；仅 `playUrlV5`、`anonymousSongUrl` 用 `cacheable:false` 排除（`endpoint_registry.dart:65,244`）。
- **线C 已做**：`putString(key, value, {Duration? ttl})` / `putJson(..., {Duration? ttl})` 写入 `ttlMs` 元数据，`getString` 优先按 `ttlMs` 判定、旧索引无该字段时自然回退全局 7 天 → 向后兼容、零调用方改动。
- **待线A收口**：`Endpoint` 增加 ttl 字段并按端点赋值；`KugouClient.request` 把 `ep.ttl` 透传给 `putJson`。接线前分级不生效（预埋不冒充完成）。

### C5 · 登出失效钩子

**结论：`clearInflight` 存在且门面调用正确；自动登出钩子缺失，越界不可修。**

- `lib/core/net/kugou_client.dart:55-61` `clearInflight()` 存在；`lib/core/net/inflight.dart:30-37`（阶段2 后 :55-63）`clear()` 存在；`cache_service.dart` `invalidateSession()` 正确调用，且 clear 已补 try/catch+Log ✅
- `lib/logic/auth/auth_logic.dart:379-402` `logout()` 清 `session.token/userid/cookies` + settings，注释明写「缓存失效由调用方执行」；`signOut()`（`:364-377`）→ `logout()` 全链路**无 `invalidateSession()` 调用**。全仓唯一调用点 = `lib/surface/pages/settings_page.dart:136-142` 的手动「清缓存」按钮 ❌
- 磁盘 L2 不清除（键含 uid，见 `:125`）；但 C2 的不稳定 hashCode + 缺 dfid/mid 使旧 uid 条目重启后无法命中，占用容量至 7 天 TTL 或 LRU 淘汰，且无按 uid/namespace 清理接口 ❌
- `lib/logic/auth/**`、`lib/session/**`、`lib/surface/**` 均在线C 严禁清单 → **待线A/主会话收口**：建议 `signOut`/`logout` 成功后经 bridge 调 `appGraph.cache?.invalidateSession()`；真清磁盘须经 bridge 暴露 `ResourceCache` 的 namespace 级清理能力。

### C1′ · CacheServiceStats 真实计数（阶段2 第 1 项附属结论）

`KugouClient` 的 `_cache`/`_inflight` 为私有 final（`kugou_client.dart:47-53`）且**无任何公开 getter**；公开成员只有 `session`(:45)、`clearInflight`(:55)、`request`(:71)、`close`(:245)。门面因此**无法**读取 `ResourceCache.stats()` 或 `InFlight` 计数。
处理：`CacheServiceStats` 的 `hits/writes/evictions` **恒 0**，并带 `exposeRealCounters=false` + `source='facade-only; KugouClient has no public cache/inflight stats getter'`；`reads/prefetched/errors` 仅门面自身调用计数（真实、非底层计数），`toJson()` 含说明避免 0 被误读为「无缓存活动」。阶段2 已在 `InFlight` 补 `started/coalesced/failed/timedOut` 只读 getter（能力就绪）。
**待线A收口**：`KugouClient` 暴露 `ResourceCache.stats()` 与 `InFlight` 计数的只读转发 getter，门面才能填真实值。不臆造数值。

---

## B. 网络传输层 5 项结论（**只读审计 · kugou_client 禁改**）

### N1 · 签名三模式

**结论：✅ 合格（android / web / register / none 四路齐全，三签名实现与上游契约一致）。**

- 分派：`lib/core/net/kugou_client.dart:163-171` `switch (ep.signType)` → `android`（`:164-165`，`KugouSign.android(p, body: bodyStr)`）、`web`（`:166-167`）、`register`（`:168-169`）、`none`（`:170` break）。
- 实现：`lib/core/net/signing.dart:25-35` android = `md5(salt + 参数名 ASCII 升序 k=v 无分隔拼接 + body 原文 + salt)`（**含 body**）；`:38-42` web = 先拼 `k=v` 串整体排序后拼接 + 双盐；`:45-49` register = **只排序值、无 k=**、salt `1014`。与 `docs/plan_upstream_endpoints_b.md §0`（helper.js:24-32 / 9-16 / 39-45）及 §9.1/§9.7 完全对齐。
- web 端点落点：`lib/core/net/endpoint_registry.dart:267,271`（`login_qr_key`/`login_qr_check`）、`:320`（`comment_count`）；none 端点 `:243,261,289,300,308`（匿名试听/注册设备/登出/短信登录/验证码），与 plan B §0「register 只用于注册/设备类、web 仅 comment_count + miniyueku」口径基本一致。
- 无越界项。仅提示（非不合格）：`register` 模式当前注册表**无端点使用**（全部 none/web/android），属预留，不要求改动。

### N2 · clienttime 秒 / 毫秒

**结论：⚠️ 部分合格，标注「待线A收口」。**

- 网关默认层：`lib/core/net/kugou_client.dart:152-153` `putIfAbsent('clienttime', () => DateTime.now().millisecondsSinceEpoch ~/ 1000)` = **秒**；`:184-187` header `clienttime='${ct ~/ 1000}'` 同为秒。与 plan B §0/§9.2「request.js:39 默认秒」一致 ✅
- 毫秒轨（FM）：`lib/core/net/endpoints/fm_endpoints.dart:148-149` `'clienttime': ms`（注释「FM 域 clienttime/key 用毫秒」）+ `:164` `signParamsKey(ms)`，与 plan B §0「fm_class/fm_recommend/fm_songs/fm_image/personal_fm … 覆盖为毫秒且 key 用同一毫秒值」一致 ✅
- 秒轨（端点封装）：`mv_endpoints.dart:311,321`、`album_endpoints.dart:158-159`、`playlist_endpoints.dart:43,45`、`playlist_write_endpoints.dart:99,115-116` 均 `nowSec` + `signParamsKey('$nowSec')` ✅
- **残留缺口**：plan B §0 列举的**毫秒轨**端点 `top_playlist / album / artist_audios / playlist_similar / search_mixed` 中，`album_endpoints.dart:158`、`playlist_endpoints.dart:43`、`artist_audios`（`endpoint_registry.dart:165-171` 由 client 默认秒注入）现按秒取值；`:184` header 恒秒，与需要毫秒的端点复用同一 `KugouClient._requestRaw` 时无法按端点切换（header 与 q 恒秒）。这些端点的 clienttime 轨位未做端点级声明，属 `endpoint_registry.dart` + `kugou_client.dart:152-153,187` 的接线缺口。
- **待线A收口**：给 `Endpoint` 增 `clienttimeMs` 布尔声明；`_requestRaw` 按声明选择秒/毫秒并同步 header 与 `signParamsKey` 同值；逐端点三态实测确认轨位。本线不越界。

### N3 · dfid 随机

**结论：⚠️ 长度合规、随机性不合格，标注「待线A收口」。**

- 生成：`lib/core/net/kugou_client.dart:23-38`，首次访问生成 24 位 `A-Z0-9`，`:142` 注入默认 q、`:186` 设 `dfid` header；`:38` setter 支持 `restoreSession` 回写（`auth_logic.dart:181,190` 从 settings 恢复，缺省 `'-'`）。长度 24 与 plan B §9.3 / `endpoint_registry.dart:234` 「randomString(24)」一致 ✅
- **不合格点**：`:31` `final rnd = DateTime.now().microsecondsSinceEpoch;` `:32-34` `List.generate(24, (i) => chars.codeUnitAt((rnd >> (i % 31)) % chars.length))` —— 这是**确定性时间戳位移**，非随机（无 `dart:math.Random`）；且 64 位微秒右移 `(i % 31)` 在 i≥31 前只用到低 24 位模式，24 位输出实为同一时刻可预测串，多实例同刻生成相同 dfid。不满足「随机 24 位」风控契约（`:25-27` 自注「必须随机 24 位 dfid，恒 '-' 时 20028」）。
- `auth_logic.dart:386` 注释承认 logout 必须删 dfid 以避复用，但确定性生成使「重新生成」仍可能撞旧值。
- 附带：C2 已列 dfid 未入 cacheKey；`endpoint_registry.dart:234-239` 匿名试听要求 cookie 注入随机 dfid，当前复用 `session.dfid`。
- **待线A收口**：改 `dart:math.Random.secure()` 生成 24 位；缓存键补 dfid 维度；匿名端点独立随机 dfid cookie；评估是否接 `registerDevice`（`mv_endpoints.dart:416-422` 标注未实测）。

### N4 · Cookie 拼接

**结论：✅ 合格。**

- `lib/core/net/kugou_client.dart:193-197`：`session.cookies.isNotEmpty` 时**一次性** `req.headers.set('Cookie', session.cookies.entries.map((e) => '${e.key}=${e.value}').join('; '))`；注释明写「旧实现对每条 cookie 全量重写整头，效率低且易错」已修。
- 与 plan B §0/§9.4（token/userid/vip_type 既进 query 也用于 body；Cookie 由会话注入）、`:141-150` 的 `dfid/mid/uuid/token/userid` 默认参数注入、`auth_logic.dart:386-395` logout 清 `cookies` + `t1` 等 settings 键形成闭环 ✅
- 无越界项。仅提示（非不合格）：Cookie 值未做 `Uri.encodeQueryComponent`，若上游回写含 `;`/`=` 的特殊值需线A复核；当前 `t1` 等为 hex/token 形态，无风险。

### N5 · 15s 响应超时

**结论：✅ 合格（连接 10s + 响应头 15s + 响应体 15s，且错误码归一）。**

- `lib/core/net/kugou_client.dart:65-67` `connectionTimeout = const Duration(seconds: 10)`。
- `:205` `const responseTimeout = Duration(seconds: 15)`；`:209-213` `req.close().timeout(responseTimeout, onTimeout: …)` 响应头阶段超时抛 `KugouApiException(-2, 'response header timeout …')`；`:216-222` `res.transform(utf8.decoder).join().timeout(responseTimeout, onTimeout: …)` 响应体阶段同样 `-2`。
- `:203-204` 注释说明「旧代码只限连接超时，服务器挂起时 join 永久悬挂且 InFlight 会让所有同键等待者一起悬挂」已修；`:206-208` 说明批2-F3 把裸 `TimeoutException` 归一为 `-2`，与 body 侧语义一致，上层可按错误码分类重试 ✅
- 与 `lib/core/net/inflight.dart` 的等待侧 timeout 语义互补（等待者超时不取消底层任务），无冲突 ✅
- 无越界项。仅提示（非不合格）：两段各 15s 串联，最坏 30s，若线A要「整体 15s」需共享单一计时器；当前口径与注释「两段 15s 时长不变」一致，判合格。

---

## C. 越界清单汇总（不修改，交线A/主会话）

| # | 缺口 | 所在文件（只读） | 建议动作 |
|---|---|---|---|
| 1 | cacheKey 缺 dfid/mid；body/token 用不稳定 hashCode；单飞键缺 rawBody | `kugou_client.dart:114-130,98` | 稳定摘要 + 设备维度 + rawBody 摘要 |
| 2 | 按端点 TTL 分级（预埋已就绪） | `endpoint_registry.dart:8-36` + `kugou_client.dart:101-106` | Endpoint 加 ttl 并透传 `putJson(ttl:)` |
| 3 | clienttime 毫秒轨未按端点声明；header 恒秒 | `kugou_client.dart:152-153,187` + registry | `clienttimeMs` 声明 + header/key 同步 |
| 4 | dfid 确定性时间戳伪随机；dfid 未入键；匿名独立随机 dfid | `kugou_client.dart:28-34` | `Random.secure()` + 键维度 + 匿名 cookie |
| 5 | 登出自动失效钩子未接；磁盘 L2 无 namespace 级清理 | `auth_logic.dart:364-402`、`settings_page.dart:136-142`、bridge | 登出后经桥调 `invalidateSession()`；暴露清理能力 |
| 6 | `KugouClient` 未暴露底层真实计数 getter | `kugou_client.dart:47-53` | 转发 `ResourceCache.stats()` / `InFlight` 计数 |
| 7 | `videoUrl` 为 `encryptKey:true` 却未标 `cacheable:false` | `endpoint_registry.dart:231-235` | 补 `cacheable:false` 或键补 mid |

**线C 已改文件（仅 3 个源 + 2 个新文档）**：
`lib/core/cache/cache_service.dart`、`lib/core/storage/resource_cache.dart`、`lib/core/net/inflight.dart`；
新建 `docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md`、`docs/autonomous_lineC_c.md`、`docs/autonomous_lineC.md`。
未触碰任何线A/线B范围、桥文件、`.github/**`、`tool/**`、`README.md`、`docs/plan_*`。
