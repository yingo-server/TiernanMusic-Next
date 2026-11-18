# 内部设计语言 · 色彩规范（森林翡翠）

> 版本：v0.1 · 2026-11-19
> 范围：Flutter 全平台（Windows/macOS/Linux/iOS/Android/Web）+ 桌面标题栏
> 前提：稳定优先。**一套内部设计语言 + 明暗双主题**，不做多设计语言全局切换。
> 默认品牌：**森林翡翠**（鼠尾草薄荷/墨绿青柠/蓝绿翡翠仅为 Primitive 替换变体，不改语义结构）

---

## 1. 设计原则

1. **语义 Token 优先**：组件不直接引用色值，只引用 `color.*` 语义 Token。
2. **明暗成对定义**：每个语义 Token 必须同时给出 Light/Dark 值，不允许单侧。
3. **绿色是主色，不是万能色**：成功/警告/错误/信息使用独立状态色，且**不能只靠颜色表达**，须配图标或文案。
4. **浅色不纯白，深色不纯黑**：浅色画布 `#F1F8F4`，深色画布 `#0B1F14`，降低长时间使用疲劳。
5. **标题栏与内容区分层**：桌面标题栏用独立 Token，不混入内容区 Surface。
6. **对比度底线**：正文 ≥ 4.5:1，大字/图标 ≥ 3:1，UI 边界 ≥ 3:1。

---

## 2. 色彩架构

```
Primitive 原始色板 → Semantic 语义 Token → Component 组件映射
```

### 2.1 Primitive 原始色板

| Token | 色值 | 用途 |
|---|---|---|
| green-900 | `#0B1F14` | 深色画布、深色文字 |
| green-800 | `#102A18` | 深色 Surface、正文文字 |
| green-700 | `#1B5E20` | 浅色主色、浅色标题栏 |
| green-600 | `#2F5D50` | 备用深绿、次级标题栏 |
| green-500 | `#52B788` | 强调色、次级按钮 |
| green-300 | `#B7E4C7` | 浅色高容器、选中底 |
| green-200 | `#D8F3DC` | 浅色容器、卡片 |
| green-100 | `#E8F5EC` | 浅色标题栏文字、浅底 |
| green-50 | `#F1F8F4` | 浅色画布 |
| neutral-0 | `#FFFFFF` | 浅色 Surface |
| neutral-900 | `#0B1F14` | 深色文字/画布 |

---

## 3. 语义 Token 与明暗映射

### 3.1 基础语义

| 语义 Token | Light | Dark | 说明 |
|---|---|---|---|
| `color.bg.canvas` | `#F1F8F4` | `#0B1F14` | 页面最底层背景 |
| `color.bg.surface` | `#FFFFFF` | `#102A18` | 卡片、面板、弹窗 |
| `color.bg.container` | `#D8F3DC` | `#17332A` | 容器、分组底 |
| `color.bg.containerHigh` | `#B7E4C7` | `#1F4432` | 高强调容器、选中底 |
| `color.primary` | `#1B5E20` | `#A7F3D0` | 主按钮、主强调 |
| `color.onPrimary` | `#FFFFFF` | `#0B1F14` | 主色上的文字/图标 |
| `color.secondary` | `#52B788` | `#52B788` | 次强调、图表 |
| `color.onSecondary` | `#0B1F14` | `#0B1F14` | 次强调上的文字 |
| `color.text.primary` | `#102A18` | `#E8F5EC` | 正文主文字 |
| `color.text.secondary` | `#4A6B55` | `#A8C5B2` | 辅助文字 |
| `color.text.disabled` | `#9BB5A3` | `#5C7A66` | 禁用文字 |
| `color.outline` | `#6B8F76` | `#5C7A66` | 边框、分割线 |
| `color.focus` | `#2F5D50` | `#A7F3D0` | 焦点环 |

### 3.2 状态色

| 语义 Token | Light | Dark | 说明 |
|---|---|---|---|
| `color.success` | `#2F7D4A` | `#7DD3A0` | 成功；与主色接近，**必须配图标** |
| `color.warning` | `#9A6700` | `#F5C542` | 警告 |
| `color.error` | `#B3261E` | `#F2B8B5` | 错误、危险操作 |
| `color.info` | `#0B6BCB` | `#8EC5FF` | 信息提示 |
| `color.onError` | `#FFFFFF` | `#601410` | 错误色上的文字 |

### 3.3 桌面标题栏专用 Token

| 语义 Token | Light | Dark | 说明 |
|---|---|---|---|
| `titlebar.bg` | `#1B5E20` | `#0B1F14` | 标题栏背景 |
| `titlebar.fg` | `#E8F5EC` | `#A7F3D0` | 标题文字/图标 |
| `titlebar.button.hover` | `#52B788` | `#17332A` | 窗口按钮悬停 |
| `titlebar.close.hover` | `#F2B8B5` | `#F2B8B5` | 关闭按钮悬停 |
| `titlebar.inactive` | `#A8C5B2` | `#6B8F76` | 非活动窗口降对比 |

> 标题栏不参与 Material ColorScheme，独立 Token 管理，避免内容区主题切换影响窗口框架。
> 悬停/失活态取色以**对比度门禁实测**为准（浅色标题栏底为深绿，悬停色须提亮方可见）。

---

## 4. 组件映射规则

| 组件 | Light | Dark |
|---|---|---|
| 主按钮 | `primary` 底 + `onPrimary` 字 | 同语义 |
| 次按钮 | `container` 底 + `primary` 字 | 同语义 |
| 输入框 | `surface` 底 + `outline` 边框 | 同语义 |
| 输入框聚焦 | `focus` 边框 2px | 同语义 |
| 卡片 | `surface` 底 + `outline` 10% 边框 | 同语义 |
| 选中项 | `containerHigh` 底 + `primary` 字 | 同语义 |
| 禁用态 | `text.disabled` + 降低不透明度 | 同语义 |
| 表格斑马纹 | `canvas` / `surface` 交替 | 同语义 |
| 弹窗遮罩 | `#0B1F14` 40% | `#000000` 60% |

> GetWidget 组件若未读取 ColorScheme，通过全局 ThemeData 与包装主题入口注入语义 Token，**不逐控件写死颜色**。

---

## 5. 主题切换策略

1. 支持 **跟随系统 / 浅色 / 深色** 三档，用户选择持久化。
2. 切换时使用 **200–300ms** 颜色过渡，避免闪白/闪黑。
3. 启动时**先读取持久化主题再渲染首帧**，防止主题闪烁。
4. 深色不用纯黑，浅色不用纯白。
5. 状态色在深色模式**必须提亮**，不得直接复用浅色值。

---

## 6. Flutter 落地映射

```dart
final lightScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF1B5E20),
  brightness: Brightness.light,
).copyWith(
  surface: const Color(0xFFF1F8F4),
  surfaceContainer: const Color(0xFFD8F3DC),
  surfaceContainerHigh: const Color(0xFFB7E4C7),
  onSurface: const Color(0xFF102A18),
  primary: const Color(0xFF1B5E20),
  onPrimary: const Color(0xFFFFFFFF),
  outline: const Color(0xFF6B8F76),
  error: const Color(0xFFB3261E),
);
```
深色主题同理：`surface` → `#0B1F14`，`primary` → `#A7F3D0`，`onPrimary` → `#0B1F14`。
标题栏颜色从独立 `titlebar.*` Token 读取，**不挂到 ColorScheme**。

---

## 7. 对比度实测（脚本化，门禁校验）

正文（`text.primary` on `bg.canvas`）、次要文字（`text.secondary` on `bg.surface`）、
图标/大字（`primary` on `bg.canvas`）、边界（`outline` on `bg.surface`）——
均需满足 §1.6 底线，由 `tool/ui_contrast_gate.py` 自动校验，**不达标即 CI 红**。

---

## 8. 验收清单

- [ ] 所有组件颜色均来自语义 Token，无硬编码色值
- [ ] Light/Dark 每个 Token 均成对定义
- [ ] 正文对比度 ≥ 4.5:1，大字/图标 ≥ 3:1
- [ ] 成功/警告/错误/信息不只靠颜色区分
- [ ] 深色模式无纯黑，浅色模式无纯白
- [ ] 桌面标题栏与内容区边界清晰，非活动窗口有降对比
- [ ] 焦点环在所有交互控件上可见
- [ ] 主题切换无闪烁，持久化生效
- [ ] 禁用态仍可读，不依赖低对比「消失」

---

## 9. 后续扩展

森林翡翠为默认。鼠尾草薄荷、墨绿青柠、蓝绿翡翠作为品牌变体，
**仅通过替换 Primitive 色板实现**，不改变语义 Token 结构。
