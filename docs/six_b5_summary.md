# 批5 整理（2026-11-15）

主题：缓存专项。按新规矩复用线C 客观报告，主线收口，不重复派代理。

## 检查结论（复用 `docs/autonomous_lineC.md` / `lineC_c.md` / `AUTONOMOUS_CACHE_NETWORK_AUDIT.md`）
- C1：不是双栈；`CacheService` 是「单一策略门面 + KugouClient 唯一执行栈」。预读 `prefetch()` 只构造请求并走本类 `get()`，与正常读同路径。
- C2：cacheKey 现有 method+path+排序 query+uid+token 有无；**body.hashCode 不稳定、token hashCode 不稳定、缺 dfid/mid、rawBody 未进单飞键**——属 `kugou_client.dart` 范围，留批6 网络专项收口。
- C3：ResourceCache 原同步 IO / 固定 tmp / cleanup 旧快照回写；已收口为异步原子 rename + 内存索引 + 串行写链 + TTL 预埋。
- C4：InFlight.clear/getter 已具备，`invalidateSession()` 接 `KugouClient.clearInflight()` 真实存在。
- C5：统计 getter 已预埋，L7 诊断页消费未做（非本批硬要求）。

## 修复结果（线C 已落盘，主线复核）
- `lib/core/cache/cache_service.dart`：零 dart:io / 零 Widget；纯策略门面；`get/prefetch/invalidateSession/stats`。
- `lib/core/storage/resource_cache.dart`：全异步 IO、唯一 tmp 命名、原子 rename、TTL 预埋。
- `lib/core/net/inflight.dart`：clear / getter 暴露，失败不缓存、finally 移除。
- 主线 `rg` 确认三文件无 `*Sync(` 残留（仅注释与 `dart:io` import），`local_gate.sh` FINAL-OK。

## 门禁
- `bash tool/local_gate.sh` → `FINAL-OK`
- `python3 tool/analyze_gate.py` → `analyze_gate ok`
- `dart format --output=none lib tool test` → 通过

## 未覆盖 / 移交批6
- `kugou_client.dart` 的 body/token 稳定摘要、dfid/mid 入键、rawBody 单飞键、按端点 TTL、登出失效钩子。
- 成熟库替换评估（磁盘缓存仍 dart:io 自研）：按用户口径「仅用库 <20% 功能才自研」的判定未执行，列入网络专项。
