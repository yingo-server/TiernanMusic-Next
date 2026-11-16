# A5 批 · 交叉汇总（L5 logic 全量 34 文件）

> 2026-11-16。三视角：`bA5_c1.md`（架构）、`bA5_c2.md`（正确性）、`bA5_c3.md`（痛点）。
> 本批 P0/P1 均为静态取证充分的功能断链/假承诺（非算法争议），主会话对最关键的 VIP 判定做了装配点复核（`bootstrap.dart:115` 未传 session + KugouSession 无 vip 字段 → 采纳）。

## 0. 关键问题

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **VerificationLogic 20028 验证死状态机**：getVerifyInfo 恒 false、submitVerification 直接 return false 不发请求、solved/failed 永不可达、全仓零消费者；playback_session 遇到 20028 只拼错误文案不触发验证 → 用户遇验证必卡死 | C2（主）+ C3 | **P0** | `verification_logic.dart:27-120` + `playback_session.dart:235-242` |
| X2 | **VIP 权益判定恒 false**：bootstrap 构造 PlaybackService 未传 session（可选参数省略）+ KugouSession 无 vip_token/vip_type → `_hasRights` 永 false → VIP 用户永远按匿名音质降级 | C2（主会话复核确认） | **P1** | `playback_service.dart:113-165` + `bootstrap.dart:115-119` + `kugou_client.dart:17` |
| X3 | **MV logic 三重错位传导**：qualities/playUrl 入参 hash 冒充数字 video_id、遇端点恒 null 后兜底 100% 早退（叠加 A3 端点 P0） | C2 + C3 | **P1** | `mv_logic.dart:33-50,66-88` + `playback_service.dart:283-330` |
| X4 | **L5 IO 直连（6 处）**：download_manager HttpClient+File、url_health HttpClient、lyrics_logic/playback_service File IO → 违反 76 §0「logic 无 IO 直连」 | C1 | **P1(架构)** | C1 结论 |
| X5 | **logic 空壳/恒空/零消费 12 文件**：20028 验证、整套 PlayResolver 死代码、FM/MV 三态、评论/歌单写/专辑/歌手等 | C2 + C3 | **P1** | 见 bA5_c3 |
| X6 | **收藏/下载 logic 实现完整但零调用**（上层无入口，A1/A3 已定位） | C2(确认) + C3 | **P1** | collect_logic.toggle / download enqueue |
| X7 | **YKG l5 落点缺失**：ykg_logic.dart 不存在，但 cookieBlob/token/mid/dfid 素材现成；应新建 L5 仅编排、crypto 落 L4、弹层文案落 L7 | C3 | **P1(需求)** | bA5_c3 YKG 节 |
| X8 | 文案泄漏 12 处（用户可见 4 处）；TnStrings 全仓零调用（与 A4 呼应） | C3 | **P2** | bA5_c3 |
| X9 | 依赖方向/桥通道/状态机归属/1500 行门禁全部合规，无反向依赖、无 P0 架构违规 | C1 | 合规 | C1 结论 |

## 1. 76 合规裁决（C1 权威）

- 依赖方向、桥通道、状态机归属（播放状态机在 L5 正确）、行数门禁：**全绿**。
- 主要架构债：6 处 IO 直连（X4）——修复时能下沉 core 的下沉，下载/URL 探测这种确需 IO 的登记例外或移到 core/storage、core/net。

## 2. 与用户痛点对应

| 用户原话 | A5 定位 |
|---|---|
| 「什么功能都用不了」 | X1 验证卡死、X3 MV 三重断、X5 十二个空壳、X6 收藏下载有实现无入口、X2 VIP 权益失效 |
| YKG | X7 ykg_logic 落点（素材现成，待建） |
| 文案没改 | X8 12 处泄漏 + TnStrings 零调用 |

## 3. 本批结论
A5 达成：三视角全落盘；P0 1 个（验证死状态机，采纳）；P1×6；架构 IO 直连债 6 处；VIP 判定经装配点复核确认真 bug。至此阶段 A 已收口 A1–A5。

## 4. 下一步
阶段 A 继续 A6（session 全量 8 文件 + 六桥 6 文件）。所有修复待 A1~A7 全完后主会话亲做。A5 定时器 `ee09d5cb` 已取消（三份齐）。
