# TiernanMusic-Next

**一款离线优先的酷狗第三方音乐客户端（Flutter）。** 直连酷狗原生 API，不依赖第三方网关，数据与下载落在本机 —— 为想要"自己掌控播放、下载与账号凭据"的用户而做，Android 与桌面（Windows / Linux AppImage）可用。

> 零源仓库代码复用：酷狗 API 知识全部来自自建的逆向知识文档 [docs/KUGOU_API.md](docs/KUGOU_API.md)。仅供学习研究，不随包分发酷狗内容。

## 它能做什么

- **播放 / 下载 / 歌词 / MV**：播放队列状态机与播放源编排（L5 logic），音频走 just_audio + audio_service，支持歌词解析与 MV 内嵌播放壳。
- **离线优先**：Isar 本地数据库 + 统一缓存服务（含预读 `prefetch`），看过/听过的不重复拉网。
- **账号**：QR 扫码登录 + **YKG 链接登录**（AES-256-GCM / PBKDF2-HMAC-SHA256 报文封装，算法全部用成熟库，设计见 [docs/YKG_LINK_CRYPTO_DESIGN.md](docs/YKG_LINK_CRYPTO_DESIGN.md)）。
- **三态适配**：匿名 / 非VIP / VIP 三种返回体逐字段实测并写入回归锚点（含 20028 / priv_status 语义），权限判定唯一可信源为 status/priv_status。

## 为什么它的 UI 可信

UI 由两套现成模块构成，我们**只写色彩，不写控件**：

- **官方 Material 3** 承载全部结构（Scaffold / NavigationBar / Card / Dialog…），只做主题与参数配置；
- **GetWidget** 补足反馈层（Obx / GetSnackbar / GetDialog / GetBottomSheet）。

色彩是"森林翡翠"设计语言（[docs/DESIGN_LANGUAGE.md](docs/DESIGN_LANGUAGE.md)）：**中性灰底 + 翡翠绿强调** —— 底色回到中性灰阶（不铺色相，保证卡片分层可辨），翡翠绿只出现在强调位与状态位。语义 token 明暗成对定义，对比度脚本化校验（正文 ≥4.5:1、边框 ≥3:1），门禁 `ui_contrast_gate.py` 同时校验**代码真源与文档一致**、并禁止错误页在 MaterialApp 之外取主题。门禁 `ui_no_custom_widgets.py` 零例外禁止自绘控件与硬编码色值 —— 所以每一屏都来自官方组件的默认质量。

## 76 原则架构（七层六桥）

权威定义见 [docs/SEVEN_SIX_RULE.md](docs/SEVEN_SIX_RULE.md)，架构规范见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：

```
L7 surface    仅 UI 控件           ⇅ bridge_surface.dart
L6 session    播放编排/导航状态     ⇅ bridge_session.dart
L5 logic      纯后端逻辑           ⇅ bridge_logic.dart
L4 core       缓存/音频网关/网络    ⇅ bridge_core.dart
L3 kernel     生命周期/日志        ⇅ bridge_kernel.dart
L2 bootloader 启动序列/依赖装配     ⇅ bridge_boot.dart
L1 init       main 入口
```

- 依赖方向 `surface → session → logic → core`，禁止反向；跨层只能经 `lib/bridges/`，`tool/layer_audit.py` CI 强制。
- 平台差异收敛到 `lib/core/platform/`（桌面标题栏 bitsdojo / window_manager），权限与系统能力走统一网关 `lib/core/capability/`（未授权/已授权/永久拒绝三态）。
- 50 个酷狗端点在 `core/net/endpoint_registry.dart` 声明式配置，改 API 不动调用方。
- 每次构建生成 `verification.json`（加盐摘要 + RSA-4096 签名），运行期校验产物完整性。

## 快速开始

### 下载现成产物

到 [Releases](https://github.com/yingo-server/TiernanMusic-Next/releases) 页面下载：

- **Android**：split-per-abi 三架构 APK（`arm64-v8a` / `armeabi-v7a` / `x86_64`）。最近的稳定版为 `v26.11.13.06`；后续版本当前均为 prerelease，可从最新 tag 下载尝鲜。
- **桌面（Windows / Linux AppImage）**：通过 `desktop-build.yml` workflow 手动触发构建并可选发布为 Release 资产。
- 每个发布附 `verification.json` 完整性校验文件。

### 从源码构建

需要本机 Flutter SDK（CI 使用 Flutter 3.50.0 stable）：

```bash
flutter pub get
dart run build_runner build --delete-conflicting_outputs
flutter build apk --release          # Android
flutter build windows --release      # Windows
flutter build linux --release        # Linux（CI 上进一步打包为 AppImage）
```

本地纯 Dart 检查（无需 Flutter SDK）：

```bash
dart run tool/smoke_check.dart    # 静态合规冒烟
dart run tool/md5_smoke.dart      # MD5 签名四向量
python3 tool/layer_audit.py       # 76 原则跨层审计
python3 tool/analyze_gate.py      # 类型真错误闸
bash tool/local_gate.sh           # 本地十道门禁，全绿输出 FINAL-OK
```

CI：推送到 main 或打 tag `v*` 触发 [ci.yml](.github/workflows/ci.yml)（analyze-test → build → release，changelog 取 `changed/<版本>.md`）；桌面构建由 [desktop-build.yml](.github/workflows/desktop-build.yml) workflow_dispatch 手动触发。

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/SEVEN_SIX_RULE.md](docs/SEVEN_SIX_RULE.md) | 76 原则（七层六桥）权威定义 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构规范：铁律 / 依赖例外 / 门禁 |
| [docs/KUGOU_API.md](docs/KUGOU_API.md) | 酷狗 API 逆向知识与三态回归锚点 |
| [docs/UI_REWRITE_PLAN.md](docs/UI_REWRITE_PLAN.md) | UI 重写与平台化总规划（M3 + GetWidget + 平台层/权限网关） |
| [docs/DESIGN_LANGUAGE.md](docs/DESIGN_LANGUAGE.md) | 森林翡翠设计语言：色彩 token 与明暗映射 |
| [docs/FOUR_RELEASE_ROADMAP.md](docs/FOUR_RELEASE_ROADMAP.md) | 四步版本路线图 |
| [docs/YKG_LINK_CRYPTO_DESIGN.md](docs/YKG_LINK_CRYPTO_DESIGN.md) | YKG 链接登录密码学设计 |
| [docs/ACCEPTANCE_CHECKLIST.md](docs/ACCEPTANCE_CHECKLIST.md) | 真机验收清单（42 条编号待执行项） |
| [docs/BOOT_FAILURE_DIAGNOSIS.md](docs/BOOT_FAILURE_DIAGNOSIS.md) | 真机启动失败与配色问题诊断（错误信息链断裂 / 像素证据 / 门禁加固） |

## 项目状态（截至 2026-11-19）

项目正按 [docs/FOUR_RELEASE_ROADMAP.md](docs/FOUR_RELEASE_ROADMAP.md) 四步推进：

1. ✅ **重写稳定**：破坏性 UI 重写（官方 M3 + GetWidget）+ 桌面标题栏挂载完成。
2. ✅ **全平台构建**：`desktop-build.yml`（Windows / Linux AppImage）已落地，Android APK 常规发布。
3. 🔄 **SOTA 文案与文档**：进行中（本 README 重写属此阶段）。
4. ⏳ **v1.0.0 正式版**：待真机验证通过后发布（prerelease=false）。

> ⚠️ **真机验证未通过（2026-11-19）**：v26.11.19.07 正式版在真机上启动失败
> （`boot rejected`）。根因是**失败信息链断裂**（失败路径不带原因 + boot log
> 只 print 不落盘），叠加存储根静默回落到相对根 `'.'`（Android CWD=`/`）。
> 已修：失败路径携带真因 + boot 日志落盘 + 步骤化诊断（错误页直接显示
> `step[xxx] failed: <原因>`）+ 相对根改显式失败 + 目录降级。
> 同时把配色从"整屏深绿"改回"中性灰底 + 翡翠强调"。
> 详见 [docs/BOOT_FAILURE_DIAGNOSIS.md](docs/BOOT_FAILURE_DIAGNOSIS.md)。

已知后续项（诚实清单）：

- **真机启动仍待复现验证**：修复已使失败原因在真机可见，但确切异常需装包验证。
- i18n 尚未全量接线：zh / zh_Hant / en 之外语言为 en 占位。
- 酷狗端点 20028（权限不足）语义已入回归锚点，相关端点的体验优化仍在进行。
- 桌面产物尚未出现在常规 Release 资产中，需手动触发 workflow。
- 动态取色链（封面取色 → 主题种子）当前**空转**：`_seedArgb` 被持久化但
  `AppRoot` 用静态 `TnPalette`，无消费者。属独立功能缺口。
- 真机验收清单（42 条）尚未全部执行完毕。

## 贡献与许可

- 版本号格式 `26.11.10.N`（日期.序号），每版一份 `changed/<版本>.md` changelog。
- 修改代码请先通过本地门禁（`bash tool/local_gate.sh` → FINAL-OK）。
- 许可证：Apache-2.0，见 [LICENSE](LICENSE)。
