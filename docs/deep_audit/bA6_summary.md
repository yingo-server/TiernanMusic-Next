# A6 批 · 交叉汇总（L6 session 8 文件 + 六桥 6 文件）

> 2026-11-16。三视角：`bA6_c1.md`（架构）、`bA6_c2.md`（正确性）、`bA6_c3.md`（痛点）。
> 本批 P0 均为跨批共识（下层已报、此处跨层确认），静态取证充分，无算法争议。

## 0. 跨批共识 P0（多视角 + 多批次命中，最高优先级）

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **boot 失败被误判成功**：bridge_boot.fromAny 对象分支硬编码 rejected=false，真拒绝原因被吞，main 误显示「核心模块缺失」 | A1-C2 + A6-C2 + A6-C1(旁证) | **P0** | `bridge_boot.dart:64-79` |
| X2 | **20028 验证死链**：playback_session 靠 toString().contains 判错，命中后不触发 VerificationLogic；VerificationLogic 本身 submitVerification 直接 return false（A5 P0）→ 用户遇验证必卡死 | A5-C2 + A6-C2 + A6-C3 | **P0** | `playback_session.dart:196-241` + `verification_logic.dart` |
| X3 | **MV 模块永不注册**：bootstrap 占位模块抢占 id `mv`，mv_page 守卫「id 存在即 return」恒真；叠加端点恒 null(A3)、hash 冒充 videoId(A5)、上层传错 hash(A1) → MV 四重断点 | A1-C2 + A3 + A5 + A6-C1/C2/C3 | **P0** | `bootstrap.dart:216-232` + `mv_page.dart:12-20` |

## 1. 关键 P1

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X4 | **playback_session 越界持有并驱动 L5 队列/reducer 状态机**（≥10 处），违反 76 §0-8（L6 不该持有状态机） | C1 | **P1(架构)** | `playback_session.dart` |
| X5 | **动态取色链 100% 断**：ThemeController 不接 L4 color_extract，L7 固定绿；取色能力在 L4 现成但 L6/L7 都没接 | C3 + A4 基线 | **P1** | `theme_controller.dart` |
| X6 | **YKG 会话零注入接口**：auth_session 无导入凭据后注入 client 的能力；导出/导入编排（L5 ykg_logic）也不存在 | C3 + A5 | **P1(需求)** | `auth_session.dart` |
| X7 | **main 直连 bridge_surface 跨 5 层 + bridge_boot re-export kernel 致 bridge_kernel 名存实亡**（A1 遗留仍在，未修） | C1 + C2 | **P1(架构)** | `main.dart:18` + `bridge_boot.dart:7` |
| X8 | 通知栏 seek 不回写、sourceKind 写而不读、单曲循环 loopOne 按钮无实现（播放会话体验断点） | C2 + C3 | **P1/P2** | `playback_session.dart` |
| X9 | 文案泄漏 3 行（playback_session 149/239/249）；桥日志无凭据泄漏（正面） | C3 | **P2** | `playback_session.dart` |

## 2. 76 合规裁决（C1 权威）

- L6 无 Widget、无影子桥、无 session→surface import、14 文件均 <1500 行——基本合规。
- 主要架构违规：playback_session 越界持有 L5 状态机（X4，§0-8）、main 跨 5 层直连桥（X7）——修复阶段需把状态机下沉回 L5、main 改经相邻桥。

## 3. 与用户痛点对应

| 用户原话 | A6 定位 |
|---|---|
| 「什么功能都用不了」 | X1 boot 误判、X2 验证卡死、X3 MV 四重断、X8 播放体验断点 |
| 「UI 不舒服」 | X5 取色链 100% 断，L7 固定绿（ThemeController 是断链点） |
| YKG | X6 auth_session 零注入接口 + L5 ykg_logic 缺失 |

## 4. 本批结论
A6 达成：三视角全落盘；P0×3（全为跨批共识）、P1×5、架构违规 2 处。阶段 A 已收口 A1–A6，仅剩 A7。

## 5. 下一步
阶段 A 最后一批 A7（surface 18 文件 + l10n arb + 文案，用户 UI 痛点主战场）。所有修复待 A1~A7 全完后主会话亲做。A6 定时器 `9d1149b5` 已取消（三份齐）。
