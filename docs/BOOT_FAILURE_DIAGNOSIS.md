# 真机启动失败与配色问题 · 诊断报告

日期：2026-11-19
触发：用户真机截图（`/var/minis/attachments/uploads/photo-1795096611956.jpg`）显示
`TiernanMusicNext 无法启动 / 启动失败: boot rejected / core assembly failed (see boot log)`。

---

## 0. 结论速览

| 问题 | 真实原因 | 状态 |
|---|---|---|
| 启动失败 | **错误信息链断裂**：失败路径不带原因 + boot log 只 print 不落盘 → 真机无从查证；同时 `rootDir` 静默回落到相对根 `'.'`，Android 上 CWD=`/` → `createSync` 抛 `PathAccessException` | 已修（诊断能力 + 根因修复 + 降级） |
| 颜色不对 | **不是 bug，是配色执行问题**：UI 重写把整屏底色铺成深绿系，卡片与背景同色相 → 无层次。像素筛查确认视觉模型报告的"品红图标"为 0 命中（误判） | 已修（回中性灰底，翡翠只做强调） |
| 底栏消失（历史） | `--tree-shake-icons` 裁掉 `iconFor()` 动态映射的导航图标 | 已修（见 `docs/ui_diagnosis.md`） |

---

## 1. 启动失败：为什么"CI 全绿但真机起不来"

### 1.1 结构性问题：失败信息链断裂（三处叠加）

```
_assembleCore 抛异常
  → BootResult(rejected: true)        ← 不带任何 error/detail
  → bridge_boot 造固定文案
      'boot rejected' / 'core assembly failed (see boot log)'
  → boot log 只 print()，release 真机 stdout 不可见
  → 用户/开发者/CI 三方都拿不到任何真实原因
```

**"see boot log" 是一张空头支票** —— 那个 log 从来不落盘。

修复：
- `BootResult` 增加 `error` / `detail` 字段，失败路径携带真实异常与堆栈
- `bridge_boot` 透传真实原因（保留 fallback 文案兜底）
- `kernel.Log` 增加可选落盘 `sink` + `recent` 缓冲（纯 Dart，不 import dart:io）
- `init` 层注入 sink → 日志写 `<storage>/logs/boot.log`（启动即截断）
- 错误页显示真实原因 + 日志尾部 40 行

### 1.2 具体根因候选：相对根回落

`main.dart` 旧行为：

```dart
String? rootDir;
try { rootDir = (await getApplicationSupportDirectory()).path; }
catch (e, st) { debugPrint('main: path_provider failed, fallback relative root: ...'); }
// → rootDir 保持 null
```

`bootloader._assembleCore` 旧行为：`core.StoragePaths.init(rootDir ?? '.')`

Android 进程 CWD 是 `/`，相对根解析为 `/downloads`、`/cache`、`/db` →
`paths.dart` 的 `_ensureDir` → `createSync(recursive: true)` → **PathAccessException**
→ boot rejected。

代码注释写着"仅 debug 可跑通"，但 **release 真机照样走这条路**。

> 该问题在 `docs/deep_audit/bA1_c2.md:355` 已被指出并建议"生产构建禁用相对根"，
> 但**从未落地**。

修复：
- `main` 拿不到存储根 → 走可见错误页并显示真实原因，不再静默回落
- `bootloader._assembleCore` 缺 `rootDir` 时抛 `StateError`（带明确说明）
- `paths._ensureDir` 创建失败时**降级**到 `Directory.systemTemp` 下的可用目录，
  不再 rethrow 拖垮整个应用

### 1.3 诊断能力：步骤化定位

`_assembleCore` 的每个装配步骤包一层 `_step()`，失败时抛
`step[storage-paths|db-dir|client|settings|auth] failed: <原因>` ——
真机错误页直接显示第几步失败。

---

## 2. 配色问题：像素证据

### 2.1 采样方法

`PIL` 直读原图（3456×4608），降采样后统计主色 + 按坐标定点采样 +
相机色偏校正（用两个已知源色做线性拟合：背景 token `(11,31,20)` → 实测 `(11,76,28)`；
白字 token `(232,245,236)` → 实测 `(254,255,250)`，得出 G 通道被显著抬升）。

### 2.2 关键结论

| 观测 | 结论 |
|---|---|
| App 内容区主色 100% 为深绿系（`#1C4C25` / `#084A14` / `#14591F`） | 底色被铺成深绿 |
| 中央圆形错误图标呈**紫色系**（`RGB(232,191,255)`≈`#E8BFFF`） | **是 Flutter 默认 M3 深色 primary `#D0BCFF`**，不是任何 `TnPalette` token |
| 品红像素分布 | 全分辨率扫描命中 2,609 个，其中 **2,367（91%）集中在 y=2200-2500** 的图标区（空心圆环+感叹号），其余为相机噪点 |
| AppBar 与画布像素差 | 无分层（符合 `AppBarTheme.backgroundColor = bgCanvas, elevation 0`） |

### 2.2b 紫色图标的根因：主题分裂（已修）

错误页旧代码在**自身 `MaterialApp` 生效之前**调用 `Theme.of(context)`：

```dart
return MaterialApp(
  theme: spErrorThemeData(),          // 深绿主题在这里才挂上
  home: Scaffold(
    Icon(Icons.error_outline,
         color: Theme.of(context).colorScheme.primary),   // ← 上层 context
```

`runApp(_BootErrorApp(...))` 时它没有 MaterialApp 祖先，`Theme.of(context)` 返回
`ThemeData.fallback()` → Flutter SDK 默认 M3 紫板（`#D0BCFF` 深 / `#6750A4` 浅）。
于是同时产生三个现象：

- 图标 → 外层默认主题的紫 `primary`（实测 `#E8BFFF` ✓）
- 标题 `titleLarge` / `labelSmall` → 外层默认主题的深色 `onSurface`（深绿底上几乎不可读）
- 正文 / AppBar → `MaterialApp` 内的深绿 `spErrorThemeData`（实测近白 ✓）

**修复**：先 `final theme = spErrorThemeData()` 再传给 `MaterialApp`，
图标改用 `scheme.error`；并加门禁禁止在 MaterialApp 之外取 `Theme.of(context)`。

> 排查方法论教训：本项目第一次颜色扫描时把图缩到 120×160，
> **降采样把图标细笔画平均掉了**，导致"品红 0 命中"的假阴性，
> 误判为视觉模型幻觉。**颜色结论必须全分辨率扫描**（或至少不降采样到
> 笔画宽度以下）。

### 2.3 真实问题：配色执行，不是配色来源

对比"真机可启动"的 `2bee0eb`：

| | 旧版（你见过、可用） | 上一版 UI 重写 | 本次修订 |
|---|---|---|---|
| 画布 | 中性灰 `#0E0F12` | **深绿 `#0B1F14`** | 中性灰 `#0E0F12` |
| 卡片 | `#1C1D21` | `#17332A` | `#181A1F` |
| 容器 | — | `#1F4432` | `#2B3038` |
| 高强调 | — | — | `#3A4049` |
| 强调色 | 亮绿 `#1DB954` | 薄荷 `#A7F3D0` | `#1DB954`（暗）/ `#12833C`（亮） |

底色回到中性灰，翡翠绿只保留在强调位。对比度实算：

- 暗色 `#1DB954` on `#0E0F12` = **7.41:1** ✓
- 亮色 `#12833C` on `#F7F8FA` = **4.56:1** ✓
  （亮翡翠 `#1DB954` 在白底仅 2.43:1，不可作正文色）

### 2.4 关键：真正的机制是**分层对比度不足**，不是绿调

量化后推翻了"绿调是主因"的初判：

| 版本 | canvas↔surface | canvas↔container |
|---|---|---|
| 上一版（深绿） | 1.12 | 1.26 |
| 改成纯中性灰后 | 1.05 | 1.14 |

改成中性灰反而**更平** —— 界面"糊成一片"是**明度差太小**，与色相无关。

因此本次把三档分层**拉开**（明暗两套，全部实算过 WCAG AA）：

| | canvas | surface | container | containerHigh |
|---|---|---|---|---|
| Dark | `#0E0F12` | `#181A1F` | `#2B3038` | `#3A4049` |
| Light | `#F7F8FA` | `#FFFFFF` | `#E4E7EB` | `#C2C8D0` |

浅色模式遵循 M3 语义：`surface`（白卡片）浮于画布之上，
`container` / `containerHigh`（凹陷底 / 选中底）比卡片**更暗**（不倒挂）。

### 2.5 outline / divider 分档

中性灰做分割线天然达不到 3:1。处理：
- `color.outline` = **可见控件边框**（3:1，翡翠灰 `#7F9186` / `#5A6B60`）
- `color.divider` = **纯装饰分割线**（低对比 `#DCDFE4` / `#2E3137`）
- `dividerColor` / `outlineVariant` 改指 `divider`

---

## 3. 门禁加固（此前是假门禁）

审计发现 `tool/ui_contrast_gate.py` 只读文档、不读代码：

| 漏洞 | 加固 |
|---|---|
| 代码改了文档没改 → 门禁永远 PASS | 从 `tokens_v2.dart` 解析实际色值，逐字段与文档比对，漂移即 FAIL |
| 门禁不覆盖 `lib/init/main.dart` 错误页 | 新增错误页检查：必须 `final theme = spErrorThemeData()`，不得在 MaterialApp 之外用 `Theme.of(context)` |
| 无主题上下文检查 | 已并入上一条（`Theme.of(context)` 在 MaterialApp 生效前取值 → 取到外层默认主题 → 配色割裂） |
| **不检查分层是否被压平** | 新增：`container/canvas ≥1.15`、`containerHigh/canvas ≥1.55` + 明度序检查（暗色 canvas≤surface≤container≤high；浅色 surface>canvas 且 container/high 更暗） |

**反向测试**（全部命中后已恢复）：
1. 改代码不改文档 → FAIL「代码值与文档不一致」
2. 错误页改回 `Theme.of(context)` → FAIL「配色割裂」
3. 暗色层次压平（代码+文档同步改） → FAIL 3 条（分层可辨 + 明度序倒挂）
4. 浅色层次配反（container 比卡片更亮） → FAIL

---

## 4. 教训

1. **"CI 全绿"不等于"真机可用"** —— CI 从不运行产物，运行期失败（目录不可写、
   插件缺失、R8 破坏）永远照不到。至少要有一条"启动失败时错误页可见真因"的通路。
2. **失败路径必须携带原因** —— 固定文案 + "see boot log"（不存在的 log）会让
   定位成本从分钟级变成跨天级。
3. **视觉模型对低饱和/受色偏影响的图像不可靠** —— 但**更不可靠的是我自己
   的降采样扫描**：把图缩到 120×160 后品红"0 命中"，实为假阴性。
   **颜色结论必须全分辨率扫描**；缩采样不得细于笔画宽度。
4. **"界面糊成一片"的机制是分层对比度，不是色相** —— 改成中性灰后
   分层对比反而从 1.12 降到 1.05。量化（canvas↔surface↔container）
   才能定位，不能凭观感归因。
5. **"以前能用"是最强的定位线索** —— 与 `2bee0eb`（真机可启动）做全量 diff，
   一眼锁定底色从灰变绿。
6. **门禁要反向测试** —— 改了门禁逻辑后，故意制造违规验证它真会 FAIL，
   否则只是"看起来更严"的假门禁。
7. **子代理审计期间读到的是并发修改中的工作区** —— 其"HEAD 已修复"类结论
   可能读到了中间状态，须自行复核后再采信。

---

## 5. 遗留与诚实边界

- **boot 失败的确切异常仍未在真机复现验证**（本次修复让它下次必现真因 + 步骤名）。
  若下次仍失败，错误页会直接给出 `step[xxx] failed: <原因>`，据此可精确定位。
- `Isar 3.1.0 + R8 full-mode` 的 JNI 绑定未实测；若 DB 打开失败，错误页会显示
  `装配失败：db open failed: ...`（异步路径，与 boot rejected 文案不同，可区分）。
- 动态取色链（封面取色 → 主题种子）仍是**空转**：`_seedArgb` 被持久化但无人消费，
  `AppRoot` 用静态 `TnPalette`。属功能未接，非配色 bug。
- i18n 全量接线（177 串）、20028 端点实测、macOS/iOS/Web CI 产物仍未做。
