> 🗄️ **已归档（2026-11-19）** — V2 契约曾为权威，现由 [架构总览](architecture/ARCHITECTURE_OVERVIEW.md) +
> [层与桥参考](architecture/LAYERS_AND_BRIDGES.md) 取代；本篇 §4/§8 措辞矛盾（"L7 session" / "L6 只有 Widget"），
> 且 §6「surface 仅占位」与实际 13 页已建不符。保留仅为追溯 76 原则的立规过程。

# 76 原则（76 原则）· 架构 V2 权威契约

> 立规来源：用户 2026-11-14 决策（推倒重建 L6 后确立）。取代 V1「76 原则（V1 已废弃）」。
> 本文件是分层、桥、依赖、缓存/预读关系的唯一权威定义。派子代理任务书开头必须贴 §0。

---

## §0 任务书前缀（直接复制给每个子代理）

```
【76 原则 · 必须遵守】
七层（低→高；**session 是 surface 的底层，surface 只画控件**）：
  L1 init        入口、完整性校验触发
  L2 bootloader  启动序列、依赖装配
  L3 kernel      生命周期编排、日志、盐值校验执行
  L4 core        存储 / 数据库 / 缓存(包容预读) / 网络 / 音频引擎 / 纯算法 / l10n 常量
  L5 logic       仅后端逻辑（无 UI、无 IO 直连）
  L6 session     编排会话层：播放控制/播放列表/装配图/模块注册表/导航状态/provider 定义
  L7 surface     **仅 UI 控件**（由独立模型负责重写，本轮只留契约占位）
六桥（相邻层各一，唯一合法跨层通道）：
  bridge_boot / bridge_kernel / bridge_core / bridge_logic / bridge_session / bridge_surface
依赖方向：surface(L7) → session(L6) → logic(L5) → core(L4)；禁止反向。
铁律：
  1. 不同层级之间必须通过桥接层调用；禁止跨层直接 import 非桥文件。
  2. 桥接层承担日志系统任务：每个桥函数 try/catch 捕获，失败必 Log 留痕，不静默吞。
  3. 桥文件唯一存在于 lib/bridges/，禁止任何影子桥目录。
  4. 每层只依赖其下层经桥暴露的门面；同层内引用合法，反向依赖一律禁止。
  5. 单文件超过 1500 行才按功能拆分；允许 dart format；L6 模块经 session 层注册表热插拔，模块间零直接 import。
  6. 网络层 core/net/endpoints/ 每端点一 dart 模块；参数多参不缺参；只连酷狗官方域名。
  7. 零源仓库代码复用；归档项目只读 docs/ 描述性文档提取功能目标。
  8. **播放控制/播放列表/缓存/预读/装配图 一律不得放进 L6**；L6 只有 Widget。
  9. 能用成熟库就用成熟库（just_audio / audio_service / video_player；缓存网络允许 dio+缓存拦截器）。
 10. 子代理只用 file_read/file_write/file_edit/ls；不验证、不跑分析器、不提交。
```

---

## 1. 分层职责（V2 重划）

| 层 | 目录 | 职责 | 明确禁止 |
|---|---|---|---|
| L1 | `lib/init/` | main、runBoot 触发、错误页 | 业务 |
| L2 | `lib/bootloader/` | core/logic 单例装配、DB await | 持有 Widget |
| L3 | `lib/kernel/` | Log、生命周期 | UI |
| L4 | `lib/core/` | net / database / storage / **cache(包容 prefetch)** / **audio(引擎封装)** / **algorithms(QR/取色)** / **l10n(常量表)** | Widget、BuildContext |
| L5 | `lib/logic/` | 纯后端逻辑、状态机数据 | Widget、IO 直连 |
| L6 | `lib/session/` | 播放编排、播放列表、装配图(AssemblyResult/provider)、模块注册表、导航状态 | 直接画控件（只对外暴露状态/回调） |
| L7 | `lib/surface/` | **只有 Widget 与 ThemeData**；本轮仅占位 | 播放控制/队列/缓存/预读/装配图/provider 图 |

> L7 surface 经 `bridge_surface` 拿 L6 的门面；L6 session 经下五桥拿 core/logic 能力。
> **session 是 surface 的底层**：surface 只能向下依赖 session，session 永不 import surface。
> 允许登记例外：`init/main.dart → bootloader/register.dart`（语言层装配必需）。
>
> 桥的相邻关系（V2 修正）：
> `bridge_boot`(L1↔L2) / `bridge_kernel`(L2↔L3) / `bridge_core`(L3↔L4) /
> `bridge_logic`(L4↔L5) / `bridge_session`(L5↔L6) / `bridge_surface`(L6↔L7)。

## 2. 六桥

| 桥 | 方向 | 暴露 |
|---|---|---|
| `bridge_boot` | L1↔L2 | BootOutcome / runBootImpl |
| `bridge_kernel` | L2↔L3 | Log |
| `bridge_core` | L3↔L4（供上层经白名单复用） | 全部 core 门面（含 cache/audio/algorithms） |
| `bridge_logic` | L4↔L5（供上层经白名单复用） | 全部 logic 门面 |
| `bridge_session` | L5↔L6 | PlaybackSession / ModuleRegistry / AppGraph / NavState |
| `bridge_surface` | L6↔L7 | SurfaceDeps / installServices / bootstrapApp / AppRoot / lightThemeData |

## 3. 缓存 ⊃ 预读（深度融合，用户裁定）

> 「预读完了不就得缓存吗？缓存包容预读。」

- **一个域**：`lib/core/cache/`（不是 cache + prefetch 两个模块）。
- `CacheService` 是唯一入口：`get / put / prefetch(keys) / stats / invalidate`。
- 预读不是外挂调度器，而是 CacheService 的**写入策略**：`prefetch()` 就是对预测键做一次 `put`（带来源标记 `prefetched`），命中时直接复用 L1 内存 / L2 磁盘。
- 三级一体：L1 LRU 内存 → L2 ResourceCache 磁盘(异步+互斥) → L3 网络(单飞合并)。
- 预读触发（队列 upcoming 窗口）由 **L7 session** 决定「预测哪些键」，但**不执行写入**；执行权在 L4 CacheService。
- 禁止 `PrefetchEngine` 作为独立类持有队列/定时器；它降级为 `CacheService.prefetchPolicy` 内部策略。

## 4. 播放控制下沉（成熟库）

- 播放状态机/队列/reducer 属 **L5 logic/player**（已有 queue_state / player_state / playback_reducer，保留）。
- **播放编排**（resolve→engine→历史→通知栏→预读触发）属 **L7 session/playback_session.dart**。
- 引擎封装 `just_audio` / `audio_service` 属 **L4 core/audio/**（成熟库边界，纯 IO 适配）。
- L6 的播放页只 `ref.watch(session 暴露的快照)` + 发意图（play/next/seek），零状态机。

## 5. 纯算法下沉（并改测试）

| 资产 | V1 位置 | V2 位置 | 测试 |
|---|---|---|---|
| QR 编码 QrMatrix/encodeQr | surface/widgets/qr_painter.dart | `core/algorithms/qr_codec.dart` | `test/qr_painter_test.dart` 改 import |
| CustomPainter 渲染 | 同上 | **留 L6**（独立模型重写时再建） | — |
| 主色提取 extractDominant/fromSeed | surface/theme/color_extract.dart | `core/algorithms/color_extract.dart` | field_truth 锚点保留 |
| i18n 10语×20键常量表 | surface/l10n/l10n_helper.dart | `core/l10n/strings.dart` | — |
| deps / assembly_result / nav_state / registry / providers | surface 根 | `session/` | — |

## 6. L6 占位约定（给独立 UI 模型）

- 仅保留可让桥编译的最小契约：`surface/app_root.dart`（SurfaceDeps/installServices/bootstrapApp/AppRoot 占位）、`surface/theme/tn_theme.dart`（tnLightThemeData 占位）。
- 页面/组件**全部不建文件**；独立模型按 `surface/pages/`、`surface/widgets/`、`surface/theme/` 自行从零写。
- 占位文件头必须写 `// PLACEHOLDER — 由独立 UI 模型重写，禁止在此堆逻辑`。
- 本轮允许编译不过（用户明示）；语法检查只用于确认**下层（L1~L5、L7、桥）自身无 surface 残留引用**。

## 7. 门禁改造

- `layer_audit.py`：LAYERS 加 `session:7`；BRIDGE_NAMES 加 `bridge_session`；LAYER_ALLOWED_BRIDGES 加 7；L7 允许 flutter/riverpod（状态容器类型）。
- `smoke_check.dart`：同步层表与六桥白名单。
- `feature_reachability_test.dart`：删除「surface/pages/*.dart 存在」断言，改为「L7 session 装配图存在」；删除 tn_theme M3 断言。
- `local_gate.sh` / CI verdict：保持十道；surface 文件数缩到占位后不强制页面存在。

---

*V2 生效后，旧 `SEVEN_SIX_RULE.md` 仅作历史留档，派代理一律贴本文件 §0。*
