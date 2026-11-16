# B1 批 · 交叉汇总（登录全链路 + YKG + 文案）· 草稿（待 C1 收口）

> 2026-11-17。三视角：`bB1_c2.md`（正确性，已到）、`bB1_c3.md`（痛点，已到）、`bB1_c1.md`（架构，运行中）。
> 本批重点：验证阶段 A 的 YKG / VIP / 20028 修复是否在跨层链路上真正生效。

## 0. 阶段 A 修复的跨层验证结果

| 阶段A修复 | 跨层验证结论 | 证据 |
|---|---|---|
| **VIP 恒 false** | ❌ **未闭环，P0 仍在**：bootstrap:125-128 构造 PlaybackService 时读一次 settings 的 vip 值做快照 Map；登录发生在启动之后，快照不刷新 → 启动后新登录的 VIP 用户仍恒按匿名音质。阶段 A 只覆盖「启动时已登录（restoreSession）」场景。 | C2 + 主会话核实 `bootstrap.dart:118-128` |
| **20028 验证死链** | ❌ **未闭环，P0 仍在**：阶段 A 打通了 session→VerificationLogic.onVerificationRequired 置 required，但 getVerifyInfo/submitVerification 仍 return false 不发请求，且 L7 无任何验证 UI 出口 → 用户遇 20028 仍卡死。 | C2 + C3 |
| **YKG 端到端** | ⚠️ **部分通，有断点**：编解码逻辑正确（C2 确认阶段A两处编译修复逻辑对）；但导入后的通知打到**从未 attach 的 AuthSession**（全仓 `AuthSession.instance.attach` 零调用）→ notify 无消费者、UI 不刷新；`onAuthChanged` 无消费者、不 bumpAuth。 | C2 + 主会话核实 |
| **i18n 接线** | ⚠️ **新代码全接，存量未接**：ykg_sheet 0 处硬编码；login_sheet 32 + account_section 4 处中文未接 S.of；登录页仍暴露 3 处开发状态文案（接口待实测/needs probe/待后端就绪）。 | C3 |

## 1. 共识/关键问题（待 C1 补充架构视角）

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **VIP 快照未刷新**（登录后不更新 PlaybackService._session） | C2 + 主会话 | **P0** | `bootstrap.dart:118-128` + `playback_service.dart:_hasRights` |
| X2 | **20028 验证 UI 出口缺失 + 端点不发请求** | C2 + C3 | **P0** | `verification_logic.dart:88-121` + L7 全域 |
| X3 | **AuthSession 从未 attach**，YKG 导入 notify 无消费者 | C2 + 主会话 | **P1** | 全仓 `AuthSession.instance.attach` 零调用 |
| X4 | **YKG 加密设计**：过期/字段未绑定 AAD（exp/d/userid 不在 GCM aad 内），理论上可被篡改而 tag 仍有效（需 d 指纹兜底，已有 d 但 m/exp 未绑） | C2 | **P1** | `ykg_codec.dart:105-118,133-140` |
| X5 | **YKG UX 8 处困惑**：导出链接显示/密码≥6位校验与 verifyPassword 脱节/有效期不展示/过期误报密码错（UI 吞错误码）/无二维码/剪贴板不清/来源不标记 | C3 | **P1** | `ykg_sheet.dart` + `ykg_logic.dart` |
| X6 | 登录页开发状态暴露用户 3 处 | C3 | **P2** | `login_sheet.dart` |
| X7 | 登录页/账号区 36 处硬编码中文未接 S.of（ykg_sheet 0 处，全接） | C3 + C1(33处) | **P2** | `login_sheet.dart` + `login_account_section.dart` |
| X8 | **bridge_core 越权导出**：把 L4 端点函数 + YKG 密码学原语 export 到全层，L7 可绕过 L5；login_sheet:13-14 已握 sendSmsCode/smsLogin（未用） | C1 | **P1(架构)** | `bridge_core.dart` + `login_sheet.dart:13-14` |
| X9 | **QR 状态机劈两半**：枚举在 L5，轮询驱动/过期重建策略在 L7 Widget（login_sheet:147-247），违反 L7 无状态机 | C1 | **P1(架构)** | `login_sheet.dart:147-247` |
| X10 | 凭据写入双路径 + 8 个键名复制；密码登录 dynamic 逃逸无收口；QR 端点无独立 endpoints 模块 | C1 | **P2** | C1 报告 |

## 3. 76 合规裁决（C1 权威）

- 阶段 A 修复的分层合规已确认：ykg_logic→bridge_session 反向依赖清零、cryptography 仅落 L4、无文件超 1500 行。
- 本批架构问题：bridge_core 越权导出（X8）、QR 状态机在 L7（X9）、登录态双广播总线（X3）——都是跨层接缝的桥/状态机归位问题。

## 4. 主会话复核修正（交叉裁定）

- C3「导出看不到链接」：ykg_sheet 导出成功后有 `_link.text = link` 显示于文本框，此条**部分误判**——但确实没有独立的"链接已生成可复制"显式提示，体验仍可改进，保留 P2。
- C3「过期误报密码错」：**成立**——`decodeYkgLink` 内部对过期单独 return `fail('link expired')`，但 L7 `_doImport` 不看具体 error，统一显示 `ykgWrongPassword`。这是 UI 层吞掉底层错误码的跨层接缝问题。

## 5. 76 合规裁决（已补 C1）

见 §3。C1 确认：阶段 A 的 YKG 分层修复合规（反向依赖清零、cryptography 仅 L4），但 bridge_core 越权导出、QR 状态机在 L7、登录态双广播是新的跨层接缝债。

## 6. B1 结论

三视角全落盘。阶段 A 三个关键修复的跨层验证：**AES Rcon 逻辑正确（编译修复无误）**；但 **VIP 快照（P0）、20028 验证出口（P0）、YKG 通知断链（P1）三个跨层闭环未完成**——这正说明阶段 B 的价值：单点修复不等于链路通。共识 P0×2、P1×6、P2×3。

## 7. 修复提示（阶段 B 全部审完后主会话亲做）

- VIP：改成 `_hasRights` 实时读 settings/AuthSession，而非构造时快照；或登录成功后重建 PlaybackService。
- 20028：L7 需真实验证 UI 出口，端点实测前至少明示"验证暂不可用"，不留假卡死。
- AuthSession：bootstrap 补 attach + onAuthChanged 消费者 + bumpAuth。
- YKG AAD：把 exp/userid/d 绑进 GCM aad 或直接用 d 指纹作为唯一完整性判据（已有 d，m/exp 可移除或绑定）。
- YKG UX：UI 区分过期/密码错错误码；有效期展示；二维码（复用 qr_codec）；剪贴板定时清空；来源标记。
