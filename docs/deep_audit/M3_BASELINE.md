# M3 硬编码基线采样（主会话，2026-11-16 A1 批运行期间采）

> 供 A7 批（surface + 文案）直接使用，避免重复采样。方法：`rg` 计数，样本为 `lib/surface/` 全 18 文件。

## 1. 量化基线

| 项 | 命中数 | 说明 |
|---|---|---|
| `Color(0x…)` 硬编码 | **20** 处 | 全部集中在 `lib/surface/design/tokens.dart`（`Sp` 类）；其余页面 0 处 |
| `Colors.xxx` 直接用 | 少量 | 同上，仅在 `tokens.dart` 的浅色变体 |
| `BorderRadius.circular(<裸数字>)` | **0** | 圆角已走 token（`Sp.r*` / gap），此项合规 |
| `fontSize: <裸数字>` | **0** | 字号已走 token，此项合规 |
| `BoxShadow` / `elevation` | 2 处 | 需核是否符合「MD3 用 tonal elevation 而非阴影」 |

## 2. 关键结构问题（tokens.dart 抽样）

`lib/surface/design/tokens.dart`（195 行）现状是一个**自定义静态类 `Sp`**：

```dart
class Sp {
  static const Color bg = Color(0xFF0E0F12);
  static const Color bgElevated = Color(0xFF141519);
  static const Color card = Color(0xFF1C1D21);
  static const Color cardHigh = Color(0xFF25272C);
  static const Color divider = Color(0xFF2E3137);
  static const Color text = Color(0xFFEDEFF2);
  static const Color textSub = Color(0xFFA9AFB8);
  static const Color textFaint = Color(0xFF6C737D);
  static const Color green = Color(0xFF1DB954);   // ← Spotify 绿，非 MD3 tonal primary
  static const Color greenDim = Color(0xFF14833C);
  static const Color red = Color(0xFFE05B5B);
  static const Color orange = Color(0xFFF2A25C);
  static const double gapXS = 4; gapS = 8; gapM = 12; ...
```

### 与 MD3 规范的偏差（对照 material-3 skill）

1. **无 `ColorScheme` 语义角色**：MD3 要求用 `primary / on-primary / primary-container / surface-container-* / outline-variant / error …` 这类**成对角色**。现在是自定义 `bg/card/text/green` 命名 → 无法承载动态取色（`core/algorithms/color_extract.dart` 已存在）也**无法启用 contrast level 调整**。
2. **primary 硬编码为非 tonal 值**：`#1DB954` 是饱和品牌绿，不是 `ColorScheme.fromSeed` 派生的 tonal palette；`primary-container/on-primary-container` 这对角色**完全缺失**。
3. **无 tonal surface 阶梯**：MD3 要求 `surface-container-lowest / low / / high / highest` 五级表达层级深度；现在只有 `bg / bgElevated / card / cardHigh` 四级自定义名，且**elevation 用颜色阶梯而非 Material 的 elevation level 语义**。
4. **`outline` vs `outline-variant` 混用风险**：MD3 明确规定分隔线用 `outline-variant`、`outline` 只用于输入框边框等重要边界；现有 `divider` 单一令牌无法区分两者。
5. **无 `Typography` 类型刻度**：虽字号走 token，但未见 Display/Headline/Title/Body/Label 五档角色映射（skill 要求正确角色而非裸字号）。
6. **无 `Shapes` 刻度**：MD3 形状刻度 none/4/8/12/16/28/32/full，现为自定义 `Sp.r*`。
7. **阴影仅 2 处**：若这两处是「用阴影表达层级」，则违反 MD3「以 tonal surface 表达深度，阴影仅作额外保护」。

## 3. 待 A7 批深挖的项（主会话未覆盖）

- [ ] `lib/surface/theme/tn_theme.dart`（11 行）是否真的产出 `ThemeData(useMaterial3: true, colorScheme:, textTheme:, shapes:)`；还是页面各自绕过 Theme 直接用 `Sp.*`。
- [ ] 动态取色（`core/algorithms/color_extract.dart` → `session/theme_controller.dart`）如何接线；是否已接进 `ColorScheme` 而非仅改某个 widget 颜色。
- [ ] **动画**：全仓 `Duration(milliseconds:…)` / `Curves.*` 清单；对照 MD3 motion 表（emphasized 500/400/200ms、standard 300/250/200ms，曲线 cubic-bezier(0.2,0,0,1) 等）逐条核；查 `AnimatedContainer/AnimatedOpacity/AnimatedSwitcher` 的中断与重复触发行为；查 setState 范围是否引发整页 rebuild。
- [ ] 触控目标 ≥48dp、语义标签（Semantics）、对比度（正文 4.5:1、大字与边框 3:1）。
- [ ] 大屏/折叠屏：内容是否限宽（840–1040dp）、导航是否该切 rail。
- [ ] `useMaterial3: true` 是否设置；是否有 MD2 遗留（Flutter 无 md2 库，但 `Theme.of(context).colorScheme` 未用而处处 `Sp.*` 等价于绕过主题）。
- [ ] 深浅色：是否两套完整 scheme，还是只切了几个颜色。

## 4. 修复方向（待 A7 批结论 + 主会话亲修时定型）

1. 建立**单一 token 源**：以 `ColorScheme.fromSeed` 派生 dark/light（seed 取品牌绿但按 MD3 生成 tonal palette），把 `Sp.*` 全部改为 `Theme.of(context).colorScheme.*` 角色引用；`Sp` 保留为**间距/形状/时长**令牌，颜色不再走常量。
2. 补齐 `surface-container` 五级 + `outline-variant` 分离。
3. 建立 `TextTheme` 五档 + `Shapes` 刻度。
4. 动画统一到 MD3 motion 令牌（Emphasized/Standard × decelerate/accelerate），抽到 `Sp.dur*` / `Sp.curve*`。
5. 动态取色改接 `ColorScheme`（dynamic scheme），而非局部换色。

---
*本文件为采样基线，A7 批须在其基础上补全，不得重复采样；结论以 A7 报告为准。*
