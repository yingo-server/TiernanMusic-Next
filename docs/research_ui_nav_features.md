# UI 布局 / 底部 bar / MV 入口 / 扫码登录 调研报告

> 只读调研，基准：当前代码（lib/surface / lib/session / lib/logic）。未改任何代码。

---

## 1. 首页臃肿定量（home_page.dart，500 行）

`HomePage.build` 是 AppBar + `ListView.builder(itemCount: 4)`，四区块自上而下：

| 区块 | 构建函数 | 行号 | 占屏估算（典型手机 ~800dp 内容高） |
|---|---|---|---|
| AppBar「首页」+搜索图标 | build 内 AppBar | 121-138 | ~56dp（5%） |
| 每日推荐（横滑 176dp 卡） | `_dailySection` | 144-191 | 标题+176 卡+间距 ≈ 240dp，空态时只有一行文案 ~70dp |
| 推荐歌单（3 列 GridView） | `_playlistSection` | 193-235 | shrinkWrap 全展开，10 个歌单 ≈ 4 行 × ~200dp ≈ 800dp+（最大臃肿源，占首屏 1 屏以上） |
| 排行榜（150dp 渐变大卡横滑） | `_rankSection` | 237-283 | 标题+150 卡 ≈ 210dp |
| 热搜 chips（Wrap 竖排 Wrap） | `_hotSection` | 285-330 | 10-20 个 chip Wrap 会折成 4-8 行 ≈ 200-400dp |

**合计 >1500dp，约 2 屏才能滚完；推荐歌单网格 + 热搜 chips 两大块贡献了 60%+ 的纵向长度。**

### 「热搜移到搜索页搜索历史下、每列 10 个横向排开」要改的文件:行
1. `lib/surface/pages/home_page.dart:285` — 删除 `_hotSection` 方法及 `build` 中 `itemCount: 4 → 3`（行 120）、`i==3 return _hotSection`（行 126-127），并删 `_hotF`/`_load` 中 `g.search?.hotSearch()`（行 47）。
2. `lib/surface/pages/search_page.dart:312-476`（`_idleBody` → `_historySection`）— 在「历史记录」区块之后新增 `_hotSection`：调 `appGraph.search.hotSearch()`，用 **GridView（crossAxisCount 由横向排开决定，scrollDirection: horizontal，每列 10 个）** 或横向 GridView 展示热搜词，点击 `_doSearch(keyword)`（旧版语义：热搜词直接触发搜索，不再是 home 那种只跳页丢关键词）。注意 `_doSearch` 已在 `_history` 维护，热搜点击应走 `_ctrl.text=kw; _doSearch(kw)` 复用联想/历史逻辑。

### 首页保留 / 删除建议
- 保留：AppBar、每日推荐（横滑）、推荐歌单（**改为横向单行 ListView**，height ~200dp，别 shrinkWrap 全展开）。
- 删除：热搜整块（移搜索页）。
- 压缩：排行榜从 150dp 渐变大卡 → 紧凑卡（width 120 / height 110）或并入歌单横排行。

---

## 2. 亮暗模式不生效

- `settings_page.dart:47` `_themeMode` 是**页面本地 state**（注释自认：`// 主题模式：当前无 L6 主题会话出口，先本地维护`）。SegmentedButton `onSelectionChanged`（行 178-179）只 `setState(_themeMode = s.first)`，**不通知任何全局**。
- `app_root.dart:35-41`：`MaterialApp(theme: Sp.theme(), home: AppShell())` — **只传了亮/暗之一，没传 `darkTheme`，也没有 `themeMode`，更没有 InheritedWidget / themeModeProvider**。`Sp.theme()`（tokens.dart:105）硬编码 `brightness: Brightness.dark` + 深色 Sp.bg 色板，且所有页面 scaffold 又显式 `backgroundColor: Sp.bg`（常量深色）。
- 所以：选「亮」只是把设置页本地整数改了 → 什么都不会变，截图里「亮」选中但页面全黑，与现象完全一致。

**最小修法（3 处）：**
1. `tokens.dart` 新增 `Sp.lightTheme()`（同工厂但 `Brightness.light` + 浅色板，或先简单用 `ColorScheme.fromSeed(seedColor: green, brightness: light)` 包 ThemeData）。
2. 新建一个全局 `ValueNotifier<ThemeMode>`（建议放 session/graph 或 app_root 顶层 `final themeModeProvider = ValueNotifier(ThemeMode.dark)`；理想是挂 `KeyValueSettings` 持久化），设置页 SegmentedButton 写入该 notifier 并持久化。
3. `app_root.dart` 把 AppRoot 改为 StatefulWidget（或包 `ValueListenableBuilder`），`MaterialApp(theme: Sp.theme(), darkTheme: Sp.theme(), themeMode: notifier.value)`；同时把各页面硬编码 `backgroundColor: Sp.bg` 去掉（交给 scaffoldBackgroundColor），否则亮色下 scaffold 仍是黑。

---

## 3. 底部 bar 顺序

- 顺序来源：`shell.dart:39-48 registerModules()` 的 install 顺序**不起作用**。真正决定顺序的是 `module_registry.dart:37-40 active()`：`_modules.values.where(enabled).toList()..sort((a,b) => a.id.compareTo(b.id))` — **按模块 id 字典序排序**。当前 5 个 nav 模块 id：home / search / playlist / library / settings → 字典序实际为 **home, library, playlist, search, settings**（与 install 顺序无关）。
- 用户想「首页/搜索/歌单/音乐库/设置」→ 现状是 library 插在 search 前，即「首页/音乐库/歌单/搜索/设置」，不符。
- **最小改法（一处）**：`module_registry.dart` 的 `active()` 排序改为按显式权重/白名单序，例如：
  ```dart
  const navOrder = ['home','search','playlist','library','settings'];
  list.sort((a,b) => navOrder.indexOf(a.id).compareTo(navOrder.indexOf(b.id))); // 未知 id 排最后
  ```
  不要靠改 id 字符串或 install 顺序来凑序（install 顺序被 sort 覆盖，改了也无效）。备选：给 `SurfaceModule` 加 `int navWeight` 字段（contracts.dart），按 navWeight 排序，扩展性更好。

---

## 4. 登录入口与 AuthLogic 能力

- settings_page.dart:132：`FilledButton(onPressed: () => _toast('扫码登录入口待接入'), ...)` — **纯占位**，没有任何 AuthLogic 调用；未接 `createQrLogin / pollQrLogin`，没有二维码弹层。
- AuthLogic（lib/logic/auth/auth_logic.dart）已实现、UI 未接的方法：
  | 方法 | 状态 |
  |---|---|
  | `createQrLogin()` | ✅ logic 完整（含官方 qrcode_img base64），UI 未接 |
  | `pollQrLogin(key)` | ✅ 状态机 0/1/2/4 完整，UI 未接 |
  | `restoreSession()` | ✅（bootstrap 启动时已用） |
  | `logout()` | ✅ settings 已接 |
  | **短信登录** | `VerificationLogic`（`sendSmsCode`/`smsLogin`，bridge_logic 批5-A GAP#31）+ `SmsLoginResult` 均已装配（bootstrap.dart:96-101），**UI 零接线**，无任何 surface 文件引用 verification/sms |
  | **多账号** | `AccountLogic`（AccountDao 多账号切换 `switchTo` 等）settings 只用了 `activeAccount()` 显示昵称，登录/切换/添加账号 UI 未接 |
- 建议：settings 账号区加「登录」入口 → 底部弹层含「扫码登录」（createQrLogin → 显示 qrImageB64 → 定时 pollQrLogin）与「手机号登录」（VerificationLogic.sendSmsCode/smsLogin）两个 tab；登录成功后刷新 `_loadAccount()`。

## 5. MV 功能

- **L7 surface 完全没有 MV 页/入口**：`rg mv` 在 lib/surface 只命中 player_page 的无关字符串。`lib/session/bootstrap.dart:86` 注册了 `'mv'` 占位模块（`enabled: false` → 不进导航），shell.dart 的 `registerModules()` 也未安装任何 MvPageModule。`MvLogic`（mv_logic.dart：`qualities()` / 播放地址）在 L5 已完整实现并装配进 AppGraph（bootstrap.dart:69），只是没有任何 UI 调它。
- 建议挂入口（按优先级）：
  1. **播放页 ⋮ 菜单**（player_page.dart）：加「查看 MV」→ `MvLogic` 按 song hash 取 MV → 弹全屏视频播放（搜歌最自然的动线）。
  2. **搜索结果**：search_typed_logic 支持 MV 分段（FUNCTION_TREE §5 有「MV」tab 设计），可加 MV 结果卡 → MV 播放页。
  3. 歌单详情歌曲行的长按/更多菜单加「看 MV」。
  实现：新建 `lib/surface/pages/mv_page.dart` + `MvPageModule(id:'mv', navEntry:null)`，用 `ModuleRegistry.instance.byId('mv').install(...)` 覆盖占位；导航条不放（navEntry 为 null 即可），仅路由跳转。

## 6. 「页面显示但数据恒空/占位」清单（按页面）

| 页面 | 恒空/占位项 | 原因（代码定位） |
|---|---|---|
| **设置页** | 扫码登录按钮 | `_toast('扫码登录入口待接入')`（settings_page.dart:132），无回调 |
| 设置页 | 主题模式 4 档 | 本地 state，不改 MaterialApp（见 §2） |
| **音乐库** | 本地曲库 tab | `library_page.dart:170` 明确注释：SongDao 未随 AppGraph 暴露 → 恒「本地曲库暂不可用」空态 |
| 音乐库 | 最近播放 tab | HistoryDao 同上未暴露 → 恒「暂无最近播放」（library_page.dart:176） |
| 音乐库 | 账号卡 | 未登录 / profile 端点未实测 → 整块隐藏 |
| **首页** | 每日推荐 | 未登录时 `getDailyRecommend` 恒空 → 「暂无每日推荐（登录后可能可见）」，而登录 UI 又未接 → **死循环空态** |
| 首页 | 热搜 | 依赖登录态与否视端点而定；且点击 chip 只跳搜索页不传关键词 |
| **搜索页** | 歌单/专辑/歌手/歌词 4 个分段 | `kSearchSegments`（search_page.dart:31 注释：仅歌曲端点可用）→ 切段恒空态；六类搜索 `SearchTypedLogic` 已装配但本页用的是旧 `SearchLogic` |
| 搜索页 | 搜索历史 | `_history` 是**内存 list**（search_page.dart:55），未持久化，重启即丢 |
| **播放/全 app** | MV | MvLogic 已实现、零 UI（见 §5） |
| 全 app | 短信登录 / 多账号切换 | VerificationLogic / AccountLogic 已装配、零 UI |
| 全 app | FM（FmLogic）、评论（CommentLogic）、歌手页（ArtistLogic）、专辑页（AlbumLogic）、歌单写（PlaylistWriteLogic）、翻译（TranslationLogic） | L5 全部已装配进 AppGraph，L7 均无页面/按钮触达 |

**总判断**：L5/L6 能力装配率高，但 L7 触达率低 —— 用户可见的「不可用」集中在：登录链路（扫码+短信）、主题切换断线、本地曲库/最近播放 DAO 未过桥、MV 无入口、搜索分段恒空、首页臃肿。按 §1-§5 的行级改法即可逐项闭环。
