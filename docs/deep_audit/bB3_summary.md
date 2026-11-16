# B3 批 · 交叉汇总（播放主链路 跨层）

> 2026-11-17。三视角：`bB3_c1.md`（架构）、`bB3_c2.md`（正确性）、`bB3_c3.md`（痛点）。均已落盘。

## 0. 阶段 A / B1 修复的跨层验证

| 修复 | 结论 | 证据 |
|---|---|---|
| VIP 恒 false（阶段A修了 bootstrap 传 session） | ❌ **P0 仍未闭环**（B1 X1 延续）：bootstrap:118 构造时快照注入 + `_session` final，启动后登录不刷新 → VIP 用户恒匿名音质；叠加 super/蝰蛇/多轨档位无端点映射、UI 勾选硬编码 128 | C2 + C3 + B1 |
| 20028 验证（阶段A修了 session→门面触发） | ❌ **仍卡死**：VerificationLogic 置 required 但 L7 无验证 UI 出口、端点不发请求 | C3 + B1（跨批共识） |
| 通知栏 updateMetadata（阶段A A4 报过已修"零调用"） | ⚠️ **部分修**：元数据正确、上下曲/播暂停可用；但 initNotification 异步赋值致首曲元数据丢失、onSeek 未绑定、handler 直驱引擎致进度失同步 | C2 + C3 |

## 1. 关键问题

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **VIP 提档链 P0**（构造快照，登录后不刷新 + 档位映射缺失） | C2 + C3 + B1 | **P0** | `bootstrap.dart:118` + `playback_service._session final` + `quality_policy` |
| X2 | **20028 验证零 UI 出口**（用户必卡死） | C3 + B1 | **P0** | L7 全域 + `verification_logic.dart` |
| X3 | **错误文案写 lastError 但播放页不读**（VIP/无源提示均不可见） | C3 + C2(lastError 未透传) | **P0** | `playback_session` lastError + `player_page` |
| X4 | **单曲循环失效**：loopOne 按钮只高亮不重播，播完仍跳曲；`_start` 每次 `const QueueState()` 重建致 shuffle 切一首即回退 | C1 + C2 + C3 | **P1** | `playback_session._start` + 循环按钮 |
| X5 | **PlayResolver 四件套 681 行死代码**（A5 问题仍在），真实链路在 PlaybackService 重复手写且缺 url_health 健康检查 | C1 + C2 | **P1** | `lib/logic/player/play_resolver.dart` 等 |
| X6 | **状态机未下沉**：L6 playback_session 持有 `_queue/_player` 直驱 playbackReducer 18 处、队列直驱 6 处（A6 报 ≥10，未修反增），违反铁律 8 | C1 | **P1(架构)** | `playback_session.dart:80-81,146-420` |
| X7 | **状态双写不同步**：`_sourceKind`（L6 私有只写不读）与 `PlayerState.sourceKind`（L7 读）永不同步 → "试听音源"提示恒不显示 | C1 + C2 | **P1** | `playback_session.dart` |
| X8 | 通知栏首曲元数据丢失（异步赋值竞态）、onSeek 悬空、L4 越权 seek 引擎致进度失同步 | C1 + C2 + C3 | **P1** | `notification_gateway.dart` + `bootstrap` |
| X9 | 预读接缝 no-op、url_health L5 直连 HTTP IO、文案未接 S.of 约 27 处 | C1 + C3 | **P2** | 见各报告 |

## 2. 76 合规裁决（C1 权威）

- 合规：L7 零状态机、六桥通道、成熟库边界、1500 行门禁、桥日志均符合。
- 违规：状态机未下沉（X6，铁律 8），L4 通知网关越权 seek 引擎（X8）。

## 3. 与用户痛点对应

| 用户原话 | B3 定位 |
|---|---|
| 「什么功能都用不了」 | VIP 提档失效、单曲循环失效、错误提示不可见、20028 卡死、进度失同步 |
| 「文案没改」 | 播放页/mini_bar 27 处中文未接 S.of |

## 4. B3 结论
三视角全落盘，高度共识。P0×3（VIP/20028/lastError 不可见）、P1×5、P2 若干。阶段 A 的 VIP 修复经跨层验证**仍未闭环**——三次审查（A5/B1/B3）持续命中同一根因。

## 5. 下一步
阶段 B 继续 B4（MV 播放跨层，验证阶段 A 四重断点修复是否真通）。所有修复待 B1~B7 全完后主会话亲做。B3 定时器 `50570d18` 已取消。
