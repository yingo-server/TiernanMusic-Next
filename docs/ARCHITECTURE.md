> 🗄️ **已归档（2026-11-19）** — 本篇曾为架构规范摘要，现由
> [层与桥参考](architecture/LAYERS_AND_BRIDGES.md) + [架构总览](architecture/ARCHITECTURE_OVERVIEW.md) 取代；
> 其中「Spotify 深色设计系统」为旧描述，当前设计语言是森林翡翠语义 token。

# TiernanMusic-Next 架构规范 · 76 原则（七层六桥）

> 权威定义：[docs/SEVEN_SIX_RULE.md](SEVEN_SIX_RULE.md)。V1 六层五桥见 [SIX_FIVE_RULE.md](SIX_FIVE_RULE.md)（DEPRECATED）。

## 七层（低→高；session 是 surface 的底层）

```
L7 surface    仅 UI 控件（Spotify 深色设计系统）      ⇅ bridge_surface.dart
L6 session    播放编排 / 播放列表 / 装配图 / 导航状态  ⇅ bridge_session.dart
L5 logic      纯后端逻辑                            ⇅ bridge_logic.dart
L4 core       缓存⊃预读 / 音频网关 / 纯算法 / 网络     ⇅ bridge_core.dart
L3 kernel     生命周期 / 日志                       ⇅ bridge_kernel.dart
L2 bootloader 启动序列 / 依赖装配                   ⇅ bridge_boot.dart
L1 init       main 入口 / 完整性校验触发
```

依赖方向 `surface → session → logic → core`，禁止反向。六桥唯一位于 `lib/bridges/`。

## 铁律
1. 跨层只经桥；`layer_audit.py` / `smoke_check.dart` CI 强制；影子 bridges 目录即违规。
2. 桥公开函数 try/catch + Log 留痕，失败不静默吞。
3. L4 端点 `core/net/endpoints/` 每端点一模块 + `endpoint_registry.dart` 声明式配置；改 API 不动调用方。
4. 缓存包容预读：`core/cache/cache_service.dart` 统一 `get/prefetch/invalidateSession`；独立预读器已删。
5. 成熟库优先：音频用 just_audio / audio_service；仅当库功能利用率 <20% 才自研。纯算法（QR/取色/i18n）下沉 L4，零 flutter 依赖。
6. L7 页面 `extends SurfaceModule`，注册表在 L6；外壳按 registry 动态生成导航；模块间零直接 import。
7. 单文件 ≤500 行；零源仓库代码复用；酷狗 API 知识仅来自 `docs/KUGOU_API.md`。

## 依赖例外（以 pubspec.yaml 为事实源）
- L7：flutter / riverpod / just_audio / audio_service / path_provider / video_player
- L6：flutter foundation/widgets（ChangeNotifier / WidgetBuilder 类型），禁渲染
- L4：isar 实体注解、just_audio、audio_service
`tool/layer_audit.py` 的 L4_EXTRA / L6_EXTRA / L7_EXTRA 与 `smoke_check.dart` 同口径。

## 门禁
本地 `tool/local_gate.sh` 覆盖 syntax / smoke / layer / analyze_gate / md5 / field_truth / reachability / boot / session / play / resolve / download 契约；CI verdict 逐项对齐。`PASS strict seven-six` 为层审计正向判据。完整性校验在 CI 构建期生成 `verification.json`（加盐摘要 + RSA-4096 签名），运行期只校验构建产物。
