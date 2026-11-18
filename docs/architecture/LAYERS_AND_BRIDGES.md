# 层与桥参考（Reference）

> 审阅：2026-11-19 · 事实源：`lib/` 目录、`tool/layer_audit.py`、`tool/smoke_check.dart`。
> 本文只陈述事实，不含操作指令；职责解释见 [架构总览](ARCHITECTURE_OVERVIEW.md)。

## 七层

| 层 | 目录 | 职责 | 已核实细节 |
|---|---|---|---|
| L1 init | `lib/init/` | main 入口、完整性校验触发、启动错误页 | `main.dart` 装配并 `runApp` |
| L2 bootloader | `lib/bootloader/` | 启动序列、依赖装配 | `bootloader.dart`（Bootstrap.run / BootResult）、`register.dart` |
| L3 kernel | `lib/kernel/` | 生命周期、日志 | `kernel.dart`（Log/LogE/LogW/LogD、Kernel.assemble） |
| L4 core | `lib/core/` | 存储 / 数据库 / 缓存(⊃预读) / 网络 / 音频 / 纯算法 / l10n / 平台层 | 端点注册表 `core/net/endpoint_registry.dart` 声明式配置 54 个 `Endpoint` 常量；`endpoints/` 每端点一模块 |
| L5 logic | `lib/logic/` | 纯后端逻辑、状态机数据 | auth / catalog / download / lyrics / player 五个子域 |
| L6 session | `lib/session/` | 播放编排、装配图、模块注册表、导航状态、主题/语言控制器 | `playback_session.dart` / `graph.dart` / `module_registry.dart` / `nav_state.dart` / `theme_controller.dart` / `locale_controller.dart` / `auth_session.dart` / `bootstrap.dart` / `contracts.dart` |
| L7 surface | `lib/surface/` | 仅 UI 控件与 ThemeData；官方 M3 + GetWidget，只写色彩 | 页面在 `pages/`；设计 token 在 `design/tokens_v2.dart`；标题栏在 `design/desktop_titlebar.dart` |

依赖方向恒为 `surface(L7) → session(L6) → logic(L5) → core(L4)`，禁止反向。

## 六桥

| 桥 | 连接 | 暴露 / 角色 |
|---|---|---|
| `bridge_boot` | L1 ↔ L2 | BootOutcome / runBootImpl，装配入口 |
| `bridge_kernel` | L2 ↔ L3 | Log |
| `bridge_core` | L3 ↔ L4（供上层经白名单复用） | core 门面：DAO、KugouClient、端点模型、CacheService、音频网关、QR/取色算法、TnStrings、平台能力/网关/窗口服务单例 |
| `bridge_logic` | L4 ↔ L5 | 各 Logic 门面与状态类型 |
| `bridge_session` | L5 ↔ L6 | PlaybackSession / ModuleRegistry / AppGraph / NavState / ThemeController / LocaleController |
| `bridge_surface` | L6 ↔ L7 | SurfaceDeps / installServices / bootstrapApp / AppRoot / 主题 |

桥文件**唯一**位于 `lib/bridges/`，影子桥目录即违规。桥函数统一 `try/catch` + Log 留痕，
失败返回语义错误或默认值，不静默吞；不在桥内写业务逻辑。
`bridge_core` 以 `export` 白名单方式暴露门面（历史上曾过宽，属登记的设计取舍）。

## 缓存 ⊃ 预读

- 唯一入口 `lib/core/cache/cache_service.dart` 的 `CacheService`：`get / put / prefetch / stats / invalidate`。
- `prefetch()` 是以来源标记 `prefetched` 的一次 `put`，不是独立调度器；禁止独立的 `PrefetchEngine` 持有队列/定时器。
- 三级一体：L1 LRU 内存 → L2 磁盘 ResourceCache → L3 网络单飞（inflight 合并）。
- 「预测哪些键」属 session 层编排，「执行写入」属 core 层 CacheService。

## 端点注册表（网络层）

- `lib/core/net/endpoint_registry.dart` 定义 `Endpoint` 与 `SignType`，每个端点一常量
  （path / base / router / signType / cacheable / tid / includeSrcappid 等）。
- `lib/core/net/endpoints/` 下每端点独立 dart 模块，改 API 不动调用方。
- 只连酷狗官方域名；签名相关见已归档 `KUGOU_API.md`。

## 例外与已登记偏差

1. `init/main.dart → bootloader/register.dart` 为语言层装配必需，登记例外。
2. `bridge_surface → surface`（AppRoot/主题）为契约要求的装配门面，登记例外。
3. L5 `download` 域 4 文件用 `dart:io`/HttpClient 直连，是历史架构债（违反「logic 无 IO 直连」），未修。
4. `SEVEN_SIX_RULE.md` §4/§8 有措辞矛盾（"播放编排属 L7 session" / "L6 只有 Widget"）；
   以 §1 表格与 §0 为准：**session(L6)=编排，surface(L7)=仅控件**。该文档已归档，勿据此实现。

## 门禁判据（事实）

- `python3 tool/layer_audit.py` → 正向判据 `PASS strict seven-six`，检查跨层 import、影子桥、
  桥 try/catch+Log、单文件行数、层白名单、regions。
- `dart run tool/smoke_check.dart` → 括号配平、禁 import、桥唯一性；无 `VIOLATION`。
- L4_EXTRA / L6_EXTRA / L7_EXTRA 例外清单与 `smoke_check.dart` 同口径，以 `pubspec.yaml` 为依赖事实源。
  L7 例外含 `package:get` 与 `bitsdojo_window` 所需依赖；`package:isar/isar.dart` 为 L4 例外。
