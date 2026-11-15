# 批1-F3 修改说明：bar 排序（navOrder）

## 变更
1. `lib/session/contracts.dart`：`NavEntry` 增加 `final int navOrder;`，构造可选参数 `{this.navOrder = 0}`，默认 0，小者靠前。其余不动（22→27 行，零依赖单测不受影响）。
2. `lib/session/module_registry.dart` `active()` 排序（约 L42-56）改为：
   - 两个模块均有 `navEntry`：按 `navOrder` 升序；相同则按 `id` 字典序兜底；
   - 无 `navEntry` 的模块一律排最后（同类间按 id 字典序）；
   - 整段保持 try/catch + Log.e 兜底，异常时返回空表，行为不变。
3. 未改任何页面文件；`shell.dart` 消费点（L93 `_modules` getter、L121-129 NavigationBar destinations、L70 `_onNavState` index）随 registry 排序自动生效，无需改动。

## 7 个模块现状核对（lib/surface/pages/*.dart，均未改动）
当前页面 NavEntry 构造均未传 navOrder（全部走默认 0），若不补值则全部回到 id 字典序（与旧行为一致，安全兜底）。建议 navOrder 值如下，留待批1 收口时主会话统一在页面文件补上：

| 模块 id | 文件 | NavEntry 现状 | 建议 navOrder | 依据 |
|---|---|---|---|---|
| home | home_page.dart L21 | `NavEntry('首页', 'home')` | **0** | 用户期望第 1 |
| search | search_page.dart L21 | `NavEntry('搜索', 'search')` | **1** | 第 2 |
| playlist | playlist_page.dart L20 | `NavEntry('歌单', 'playlist')` | **2** | 第 3 |
| library | library_page.dart L261 | `NavEntry('音乐库', 'library_music')` | **3** | 第 4 |
| settings | settings_page.dart L274 | `NavEntry('设置', 'settings')` | **4** | 第 5 |
| player | player_page.dart L365 | `navEntry => null` | 不需要 | 无 navEntry，registry 自动排尾 |
| lyrics | lyrics_page.dart L275 | `navEntry => null` | 不需要 | 同上 |

补法示例（收口时）：`const NavEntry('首页', 'home', navOrder: 0)`。

## 验收自检
- contracts.dart 有 `navOrder` 字段且默认 0 ✅（构造 `{this.navOrder = 0}`）
- registry `active()` 排序含 navOrder 升序 + id 字典序兜底 + 无 navEntry 排尾 ✅
- contracts.dart 27 行 / module_registry.dart 84 行，均 ≤500 行 ✅
- 类名唯一（NavEntry / SurfaceModule / ModuleRegistry）✅；仅改 2 个目标文件 ✅
