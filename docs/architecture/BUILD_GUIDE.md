# 构建指南（How-to）

> 审阅：2026-11-19 · 适用读者：需要在本机做静态检查、或在 CI 出各平台产物的开发者。
> 前置知识（76 原则、平台层落位）见 [架构总览](ARCHITECTURE_OVERVIEW.md)；本文只讲「怎么做」。

## 前置条件（诚实说明）

- **构建与测试全部在 CI 完成**：本开发环境是 arm64、无 Flutter SDK，仅有独立 Dart SDK（`/opt/dart/bin/dart`）与 Python3。
- 本地只能跑纯 Dart / Python 静态检查；`flutter analyze` / `flutter test` / 各平台构建需已安装 Flutter SDK 的机器或 CI。
- CI workflow：`.github/workflows/ci.yml`（push main / tag `v*` / workflow_dispatch）与
  `.github/workflows/desktop-build.yml`（仅 workflow_dispatch）。

## 本地门禁（怎么跑）

在仓库根目录依次执行（全绿）：

```bash
python3 tool/layer_audit.py                       # 跨层 import / 影子桥 / 桥 try-catch / 行数；PASS strict seven-six
/opt/dart/bin/dart format --output=none lib tool  # 语法闸（无 Flutter SDK 也能抓编译级语法错）
/opt/dart/bin/dart run tool/smoke_check.dart      # 括号配平 / 禁 import / 桥唯一性；无 VIOLATION
python3 tool/analyze_gate.py                      # 项目类型真错误闸
/opt/dart/bin/dart run tool/md5_smoke.dart        # MD5 签名四向量
/opt/dart/bin/dart run tool/field_truth_test.dart # 字段事实锚点；FIELD-TRUTH-OK
/opt/dart/bin/dart run tool/feature_reachability_test.dart # FEATURE-REACHABILITY-OK
/opt/dart/bin/dart run tool/boot_contract_test.dart
/opt/dart/bin/dart run tool/play_contract_test.dart
/opt/dart/bin/dart run tool/session_contract_test.dart
/opt/dart/bin/dart run tool/resolve_contract_test.dart
/opt/dart/bin/dart run tool/download_contract_test.dart
```

一条命令：`bash tool/local_gate.sh` —— 上述 12 道全过输出 `FINAL-OK`，任一失败输出 `FAIL-*` 并退出 1。

UI 三门禁（重写后新增，独立于 local_gate）：

```bash
python3 tool/ui_no_custom_widgets.py   # 零手写控件 / 零自绘（当前可能仍有范围外历史违规）
python3 tool/ui_contrast_gate.py       # 语义 token 明暗成对 + 对比度底线
python3 tool/bottom_bar_gate.py        # 底栏系统层 + Flutter 层深色双锁
```

有 Flutter SDK 时再跑 `flutter pub get && dart run build_runner build --delete-conflicting-outputs &&
flutter analyze && flutter test`。依赖事实源是 `pubspec.yaml`；版本当前 `26.11.10+1`。

## Android 产物（CI）

1. 推 main 或打 `v*` tag 触发 `ci.yml`，或手动 workflow_dispatch（可选 `release` / `debug`）。
2. 流水线：`analyze-test` → `build`（`flutter build apk --release --split-per-abi -t lib/init/main.dart`，shrunk）→ `release`。
3. `debug=true` 允许完整性 bypass；正常构建在 CI 生成 `verification.json`（加盐摘要 + RSA-4096 签名），运行期只校验构建产物。
4. release body 取 `changed/<版本>.md`（缺失回退最近 20 条 commit）。
5. 若 native 插件 AAR 的 compileSdk 冲突，CI 已统一抬到 35；桌面拖拽/多屏用官方 DragTarget + MediaQuery，
   不引 `desktop_drop` / `screen_retriever`。

## 桌面产物（CI · Windows / Linux + AppImage）

触发 `.github/workflows/desktop-build.yml` 的 workflow_dispatch（可选 `version` 与 `release=true`）：

- **Windows**：`windows-latest`，`flutter create --platforms=windows` 生成脚手架 →
  patch `windows/runner/main.cpp`（注释锚 `BITSDOJO_TITLEBAR_PATCH`）→ `flutter build windows --release` → zip artifact。
- **Linux**：`ubuntu-22.04`（glibc 2.35），安装 GTK/GStreamer 等依赖 + 下载 `appimagetool` →
  `flutter create --platforms=linux` → patch `linux/runner/my_application.cc`（`gtk_window_set_decorated(FALSE)`）→
  `flutter build linux --release` → 打 AppImage（`--appimage-extract-and-run`，FUSE-free，含全部依赖）。
- 产物：`desktop-windows` / `desktop-linux-appimage` artifacts；`release=true` 时由 `publish` job 发布为 prerelease
  （默认 tag `v0.1.1-beta`）。
- bitsdojo 生效依赖每次 `flutter create` 后对原生 runner 的 patch；不可跳过。
- 仓库不提交原生目录、不提交构建产物。

## 四步版本路线（当前计划，未全部完成）

| 版本 | 目标 | 证据状态 |
|---|---|---|
| `v0.1.0-alpha` | 现有重写 CI 全绿 + 桌面标题栏挂载 | 标题栏已挂载（commit `0d8790a` / `f6b02bc`）；本次无 Flutter SDK，CI 全绿未在本文复核 |
| `v0.1.1-beta` | 全平台构建（Windows/Linux AppImage） | `desktop-build.yml` 已落盘；产物需 workflow 实跑验证 |
| `v0.2.0-rc` | SOTA 文案 + 技术文档（四个 agent） | 本轮 sota-docs-workflow 审计属于此步；另三个 agent 产出不在本文范围 |
| `v1.0.0` | 正式版 stable（非 prerelease） | 未发布 |

发布渠道：仅 GitHub Release（internal tools 定位，不上架 Google Play / Apple App Store）。
版本命名：历史版本 `YY.MM.DD.NN`（如 `26.11.10.1`）；四步路线使用 SemVer 语义的 `v0.1.x` / `v1.0.0`，
两套命名并存，以当步 tag 为准（见已归档 `FOUR_RELEASE_ROADMAP.md`，本文按计划原样保留）。

## 失败怎么办（故障排查）

- `layer_audit` 报 VIOLATION：检查是否新增了跨层非桥 import 或影子桥目录；参照 [层与桥参考](LAYERS_AND_BRIDGES.md)。
- 本地 `flutter analyze` 缺失符号：本地无 Flutter SDK 时以 `analyze_gate.py` 为准；完整检查交给 CI。
- `ui_no_custom_widgets.py` FAIL：若违规在本次改动范围外的历史文件（`design/components.dart` / `mini_bar.dart` /
  `app_root.dart` 等），登记为后续项，不要假装全绿。
- AppImage 校验缺 icon：`desktop-build.yml` 已有最小 PNG 占位回退；缺资源时用仓库 `assets/` 下的图标。
