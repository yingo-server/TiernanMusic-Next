# 批1-C3 门禁检查报告（只读）

## 1. 批1 预期改动 vs 门禁冲突点

- 删首页热搜区块：feature_reachability 要求 `searchHot` 端点存在且其封装函数被 logic/surface/bridge 引用（③ no orphan endpoint functions）。删 UI 区块可以，但若顺带删 `searchHot` 端点或其封装函数未被引用 → FAIL。surface/pages/home_page.dart 必须仍存在（⑤ surface pages rebuilt）。
- 加 L6 ThemeController：layer_audit L6_EXTRA 只允许 riverpod + flutter/foundation + flutter/widgets.dart；ChangeNotifier 类 Controller 放 L6 可行（foundation/widgets 允许）。**允许 L6 import bridge_core**：LAYER_ALLOWED_BRIDGES[6] 已含 bridge_core，KeyValueSettings 若在 bridge_core 暴露则放行；但若 ThemeController 直接 import core 层文件 → 跨层直连违规，必须走 bridge_core / bridge_session。
- **L7 import bridge_session 的 ThemeController：允许**（白名单 7 含 bridge_session）；注意 smoke_check.dart 的 `_layerAllowedBridges` 与 layer_audit.py 的 LAYER_ALLOWED_BRIDGES 是两份手写副本，必须同步。
- active() 排序改动：纯 L6/session 逻辑，无门禁冲突；但桥函数改动需 try/catch 留痕（check_bridge_try_catch），且空 catch 检测会拦静默吞异常。
- tokens 亮色工厂：feature_reachability ⑦ 要求 `ColorScheme.fromSeed` 出现在 surface/theme/tn_theme.dart 或 sessionSrc——改 tn_theme 时保留该字符串。
- smoke 500 行上限：`_checkLineBudget` 严格 ≤500 行，ThemeController/新 tokens 文件若塞进已有接近 500 行的文件会触发拆分要求。
- 同名类风险：`_checkDuplicateClassNames` 要求类名全局唯一；新增 `ThemeController`/`ThemeTokens` 若与 core/surface 既有类重名（如已存在的 theme 相关类）→ VIOLATION（BootResult 事故前车之鉴）。

## 2. CI verdict 判据清单（ci.yml verdict step）

1. dart syntax：steps.syntax.outcome=success 且无 "Could not format"
2. analyze：日志含 "issues found|No issues found"，且无 `error •`
3. flutter test：All tests passed
4. layer.log：无 VIOLATION，且有 "PASS strict seven-six"
5. analyze_gate.log：无 REAL-ERRORS / ^FAIL / Traceback，且有 "analyze_gate ok"
6. smoke.log：无 ^VIOLATION|^FAIL，且有 "PASS smoke_check"
7. md5 四向量：empty/abc/fox/long 四条 ^PASS 齐备且无 ^FAIL
8. field_truth：FIELD-TRUTH-OK（后续还有 reachability/boot/session/resolve/play/download 等同型正向判据）

批1 会触碰：②③（改代码引入 error/测试失败）、④⑥（新增 import、跨层、同名类、500 行）、reachability（热搜端点 orphan / ColorScheme 锚点 / home_page 存在性）。

## 3. 安全实施顺序

1. **先 L6**：`lib/session/` 新建 theme_controller.dart（riverpod + foundation，≤500 行，类名查重）→ layer_audit / smoke / analyze 可过。
2. **bridge_core**：如需 KeyValueSettings，仅在 `lib/bridges/bridge_core.dart` 加暴露函数（try/catch 留痕）；L6 白名单已含 bridge_core，无需改白名单。
3. **bridge_session**：在 `lib/bridges/bridge_session.dart` 暴露 ThemeController 读写，供 L7 使用（白名单已放行）。
4. **tokens 亮色工厂**：改 `lib/surface/theme/tn_theme.dart`，保留 `ColorScheme.fromSeed` 字符串与 home_page.dart。
5. **删热搜区块 + active() 排序**：最后改 UI/session 调用点；只删 UI 引用，保留 `searchHot` 端点与封装函数（或同步更新调用处避免 orphan）。
每步后跑 `tool/local_gate.sh`，绿色再进下一步。

## 必修 TOP5

1. L6→L7 的 ThemeController 只能经 bridge_session，禁止跨层直连 import。
2. 同步 layer_audit.py 与 smoke_check.dart 两份层-桥白名单（任何白名单改动都要双改）。
3. 新增类名（ThemeController/ThemeTokens）全局唯一，防同名类遮蔽。
4. 单文件 ≤500 行；新控制器独立文件，不塞满现有文件。
5. 删热搜不删 searchHot 端点/封装函数引用，ColorScheme.fromSeed 锚点保留。
