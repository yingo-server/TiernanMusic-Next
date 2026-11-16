# 14 批深度审查 · 总任务书（权威）

> 立规来源：用户 2026-11-16 指令。本文件是唯一执行契约，所有子代理先完整读它再开工。
> 仓库根：`/var/minis/workspace/NextWorkspace/TiernanMusic-Next`

## 0. 背景与用户原话（痛点，必须逐条对照）

- 「UI 很不舒服，动画也是，细节都是瑕疵，不经看」→ 用 **material-3 skill** 规范审查（`MD3 Compliance Audit` 十类打分：Color tokens / Typography / Shape / Elevation / Components / Layout / Navigation / Motion / Accessibility / Theming）。
- 「你这版本，什么功能都用不了，MV 等等」→ 功能可达性/死链/断点必须逐条定位（尤其 MV）。
- 「登录方式支持 ykg 协议的浏览器链接，本质是 base64 编码的 cookie 加 md5 加盐密码等信息，支持从 app 导出，输入密码才能通过此方式登录，具体密码学自己设计」→ 现状盘点 + 落地设计输入（本轮只审不改）。
- 「相关文案也没改」→ i18n 文案缺口、硬编码中文、占位/旧文案清单。
- 「全面深度检查 / 从上至下 / 每层级三个子代理交叉 / 超时 60 分钟 / 只允许 ls 和 read / 一口气读完 / 76 原则别忘记 / 先从底层做起 7 批 → 主会话亲修 → 再 7 批按功能跨层」。

## 1. 【76 原则 · 必须遵守】§0 前缀（照抄 SEVEN_SIX_RULE.md）

```
【76 原则 · 必须遵守】
七层（低→高；session 是 surface 的底层，surface 只画控件）：
  L1 init        入口、完整性校验触发
  L2 bootloader  启动序列、依赖装配
  L3 kernel      生命周期编排、日志、盐值校验执行
  L4 core        存储 / 数据库 / 缓存(包容预读) / 网络 / 音频引擎 / 纯算法 / l10n 常量
  L5 logic       仅后端逻辑（无 UI、无 IO 直连）
  L6 session     编排会话层：播放控制/播放列表/装配图/模块注册表/导航状态/provider 定义
  L7 surface     仅 UI 控件
六桥（相邻层各一，唯一合法跨层通道）：
  bridge_boot / bridge_kernel / bridge_core / bridge_logic / bridge_session / bridge_surface
依赖方向：surface(L7) → session(L6) → logic(L5) → core(L4)；禁止反向。
铁律：
  1. 不同层级之间必须通过桥接层调用；禁止跨层直接 import 非桥文件。
  2. 桥接层承担日志系统任务：每个桥函数 try/catch 捕获，失败必 Log 留痕，不静默吞。
  3. 桥文件唯一存在于 lib/bridges/，禁止任何影子桥目录。
  4. 每层只依赖其下层经桥暴露的门面；同层内引用合法，反向依赖一律禁止。
  5. 单文件超过 1500 行才按功能拆分；允许 dart format；L6 模块经 session 层注册表热插拔。
  6. 网络层 core/net/endpoints/ 每端点一 dart 模块；参数多参不缺参；只连酷狗官方域名。
  7. 零源仓库代码复用；归档项目只读 docs/ 描述性文档提取功能目标。
  8. 播放控制/播放列表/缓存/预读/装配图 一律不得放进 L6；L6 只暴露状态/回调。
  9. 能用成熟库就用成熟库（just_audio / audio_service / video_player）。
 10. 子代理只用 file_read/file_write/file_edit/ls；不验证、不跑分析器、不提交。
```

**本轮对 §0 第 10 条的唯一覆盖（以用户最新指令为准）**：
- 审查对象 **只读**：允许 `ls`、`rg --files`、`rg`（只读检索）、`file_read`。
- **禁止** 改动 `lib/`、`tool/`、任何配置/文档源码；禁止编译/测试/跑门禁/跑分析器；禁止 git 任何写操作。
- **唯一允许的写**：把发现 **追加（append）** 到你自己的报告文件 `docs/deep_audit/<你的文件名>.md`。
- 结果必须**实时落盘**：每读完一组/得到一条结论就 append 一次，不要憋到最后一次性写；中途超时也留下已完成部分。

## 2. 通用纪律（所有批、所有视角）

1. **一口气读完**：开工先把本批范围内的文件按清单连续读完（可 `ls`/`rg --files` 展开目录），再分析下结论；禁止边读边挤牙膏式来回试探。
2. **60 分钟硬超时**：到点用已有发现收口，未查完的条目明确写「未覆盖：<范围>」，**不为完整性无限加调用**；效率优先，允许交付不完美结论。
3. **交叉**：每批 3 个子代理审**同一批文件**，各用一个视角，结论互不引用、独立取证；主会话做交叉比对（共识=确认，分歧=复核）。
4. **证据化**：每条发现必须带 `文件:行` + 代码片段或字段事实；禁止「可能/建议加强」这类无证据空话。
5. **聊天汇报极短**（<200 字），完整结论全部落盘；不通知中间进度。
6. **只审不改**：任何「应该怎么改」只写建议，不动代码。修复由主会话在阶段 A 七批全部完成后**亲自**做。
7. 严格遵守 76 原则：报告里单列「76 合规」小节，指出越级 import / 影子桥 / 反向依赖 / 层职责越界（如 surface 里塞状态机、L6 里画控件）。

## 3. 三个固定交叉视角（每批都是这三个）

- **C1 架构合规**：76 原则逐条核（层归属、六桥唯一通道、依赖方向、桥 try/catch+Log、端点分文件、1500 行、成熟库边界）；建立本批文件的 import 依赖图；列出所有越级/反向/影子桥/职责越界。
- **C2 实现正确性**：空安全、状态机断点、失败/空结果路径、缓存失效语义、异步竞态、可空访问、字段解析与真实契约对齐、死链/死代码、**功能可达性（点名 MV）**、异常吞没、密码学实现缺陷。
- **C3 用户痛点专项**：
  - **M3/UI**：按 material-3 skill 十类打分，硬编码 `Color(0x…)`/裸 hex、magic number 圆角/间距、字号无 token、 tonal pairing 错误、阴影代替 tonal elevation、动画时长/曲线与 emphasized 规范不符、无语义/无 48dp 触控、无自适应/大屏 maxWidth。
  - **动画细节**：曲线/时长/中断/重复触发/rebuild 风暴/setState 范围。
  - **文案**：`lib/l10n/*.arb` 与 `lib/core/l10n/strings.dart` 缺口、硬编码中文、占位/旧文案、登录/YKG 相关文案未改清单。
  - **YKG 登录现状**：base64(cookie) + md5 加盐密码、导出、输密码解锁、现有 crypto 原语可复用性盘点，给出**密码学设计输入**（不实现）。

## 4. 阶段 A · 7 批（从底层做起，L1→L7，按层）

| 批 | 层 | 范围（文件/目录） |
|---|---|---|
| A1 | L1 init + L2 bootloader + L3 kernel | `lib/init/`, `lib/bootloader/`, `lib/kernel/`, `lib/bridges/bridge_boot.dart`, `bridge_kernel.dart` |
| A2 | L4 core·net 底座 | `lib/core/net/` 根文件（kugou_client / signing / crypto_* / inflight / endpoint_registry / network_phase / cover_color / database_opener / endpoints 之外的全部）+ `lib/core/net/endpoints/models*.dart` |
| A3 | L4 core·net endpoints | `lib/core/net/endpoints/*.dart` 全部（含 `mv_*` / `auth_*` / `play_*` / `quality_*`） |
| A4 | L4 core 非网络 | `lib/core/database/`, `storage/`, `cache/`, `audio/`, `algorithms/`, `l10n/`, `memory/` |
| A5 | L5 logic 全量 | `lib/logic/` 全部 34 文件（auth/player/download/catalog/mv/lyrics） |
| A6 | L6 session + 六桥 | `lib/session/` 全部 + `lib/bridges/` 全部 6 座 |
| A7 | L7 surface + 文案 | `lib/surface/` 全部 18 文件 + `lib/l10n/*.arb` + `lib/l10n/README.md` |

> A1 的 C1 允许**只读**扩展扫全部 6 座桥建立全局依赖图；A1 的 C3 允许**只读**扩展扫 `lib/core/l10n/`、全部 arb、`lib/core/net/crypto_*`，做全局文案/YKG/密码学资料盘点。

## 5. 阶段 B · 7 批（主会话亲修完之后，按功能跨层追踪）

| 批 | 功能 | 跨层链路（追踪到底，不局限单层） |
|---|---|---|
| B1 | 登录全链路 + **YKG 新方式** + 文案 | L7 登录页 → L6 auth_session → L5 auth_logic → L4 auth_endpoints/crypto/settings → 导出/解锁/加盐/文案 |
| B2 | 搜索 / 联想 / 热搜 / 榜单 / 推荐 | L7 search → L5 search/rank/recommend → L4 endpoints → 三态与空结果 |
| B3 | 播放主链路 | L7 player/mini_bar → L6 playback_session → L5 play_resolver/queue/reducer → L4 audio/play_url/缓存预读 → 通知栏 |
| B4 | **MV 播放**（用户点名） | L7 mv_page → L5 mv_logic → L4 mv_endpoints/mv_anonymous/video_player → 匿名/VIP 三态 |
| B5 | 下载 / 收藏 / 歌单 / 缓存 | L7 library/playlist → L5 download/collect/playlist_write → L4 storage/cache/db |
| B6 | UI / M3 / 主题 / 动画 / 动态取色 | L4 color_extract → L6 theme_controller → L7 tn_theme/tokens/components/全部页面动效 |
| B7 | i18n 文案 / 设置 / 导航 / 错误空态 | L7 settings/shell/各 state_view → L6 nav_state → L4 l10n/strings → 全 arb 一致性 |

## 6. 落盘规范（实时追加）

- 目录：`docs/deep_audit/`（已建）。
- 每子代理一个文件：`bA{N}_{c1|c2|c3}.md` / `bB{N}_{c1|c2|c3}.md`（例如 `bA1_c2.md`），**append 写入**，带时间戳小节。
- 交叉汇总：主会话收口写 `bA{N}_summary.md` / `bB{N}_summary.md`。
- 全局状态：`docs/DEEP_AUDIT_STATE.md`（主会话维护，子代理只读）。

## 7. 推进与定时器

- 每批派完 3 个子代理后，主会话设 **50 分钟单次定时器**（`minis-scheduled --after 50m`），触发时：读落盘进度 → 对仍在跑的 job 发 steer「用已有发现收口，未查完标未覆盖」→ 留 10 分钟给其写完 → 收口。
- 子代理结果以新消息自动到达，主会话据此整理、写 summary、**推进下一批**；14 批全部完成前不向用户汇报中间进度。
- 阶段 A 七批完成后：主会话**亲自修复**（M3/动画/功能/MV/YKG 登录/文案），跑门禁 + 提交；再启动阶段 B。

## 8. 返回格式（落盘用）

```
## <视角> · <文件:行> · <严重度 P0/P1/P2> · <类别>
证据：<代码片段 / 字段事实>
问题：<一句话，可复现/可定位>
建议：<具体改法，不改代码>
76 合规：<本条是否违反 76；违反则注明条款号>
```

文件末尾必须有：`## 本视角结论`（3–8 条要点）、`## 未覆盖`（如实列）、`## 76 合规小结`。
