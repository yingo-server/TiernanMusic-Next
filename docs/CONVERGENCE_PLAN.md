# 六五原则严格收敛方案（最后一批执行）

> 用户要求：完全对齐原项目功能面 + 增强改进架构 + **坚持六五原则**。
> 现状：六层目录齐全、五桥只有 3 个实体文件（bridge_boot / bridge_core / bridge_logic），
> 各层存在大量「跨层直接 import 非桥文件」与「桥只 export 无捕获函数」，属过渡口径。
> 本文档是收敛批（批7）的唯一执行基准。

## 目标态

```
L1 init ──bridge_boot── L2 bootloader ──bridge_kernel── L3 kernel
    ──bridge_core── L4 core ──bridge_logic── L5 logic ──bridge_surface── L6 surface
```

- 五个桥**全部存在**于 `lib/bridges/`：`bridge_boot.dart` / `bridge_kernel.dart` /
  `bridge_core.dart` / `bridge_logic.dart` / `bridge_surface.dart`。
- 每个桥 = 唯一合法跨层通道 + 日志载体：**每个桥函数** `try/catch` + `Log.e(tag,...,e,st)` 留痕，
  失败返回语义默认值/错误，不静默吞。桥内不写业务逻辑，只做转发/包装/错误翻译。
- 每层只 import：相邻桥 + 本层 + SDK（L6 另可 flutter/miuix/riverpod）。
- `init/main.dart → surface/app_root.dart` 白名单**删除**（改经 bridge_surface 的 bootstrapApp 挂钩）。
- `tool/layer_audit.py` 升级为强约束：跨层 import 非桥文件 → VIOLATION；桥函数无 try/catch → VIOLATION；
  影子桥目录 → VIOLATION；同层/SDK import 合法。

## 三个收敛子任务（批7，3 代理并行，各贴 §0 前缀）

### 批7-A：补齐 2 个缺失桥 + 桥函数捕获化
1. 新建 `lib/bridges/bridge_kernel.dart`：包装 kernel 能力（Log / IntegrityVerifier / KernelContext /
   Sha512 / Ed25519Verifier），每个函数 try/catch+Log 留痕；供 L2 bootloader 使用（替代直接 import kernel）。
2. 新建 `lib/bridges/bridge_surface.dart`：暴露 bootstrapApp / installServices / AppRoot 装配入口 +
   LogicFacade 状态订阅；供 L1 init 使用（替代 main.dart 直接 import surface/app_root.dart）。
3. 把 `bridge_boot.dart` / `bridge_core.dart` / `bridge_logic.dart` 从「纯 export」升级为
   「export + 关键门面包装函数」（至少：assembleKernel / openDatabase / createLogicSet 各一个带捕获的函数），
   保持向后兼容（原 export 全保留，不删）。
4. 修改 `lib/init/main.dart`：删 `import '../surface/app_root.dart'`，改 import bridge_surface；
   删 `import '../bootloader/bootloader.dart'` 直连，改经 bridge_boot 的 run() 包装。
5. 修改 `lib/bootloader/bootloader.dart`：删直接 import bridge_core/bridge_logic，改经 bridge_kernel 取 kernel
   能力 + 经桥函数组装 core；删 `widgetBuilderHook` 残留。
6. 删除 layer_audit.py 里 `init/main.dart → surface` 白名单。

### 批7-B：core/logic 层跨层 import 收敛
1. `lib/core/**` 里所有 `import '../../kernel/kernel.dart' show Log` → 改 `import '../bridges/bridge_kernel.dart' show Log`
   （路径按文件深度调整），约 15 处。
2. `lib/logic/**` 里所有直接 `import '../../core/...'` → 改经 `bridge_core` 导出的门面；
   若 bridge_core 未导出某类型，则**在桥里追加 export**（不偷懒直接 import 非桥文件）。
3. 检查 `lib/logic/**` 里同层互调（如 download_manager → playback_service）合法保留。
4. `lib/surface/**` 里所有直接 `import '../../kernel/kernel.dart'`（如 qr_painter.dart）→ 改经 bridge_surface/bridge_logic。
5. 每文件 ≤500 行不变；跑 layer_audit 自证。

### 批7-C：layer_audit 强约束 + CI 门禁 + 文档
1. 重写 `tool/layer_audit.py`：
   - 允许：同层 import、SDK import、相邻桥 import、L6 的 flutter/miuix/riverpod。
   - 拒绝：跨层 import 非桥文件（含 init→surface、core→kernel 直连、logic→core 直连）。
   - 拒绝：lib/bridges 之外的任何 `bridges/` 影子目录含 .dart。
   - 拒绝：桥文件里存在公开函数无 try/catch（简单词法扫描）。
   - 输出 PASS / VIOLATION 清单 + 退出码。
2. `tool/smoke_check.dart` 的禁 import 规则同步收紧（与 layer_audit 一致）。
3. 更新 `docs/SIX_FIVE_RULE.md`：§4 历史偏差改为「已收敛」，附收敛日期与 CI run。
4. 更新 `docs/ARCHITECTURE.md`：五桥定义表补齐 5 个文件，删过渡口径注记。

## 收敛验收

- `python3 tool/layer_audit.py` → `PASS strict six-five`
- `dart run tool/smoke_check.dart` → `PASS smoke_check`
- CI（analyze/test/build/release）全绿 → 自动发版（东八区 YY.MM.DD.NN）
- 与功能对齐无关：收敛不删任何功能代码，只改 import 路径与桥包装。

## 纪律

- 三个代理任务书开头**原文粘贴 §0 前缀**。
- 子代理只用 file_read/file_write/file_edit/ls，不验证不提交。
- 每批完成主会话逐文件审查，全批通过后**只推一次、只跑一次 CI**（用户要求：3 批一次，不反复过 CI）。
