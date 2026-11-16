# A3 批 · 交叉汇总（L4 core·net endpoints 全 26 文件）

> 汇总时间 2026-11-16。三视角：`bA3_c1.md`（架构合规）、`bA3_c2.md`（实现正确性）、`bA3_c3.md`（用户痛点）。
> **特别**：C2 报的 MV P0 与 C3「接口正确」冲突，主会话用仓库实测留样复核，**确认 C2 为真 P0**（见 `A3_MV_P0_VERIFICATION.md`）。C1/C3 因模型服务 DNS 抖动开局失败后重派成功，C2 因 app 重启丢失后重派成功——均已完成。

## 0. 复核后的裁定

| 发现 | 裁定 | 依据 |
|---|---|---|
| `mv_endpoints.dart:57,287` MvBrief 不读 video_id、以不存在的 hash 为门槛 | ✅ **真 P0** | 实测留样 `mvItem` 只有 video_id 无 hash；fromMap 读三键均不存在→hash 空→getMvBySong 恒 null；field_truth 从不断言 hash |

## 1. 共识/关键问题

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **按歌查 MV 恒返回 null**（MvBrief 字段解析错 + 成功门槛错） | C2(复核确认) | **P0** | `mv_endpoints.dart:57,287` |
| X2 | getVideoQualities 用 32 位 hash 冒充数字 video_id → 档位恒空 | C2（C3旁证接口参数） | **P1** | `mv_endpoints.dart:305,324` |
| X3 | 匿名 MV 链（mv_anonymous 227 行）死代码半成品、标待实测、上游实测恒 20028 | C3(主) + C2 | **P1** | `mv_anonymous.dart` |
| X4 | 5 个登录端点标注待实测却 `kAuthEndpointsProbed=true` 放行真实凭据外发，且依赖有 Rcon bug 的 AesCbc | C2 + C3 | **P1** | `auth_endpoints.dart:38` |
| X5 | `fetchTranslation` 恒返回空 TranslationResult 的死代码，仍被 bridge_core 导出 | C2 + C3 | **P1** | `translation_endpoints.dart:137-152` |
| X6 | 端点层用户可见中文 10 处（MV 档位 6 + 评论错误 4），无 i18n key；档位命名倒挂（540P「超高清」>1080P「全高清」） | C3 | **P1** | `mv_endpoints.dart:141-145,175` + `comment_endpoints.dart` |
| X7 | 死端点约 7 组（getPrivilegeLite/用户域4/翻译2/上报等）有实现+桥导出但上层零调用 | C3 | **P1** | 见 bA3_c3 |
| X8 | user uploadPlayHistory/reportListen 成功判定用 `\|\|` 过宽，业务失败可能判成功 | C2 | **P1** | `user_endpoints.dart:209,340` |
| X9 | mv_anonymous:114 明文记录 dfid 设备指纹；misc_endpoints 混装 rank+lyric+krc 三域 | C1 | **P2** | C1 结论 |

## 2. 76 合规裁决（C1 权威）

- 全 26 文件：**零 Flutter import、零反向依赖**，唯一跨层走 bridge_kernel.Log；端点全 try/catch+Log 不静默吞；token 只打长度/掩码；零硬编码 IP/第三方域；1500 行全过（最长 546）——**架构主干 76 全绿，0 P0/P1 架构违规**。
- 职责越界（C3）：端点层持有面向用户文案（MV 画质 label、评论错误串），违反「l10n 归 core/l10n、端点应纯数据」精神（同层但落错子域 + i18n 未接线）。
- 桥导出噪音：bridge_core 导出多个零消费端点，制造死端点假象（非 76 违规）。

## 3. 与用户痛点对应

| 用户原话 | A3 定位 |
|---|---|
| 「MV 用不了」 | **X1（端点层恒 null，新根因）** + X2（档位恒空）+ X3（匿名链死代码）；叠加 A1 的上层模块 id 抢占 + 歌曲 hash 当 video_id → MV 三重断点 |
| 「什么功能都用不了」 | X5 翻译恒空、X7 七个死端点、X4 登录端点冒充可用 |
| 「文案没改」 | X6 端点层 10 处中文硬编码 + 命名倒挂 |
| 密码学成熟库 | X4 登录依赖有 Rcon bug 的 AesCbc，印证必须换成熟库 |

## 4. 本批结论

A3 达成：三视角全落盘（含多次重派恢复）；真 P0 1 个（MV 端点恒 null，主会话实测留样复核确认）；共识 P1×7、P2×2；架构主干 76 全绿。
C3 的「接口正确」与 C2 的「恒 null」分歧已裁定——接口形状对但字段解析错，属 C3 误判，已在复核文档记录。

## 5. 下一步

阶段 A 继续 A4（core 非网络：database/storage/cache/audio/algorithms/l10n/memory）。所有修复待 A1~A7 全完后主会话亲做。
A3 定时器 `8ea16930` 已取消（三份报告齐，提前收口）。
