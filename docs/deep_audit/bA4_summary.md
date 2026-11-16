# A4 批 · 交叉汇总（L4 core 非网络 15 文件）

> 2026-11-16。三视角：`bA4_c1.md`（架构）、`bA4_c2.md`（正确性）、`bA4_c3.md`（痛点）。
> 特别：QR off-by-one 经主会话 Python 仿真复核（`A4_QR_VERIFICATION.md`）——确认 bug、修正后果描述（布局错位非码字丢失）。

## 0. 复核裁定
| 发现 | 裁定 |
|---|---|
| qr_codec.dart:283 列对从 size-2 起 | ✅ 真 P1（漏列7+最右列，布局错位标准扫码器读不出；但码字不丢，C2 后果描述有误） |

## 1. 关键问题（共识 + 单视角）

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **QR 数据放置 off-by-one**，V1–V4 布局错位，标准扫码器读不出（当前死代码，YKG 扫码前必修） | C2(复核确认) | **P1** | `qr_codec.dart:283` |
| X2 | **download_store 索引先删后 rename 有崩溃空窗**，可丢全部下载记录 | C2 | **P1** | `download_store.dart:116` |
| X3 | **resource_cache 写失败静默 return + _saveIndex 返回值忽略**，数据/索引不一致无信号 | C2 + C3(缓存固化旁证) | **P1** | `resource_cache.dart:339-372,352` |
| X4 | **缓存实现体分散**：磁盘在 storage/、网络在 net/、cache/ 仅门面，与 76 §3「一个域」不符；DB 开门面错放 net/（与 A2 呼应） | C1 | **P1(架构)** | C1 结论1/2 |
| X5 | **动态取色链全断**：L4 算法（提取+HSL+降级）完整健壮，但零消费者，缺口在 L6/L7 接线 | C3 + M3基线 | **P1** | `color_extract.dart` |
| X6 | **TnStrings/i18n 取词器死代码**：10 语常量表齐全但与 10 ARB 键一致，**全仓零业务调用** → 用户「文案没改」在 core 侧落实为零 | C2 + C3 | **P1** | `strings.dart:280-295` |
| X7 | **通知栏**：updateMetadata 已实现且 L6 已调用（历史零调用 bug 已修）；残留初始化竞态致首曲元数据丢失、onSeek 死字段、状态多跳同步 | C3 | **P2** | `notification_gateway.dart` |
| X8 | strings.dart import bridge_core 取同层 storage，bridge_core 又导出 strings → 回环（违反 76 第1/4条精神）；15 文件统一经 bridge_kernel 取 Log 属桥相邻错位待裁定 | C1 | **P2** | C1 结论3 |
| X9 | resource_cache FNV-1a 负哈希产生含 '-' 不定长文件名（native 位模式对、web 目标风险） | C2 | **P2** | `resource_cache.dart:158-200` |
| X10 | cache_service get 失败吞成空 Map、无按 key/namespace 失效 API；空结果落 L2（net 根因） | C2 + C3 | **P2** | `cache_service.dart:139-158` |

## 2. 76 合规裁决（C1 权威）

- 层职责纯净（audio/notification 用成熟库 just_audio/audio_service 合规）；无反向依赖、无 UI 泄漏。
- 架构瑕疵：缓存「一个域」未落实（X4，P1）、strings↔bridge_core 回环（X8，P2）。
- LRU 淘汰算法正确（C2 已核）；DB 竞态本层未复现（A1 的 main DB await 分歧仍待主修裁定）。

## 3. 与用户痛点对应

| 用户原话 | A4 定位 |
|---|---|
| 「UI 不舒服」 | X5 动态取色全链断（L4 有能力、L6/L7 没接） |
| 「文案没改」 | X6 TnStrings 死代码，i18n 表内一致但全仓零调用 |
| 「功能用不了」 | X2 下载记录可丢、X3 缓存不一致、X7 通知栏首曲元数据丢 |
| YKG | X1 QR bug（当前死代码，扫码导入前必修）、X6 i18n YKG key 缺 |

## 4. 本批结论
A4 达成：三视角全落盘；复核 1 项（QR，确认 bug 修正后果）；P1×6、P2×4；架构主干 76 基本健康，缓存域分散是主要架构债。

## 5. 下一步
阶段 A 继续 A5（logic 全量 34 文件）。所有修复待 A1~A7 全完后主会话亲做。A4 定时器 `4c99fead` 已取消（三份齐，提前收口）。
