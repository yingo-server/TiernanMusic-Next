# 文档工作流审计与改动清单（docs/DOCS_WORKFLOW_AUDIT.md）

> 审计日期：2026-11-19 · 依据：`sota-docs-workflow` SKILL.md 全文 + rules 01–05 全部 Audit checklist
> 方法：只读审计——`rg`/`file_read` 核对 `lib/` 代码、`pubspec.yaml`、`.github/workflows/`、工具门禁后，
> 才判定文档事实；**未改任何代码、未 commit/push**，只写/改 `docs/**` 的 Markdown。

## 1. 审计范围与结论

- 覆盖 `docs/` 全部 Markdown（约 130 篇）+ README.md；抽样精读权威/规划类 12 篇，并对全树跑过时术语扫描。
- 结论：旧文档体系存在**权威性分裂**（多个「权威定义」互相矛盾）、**大规模过时**（描述重写前的六层五桥、
  `Sp.*` 自绘、Spotify 深色、`lib/platform/` 路径）、**缺关键事实**（平台层/权限网关/桌面标题栏/全平台构建/
  森林翡翠 token 从未有一篇权威文档完整描述）三类问题，已按 Diátaxis 重组并新增 `docs/architecture/` 权威页。

## 2. 发现（按严重度排序，证据驱动）

### [HIGH] 多篇「权威」文档互相矛盾且描述重写前状态
Where: `docs/SEVEN_SIX_RULE.md`、`docs/ARCHITECTURE.md`、`docs/SIX_FIVE_RULE.md`
Rule: rules/01 §1、§4（Diátaxis 混用 + 错误文档比没有更糟）
Issue: 三篇都自称「唯一权威定义」：SIX_FIVE 是六层五桥（V1，已标 DEPRECATED）、SEVEN_SIX 是七层六桥 V2
  但 §4/§8 自相矛盾（"播放编排属 L7 session" / "L6 只有 Widget"），ARCHITECTURE 仍写「Spotify 深色设计系统」。
   ruled §11：SEVEN_SIX §6 写「surface 仅占位、页面全部不建」，实际 `lib/surface/pages/` 有 13 个页面——
   这是会随普通重构失效的观察，不是不变量。
Impact: 新读者/子代理按任一「权威」实现都会与当前代码冲突。
Fix: 三篇加「已归档」横幅指向 `architecture/`；新建 [架构总览](architecture/ARCHITECTURE_OVERVIEW.md) +
  [层与桥参考](architecture/LAYERS_AND_BRIDGES.md) 作为唯一事实源，明确「session(L6)=编排，surface(L7)=仅控件」。

### [HIGH] 平台层 / 权限网关 / 桌面标题栏 / 全平台构建 / 语义色 token 无权威文档
Where: 全 docs 树（旧规划 `UI_REWRITE_PLAN.md` 是规划稿，非事实）；代码事实在
  `lib/core/platform/`、`lib/core/capability/`、`lib/surface/design/{tokens_v2,desktop_titlebar}.dart`、
  `.github/workflows/desktop-build.yml`
Rule: rules/01 §2、§4、§6（docs 与代码同仓、单一事实源、可发现性）
Issue: 重写后新增的四个能力在规划文档里写的是「将要做」（且路径写 `lib/platform/`，实际落盘 `lib/core/platform/`），
  没有任何文档描述它们**现在是什么**。典型：`CapStatus` 五态、`IoCapabilityGateway` 的
  `markResult()` 回写真实权限、`bitsdojo` 与 `window_manager` 职责分离、AppImage 在 ubuntu-22.04 构建。
Impact: 平台相关代码无人能从文档理解，易被误改；审计子代理只能读源码猜测。
Fix: 新增 [平台能力参考](architecture/PLATFORM_CAPABILITIES.md) + [设计语言参考](architecture/DESIGN_LANGUAGE.md) +
  [构建指南](architecture/BUILD_GUIDE.md)；规划稿 `UI_REWRITE_PLAN.md` 归档并注明路径差异。

### [MEDIUM] Diátaxis 模式混用、结构混乱、无索引
Where: 旧 `docs/` 为扁平 130 篇堆叠：教程/规划/参考/审计日志/临时 batch 报告混杂；无 `docs/README.md` 分类入口。
Rule: rules/01 §1（一次一文一模式）、§6（每仓一个 docs 入口按模式索引）
Issue: 例如 `FOUR_RELEASE_ROADMAP.md` 混 Explanation（为什么四步）与 How-to（怎么发版）；
  `ARCHITECTURE_REVIEW.md` 混 Reference（行数表）与 Explanation（架构债判断）。
Impact: 读者不知道该读哪篇；搜索命中归档稿多于现行稿。
Fix: 新建 `docs/README.md` 按 Tutorial/How-to/Reference/Explanation 四类归位；新文档严格单模式命名；
  归档稿统一横幅 + 指针（含 `deep_audit/README.md`）。

### [MEDIUM] 诚实边界缺失：i18n 全量接线 / 20028 端点被规划稿暗示为完成
Where: 旧 `FOUR_RELEASE_ROADMAP.md` 写「v0.2.0-rc 三语真译文、其余 7 语 en 占位」，
  `FINAL_VERIFICATION.md` 写「i18n 全量接线率≈0%」「20028 端点 return false、L7 无验证 UI」（后者正确但散落）。
Rule: rules/01 §3（README status honesty）、§11（记录不变量而非观察）；rules/02 §4（文档失败模式）
Issue: 一处说要做、一处说没做，无单一权威的「当前已实现 vs 后续项」清单。
Impact: 读者误以为 10 语已可用 / 验证流程可解。
Fix: [架构总览 · 诚实现状](architecture/ARCHITECTURE_OVERVIEW.md#诚实现状不是已实现功能请勿当作已交付)
  明确标注：10 份 `.arb` 数据已落盘但界面接线率低（需真实译文的后续专项）；20028 端点未实测、`return false`、
  L7 无验证 UI（只做到错误文案可见）；macOS/iOS/Web 无 CI 产物。

### [MEDIUM] Agent B 产出路径命名不一致
Where: `FOUR_RELEASE_ROADMAP.md` 小版本 3 写「产出 `docs/DOCS_AUDIT.md`」；本任务要求 `docs/DOCS_WORKFLOW_AUDIT.md`。
Rule: rules/01 §8（每个工件一个规范home）、§4（不留重复）
Issue: 两份名字指向同一职责，后续易生成两份分叉审计。
Fix: 统一为 `docs/DOCS_WORKFLOW_AUDIT.md`（本文件），归档稿加注说明。

### [LOW] 陈旧术语广泛残留（不作为独立事实源，但污染搜索）
Where: 扫描命中 `Sp.*`（30+ 文件）、`miuix`、`Spotify`、`六层五桥`/`五桥`、`lib/platform/` 注释。
Rule: rules/01 §4（删除陈旧页、不留搜索引擎能命中的坟场）
Issue: 多数在已归档历史批次报告/deep_audit 内，属合理历史记录，但缺「已归档」标注时会被当作现行事实。
Fix: 对 9 篇权威/规划/验收类文档加归档横幅；deep_audit 与 UI_REWRITE_LOG 加目录级归档说明。
  逐篇历史批次报告（batch*/six_*/autonomous_* 等）为过程记录，保持原样但由 `docs/README.md` 统一声明为历史。

### [LOW] 文档基线缺口（超出本次授权范围，仅登记）
Where: 仓库根有 README.md、LICENSE（Apache-2.0）、CHANGELOG 散在 `changed/`（非根 `CHANGELOG.md`）；
  无 `SECURITY.md` / `CONTRIBUTING.md` / `AGENTS.md`（rules/01 §8、§7）。
Rule: rules/01 §8（baseline）、rules/02 §6（Keep a Changelog）
Issue: 无根目录 CHANGELOG.md（changelog 在 `changed/<版本>.md`，由 CI 拼 Release body）；
  无 agent 文件（本仓大量子代理工作流却无 AGENTS.md）。
Impact: 外部贡献者/新 agent 无规范入口。
Fix: 本次任务限定「只写/改 docs/ 下的 markdown」，未在数据仓根新增文件；登记为后续项，待授权后补齐。

## 3. 改动清单（本轮落盘）

### 新增（5 + 2 索引/归档说明）
| 文件 | Diátaxis 模式 | 内容 |
|---|---|---|
| `docs/README.md` | 索引（按四模式分类，非独立模式） | docs 入口：四类归位 + 归档清单 |
| `docs/architecture/ARCHITECTURE_OVERVIEW.md` | Explanation | 76 原则形状、横切关注点落位、门禁/构建、诚实现状 |
| `docs/architecture/LAYERS_AND_BRIDGES.md` | Reference | 七层六桥、缓存⊃预读、端点注册表、例外与门禁判据 |
| `docs/architecture/DESIGN_LANGUAGE.md` | Reference | 森林翡翠语义 token 明暗表、标题栏 token、零手写控件 |
| `docs/architecture/PLATFORM_CAPABILITIES.md` | Reference | 平台层条件导入、能力集合、权限网关五态、窗口服务、全平台构建 |
| `docs/architecture/BUILD_GUIDE.md` | How-to | 本地门禁命令、Android/CI、桌面 AppImage、四步版本路线、故障排查 |
| `docs/deep_audit/README.md` | 归档说明 | 指向新权威文档 |
| `docs/DOCS_WORKFLOW_AUDIT.md` | Reference（审计报告） | 本文件 |

### 重写 / 归档（加「🗄️ 已归档」横幅 + 指针，正文保留追溯）
`ARCHITECTURE.md`、`SEVEN_SIX_RULE.md`、`SIX_FIVE_RULE.md`（原有 DEPRECATED 标注保留）、
`UI_REWRITE_PLAN.md`、`UI_IA_PLAN.md`、`UI_REWRITE_LOG.md`、`DESIGN_LANGUAGE.md`、
`FINAL_VERIFICATION.md`、`ARCHITECTURE_REVIEW.md`、`FOUR_RELEASE_ROADMAP.md`。

> 说明：按 rules/01 §4「删除陈旧页」的严格口径，这些页本应删除只留 git 历史；本任务明确要求
> 「旧文档保留但加已归档标注并指向新文档」，故采用 tombstone 横幅方案——这是本次的显式权衡。

## 4. Diátaxis 归类结果

| 模式 | 文档 |
|---|---|
| Tutorial | 暂无独立教程页（首上手走 BUILD_GUIDE 前置 + 本地门禁；README 未重写，本次不在范围） |
| How-to | `architecture/BUILD_GUIDE.md` |
| Reference | `architecture/LAYERS_AND_BRIDGES.md`、`architecture/DESIGN_LANGUAGE.md`、`architecture/PLATFORM_CAPABILITIES.md`、本审计 |
| Explanation | `architecture/ARCHITECTURE_OVERVIEW.md`、`FOUR_RELEASE_ROADMAP.md`（已归档计划） |
| 索引 | `docs/README.md` |
| 归档 | 见第 3 节「重写/归档」清单 + `deep_audit/` |

## 5. 事实核验依据（抽样）

- 七层六桥：`lib/{init,bootloader,kernel,core,logic,session,surface,bridges}/` 目录 + 六桥文件存在。
- 端点数：`endpoint_registry.dart` 中 `static const Endpoint` 计 54（旧 README 写 50/53，实际 54——已以「54」写入新文档）。
- 语义色：`tokens_v2.dart` 中 `TnPalette.light/dark` 24 字段逐项对照；浅 `#F1F8F4` / 深 `#0B1F14`。
- 平台层：`platform.dart` 条件导入；`io_capability_gateway.dart` 五态与 `markResult()`；`io_window_service.dart` 用 window_manager。
- 标题栏：`desktop_titlebar.dart` 用 bitsdojo 官方按钮 + `titlebar.*`，仅 `supportsCustomTitleBar` 时渲染。
- 全平台构建：`desktop-build.yml`（windows zip / ubuntu-22.04 AppImage，patch 原生 runner）；`ci.yml`（apk split-per-abi）。
- i18n：10 份 `.arb` 存在；`FINAL_VERIFICATION.md`/`UI_REWRITE_LOG.md` 明确「接线率低/需真实译文」。
- 20028：`FINAL_VERIFICATION.md` B1 明确「端点 return false、L7 无验证 UI」。
