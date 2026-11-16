# A1 批 · 交叉汇总（init + bootloader + kernel + bridge_boot + bridge_kernel）

> 汇总时间：2026-11-16。三视角报告：`bA1_c1.md`（架构合规）、`bA1_c2.md`（实现正确性）、`bA1_c3.md`（用户痛点/全局盘点）。
> 交叉规则：多视角同指一处=确认并升级；单视角独有=保留待 B 阶段跨层复核；分歧=列明。

## 0. 共识问题（≥2 视角命中，优先级上调）

| # | 问题 | 命中视角 | 定级 | 证据锚点 |
|---|---|---|---|---|
| X1 | **MV 模块不可达**：启动期占位模块抢占 id `mv`，L7 `registerMvModule()` 见 id 存在即 return，真实 MvPageModule 永不注册；且 builder 硬编码 `songHash:''` | C2 + C3 | **P0** | `bootstrap.dart:216-232` + `mv_page.dart:12-20,30-32` |
| X2 | **MV hash 语义错配**：MV 页把歌曲 hash 当 video_id 送 `getVideoQualities`，正确须先 `getMvBySong(albumAudioId)→mvBrief.hash` | C3（C2 部分覆盖启动面） | **P0** | `mv_page.dart:32` + `mv_logic.dart:32,48` + `playback_service.dart:291` |
| X3 | **boot 失败被误判成功**：`bridge_boot.fromAny` 非 Map 分支硬编码 `rejected=false`，真实 `BootResult(rejected:true)` 原因不上抛，main 显示误导文案 | C2（C1 旁证桥职责混乱） | **P0** | `bridge_boot.dart:65-79` + `bootloader.dart:92` |
| X4 | **kernel / bridge_kernel 空壳**：L3 kernel 无生命周期/模块表（get<T> 必抛），`bridge_kernel.assembleKernel` 零调用；Log/kernel 反而从 bridge_boot re-export，或用 bridge_logic/session/surface 直连 kernel → bridge_kernel 唯一出口名存实亡 | C1 + C2 | **P1** | `kernel.dart:5-34` + `bridge_boot.dart:7` + C1 桥核查表 |
| X5 | **跨层直连**：`main.dart:18` L1 直连 bridge_surface（L6↔L7）跨 5 层；`bootloader.dart:13-14` L2 直取 L5（经桥但非相邻）；多处直连 kernel | C1 | **P1** | `main.dart:18` + `bootloader.dart:13-14` |
| X6 | **异常吞没**：restoreSession、启动期 prefetch 未 await 且异常被吞（缓存全空却报启动成功）；`__raw` 管线空操作丢弃 BootResult | C2 | **P1** | `bootstrap.dart:200-215` + `main.dart:114` + `app_root.dart:92-94` |
| X7 | **AuthLogic 双实例**：L2 与 L6 各构造一个（历史同款 settings 双实例互盲） | C2 | **P1** | C2 boot 装配段 |
| X8 | **死代码/占位**：`mv_anonymous.dart` 227 行（registerDevice/anonymousPlayUrl）全仓零调用；`bootBridgeInstalled`/`register.dart:13-14` 无消费者；comment/album/artist id 永远停在占位模块 | C2 + C3 | **P1** | `mv_anonymous.dart:57,144` + `register.dart:13-27` + `bootstrap.dart:216-232` |

## 1. 单视角独有（保留，B 阶段复核）

- C3：**下载 enqueue 零调用（实现无入口）**、**收藏按钮纯本地 setState 不落库**（`CollectLogic.toggle` 零调用）— 属跨层功能链，B5 复核。**P0**。
- C3：`login_sheet` 密码/验证码登录端点标注「待实测」却 UI 承诺「后端就绪」— 文案诚信问题，B1 复核。**P1**。
- C2：`main.dart:41-47` 存储根失败回落 `'.'` 相对路径（生产写错位置）；`main.dart:90-93` DB future 类型判断 `is Future<bool>` 静默跳过 await（DAO 首访 StateError）。**P0**（DB 项与 C1「DB 已 await」结论**分歧**，见 §2）。
- C1：无影子桥（合规确认）；例外登记 `init→register` 仍使用且合理。
- C3：i18n 与 strings.dart 一致性、全仓硬编码中文清单（详见 `bA1_c3.md` 前两节）。

## 2. 分歧（需复核）

- **DB await 状态**：C1 判「DB future 已 await，竞态已修」，C2 判「`main.dart:90-93` `if (dbFuture is Future<bool>)` 静默跳过 await，`dbOpenFuture` 不在 requiredDeps → 首屏 StateError」。
  - 处置：主会话亲修阶段**读 `main.dart` 原文裁定**；倾向 C2（它给了具体行号与类型判断），记为**待确认 P0**。
- 无其他实质分歧。

## 3. 76 合规裁决（C1 权威）

- 层归属：init/bootloader/kernel 大体守职责，但 L1/L2 有跨层直连（X5）。
- 六桥：bridge_boot 承担了 bridge_kernel 的职责（X4），brace_kernel 名存实亡——**违反第 2 条（桥 try/catch+Log）的第 4 条（相邻桥唯一通道）**。
- 影子桥：无（合规）。
- 例外登记：`init/main→bootloader/register` 合规且仍使用。
- 端点分文件：符合（本批无端点改动）。

## 4. 与用户痛点对应

| 用户原话 | A1 已定位 |
|---|---|
| 「什么功能都用不了，MV 等等」 | X1+X2（MV 双重断点）、死代码 mv_anonymous、下载无入口、收藏假按钮 |
| 「文案没改」 | C3 硬编码中文清单 + 登录端点「待实测」却 UI 承诺 |
| 「密码学自己设计→纠正为成熟库封装」 | X：YKG 全仓零实现；设计稿已改为成熟库 + 自有封装（见 `docs/YKG_LINK_CRYPTO_DESIGN.md`） |
| 「UI 不舒服/动画/细节」 | 本批未覆盖（A7 + B6），主会话已采 M3 基线（`M3_BASELINE.md`） |

## 5. 本批结论

A1 达成目标：三视角各自完整落盘；共识 8 条（6×P0/P1 级）、分歧 1 条（DB await）、功能可达性断点 5 类。
**C3 因 503 中断收尾，但正文 27075 字节已含所需四节（i18n/硬编码/YKG/功能可达性），判为可用，不重派。**

## 6. 下一步

阶段 A 继续 A2（core·net 底座）；所有修复待 A1~A7 全完后主会话亲做。定时器已被用户 Stop All 取消，A2 改由主会话在每批发完后**即时设定**新的单次定时器。
