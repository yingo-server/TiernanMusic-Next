# B5 批 · 交叉汇总（下载 / 收藏 / 歌单 / 缓存 跨层）

> 2026-11-17。三视角：`bB5_c1.md`（架构）、`bB5_c2.md`（正确性，报告完整落盘但 job 丢失，正文可用）、`bB5_c3.md`（痛点）。均已落盘。

## 0. 阶段 A 修复的跨层验证

| 修复 | 结论 | 证据 |
|---|---|---|
| 下载索引原子 rename | ✅ 生效（单点） | C2 |
| resource_cache 写失败信号 | ✅ 生效（单点） | C2 |
| 下载 L7 入口（⋮菜单） | ✅ 真接 enqueue + Snackbar | C2 + C3 |
| 收藏 L7 真逻辑（FavoriteButton） | ✅ 真读镜像+真 toggle+needsLogin 反馈，单账号持久化成立 | C2 + C3 |

**但**：四链均"半通"——写入侧真通，展示/恢复/事件/换号侧断。C2 一句话定调：**能力存在≠用户可用**，L5 提供的 onTask/resetLocalMirror/onChanged/saveLocalMirror 在 L6/L7 没接线。

## 1. 关键问题

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **下载 onTask 全仓零订阅**→进度/完成/失败不刷新、重启任务恒空、无删除/暂停入口 | C1 + C2 + C3 | **P0** | `download_manager.onTask` 零订阅 + `library_page` |
| X2 | **换号收藏串号**：无 AuthChanged→collect.resetLocalMirror 接线；多账号收藏镜像不隔离 | C1 + C2 | **P1** | `bootstrap` 装配 + `collect_logic` |
| X3 | **歌单写链全断**：L4 端点+DAO+L5 write logic 齐全，但 L7 零入口、saveLocalMirror 零调用、镜像恒空 | C1 + C2 + C3 | **P1** | `playlist_write` + `playlist_page` |
| X4 | **收藏计数端点空转**：getFavoriteCount 空 query → 计数恒不准 | C2 | **P1** | `collect_endpoints` |
| X5 | **缓存预读失效**：CacheService.prefetch 参数与业务不匹配 + L2 ResourceCache / L5 LruCache / CacheService 门面三套不相交 → 预读真命中≈0（与 A4 X4 同根）；bootstrap:214 预读回调只打一条 Log | C1 + C2 | **P1** | `cache_service` + `bootstrap.dart:214` |
| X6 | **收藏持久化失败无回滚**：_flush() 返回 false 仍向 UI 报 ok、内存已改 → 重启丢失 | C2 | **P1** | `collect_logic._doToggle` |
| X7 | **下载建档吞异常**：syncSongRecord catch 吞后 committer 仍标 done → 文件落盘但曲库不建档，用户找不到 | C2 | **P1** | `download_song_sync.dart` |
| X8 | 实体文件 commit deleteSync 后 rename 空窗（阶段A只修了索引，没修实体文件） | C2 | **P1** | `download_commit.dart` |
| X9 | **L5 下载 IO 直连未修**：download_manager:344 HttpClient + :359 File、download_commit/paths 多处（A5 已报，仍存在） | C1 | **P0(架构)** | download 域无 L4 端点模块 |
| X10 | 六桥失守：AppGraph 暴露 SongDao/HistoryDao/Client，library_page:33 直取 L4 DAO | C1 | **P1(架构)** | `library_page.dart:33` |
| X11 | 文案未接 S.of：library 13 行、playlist 20 行中文零接线 | C3 | **P2** | 两页面 |

## 2. 76 合规裁决（C1 权威）

- 依赖方向正确，无反向 import；层职责基本合规（download IO 直连为阶段A已裁定例外）。
- 主要问题非越级，而是「该接的线没接」：L6 装配层漏接 L5 的 resetLocalMirror/onChanged，L5→L7 事件通道（onTask/onChanged）建而不用；缓存「一个域」未落实（三套缓存表）。

## 3. 与用户痛点对应

| 用户原话 | B5 定位 |
|---|---|
| 「什么功能都用不了」 | 下载点了没进度/重启没了、歌单写完全没入口、换号收藏串、缓存预读白做 |
| 「文案没改」 | library/playlist 33 行中文零接线 |

## 4. B5 结论
三视角全落盘。核心定调「能力存在≠用户可用」——阶段 A 的入口/写入修复生效，但 L6/L7 接线缺失导致用户仍感知不到。真 P0×2（onTask 断、下载 IO 越层）、P1×8、P2×1。

## 5. 下一步
阶段 B 继续 B6（UI/M3/动画/取色跨层）。所有修复待 B1~B7 全完后主会话统一亲修 + CI。B5 定时器 `c8ba377a` 已触发，本轮已收口。
