# 六五规则（六层五桥）—— 权威契约 · 派代理必贴

> 本文件是 TiernanMusic-Next 架构的唯一权威定义。**每次派子代理，任务书开头必须原文粘贴本文件「§0 任务书前缀」，不得改写、不得省略、不得用"宽松口径"替代。**
> 立规来源：项目启动时的用户定义（2026-11-10）。历史批次曾因任务书未贴本规则而按"单向依赖+桥作导出表"的宽松口径实现，已在收尾阶段统一收敛。

---

## §0 任务书前缀（直接复制给每个子代理）

```
【六五规则 · 必须遵守】
六层（低→高）：
  L1 init        入口、完整性校验触发
  L2 bootloader  启动序列、依赖装配
  L3 kernel      生命周期编排、模块注册表、日志、盐值校验执行
  L4 core        存储 / 数据库 / 内存缓存 / 网络请求 四大域
  L5 logic       仅后端逻辑（无 UI、无 IO 直连）
  L6 surface     交互 UI 设计（miuix），模块可热插拔
五桥（相邻层各一，唯一合法跨层通道）：
  bridge_boot / bridge_kernel / bridge_core / bridge_logic / bridge_surface
铁律：
  1. 不同层级之间必须通过桥接层调用；禁止跨层直接 import 非桥文件。
  2. 桥接层承担日志系统任务：每个桥函数 try/catch 捕获，失败必 Log 留痕，不静默吞。
  3. 桥文件唯一存在于 lib/bridges/，禁止任何影子桥目录。
  4. 每层只依赖其下层经桥暴露的门面；同层内引用合法，反向依赖一律禁止。
  5. 单文件 ≤500 行；UI 模块经 SurfaceRegistry 热插拔，模块间零直接 import。
  6. 网络层 core/net/endpoints/ 每端点一 dart 模块，相对独立便于修改；参数多参不缺参，dfid/mid/uuid 恒显式携带并参与签名；只连酷狗官方域名。
  7. 零源仓库代码复用；归档项目只读 docs/ 描述性文档提取功能目标。
  8. 子代理只用 file_read/file_write/file_edit/ls；不验证、不跑分析器、不提交。
```

---

## §1 六层定义

| 层 | 目录 | 职责 | 允许 import |
|---|---|---|---|
| L1 init | `lib/init/` | `main()`、完整性校验触发、装配根 | bootloader 桥 + surface 桥（经白名单收敛后取消直连） |
| L2 bootloader | `lib/bootloader/` | 启动序列、依赖装配、签名校验触发点 | bridge_boot |
| L3 kernel | `lib/kernel/` | 生命周期编排、模块注册表、日志、加盐 SHA-512 校验执行 | bridge_kernel 下层 + SDK |
| L4 core | `lib/core/` | 四域：`storage/` `database/` `memory/` `net/`（含 `endpoints/` 每端点一模块） | bridge_core 下层 + SDK |
| L5 logic | `lib/logic/` | 纯后端逻辑：播放器状态机、搜索/歌单/下载/歌词/账号策略 | bridge_logic 下层（只经桥拿 core 能力） |
| L6 surface | `lib/surface/` | 交互 UI（miuix）、主题、页面模块、动画 | bridge_surface + flutter/miuix/riverpod + 本层 |

## §2 五桥定义

| 桥 | 文件 | 连接 | 暴露内容 |
|---|---|---|---|
| Bridge-Boot | `lib/bridges/bridge_boot.dart` | L1 ⇅ L2 | BootResult、装配入口、完整性校验 |
| Bridge-Kernel | `lib/bridges/bridge_kernel.dart` | L2 ⇅ L3 | Log、KernelContext、IntegrityVerifier |
| Bridge-Core | `lib/bridges/bridge_core.dart` | L3 ⇅ L4 | 四域门面类 + 端点强类型模型 |
| Bridge-Logic | `lib/bridges/bridge_logic.dart` | L4 ⇅ L5 | 各 Logic 门面 + PlayerState/QueueState 等 |
| Bridge-Surface | `lib/bridges/bridge_surface.dart` | L5 ⇅ L6 | LogicFacade、状态订阅、动作分发 |

**桥的职责**：唯一跨层通道 + 日志系统载体。每个桥函数：
- `try { ... } catch (e, st) { Log.e(tag, msg, e, st); ... }`
- 失败必须留痕（返回语义错误/默认值，不静默吞）
- 不在桥内写业务逻辑，只做转发、包装、错误翻译

## §3 判定基准（layer_audit 升级目标）

- 跨层 import 非桥文件 → `VIOLATION`
- 桥文件出现在 `lib/surface/bridges/` 等影子目录 → `VIOLATION`
- 同层 import、SDK import（`dart:*`）、`package:flutter*` 仅 L6 → 合法
- 桥函数无 try/catch → CI lint 报错（收敛阶段加）

## §4 历史偏差与收敛说明

批1-5 及功能对齐批1-2 的任务书曾写「L5 可用 L4 全部，直接 import 合法」，属**过渡口径**，产出的代码存在：
- `core/*` 直接 `import kernel.dart show Log`（应经 bridge_kernel）
- `logic/*` 直接 import `core/` 内部多个文件（应经 bridge_core）
- `bootloader` 越级使用 bridge_core/bridge_logic
- `init/main.dart → surface/app_root.dart` 白名单直连
- 桥只有 3 个（缺 bridge_kernel / bridge_surface），且桥只 export 无捕获函数

用户已定：**功能优先，最后收敛**。功能补齐 5 批全部完成后，按 §3 统一收敛：
补齐 2 个缺失桥 → 全仓跨层 import 改走相邻桥 → 删 init→surface 白名单 → layer_audit 升级为强约束 → CI 全绿后发布新版本。

## §5 附带原则（同样每次贴）

- 三态登录：匿名 / VIP / 免费，每个 API 调用必须验证三态返回并计入测试原则。
- 版本号由 CI 按东八区生成 `YY.MM.DD.NN`（日期+两位序号）。
- 等待用定时器，不用 sleep；报错不妥协，尽量跑完全程一次暴露全部错误。
- 每批 3 子代理并行、自上而下（core→logic→surface）构建；每批完成后主会话逐文件审查，审查通过才提交；子代理不 commit/push。
- 本地只有 Dart SDK 做静态分析，需过滤 Flutter 噪音；构建与测试全部在 CI 完成。
- 极限包体、性能、动画完善（TnMotion 常量表统一曲线）。
