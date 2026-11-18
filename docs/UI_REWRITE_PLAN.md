# UI 层全面重写 · 平台化改造总规划（v0.1）

> 状态：规划阶段（2026-11-19）
> 范围：Flutter 全平台（Windows / macOS / Linux / iOS / Android / Web）+ 桌面标题栏 + Material 3 + GetWidget
> 前提：稳定优先。一套内部设计语言（森林翡翠）+ 明暗双主题，不做多设计语言全局切换。

---

## 0.0 两个互补的 UI 模块（最高契约，不可违背）

本项目 UI 由**两个现成模块互补构成**，我们**只写色彩**，不写控件：

```
┌─────────────────────────────────────────────────────────────┐
│ 模块 A：官方 Material 3（flutter/material.dart）——主干       │
│   承载一切结构：Scaffold / AppBar / NavigationBar /         │
│   NavigationRail / Card / ListTile / Chip / Button /         │
│   TextField / Dialog / BottomSheet / Snackbar / …            │
│   我们只对官方控件做「主题 + 参数」配置，不改其内部实现。    │
├─────────────────────────────────────────────────────────────┤
│ 模块 B：GetWidget（get 包）——补充包                          │
│   只用其现成能力补足官方控件没有的部分：                     │
│   Obx / GetBuilder / GetView（响应式绑定）、                 │
│   GetSnackbar / GetDialog / GetBottomSheet（反馈与弹层）、    │
│   GetMaterialApp / GetCupertinoApp（根级）                   │
│   不自写任何 GetWidget 扩展控件，只用官方提供的。            │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │  我们唯一手写的东西
                    语义色彩 Token + 主题（ColorScheme/ThemeData）
```

**推论（铁律）**：
1. 任何页面 = 官方 M3 控件树 + GetWidget 现成能力；不出现自建 `StatelessWidget`/`StatefulWidget`。
2. 不出现 `CustomPainter` / `Canvas` / `drawRect` 等任何自绘路径（**零例外**，不设登记制）。
3. 不引入第三方 UI 组件库（除 `get` 本身）；不用 `Cupertino` 风格控件做视觉（仅 `bitsdojo_window` 属平台层，非 UI 控件）。
4. 我们写的代码仅限：`lib/surface/design/tokens*.dart`（色彩语义）、`lib/surface/theme/*`（主题装配）、页面内对官方控件的参数编排。



### 0.1 为什么要重写
现状 `lib/surface/` 20 文件 / 5457 行，存在三个结构性问题：
1. **自写控件成体系**：`SpCover / SpSongTile / SpSectionHeader / SpSkeleton / SpListSkeleton / SpStateView / SpPlayButton / SpRoundButton / SpMiniBar` 共 9 个自绘控件，与官方 Material 3 语义重复，导致 M3 合规只能停在 ~42/100，且每处样式要手工同步。
2. **平台差异无处安放**：仓库无原生平台目录，CI 每次 `flutter create` 临时生成；桌面端（窗口、标题栏、文件选择、剪贴板、媒体键、系统托盘）完全空白。
3. **权限/能力没有网关**：网络、存储、剪贴板、通知、文件系统访问散落在各处，桌面端与移动端权限模型完全不同（移动端运行时权限 vs 桌面端文件系统/网络自由），无法统一表达。

### 0.2 目标（可验收）
| # | 目标 | 验收方式 |
|---|---|---|
| G1 | **UI 层零手写控件**：只能用官方 Material 3 控件 + GetWidget 提供的控件；唯一允许的自定义是**色彩**（语义 token 与主题配置）。不得新增任何自绘 widget，不得自绘 Canvas/CustomPaint/Paint | 门禁 `ui_no_custom_widgets.py`：禁止 `CustomPainter`/`Canvas`/`drawX(`/自建 `StatelessWidget`+`StatefulWidget`（token/主题/纯组合除外），且必须有**零例外** |
| G2 | 组件颜色 100% 来自语义 token，无硬编码色值 | 门禁扫描 `lib/surface` 禁止 `Color(0x` 与裸色常量（token 定义处除外） |
| G3 | Light/Dark 每个 token 成对定义 | 门禁校验 token 表双侧齐全 |
| G4 | 平台差异收敛到独立「平台层」 | 新增 `lib/platform/`，跨层访问一律经桥；L7 不感知平台 |
| G5 | 权限/系统能力经统一网关 | 新增权限网关 `lib/core/capability/`，能力查询+请求统一入口 + 未授权/已授权/永久拒绝三态 |
| G6 | 桌面端可用（窗口、标题栏、快捷键、拖拽） | Linux AppImage / Windows / macOS 产物可在对应系统启动，标题栏可拖拽、按钮可用 |
| G7 | 对比度达标 | 正文 ≥4.5:1、大字/图标 ≥3:1、UI 边界 ≥3:1（脚本化校验 token 对） |
| G8 | 主题切换无闪烁、持久化生效 | 启动先读持久化再渲染首帧；切换 200–300ms 过渡 |

---

## 1. 76 原则下的新分层（平台层的落位）

现有 76 原则 = 7 层 6 桥：
```
L1 init / L2 bootloader / L3 kernel / L4 core / L5 logic / L6 session / L7 surface
```
**平台层**是新增的横向关注点，不能破坏 7×6 的依赖方向。落位方案：

```
L7 surface        ← UI：只画控件（官方 M3 + GetWidget），不含平台分支
   │  经 bridge_surface
L6 session        ← 能力状态：能力是否可用/是否已授权（平台无关的语义）
   │  经 bridge_core
L4 core/
   ├─ capability/ ← 权限网关（平台无关的接口 + 平台无关的语义模型）
   └─ platform/   ← 平台差异实现（Windows/Linux/macOS/Web/Android/iOS 各一份）
```

**铁律**：
- `lib/surface/**` **禁止**出现 `Platform.isWindows` / `Platform.isLinux` / `dart:io` / `defaultTargetPlatform` 判断平台；
  桌面/移动差异通过**能力查询**（如 `capabilities.desktopWindow`、`capabilities.customTitleBar`）表达，不问平台。
- `lib/platform/**` 只被 `lib/core/capability/**` 依赖，不得反向依赖 logic/session/surface。
- 平台实现用条件导入（`conditional_import`）+ stub，保证单一平台编译时无死代码报错。

---

## 2. 平台区别层（Platform Layer）

### 2.1 职责
把「同一件事在不同平台不同做法」的所有分叉收进一处：
| 关注点 | 移动端 | 桌面端 | Web |
|---|---|---|---|
| 应用外壳 | 单窗口 + 底栏 | 多窗口/单窗口 + 自定义标题栏 | 单窗口，无标题栏 |
| 导航形态 | 底部 NavigationBar | NavigationRail（侧栏）| 底部 NavigationBar |
| 返回 | 系统返回键/手势 | Alt+← / Esc | 浏览器历史 |
| 文件选择 | 系统选择器 | 原生文件对话框 | 上传 |
| 剪贴板 | 系统剪贴板 | 系统剪贴板 | 浏览器剪贴板 |
| 通知 | 需运行时权限 | 桌面通知 | Notification API |
| 存储 | 应用沙盒 + 媒体库 | 用户目录（用户可指定） | 浏览器存储 |
| 媒体键 | 锁屏/耳机 | 键盘快捷键 | 媒体会话 API |
| 窗口 | 无 | 尺寸/最小尺寸/最大化/全屏/主题跟随 | 标签页 |

### 2.2 结构（伪代码）
```
lib/platform/
  platform.dart            ← 统一入口 facade（对外唯一 API）
  platform_stub.dart       ← 不支持平台的降级实现
  platform_io.dart         ← dart:io 平台（Windows/Linux/macOS/Android/iOS）
  platform_web.dart        ← Web 实现
  capability/
    capabilities.dart      ← 能力集合（bool + 数值 + 字符串）
  window/
    window_service.dart    ← 窗口尺寸/最小化/最大化/全屏/事件流
    titlebar/
      titlebar.dart        ← 标题栏 widget（surface 层用？还是 platform 层？）
      titlebar_stub.dart   ← 移动/Web 无标题栏
  file_picker/
  notifications/
  clipboard/
  media_keys/
  storage_root/
```

### 2.3 标题栏归属决策（重要）
bitsdojo_window 需在 **platform 层**持有原生窗口句柄，而标题栏 widget 要在 **surface 层**渲染（走 M3 语义）。
方案：**platform 层只暴露「窗口句柄 + 操作方法」，标题栏 UI 由 surface 渲染**。
```
platform.window.nativeHandle   → bitsdojo_window 的 handle
platform.window.minimize()/maximize()/close()/isMaximized
surface：TitleBar(widget) 消费 handle → 用官方 IconButton 渲染按钮
```
这样标题栏颜色走 surface 的 `titlebar.*` token（独立于内容区 ColorScheme），符合设计语言规范第 1.5 条。

---

## 3. 权限网关（Capability & Permission Gateway，全平台）

### 3.1 为什么需要
- 移动端：运行时权限（Android 13+ 通知、存储、麦克风），需「请求 → 拒绝 → 永久拒绝 → 去设置」四态；
- 桌面端：无运行时权限，但有**文件系统作用域**（用户选择目录后才有权）与**网络**（不受限）；
- Web：浏览器权限模型（通知需授权、剪贴板需用户手势、文件系统需 handle 授权）。
若不设网关，这些分支会污染 logic/surface。

### 3.2 统一模型（伪代码）
```
enum CapStatus { granted, denied, permanentlyDenied, restricted, unsupported }

class Capability {
  final String id;              // 'notification' | 'fileRead' | 'clipboard' | 'network' | 'storage' ...
  final CapStatus status;
  final String? reason;
}

abstract class CapabilityGateway {
  Future<CapStatus> status(String id);
  Future<CapStatus> request(String id);      // 触发系统授权流程
  Future<bool> openSettings();               // 跳系统设置（移动端永久拒绝时）
  Stream<CapStatus> watch(String id);
}
```
### 3.3 平台实现
| capability | Android | iOS | Windows | Linux | Web |
|---|---|---|---|---|---|
| notification | POST_NOTIFICATIONS 运行时 | 请求授权 | 免授权 | 免授权（桌面通知） | Notification API |
| fileRead | SAF / 媒体库 | DocumentPicker | 原生对话框 | 原生对话框 | input[type=file] |
| storage | scoped 目录 | 沙盒 | 用户目录 | XDG 目录 | OPFS |
| clipboard | 系统剪贴板 | ✅ | ✅ | ✅ | 需用户手势 |
| network | ✅ | ✅ | ✅ | ✅ | ✅ |
| mediaKeys | 媒体会话 | ✅ | 全局快捷键 | 全局快捷键 | Media Session |

### 3.4 铁律
- `lib/logic/**` 与 `lib/surface/**` **禁止**直接调用平台 API（PathProvider/Clipboard/Notification 等），一律经 `bridge_core` 暴露的网关门面。
- 未授权时 UI 必须走「已授权/未授权/受限」三态视觉（`text.disabled` + 说明文案 + 「去设置」动作），不得静默失败。

---

## 4. 依赖变更

```yaml
dependencies:
  get: ^4.7.3                 # GetWidget（官方 M3 之外的补充包：状态/响应式绑定）
  bitsdojo_window: ^0.1.6     # 桌面自定义标题栏
  window_manager: ^0.4.3      # 窗口最小尺寸/最大化/全屏（与 bitsdojo 配合）
  file_selector: ^1.0.3       # 跨平台文件选择
  desktop_drop: ^0.6.0        # 桌面拖拽
  screen_retriever: ^0.2.0    # 多显示器
```
> 依赖是否可用性需在 CI 用 `flutter pub get` 验证；任何新依赖若引入编译问题，回退到官方等价 API（`file_selector`→`dart:io` 封装）。

---

## 5. 实施阶段（每阶段独立可发布、可回滚）

| 阶段 | 内容 | 产出 | 门禁 |
|---|---|---|---|
| **P0 规划** | 本文档 + DESIGN_LANGUAGE.md + UI_IA_PLAN.md（子代理产出） | 3 份规划文档 | 人工评审 |
| **P1 设计语言落地** | 新增 `lib/surface/design/tokens_v2.dart`（语义 token 明暗成对）+ 主题工厂 + token 门禁 | token 体系 + 2 个门禁 | `ui_tokens_gate` |
| **P2 平台层骨架** | `lib/platform/` 骨架 + capability 网关 + 条件导入 stub + 窗口服务 | 平台层可编译（6 平台） | `platform_gate` |
| **P3 UI 控件替换** | 9 个自写控件 → 官方 M3 等价物；12 页面逐步换皮 | 无自写控件 | `ui_no_custom_widgets` |
| **P4 桌面标题栏** | bitsdojo_window 接入 + TitleBar widget + 快捷键 | 桌面三平台可运行 | 人工 + 截图 |
| **P5 响应式与 IA** | 断点三档：底栏/NavigationRail、列数、边距 | IA 落地 | `ui_responsive_gate` |
| **P6 多平台构建** | CI 增 Linux/Windows/macOS 构建；Linux 出 AppImage（含全部依赖） | 6 平台产物 | 构建矩阵绿 |
| **P7 收口** | 全量 i18n 接线、对比度脚本、主题闪烁修 | 验收清单全绿 | 全部新门禁 |

---

## 6. 修改范围清单（预估）

| 路径 | 动作 | 影响 |
|---|---|---|
| `lib/surface/design/tokens.dart` | 重写为 v2 语义 token（保留旧名为过渡期） | 全 surface 引用 |
| `lib/surface/design/components.dart` | **删除** 9 个自写控件，改为官方控件组合 | 12 页面 |
| `lib/surface/design/mini_bar.dart` | 改官方 `Material`+`ListTile`/`IconButton` 组合 | shell |
| `lib/surface/pages/*.dart` | 逐页换皮 + 响应式 + GetWidget 绑定 | 12 页面 |
| `lib/surface/shell.dart` | 移动端 NavigationBar / 桌面 NavigationRail 分流 | 导航 |
| `lib/surface/app_root.dart` | 双主题（light/dark）+ 标题栏 + 无闪烁首帧 | 启动 |
| `lib/platform/**` | **新建** | 平台层 |
| `lib/core/capability/**` | **新建** | 权限网关 |
| `lib/bridges/bridge_core.dart` | 导出网关门面 | 桥 |
| `lib/logic/**` | 平台 API 改为经网关 | 局部 |
| `pubspec.yaml` | 加 6 个依赖 | 构建 |
| `.github/workflows/ci.yml` | 多平台构建矩阵 + Linux AppImage + 新门禁 | CI |
| `tool/*.py` | 新增 4 个门禁脚本 | 门禁 |
| `docs/**` | 规划/验收文档 | 文档 |

**不在范围**：L1–L5 的业务逻辑、酷狗 API 协议、YKG 加密、数据库 schema、播放内核（仅在需要平台能力时经网关调用）。

---

## 7. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| GetWidget 与 Riverpod 双状态源混乱 | 状态不一致 | GetWidget 只用于 **L7 视图层响应式**，业务状态仍归 L6/session；不新增跨层状态容器 |
| 自写控件删除后视觉回退 | UI 变丑 | 严格按 DESIGN_LANGUAGE 的 token 做等价配置；每阶段出截图对比 |
| 桌面端原生目录进仓库 | 仓库膨胀/CI 慢 | 只提交必要配置（不提交构建产物），Linux 用 AppImage 打包依赖 |
| bitsdojo_window 与 window_manager 冲突 | 窗口行为异常 | 二者职责分离：前者取句柄+置标题栏透明，后者管尺寸/最大化；窗口操作统一走 platform 层 |
| CI 时长激增 | 迭代变慢 | 构建矩阵并行；本地不阻塞（CI 只作验证） |
| 图标再被裁（tree-shake 历史问题） | tab 消失 | 已有门禁锁死 `--tree-shake-icons` |

---

## 8. 验收清单（最终）

- [ ] `lib/surface/**` 无自写控件（门禁）
- [ ] 组件颜色全部来自语义 token，无硬编码色值（门禁）
- [ ] 每个 token Light/Dark 成对（门禁）
- [ ] 正文对比度 ≥4.5:1、大字/图标 ≥3:1、UI 边界 ≥3:1（脚本）
- [ ] 状态色均配图标/文案，不只靠颜色
- [ ] 深色无纯黑、浅色无纯白
- [ ] 桌面标题栏与内容区分层，失焦降对比
- [ ] 焦点环在所有交互控件可见
- [ ] 主题切换无闪烁、持久化生效
- [ ] 禁用态可读
- [ ] 六平台构建产物齐；Linux AppImage 自带依赖，可在 Ubuntu 22.04 运行
- [ ] 权限三态（已授权/未授权/受限）有对应 UI
- [ ] 桌面快捷键可用（搜索/播放暂停/切歌/返回）
