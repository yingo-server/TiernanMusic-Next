# UI 重写 · 四步小版本实施计划（SOTA skills 驱动）

> 版本：v0.1 · 目标：在现有破坏性 UI 重写（P1–P3 已实施）基础上，
> 分 **4 个可发布的小版本** 完成用户全部要求，最终发布 **正式版（stable）**。
> 用户离线，全程自主、不中断、使用接续 1h 计时器提醒。
> 铁律复述：**不得自己写控件、不得自设间距（全部用官方 M3/GetWidget 默认或 token）、
> 全部原生、颜色色系严格遵循 `docs/DESIGN_LANGUAGE.md`（森林翡翠）。**

---

## 总原则（四步共同遵守）

1. **控件来源只有两个**（docs/UI_REWRITE_PLAN.md §0.0）：
   - 官方 Material 3（`package:flutter/material.dart`）
   - GetWidget（`package:get` 提供的现成能力：Obx/GetBuilder/GetView/GetSnackbar/GetDialog/GetBottomSheet/GetMaterialApp）
   - 桌面标题栏用 bitsdojo 官方控件（WindowBorder/WindowTitleBarBox/WindowButton 家族）
   - **禁止**：自建 StatelessWidget/StatefulWidget 可复用控件、CustomPainter/Canvas/drawX、自设间距常量
2. **间距只用官方默认**：ListView/Column/Row/Card/ListTile 的默认 padding；
   不new写 Sp.gapXX 式自设间距（旧 tokens 已删）。
3. **颜色只用语义 token**：`context.cs.*` / `TnPalette.*` / `TnSystemColors.*`，
   禁止裸 `Color(0x…)` / `Colors.xxx`（门禁 `ui_no_custom_widgets.py` 强制）。
4. **每个小版本**：实现 → 全门禁 PASS（layer_audit/bottom_bar/ui_no_custom_widgets/ui_contrast）→
   push → CI 全绿 → 独立 tag/release。CI 失败逐条修，不绿不进下一步。
5. **sota skills 一律派子代理执行**（审计与修改），主会话不亲自写文案/文档，只裁定与集成。

---

## 四步路线图

### 小版本 1：v0.1.0-alpha · 现有重写 CI 全绿 + 桌面标题栏挂载
**目标**：把 P1–P3 的破坏性重写稳定到 CI 全绿，接上桌面标题栏。
**实现**：
- 主会话：逐条修 CI 编译错（get/bitsdojo/window_manager 依赖、子代理页面 API 误用、Obx 绑定）直到全绿
- 主会话：`app_root.dart` 挂载 `desktop_titlebar.dart`（仅桌面；bitsdojo 官方控件 + titlebar.* token）
- 主会话：CI 原生 runner patch（Windows main.cpp / Linux my_application.cc 让 bitsdojo 生效）
**门禁**：四门禁全 PASS + CI 全绿
**发布**：tag `v0.1.0-alpha`（prerelease）

### 小版本 2：v0.1.1-beta · 全平台构建（Windows/Linux + AppImage）
**目标**：三平台产物可下载。
**实现**：
- 主会话：新建 `desktop-build.yml` workflow（workflow_dispatch）：
  - Windows：`flutter build windows --release` → zip
  - Linux：`flutter build linux --release` → 打包 **AppImage**（含全部依赖：
    appimagetool + desktop 文件 + 依赖归档），兼容 Ubuntu 22.04 glibc
  - Android：沿用现有 apk 流程
  - 上传 artifacts
**门禁**：构建产物存在性校验脚本
**发布**：tag `v0.1.1-beta`

### 小版本 3：v0.2.0-rc · SOTA 文案 + 技术文档（四个 agent 分工）
**目标**：所有界面文案与技术文档达到 SOTA 水准。
**实现**（全部派子代理，读对应 SKILL.md 后执行 AUDIT/BUILD）：
- **Agent A · sota-ux-writing**：读字典（`lib/l10n/*.arb` + 全 surface 硬编码文案），
  审计并重写界面文案（错误态/空态/按钮/通知），zh/zh_Hant/en 三语真译文，
  其余语用 en 占位；产出 `docs/UX_COPY_AUDIT.md` + 改 arb/strings
- **Agent B · sota-docs-workflow**：审计并重写技术文档（README 之外：
  ARCHITECTURE / SEVEN_SIX_RULE / UI_REWRITE_PLAN / DESIGN_LANGUAGE / 各 PLAN），
  按 Diátaxis 分类、docs-as-code、CHANGELOG；产出 `docs/DOCS_AUDIT.md`
- **Agent C · sota-copywriting**：审计并重写 README（对外门面：what/why/quickstart/honest status），
  产出 `docs/COPYWRITING_AUDIT.md` + 改 README.md
- **Agent D · sota-ux-writing（第二轮）**：文案字典一致性复核（术语一词一名、banned greps、
  i18n 安全），产出 `docs/UX_COPY_FINAL.md`
- 主会话：写记忆（本计划 + 四步结论 + 关键决策）
**门禁**：文案 banned-pattern grep + 文档链接检查
**发布**：tag `v0.2.0-rc`

### 小版本 4：v1.0.0 · 正式版（stable）
**目标**：全平台正式发布。
**实现**：
- 主会话：最终全门禁 + CI 全绿 + 全平台构建复核
- 用 `workflow_dispatch` 的 `stable=true` 发 **prerelease=false** 的正式版
- 归档：releases.json / 文档 / 校验和
**门禁**：所有验收清单（docs/UI_REWRITE_PLAN.md §验收 + DESIGN_LANGUAGE.md §验收 +
UI_IA_PLAN.md §验收 + 三个 SOTA skill 的 audit checklist）
**发布**：tag `v1.0.0`（**正式版，非 prerelease**）

---

## 关键依赖与风险

- **AppImage glibc 兼容**：Ubuntu 22.04 用 glibc 2.35；需在 Ubuntu 22.04 runner 构建，
  或静态打包依赖；appimagetool 下载需网络。
- **bitsdojo 原生 patch**：CI 每次 `flutter create` 生成裸 runner，必须 patch 才能自绘标题栏。
- **Google Play / Apple 审核**：正式版仅 GitHub Release，不上架商店（internal tools 定位，README 诚实说明）。
- **i18n 10 语**：日常只保 zh/zh_Hant/en 三语真译文，其余 7 语用 en 占位（不塞中文），honest status 写明。

---

## 记忆写入点（用户明确要求）
每一步完成写 `memory_write`：版本号 + 做了什么 + CI 结果 + 决策。
第 3 步四个 agent 的产出路径 + 关键文案决策单独记一条。
第 4 步正式版 tag + 产物清单单独记一条。
