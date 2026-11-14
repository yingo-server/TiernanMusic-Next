# TiernanMusic-Next

Flutter 离线优先的酷狗第三方客户端（酷狗原生 API 直连，不依赖第三方网关）。
六层五桥架构 + Riverpod + Isar，目标平台 Android（split-per-abi 三架构极限包体）。

> 零源仓库代码复用：酷狗 API 知识全部来自逆向知识文档 [docs/KUGOU_API.md](docs/KUGOU_API.md)。

## 架构速览：六层五桥

```
L6 surface    交互/UI (Flutter M3)       ⇅ bridge_surface.dart
L5 logic      纯后端逻辑（无UI无IO直连）    ⇅ bridge_logic.dart
L4 core       存储/数据库/内存/网络        ⇅ bridge_core.dart
L3 kernel     生命周期/注册表/日志/校验     ⇅ bridge_kernel.dart
L2 bootloader 启动序列/依赖装配           ⇅ bridge_boot.dart
L1 init       main 入口/完整性校验触发
```

**铁律**

1. 跨层只能经桥文件（lib/bridges/），`tool/layer_audit.py` CI 强制。
2. 桥函数统一 try/catch + Log 留痕，失败不静默吞。
3. core/net/endpoints/ 每端点一模块 + `core/net/endpoint_registry.dart` 的 `EndpointRegistry` 声明式配置（50 个端点常量，从 `kugou_client.dart` 拆出），改 API 不动调用方。
4. 零源仓库代码复用；酷狗 API 知识仅来自 docs/KUGOU_API.md。
5. 依赖纪律：SDK 可实现（≤500行/文件）不引库；例外清单：`riverpod / just_audio / audio_service / isar / isar_flutter_libs / path_provider / video_player`（MV 内嵌播放壳，`video_player` 已加入 pubspec 并同时列入 `tool/layer_audit.py` / `tool/smoke_check.dart` 的 L6 白名单；`package:isar/isar.dart` 为两工具共同的 L4_EXTRA 例外）。以 `pubspec.yaml` 为唯一依赖事实源。
6. L6 热插拔：页面/组件为 SurfaceModule，注册表一行增删，模块间零直接 import。

## 快速开始

本项目**构建与测试全部在 CI 完成**（本地 arm64 无 Flutter SDK）：

- 推送到 main 或打 tag `v*` 触发 [.github/workflows/ci.yml](.github/workflows/ci.yml)；
- 手动触发：workflow_dispatch，可选 `release`（发布 Release）与 `debug`（debug 构建，允许完整性 bypass）；
- 产品为 `analyze-test` → `build`（split-per-abi APK）→ `release`（changelog 取 changed/<版本>.md）。

本地仅支持纯 Dart 检查（无需 Flutter SDK）：

```bash
dart run tool/smoke_check.dart   # 静态合规冒烟：括号/禁import/桥唯一性
dart run tool/md5_smoke.dart     # MD5 签名四向量
python3 tool/layer_audit.py      # 跨层审计
python3 tool/analyze_gate.py     # 项目类型真错误闸
flutter analyze / flutter test   # 需本机安装 Flutter SDK
```

`tool/local_gate.sh` 为**本地十道门禁**（全绿输出 `FINAL-OK`；旧的「八道」口径已废弃，十道含 `smoke_check` 与 `analyze_gate`）。CI `.github/workflows/ci.yml` 的 `verdict` 与之逐项对齐：覆盖 `layer_audit` / `syntax` / `smoke` / `analyze_gate` / `md5` / `field_truth` / `reachability` 及 `boot` / `play` / `resolve` / `download` 契约自检，每道都有独立 `tee /tmp/*.log` 与正向 PASS / 反向 FAIL grep 判据。

## 模块清单（lib/ 六层目录）

| 目录 | 层 | 说明 |
|---|---|---|
| lib/init/ | L1 | main 入口：启动 bootloader、触发完整性校验 |
| lib/bootloader/ | L2 | 启动序列与依赖装配 |
| lib/kernel/ | L3 | 生命周期、注册表、日志、完整性校验 |
| lib/core/ | L4 | 签名引擎、50 端点声明注册表（`core/net/endpoint_registry.dart`，已拆出 `kugou_client.dart`）、KRC 解密、AES/RSA、Isar 数据库、文件存储、LRU/磁盘缓存 |
| lib/logic/ | L5 | 播放队列状态机、播放源编排、下载管理、歌词解析、账号（QR 登录）、搜索/歌单/榜单 |
| lib/surface/ | L6 | 热插拔 SurfaceModule 注册表、六大页面模块、亮暗主题、播放器控制器 |
| lib/bridges/ | 桥 | 五桥门面：唯一合法跨层通道，统一日志留痕 |

## 测试策略

- **签名四向量**：`tool/md5_smoke.dart` / `test/signing_test.dart` 用 MD5 标准向量（empty/abc/fox/long）锁定签名引擎的哈希底座。
- **层审计**：`tool/layer_audit.py` 静态扫描全部 import，跨层即 VIOLATION（含桥的使用层级白名单，init→app_root 装配特例除外）。
- **三态回归锚点**：酷狗端点返回体按匿名/非VIP/VIP 三态实测，字段路径与错误语义（20028 / priv_status=0）写入 docs/KUGOU_API.md 作为回归锚点，play_url 权限判定唯一可信源为 status/priv_status。
- **静态冒烟**：`tool/smoke_check.dart`（括号配平 / 禁 import / 桥文件唯一性），CI 在 pub get 后、analyze 前执行；`tool/analyze_gate.py` 只挑项目内类型真错误，二者同为本地十道门禁成员。
- CI 报错不妥协：全部门禁 continue-on-error 跑完，末尾 verdict 汇总判定（与本地十道逐项对齐）。

## 版本策略

`26.11.10.N`（日期.序号）。每个发布版本一份 `changed/<版本>.md` changelog，CI 的 release job 自动将其作为 Release body（缺失则回退最近 20 条 commit）。当前版本：26.11.10.1 LTS。

## License

Apache-2.0
