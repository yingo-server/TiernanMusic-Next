# 架构总览（Explanation）

> 审阅：2026-11-19 · 事实源是 `lib/` 代码本身；本文解释「为什么是这个形状」。
> 查具体层/桥/token/能力定义请看文末的 Reference 链接，本文不复述其数值。

TiernanMusic-Next 是 Flutter 离线优先的酷狗第三方客户端（直连酷狗官方域名，不依赖第三方网关）。
当前架构由两条线构成：**76 原则的七层六桥纵向分层**，以及**平台层 / 权限网关 / 设计语言三个横切关注点**。

## 为什么是七层六桥

76 原则的核心约束是「跨层只走相邻桥、依赖只能向下」。七层自底向上：

```
L7 surface   ← 仅 UI 控件（官方 M3 + GetWidget，只写色彩）
L6 session   ← 编排会话：播放编排 / 装配图 / 模块注册表 / 导航状态
L5 logic     ← 纯后端逻辑与状态机
L4 core      ← 存储 / DB / 缓存(包容预读) / 网络 / 音频 / 纯算法 / l10n / 平台层
L3 kernel    ← 生命周期 / 日志
L2 bootloader← 启动序列 / 依赖装配
L1 init      ← main 入口 / 完整性校验触发
```

六桥 `bridge_boot / bridge_kernel / bridge_core / bridge_logic / bridge_session / bridge_surface`
各连接一对相邻层，是唯一合法的跨层通道；桥函数统一 `try/catch` + Log 留痕。
依赖方向恒为 `surface → session → logic → core`，禁止反向。
逐层职责、桥暴露内容、例外登记见 [层与桥参考](LAYERS_AND_BRIDGES.md)。

这样切的理由：UI 重写后 surface 只剩控件与主题，「能不能做、状态是什么」全部下沉到 session 与 logic，
使破坏性换皮不触碰业务；桥把日志与错误翻译集中在一处，避免静默失败。

## 横切关注点落位（重写后的新增部分）

| 关注点 | 落位 | 为什么不破坏分层 |
|---|---|---|
| 平台差异（怎么做） | `lib/core/platform/`（条件导入 stub/io/web） | 只在 L4 内实现，经 `bridge_core` 暴露平台无关接口 |
| 能力/权限（有没有权） | `lib/core/capability/` | 平台无关的 `CapabilityGateway` 语义模型，logic/surface 不碰 `Platform.isXxx` |
| 设计语言（长什么样） | `lib/surface/design/tokens_v2.dart` | 纯色彩 token 与主题装配，不是控件；零手写控件 |

- **平台层**：实际落盘在 `lib/core/platform/`（早期规划文档 `UI_REWRITE_PLAN.md` 写的是 `lib/platform/`，
  该规划已归档；以代码路径为准）。窗口服务用 `window_manager`，bitsdojo 只提供原生句柄与按钮控件，
  二者职责分离，见 [平台能力参考](PLATFORM_CAPABILITIES.md)。
- **权限网关**：`CapStatus` 五态（granted / denied / permanentlyDenied / restricted / unsupported），
  桌面与移动差异收敛在网关内；见 [平台能力参考](PLATFORM_CAPABILITIES.md)。
- **桌面标题栏**：仅 Windows/Linux 自绘，`buildDesktopTitleBar()` 用 bitsdojo 官方按钮 + `titlebar.*` token，
  颜色独立于内容区 ColorScheme；见 [设计语言参考](DESIGN_LANGUAGE.md)。

## 门禁与构建（怎么保证不腐化）

- 本地：`tool/local_gate.sh` 串起 12 道门禁（layer_audit / syntax / smoke / analyze_gate / md5 /
  field_truth / reachability / boot / play / session / resolve / download），另有 UI 三门禁
  （`ui_no_custom_widgets.py`、`ui_contrast_gate.py`、`bottom_bar_gate.py`）。
- CI：`.github/workflows/ci.yml`（analyze-test → build apk split-per-abi → release）；
  全平台桌面走 `.github/workflows/desktop-build.yml`（Windows zip、Ubuntu 22.04 上打 Linux AppImage）。
- 怎么运行、四步版本路线见 [构建指南](BUILD_GUIDE.md)。

## 诚实现状（不是已实现功能请勿当作已交付）

- **i18n 全量接线**：10 份 `.arb` 翻译数据已落盘，但界面文案的全量接线率仍很低，属需真实译文的后续专项。
- **20028 验证端点**：`getVerifyInfo` / `submitVerification` 目前 `return false`（未实测），L7 无验证 UI；
  用户遇验证时只做到「错误文案可见」，不是「能解」。
- 其它明确后续项：歌单写入口、缓存域统一、动画体系、设置页/导航细节、分页/热搜/榜单详情、
  匿名 MV 死代码、MV 端点级测试锚点、L5 download 域 `dart:io` 直连（历史架构债）。
  逐条证据见已归档的 `FINAL_VERIFICATION.md` / `ARCHITECTURE_REVIEW.md`。

## Reference（事实页）

- [层与桥参考](LAYERS_AND_BRIDGES.md)
- [设计语言参考](DESIGN_LANGUAGE.md)
- [平台能力参考](PLATFORM_CAPABILITIES.md)
