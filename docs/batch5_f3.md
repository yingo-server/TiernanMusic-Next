# 批5-F3 文档最终收口 · 改动说明

> 范围：仅 4 个 Markdown 文件（`FUNCTION_TREE.md` / `README.md` / `docs/API_TEST_REPORT.md` / `docs/ACCEPTANCE_CHECKLIST.md`）。
> 未改任何 `.dart` / `.yml` / `.py` / `.sh`；未跑分析器；未提交；未删旧锚点（`API_TEST_REPORT.md` 原「六、对照文档」整体下移为「七、对照文档」，条目内容一字未动）。
> 本文件为改动说明，与批5-C1/C2/C3 报告并存（`docs/batch5_c1.md` / `docs/batch5_c2.md` / `docs/batch5_c3.md`）。

## 1. FUNCTION_TREE.md

### 1.1 §11 标题与导语
- 标题由「接线状态清单（批3-F3 按当前代码逐文件核对）」改为「**批5-F3 按批1~4 最新修复刷新**」。
- 导语增补两句：批4 修复项已按当前代码回填；批5 项如实标注「批5 进行 / 待验收」，不冒充完成。
- 保留「逐项以文件存在 / import 与调用点为据；无法从当前代码确认的标『待核对』，不杜撰完成度」原句。

### 1.2 §11.2 仍未接线表（逐条刷新）
| 项 | 变化 |
|---|---|
| 音质当前档回显 | ⚠️ 硬编码 `selected: q128` → **✅ 批4 已修**：音质偏好读取真实当前档并生效 |
| 通知栏系统事件 | ⚠️ 部分接线 → ⚠️ **批5 进行 / 待验收**：批5-C2 核对时 `next`/`prev`/`seek` 仍未接，方案见 `docs/batch5_c2.md`；工作区 `audio_service_bridge.dart` / `modules.dart` 已改动（见 `docs/batch5_f2.md`），**未跑分析器、未构建、未真机验收、未提交**。`updateMetadata` 现状描述保留 |
| 收藏 fileid 落盘 | **新增行**：⚠️ 批5 进行 / 待验收——批5-C2 核对时 collect 只存 hash、回执 `fileid` 被丢弃；工作区已实现 fileid 镜像键 `favorites.fileids.<uid>` 与回执取 fileid（`docs/batch5_f2.md`），**未跑分析器、未构建、未真机验收、未提交**，旧镜像缺 fileid 不自动补齐 |
| app_root 主题 | **新增行**：⚠️ 批5 进行 / 待验收——`app_root` 已切 `Sp.theme()`（批5-F1：`spotify_tokens.dart` + `app_root.dart`），light 槽位仍渲染同一套深色主题为已知取舍；**未跑分析器、未构建、未真机验收、未提交** |
| 存储一键清理 / 评论发表、点赞、热词 / 歌词行 seek / 其它待核对项 | 原文保留，未改 |

### 1.3 新增 §11.4「批4 完成项与批5 现状」
- **批4 完成**（3 项）：
  1. **10 文件 Sp 收敛**——按 10 个文件为一批收敛 `Sp.*` 令牌消费，统一走 surface 层主题/间距令牌（批5-C1 核对显示全仓仍有 21 个页面消费 `Sp.*`，两套设计系统并存，其余批次待继续迁移，见 `docs/batch5_c1.md` §①）；
  2. **ResourceCache 异步 IO + 互斥**——`core/memory` 的 `ResourceCache` 磁盘读写改异步 IO 并加互斥，避免并发重复写/写冲突；
  3. **音质偏好生效**——读取真实当前档并实际生效（原硬编码 `q128` 回显已移除）。
- **批5 现状**（4 行表，均带检查报告路径）：通知栏 next/prev（进行/待验收，`docs/batch5_c2.md` + `docs/batch5_f2.md`）、collect fileid 落盘（进行/待验收，同上两处）、app_root 主题（进行/待验收，`docs/batch5_c1.md` + `docs/batch5_f1.md`）、真机验收清单（待执行，`docs/batch5_c3.md` 与 `docs/ACCEPTANCE_CHECKLIST.md`）。前三项均如实标注「未跑分析器、未构建、未真机验收、未提交」。
- 末尾给出批5 检查报告索引一行（C1 / C2 / C3 / F1 / F2 各自职责）。
- 锚点提示：§11.1 / §11.3 / §12 / §13 的全部旧内容与旧锚点均未删除或改写。

## 2. README.md

- 依赖清单（第 5 条例外清单）与「本地十道门禁」（`tool/local_gate.sh` → `FINAL-OK`，含 `smoke_check` / `analyze_gate`）段落**原样保留**，一字未动。
- 新增章节「## 验收与批5 检查报告」，位于「## License」之前：
  - **真机验收**：指向 `docs/ACCEPTANCE_CHECKLIST.md`，写明为 42 条编号待执行验收项 + 风险与结论，覆盖启动/首页/搜索/歌单/播放/收藏/下载/歌词/评论/设置/通知栏；
  - **批5 检查报告**：指向 `docs/batch5_c*.md`（C1 UI 残留与 app_root 主题统一方案、C2 通知栏 next/prev + collect fileid 方案、C3 真机验收清单产出），并补 `docs/batch5_f1.md`（app_root 主题收口）与 `docs/batch5_f2.md`（通知栏 next/prev + collect fileid 补齐）。

## 3. docs/API_TEST_REPORT.md

- **保留匿名 20028 / 31833 错盐负对照口径**：§一矩阵行 `play_url_v5`（anonymous 列）、§四-3、§五-2 原文均未改；并在新增段中复述同一口径。
- 新增「## 六、批5 说明」（原「六、对照文档」顺延为「## 七、对照文档」，条目内容与顺序不变）：
  1. **批5 未新增三态实测**——本报告三态矩阵仍为 2026-11-13 `tool/api_probe.dart` 产物，批5 未新增任何端点的三态样本；
  2. **未实测端点清单**——见 `docs/API_CONTRACT_MATRIX.md` 与 `docs/batch5_c2.md`；
  3. 口径不变——匿名正确盐 `errcode=20028`（人机验证），`31833` 仅为错盐负对照（签名失败）。

## 4. docs/ACCEPTANCE_CHECKLIST.md（新建）

- 原 `docs/ACCEPTANCE_CHECKLIST.md` 不存在，本轮新建。
- 内容**从 `docs/batch5_c3.md` 复制**，11 组（启动/首页/搜索/歌单/播放/收藏/下载/歌词/评论/设置/通知栏）编号验收项（源文件实为 42 条编号项 + 「风险与结论」4 条，编号 1.1–11.3 连续无缺，**逐条原样保留**）：验收项文案、预期结果、失败看哪里、登录/VIP 列全部未改语义；表头、分组编号、「风险与结论」4 条同样保留。
- 头部导语增补来源说明（内容来源 `docs/batch5_c3.md`，本文件仅做收口整理，未改语义）与失败排查口径（`-1` 网络 / `-2` 超时 / `-3` 非 JSON 解析错、`adb logcat` 排查入口）。
- 末尾新增「附：批5 收口对照」小节（不改动上方任何验收项语义）：通知栏 next/prev = 批5 进行/待验收；collect hash→fileid 落盘 = 批5 进行/待验收；app_root 主题 = 批5 进行/待验收（已切 `Sp.theme()`）；音质偏好生效 = 批4 已完成（验收时以真实当前档为准）。

## 5. 校验与边界

- 改动仅限上述 4 个 Markdown 文件；未触碰任何代码、配置、CI 文件；未执行分析器与门禁；未提交 Git。
- 未删除任何既有锚点：§11.1 / §11.3 / §12 / §13 全文保留；`API_TEST_REPORT.md` 的「对照文档」条目与锚点原样保留（仅小节序号顺延）。
- 三项「未完成」事实（通知栏 next/prev、collect fileid 落盘、app_root 主题统一）在 §11.2 / §11.4 / 验收清单附录三处口径一致，均写作「批5 进行 / 待验收」，并注明「未跑分析器、未构建、未真机验收、未提交」，未冒充完成。
- 说明：工作区中 `lib/` 下若干 `.dart` 的修改来自批5-F1/F2 等其它批次，本批**未改动任何 `.dart`**，也未回退或提交它们。

*产出：批5-F3 文档最终收口 · 未运行分析器、未改代码、未提交*
