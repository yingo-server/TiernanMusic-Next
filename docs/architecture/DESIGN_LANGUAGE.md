# 设计语言参考（Reference）

> 审阅：2026-11-19 · 事实源：`lib/surface/design/tokens_v2.dart`（森林翡翠语义色）、
> `lib/surface/theme/tn_theme.dart`、`lib/surface/design/desktop_titlebar.dart`。
> 本文只陈述事实；「为什么这样设计」见已归档的 `DESIGN_LANGUAGE.md`（概念一致，数值以 token 文件为准）。

## 架构

```
Primitive 原始色板 → Semantic 语义 token（TnPalette，Light/Dark 成对）→ 官方 ColorScheme/ThemeData
```

- 组件只用语义 token：`context.cs.*`（官方 ColorScheme 角色）与 `context.palette.*`（森林翡翠扩展别名），
  不引用裸色值；`Color(0x…)` 仅允许出现在 token 定义处。
- 每个语义 token **Light / Dark 成对**定义，由 `tool/ui_contrast_gate.py` 校验成对性与对比度。
- `TnPalette.toColorScheme()` 从 `ColorScheme.fromSeed(seedColor: primary)` 再 `copyWith` 角色；
  `toThemeData()` 装配 M3 官方组件主题（AppBar / NavigationBar / ListTile / Button / Card / Dialog 等）。
- `TnSystemColors` 是少数脱离 context 的系统层 token（SystemChrome 导航/状态栏锁暗 `#0B1F14`）。
- 桌面标题栏走独立 `titlebar.*` token，**不挂到 ColorScheme**。

## 语义 token 明暗对照（森林翡翠）

| token（TnPalette 字段） | Light | Dark |
|---|---|---|
| `bgCanvas` | `#F1F8F4` | `#0B1F14` |
| `bgSurface` | `#FFFFFF` | `#102A18` |
| `bgContainer` | `#D8F3DC` | `#17332A` |
| `bgContainerHigh` | `#B7E4C7` | `#1F4432` |
| `primary` | `#1B5E20` | `#A7F3D0` |
| `onPrimary` | `#FFFFFF` | `#0B1F14` |
| `secondary` | `#52B788` | `#52B788` |
| `onSecondary` | `#0B1F14` | `#0B1F14` |
| `textPrimary` | `#102A18` | `#E8F5EC` |
| `textSecondary` | `#4A6B55` | `#A8C5B2` |
| `textDisabled` | `#9BB5A3` | `#5C7A66` |
| `outline` | `#6B8F76` | `#5C7A66` |
| `focus` | `#2F5D50` | `#A7F3D0` |
| `success` | `#2F7D4A` | `#7DD3A0` |
| `warning` | `#9A6700` | `#F5C542` |
| `error` | `#B3261E` | `#F2B8B5` |
| `onError` | `#FFFFFF` | `#601410` |
| `info` | `#0B6BCB` | `#8EC5FF` |

浅色不用纯白（画布 `#F1F8F4`），深色不用纯黑（画布 `#0B1F14`）。状态色不能只靠颜色表达，须配图标或文案。

## 桌面标题栏 token（独立于 ColorScheme）

| token | Light | Dark |
|---|---|---|
| `titlebarBg` | `#1B5E20` | `#0B1F14` |
| `titlebarFg` | `#E8F5EC` | `#A7F3D0` |
| `titlebarButtonHover` | `#52B788` | `#17332A` |
| `titlebarCloseHover` | `#F2B8B5` | `#F2B8B5` |
| `titlebarInactive` | `#A8C5B2` | `#6B8F76` |

`buildDesktopTitleBar()`（`lib/surface/design/desktop_titlebar.dart`）仅当
`platformCapabilities.supportsCustomTitleBar` 为真时返回控件（Windows/Linux），否则返回 null 回退默认布局。
控件全部用 bitsdojo 官方 `WindowBorder / WindowTitleBarBox / MinimizeWindowButton /
MaximizeWindowButton / CloseWindowButton` + M3 `Text / GestureDetector`，不手写按钮；
失焦用 `titlebarInactive` 降对比。

## 官方 M3 + GetWidget：零手写控件

- 控件来源只有官方 `package:flutter/material.dart` 与 GetWidget（`get` 包的 `Obx / GetBuilder /
  GetView / GetSnackbar / GetDialog / GetBottomSheet / GetMaterialApp`）。
- 禁止自建 `StatelessWidget`/`StatefulWidget` 可复用控件、`CustomPainter`/`Canvas`/`drawX`、自设间距常量；
  原 9 个 `Sp*` 自绘控件已删除。门禁 `ui_no_custom_widgets.py` 强制。
- 主题档位 0=跟随系统 / 1=浅色 / 2=深色 / 3=纯黑，经 `ThemeController.instance.setMode()` 持久化；
  切换 200–300ms 过渡，启动先读持久化再渲染首帧（`app_root.dart`）。

## 品牌变体（仅规划，未实现）

鼠尾草薄荷 / 墨绿青柠 / 蓝绿翡翠为 Primitive 色板替换变体，设计上不改变语义 token 结构；
当前代码只有森林翡翠一套，未实现运行时切换。
