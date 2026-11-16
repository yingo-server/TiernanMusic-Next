# A2 批 · 交叉汇总（L4 core·net 底座）

> 汇总时间 2026-11-16。三视角：`bA2_c1.md`（架构合规）、`bA2_c2.md`（实现正确性）、`bA2_c3.md`（用户痛点）。
> **特别**：本批两个密码学 P0 经主会话用 Python 精确仿真独立复核（`A2_P0_VERIFICATION.md` + `verify_*.py`），结论一真一假，以下汇总以复核结果为准。

## 0. 复核后的裁定（最高优先级）

| 子代理 P0 | 复核裁定 | 依据 |
|---|---|---|
| `crypto_aes.dart:574` AES Rcon 恒 0x01 | ✅ **真 P0** | FIPS-197 C.1 向量：const1→`891a2af9…` FAIL，标准 Rcon→`69c4e0d8…` PASS |
| `crypto_bigint.dart:82` BigIntL.mul 溢出 | ❌ **误报，撤销** | 完整 mul 仿真 10 万组 + modPow 3000 组，错误数 0；数学上 a*b 自带 2^33 余量，不越 int64 |

→ **只修 AES，禁止改 RSA**（改了反而破坏正确的 modPow）。

## 1. 共识问题（≥2 视角，优先级上调）

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **AES Rcon 恒 0x01**，第 2–10 轮密钥全错，与标准 AES 不互通（自洽测试测不出） | C2 + C3 + 主会话FIPS向量确认 | **P0** | `crypto_aes.dart:570-575` |
| X2 | **缓存失效语义未根治**：业务失败(HTTP200+status!=1/空数据)按 7 天 TTL 固化；cacheKey 构造异常降级为 method+path 粗键→跨用户脏命中 | C2 + C3 | **P1** | `kugou_client.dart:94,108-115,135-143` + `resource_cache.dart:69` |
| X3 | **inflight clear 竞态**：finally 无身份校验 remove，clear 后旧任务误删新在飞条目→单飞失效（文件头已自认未改） | C2 + C3 | **P1** | `inflight.dart:62` |
| X4 | **错误码无文案映射**：20006/20028/200103 等已知坑无统一 code→i18n 映射；上层 `$e` 直显硬编码中文（≥12 处） | C3(主) + C2(异常吞没旁证) | **P1** | `cache_service.dart:110-120` + 各页面 |
| X5 | **动态取色链断裂**：`core/algorithms/color_extract → session/theme_controller` 写了，但 L7 无消费者；`NetworkPhaseTracker` 全量死代码（写了没接） | C1(死代码) + C3 | **P1** | `color_extract.dart` / `network_phase.dart` |
| X6 | **明文 http:// 2 处**：loginToken(L368)、sendSmsCode(L410) | C1 | **P2** | `endpoint_registry.dart` |
| X7 | **死代码/卫生**：`network_phase` 整模块、`fetchCoverBytes`、`SignType.register` 签名链均零调用；bridge_core 对 core/net 有 10+ 处重复 export；database_opener 目录错位 | C1(主) + C3 | **P2** | 见 C1 结论 5/7 |

## 2. 单视角独有（保留待 B/A6 复核）

- C2：`cover_color.dart:35-40` body 流无整体超时（涓流攻击致永久悬挂）；rawBody Content-Type 恒标 application/json 与实际编码不符；dfid 用时间戳派生非真随机（契约偏离）。P2。
- C2：`models_util.dataOf` 遇数组 data 静默返回空、safe* 工具 0/null 折叠——字段解析容错盲区。P2（translation id=0 / priv_status 历史坑同款）。
- C3：超时最坏 ~40s 且无重试/取消；缓存开关默认值与时效语义错位。P1/P2。
- C1：Log 全局桥引用（core/logic/session ← bridge_kernel.Log）对「禁反向依赖」呈灰色——**待 A1/A6 全局依赖图交叉裁定**，倾向确认为既定例外（日志桥全局可见）。

## 3. 76 合规裁决（C1 权威）

- 层归属 / 依赖方向 / 端点一文件一模块 / 域名白名单 / 1500 行门禁：**五项全绿**，core/net 是健康的 L4。
- 唯一灰项：bridge_kernel.Log 全局引用（待裁定）；明文 http 2 处（安全 P2，非分层违规）。
- 成熟库边界（§0-9）：全自研 MD5/AES/RSA + AES 有 bug → 印证 YKG 新代码必须走成熟库、不复用 AesCbc（设计稿 §8 已定）。

## 4. 与用户痛点对应

| 用户原话 | A2 定位 |
|---|---|
| 「什么功能都用不了」 | 缓存固化 7 天（失败自愈难）、单飞竞态、取色链断、NetworkPhase 没接、错误码无文案 |
| 「密码学自己设计」→纠错成熟库封装 | C3 确认全自研且 AES 有 bug；设计稿成熟库路线方向正确，需补 4 项（依赖可用性门禁/base64Url说明/MD5措辞/禁用AesCbc声明） |
| 「文案没改」 | 错误态 i18n key 为 0、YKG 文案 key 全缺、上层 `$e` 直显 ≥12 处 |
| 「UI/动画/细节」 | 本层纯 Dart，MD3 十类 N/A（归 A7/B6） |

## 5. 本批结论

A2 达成：三视角完整落盘；**真 P0 仅 1 个（AES Rcon）**，RSA 误报已撤销；共识 P1×5、P2×2；架构主干 76 全绿。
C1/C3 回调未到但正文完整（179/303 行，含全部收口小节），判可用。

## 6. 下一步

- A2 定时器 `8f101ba9`（50min）仍在，到期会自动触发收口 + 派 A3。但三份报告已齐，主会话可**提前收口并派 A3**，不必等定时器。
- AES Rcon 真 P0 已明确，留待阶段 A 全审完后主会话亲修（优先用成熟库替换 AesCbc，符合用户纠正）。
