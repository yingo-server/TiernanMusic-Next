# 批1-C2 只读检查报告（surface 主题/令牌/导航）

## 1. tokens.dart（166 行）
- 仅 dark 工厂：`Sp.theme()` 只 `ColorScheme.fromSeed(brightness: Brightness.dark)`（L57-60），无亮色对应物，无 `Sp.themeLight()`。
- 亮色色板缺失常量：无 `bgLight / textDark / cardLight / greenDark(可复用 green) / dividerLight / textSubLight` 等亮色变体；全部 12 个颜色常量（L10-21）均为深色值且 `static const`。间距/圆角/字号与明暗无关，可复用。
- `_text()` 的 TextTheme 颜色也硬绑深色 `text/textSub`（L160-165）。

## 2. settings_page / app_root
- settings_page.dart L37-38：`int _themeMode = 2` 为页面本地 state，注释自认"无 L6 主题会话出口，TODO 接 theme 会话持久化"；L183-184 `onSelectionChanged` 仅 `setState`，无持久化、无 ChangeNotifier 通知任何监听者，切换后 MaterialApp 毫无反应（死开关）。
- app_root.dart：MaterialApp（L37-43）只有 `theme: Sp.theme()`，缺 `darkTheme:` 与 `themeMode:` 两个参数——即缺在第 40-41 行附近；且 AppRoot 是 StatelessWidget，即使有 themeMode 也无 Listenable 重建。

## 3. 最小方案结论：选 L6 ThemeController（ValueNotifier<int> + KeyValueSettings）
理由：
- 现状 AppRoot 是 StatelessWidget，InheritedWidget 需包在 MaterialApp 之上并要求所有取色点改 `context.watch`，而全工程 17 处 `Sp.bg/card` 都是 const 直引，改造面大，违背"最小改动"。
- 76 原则要求状态/持久化在 L6、L7 只画控件：settings_page 现在自己持 `_themeMode` 正是违规。ThemeController 放 L6 session（foundation 允许，ValueNotifier 来自 foundation，KeyValueSettings 已由 bridge_core 暴露给 L7，见 app_root.dart L8-9 导入），持久化天然归属 session。
- L7 侧只需：AppRoot 改 StatefulWidget 监听 controller + 补 `darkTheme/themeMode` 两行；settings_page 删本地 state 改调 controller。共约 3 个文件小改，工作量最小。

## 4. Sp.bg / Sp.card const 用量
rg 统计（行数）：
| 文件 | 处数 |
|---|---|
| search_page.dart | 5 |
| home_page.dart | 4 |
| settings_page.dart | 2 |
| design/components.dart | 2 |
| playlist_page.dart | 1 |
| player_page.dart | 1 |
| lyrics_page.dart | 1 |
| library_page.dart | 1 |

合计 17 处、涉及 **8 个文件**。若做动态主题需把这些 const 上下文改为 getter（或改用 Theme.of(colorScheme)），涉及 8 个文件，是亮色方案的主要成本，进一步支持"先 L6 controller + 仍用深色令牌（亮色映射进 tokens 内部）"的折中：色板值在 tokens 内部按 themeMode 分流，页面代码尽量不动。

## 5. bar 顺序
- module_registry.dart L42-47 `active()`：`_modules.values.where(enabled)..sort(a.id.compareTo(b.id))` —— 按模块 id 字典序，行号 45-46（sort 语句）。
- contracts.dart 无 `navWeight` / `navOrder` 字段（全仓 rg 0 命中），NavEntry 只有 label/icon。
- shell.dart 消费点：L93 `_modules` getter（active().where(navEntry!=null)），L121-129 NavigationBar destinations 按 active() 顺序渲染，L70 `_onNavState` 也依赖该顺序 index。
- 建议：加 `navOrder`（int，小者靠前，缺省大数），比 navWeight 语义直白且 `sort` 一行可改；weight 易和 M3 weight 概念混淆。registry 的 sort 改为 `(a,b) => (a.navOrder ?? 99).compareTo(b.navOrder ?? 99)`，再按 id 稳定排序。

## 必修 TOP5（修改点清单：文件:行:改什么）
1. `lib/session/theme_controller.dart:新建`：L6 ThemeController extends ValueNotifier<int>，init 读 KeyValueSettings('theme_mode')，set 模式时写回并 notify。
2. `lib/bridges/bridge_session.dart:导出区`：导出 themeController 单例（随 appGraph 或顶层 getter）。
3. `lib/surface/app_root.dart:37-43`：AppRoot 改 StatefulWidget，AnimatedBuilder 监听 controller，补 `darkTheme:`（纯黑可再给超暗变体）与 `themeMode:` 映射（0 system/1 light/2 dark/3 纯黑→dark+超暗 scheme）。
4. `lib/surface/pages/settings_page.dart:37-38,183-184`：删 `_themeMode` 本地 state，onSelectionChanged 改调 themeController.setMode。
5. `lib/surface/design/tokens.dart:57-60`：theme() 抽参 `Sp.theme(Brightness b)`，新增亮色映射（surface/card/onSurface/primary 等内部换值），供 darkTheme 使用；不要求页面改 const（见第 4 点折中）。

可选：`lib/session/contracts.dart:8-13`：NavEntry/SurfaceModule 加 `int? navOrder`；`lib/surface/shell.dart:121-129` 顺序随 registry 排序自然生效。
