# 线C 自主执行总报告 · 缓存 + 网络专项

> 2026-11-15 · 项目根 `/var/minis/workspace/NextWorkspace/TiernanMusic-Next/`
> 角色：自主执行代理「线C」，负责原计划批11/批12 中**不与线A冲突**的部分，与线A/B 并行。
> 76 原则 §0：七层六桥；L4 core 只写 IO/缓存/传输；跨层只经六桥；桥 try/catch+Log；单文件 ≤500 行；缓存包容预读（深度融合）；成熟库优先。
> 硬规范执行：源码读取全部用 file_read（未用 shell 读文件内容）；每阶段即时落盘；未触碰任何禁改范围；聊天汇报 <500 字。

---

## 0. 边界声明（严格遵守）

**只读、未改**：`lib/core/net/kugou_client.dart`、`endpoint_registry.dart`、`play_endpoints.dart`、`mv_endpoints.dart`、`mv_anonymous.dart`、`lib/session/**`（含 bootstrap.dart）、`lib/logic/**`（含 player/auth/catalog）、`lib/surface/**`、`lib/bridges/**`（桥文件）、`endpoint_registry.dart`、`lib/core/net/endpoints/{playlist_write,collect,comment}_endpoints.dart`、`.github/**`、`tool/local_gate.sh`、`tool/**`、`README.md`、`docs/plan_*`、`docs/autonomous_lineA*|lineB*`。

**实际改动集合（git status 核实，仅 5 个文件）**：

| 文件 | 类型 | 阶段 |
|---|---|---|
| `lib/core/cache/cache_service.dart` | 改 | 2-① |
| `lib/core/storage/resource_cache.dart` | 改 | 2-② |
| `lib/core/net/inflight.dart` | 改 | 2-③ |
| `docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md` | 新建 | 2-④ |
| `docs/autonomous_lineC_c.md` | 新建 | 1（阶段1 检查报告） |
| `docs/autonomous_lineC.md` | 新建 | 3（本文件） |

---

## 1. 阶段1 检查（已落盘 `docs/autonomous_lineC_c.md`，五项逐条结论）

只读对象：`cache_service.dart`、`resource_cache.dart`、`inflight.dart`、`session/bootstrap.dart`、`kugou_client.dart`、`docs/audit_rewritten_core_gates.md`、`docs/plan_upstream_endpoints_b.md`（含 §9 签名坑）。

| # | 检查项 | 结论 |
|---|---|---|
| ① | CacheService 门面 vs KugouClient 内置 ResourceCache/InFlight 是否重复双栈 | **否**。`cache_service.dart:34-105` 只持 `final KugouClient _client` + 3 计数，零 ResourceCache/InFlight 引用、零 dart:io；执行栈唯一在 `kugou_client.dart:82-106`（`getJson→InFlight.run→putJson`），由 `bootloader.dart:121-128` 注入唯一一份实例。职责边界 = 门面策略层 / client 唯一执行层 / ResourceCache 纯 IO / InFlight 纯合并。与 `audit_rewritten_core_gates.md §5` 结论一致（该文档「client 内 L1」措辞略误，实为 ResourceCache._index + logic 层 LruCache）。**两处不纯**：改前 `prefetch` 直接调 `_client.request` 绕过 `get`；`CacheServiceStats` 自造计数与底层 L2 真实命中脱节。 |
| ② | cacheKey 维度（body/token/uid/dfid/clienttime）完备性 | **不完备**。唯一真源 `kugou_client.dart:114-130`：method+base+path+排序 query ✅、uid ✅、token 只区分有无 ⚠️、clienttime 不入键 ✅（合理，`:152-153` 在 _requestRaw 内生成，入键反致永不命中）；**缺 dfid/mid** ❌（`encryptKey` 端点 `key=playKey(hash,mid,userid)` 依赖 mid，`videoUrl` 未标 cacheable:false 可脏命中）；`body.hashCode`/`token.hashCode` 进程内不稳定 ❌（重启后磁盘缓存永不命中）；单飞键复用 cacheKey 且不含 rawBody ❌（不同 rawBody 并发 delete_list 错误合并）。 |
| ③ | ResourceCache 同步 IO / 固定 tmp / cleanup 旧快照回写 | **三旧疾整体已清除**：全文 IO 全 `await`、零 `*Sync`；tmp 已用微秒时间戳唯一命名；`_writeChain` 串行 + `_swallow` 异常不饿死；cleanup(`:342-371`) 只取排序快照、逐个 `containsKey` 复查、以当前 `_index` 落盘，**不持旧副本跨 await**；失败保留内存索引。**唯一实质残留**：`putString` 旧 `:296-299`「先 delete 目标→再 rename」非原子窗口（rename 失败即旧数据丢失且索引悬空）。 |
| ④ | 按端点 TTL 分级 | **缺失**。`resource_cache.dart:58` 全局 7 天且 `bootloader.dart:123-126` 未传 ttl；`Endpoint`（`endpoint_registry.dart:8-36`）无 ttl 字段；`kugou_client.dart:101-106` `putJson` 无 ttl 参数。仅 `playUrlV5`/`anonymousSongUrl` 用 `cacheable:false` 排除。根因在线A范围。 |
| ⑤ | 登出失效钩子 | `KugouClient.clearInflight()`（`kugou_client.dart:55-61`）**确证存在**，`InFlight.clear()` 存在，`CacheService.invalidateSession()` 调用正确 → 无 GAP、无需臆造。**但自动钩子未接**：`auth_logic.dart:379-402` logout / `:364-377` signOut 全链路无 `invalidateSession()`，唯一调用点是 `settings_page.dart:136-142` 手动按钮；磁盘 L2 不清除。挂接需改 logic/session/surface → 越界。 |

---

## 2. 阶段2 修复（4 项，均已落盘并 file_read 回读）

### 2-① `lib/core/cache/cache_service.dart` → 纯策略门面（173 行）
- 确认 `KugouClient.clearInflight` 存在（先 file_read 确认，未臆造）→ `invalidateSession()` 保留调用。
- **统一为策略层**：零 `dart:io`、零 ResourceCache/InFlight 引用、零第二份异步读写；`get()` = 构造+转发 `_client.request`+try/catch+Log；`prefetch()` 改为**只构造 (ep, params) 并调用本类 `get()`**（改前直接调 `_client.request` 绕过门面），与正常读完全同路径 → 「缓存⊃预读」真正深度融合、无第二套状态。
- **CacheServiceStats 诚实化**：`KugouClient` 的 `_cache`/`_inflight` 为私有 final 且**无任何公开 getter**（`kugou_client.dart:47-53`），门面无法取真实计数 → `hits/writes/evictions` **恒 0**，带 `exposeRealCounters=false` + `source='facade-only; KugouClient has no public cache/inflight stats getter'`；`reads/prefetched/errors` 仅门面自身调用计数（真实、非底层计数）；`toJson()` 含说明避免 0 被误读。不伪造数值。
- 保留 `CacheOrigin` 枚举与 `CacheService(client)` / `get` / `prefetch` / `invalidateSession` 签名，兼容 `bridge_core.dart:107` 导出、`bootstrap.dart:103-110` 装配、`graph.dart:80`、`settings_page.dart:136-142`、`tool/resolve_contract_test.dart:27-43` 静态契约锚点。

### 2-② `lib/core/storage/resource_cache.dart` → 批4-F2 异步互斥收口（471 行 ≤500）
- 全文 file_read 确认后按既有方案修：保留 `_writeChain` 串行（`:84` + `_enqueue`/`_swallow`）、cleanup 不持旧副本跨 await、失败保留内存索引。
- **修非原子窗口**：新增 `_renameAtomic()`（rename 覆盖优先，仅平台不支持覆盖时才退化「删后改名」，且处于串行段内、失败保留旧文件+tmp）；`putString` 与 `_saveIndex` 均改用它，删掉旧「先 delete 目标再 rename」。
- **tmp 唯一命名加固**：`_tmpPath()` = 微秒时间戳 + 实例 hashCode + 静态单调自增序号，杜绝同微秒同键并发撞名；新增 `_discardTmp()` 尽力清理。
- **失败保留内存索引**：仅在数据文件替换成功后才更新 `_index`；`_saveIndex` 失败返回 false 不回滚。
- **按端点 TTL 分级能力预埋**：`putString(key, value, {Duration? ttl})` / `putJson(..., {Duration? ttl})` 写入 `ttlMs` 元数据，`getString` 优先按 `ttlMs` 判定、旧索引无该字段自然回退全局 7 天 → 向后兼容、零调用方改动。接线点在 Endpoint/KugouClient（线A范围），预埋不冒充完成。

### 2-③ `lib/core/net/inflight.dart` → 语义确认 + clear/getter 补强（112 行 ≤200）
- 逐项确认（均**已满足**，不改逻辑）：`finally` 移除 key（失败不缓存）；`f.timeout` 只作用等待侧、**不取消底层任务**（底层仍由 finally 自行移除）；异常共享同一对象不吞；`clear()` 只清等待表不取消底层请求。
- 补强：`clear()` 加 try/catch + Log（六桥留痕铁律）；新增 `started/coalesced/failed/timedOut` 只读 getter（统计能力就绪，但 KugouClient 未转出 → 门面仍取不到）。纯 `dart:async`，**无新第三方包**。

### 2-④ 新建 `docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md`
缓存专项 5 项（C1 双栈、C2 键维度、C3 三旧疾、C4 TTL、C5 登出钩子，另 C1′ 统计真实计数）+ 网络传输层 5 项**只读审计**（逐项给 `文件:行` 证据）：
- **N1 签名三模式 ✅**：`kugou_client.dart:163-171` 四路分派；`signing.dart:25-35/38-42/45-49` android(含 body)/web/register(只排序值、salt 1014) 与 plan B §0/§9.1/§9.7 一致；web 端点落点 `endpoint_registry.dart:267,271,320`。
- **N2 clienttime 秒/毫秒 ⚠️ 待线A收口**：网关默认秒（`kugou_client.dart:152-153,187`）、FM 毫秒（`fm_endpoints.dart:148-149,164`）、封装秒（`mv_endpoints.dart:311,321` 等）均正确；但 plan B §0 的毫秒轨端点（top_playlist/album/artist_audios/playlist_similar/search_mixed）未按端点声明，header 恒秒无法按端点切换。
- **N3 dfid 随机 ⚠️ 待线A收口**：长度 24 合规（`kugou_client.dart:28-34,142,186`），但 `:31` 用 `DateTime.now().microsecondsSinceEpoch` 位移、无 `Random.secure()` → **确定性伪随机**，不满足「随机 24 位」风控契约；另 dfid 未入 cacheKey、匿名端点未独立随机。
- **N4 Cookie 拼接 ✅**：`kugou_client.dart:193-197` 一次性 `set('Cookie', entries.join('; '))`，与 plan B §9.4 一致。
- **N5 15s 响应超时 ✅**：连接 10s(`:65-67`) + 响应头 15s(`:205,209-213`) + 响应体 15s(`:216-222`)，均归一 `KugouApiException(-2)`（`:203-208` 注释），与 InFlight 等待侧超时互补。

---

## 3. 阶段3 自检（全部通过）

| 项 | 方法 | 结果 |
|---|---|---|
| 回读全部改动 | file_read ×3 源文件 + 2 份新文档 | ✅ 内容完整、无截断 |
| 行数 | file_read 元数据 | `cache_service.dart` 173、`resource_cache.dart` 471（≤500）、`inflight.dart` 112（≤200）✅ |
| 无同步 IO 残留 | rg 单次终检 `lib/core/cache lib/core/storage lib/core/net/inflight.dart` | 改动 3 文件零 `*Sync`；`resource_cache.dart` 所有 `readAsString/writeAsString` 均 `await` ✅（rg 命中的 `*Sync` 全部在**未改**的 `paths.dart`/`settings_store.dart`/`download_store.dart`，不属本线范围） |
| 格式 | `dart format --output=none lib/core/cache lib/core/storage lib/core/net/inflight.dart` | exit 0、**无 "Could not"** ✅（仅有 `flutter_lints` 包解析 warning，与语法无关；已对本线 3 文件实跑 `dart format`，未改其他文件） |
| 边界核实 | `git status --short` | 仅 3 改 + 2 新建文档，零禁改文件 ✅ |

---

## 4. 完成 / 未完成 / 与线A衔接点

### ✅ 完成
1. 阶段1 检查报告落盘 `docs/autonomous_lineC_c.md`（五项逐条 + 文件:行证据）。
2. `cache_service.dart` 收口为真正单一策略门面；prefetch 走 get 同路径；Stats 真实计数不可得则标 0 + source 说明，不臆造；`clearInflight` 先确认存在。
3. `resource_cache.dart` 修完最后一个原子性缺口（rename 覆盖优先）、tmp 唯一命名加固、per-entry TTL 能力预埋；同步 IO/固定 tmp/cleanup 旧快照回写均已确认清除。
4. `inflight.dart` 三项语义确认 + `clear()` 补 try/catch+Log + 只读 getter，无新依赖，≤200 行。
5. 新建 `docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md`：缓存 5 项 + 网络 5 项只读结论，逐项 `文件:行` 证据。
6. 阶段3 自检全通过；全程未触碰线A/线B/桥/门禁/README/plan 文档。

### ⏳ 未完成（**全部因越界，按规范不修，已在审计文档标注「待线A收口」**）
1. cacheKey 缺 dfid/mid、body/token 用不稳定 hashCode、单飞键缺 rawBody → 根因 `kugou_client.dart:114-130,98`（线A）。
2. 按端点 TTL 分级**接线**（本线只预埋 `putJson(ttl:)` 能力）→ `endpoint_registry.dart:8-36` + `kugou_client.dart:101-106`（线A）。
3. clienttime 毫秒轨端点级声明 + header/key 同步（N2）→ `kugou_client.dart:152-153,187` + registry（线A）。
4. dfid 改 `Random.secure()` + 入键 + 匿名独立随机 cookie（N3）→ `kugou_client.dart:28-34`（线A）。
5. 登出自动失效钩子（signOut/logout 后调 `invalidateSession()`）、磁盘 namespace 级清理能力 → `lib/logic/auth/**`、`lib/session/**`、`lib/surface/**`、桥（线A/主会话）。
6. `KugouClient` 暴露 `ResourceCache.stats()` / `InFlight` 计数的只读转发 getter，门面才能填真实统计（线A）。
7. `videoUrl`（`endpoint_registry.dart:231-235`）`encryptKey:true` 却未标 `cacheable:false`（线A）。

### 🔗 与线A衔接点（交接线A，零冲突）
- **接口已就绪、等线A接线**：`ResourceCache.putJson(key, value, {Duration? ttl})` 与 `putString(...,{Duration? ttl})`（可选参数，不改现有调用方）；`InFlight` 的 `started/coalesced/failed/timedOut/pendingCount` 只读 getter；`CacheServiceStats` 的 `hits/writes/evictions/exposeRealCounters/source` 字段（线A 暴露 getter 后门面即可填真值，无需再改门面形状）。
- **需线A决策/收口的 7 项**：见上「未完成」1-7，全部集中在 `kugou_client.dart`、`endpoint_registry.dart`、`auth_logic.dart`、桥出口，均可独立改动、不与本线 3 个源文件冲突。
- **契约锚点保持**：`CacheService(client)`、`get`、`prefetch`、`invalidateSession`、`CacheOrigin` 与 `resolve_contract_test.dart:27-43` / `bridge_core.dart:107` / `bootstrap.dart:103-110` 完全兼容，线A 改键/TTL/dfid 不需动门面。
- **并行安全**：本线未写任何线A/线B 文件，未改 `docs/plan_*`、`docs/autonomous_lineA*|lineB*`；`git status` 仅 3 源 + 2 文档，线A/B 可并行合入。

---

## 5. 交付物清单

| 文件 | 说明 |
|---|---|
| `docs/autonomous_lineC_c.md` | 阶段1 检查报告（五项 + 只读证据，109 行） |
| `docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md` | 缓存 5 项 + 网络 5 项只读审计 + 越界清单（147 行） |
| `docs/autonomous_lineC.md` | 本总报告（完成/未完成/衔接点） |
| `lib/core/cache/cache_service.dart` | 纯策略门面（173 行） |
| `lib/core/storage/resource_cache.dart` | 异步互斥 + 原子 rename + TTL 预埋（471 行） |
| `lib/core/net/inflight.dart` | 语义确认 + clear/统计补强（112 行） |

> 全部阶段即时落盘；被中断亦保留已完成成果。未创建计划任务、未提交、未委派。
