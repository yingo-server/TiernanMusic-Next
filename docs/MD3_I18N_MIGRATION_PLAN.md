# MD3 重构 + i18n 全量接线 · 执行方案（主会话，2026-11-17）

## 现状（已 CI 验证的事实）

- 主线 `d668443` = CI 全绿（完整 Flutter SDK 编译 + 十门禁通过）。14 批审查 + 首轮跨层修复已完成。
- **MD3 遗留**：199 处 `Sp.*` 语义静态色，分布在 16 个 surface 文件；其中相当多在 `const` 表达式里（如 `const TextStyle(fontSize: Sp.fItem, color: Sp.text)`）。MD3 复评 42/100，较阶段 A 仅 +2——令牌建了但页面没消费。
- **i18n 遗留**：213 处中文硬编码，多为 `const Text('...')`；S.of 门面、56 键 ×10 语 arb、TnStrings 常量表、语言切换入口**都已就绪且 CI 通过**，只差页面接线。接线率≈0%。
- 本地无 dart/flutter，编译只能靠 GitHub Actions（一轮约 4–8 分钟）；历史经验：批量改动后 CI 抓编译错，逐条修 2–3 轮可达全绿。

## 三个可选方案

### 方案 A：专门迭代分批做（推荐）
- MD3 分 4 批、i18n 分 4 批，每批 4–5 个文件、约 40–50 处改动。
- 每批流程：改 → 本地门禁（layer_audit + 静态冒烟）→ 提交 → 推 CI → 逐条修编译错 → 全绿 → 下一批。
- 每批改动小，CI 编译错预计 0–3 个，出问题可单批回退，不影响已全绿主线。
- 代价：约 8 批 ×（改 + CI + 修错），耗时较长。

### 方案 B：本轮硬做 + CI 大收口
- 一次性脚本批量替换 400+ 处，推 CI，逐条修编译错。
- 首轮预计 30–80 个编译错（跨多行 const 去不干净、无 context 作用域），需多轮 CI 收口。
- 代价：全绿状态被破坏较久，反复修错成本高，且有把正确代码改坏的风险。

### 方案 C：只修最致命的
- MD3：强制使用深色板（禁用亮色），规避白底白字——一行改动，但剥夺亮色选择，MD3 分数提升有限。
- i18n：保持现状（翻译数据已备、语言切换已通、新代码全接），存量 213 处不动。
- 代价：UI 精细化问题仍在，用户"文案没改/UI 不舒服"的存量痛点未解决。

## 推荐：方案 A，具体批次

### MD3 迁移（目标：页面改用 ColorScheme 语义角色，消除白底白字）
- 在 `tokens.dart` 建立 `BuildContext` 扩展取色门面（`context.spColors.text/onSurface...`），作为单一事实源。
- M1 试点：`design/{tokens,components,mini_bar}.dart` + `theme/tn_theme.dart` + `app_root.dart` + `shell.dart`，验证脚本/改法正确后推广。
- M2：`home_page` + `home_state_views` + `search_page` + `search_tile_widgets`。
- M3：`player_page` + `lyrics_page` + `mv_page`。
- M4：`library_page` + `playlist_page` + `login_account_section` + `login_sheet` + `settings_page`。

### i18n 接线（目标：213 处中文改走 S.of(context).t(key)）
- I1：`login_sheet`(32) + `login_account_section`(4) + `settings_page`；补缺失 key 到 10 语 arb + 重生成 strings.dart。
- I2：`home_page` + `search_page` + `library_page`。
- I3：`player_page` + `lyrics_page` + `mv_page` + `mini_bar`。
- I4：`playlist_page` + `shell` + 剩余页面。

### 关键技术手段（降低 const 去除风险）
- 用带括号深度状态机的脚本：识别 `const Constructor(` 的括号范围，若范围内出现 `Sp.<色>`（MD3）或中文字符串（i18n），才移除该 `const`，并做语义替换。
- `Theme.of(context)` / `S.of(context)` 只注入到有 `BuildContext` 的作用域；无 context 的字段/构造函数默认值位置跳过并单独人工处理。
- 每批改完先跑本地门禁，再推 CI；编译错逐条修。

## 验收标准
- 每批 CI 全绿；全部完成后 MD3 复评显著提升（目标 ≥70 pass）、surface 硬编码中文清零、`S.of` 覆盖率 100%。
- 全程保持功能 P0/P1 修复不回归（VIP/语言/错误/下载/循环/seek/取色链）。
