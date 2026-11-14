# 重构后 L7 UI 全面审查报告（b52f16b → HEAD 577bdd9）

审查范围：lib/surface/ 全部 13 个 dart 文件（app_root、shell、design/ 三件、theme/tn_theme.dart、pages/ 七页）。只读审查，未改任何代码。

## 1. 旧系统残留（逐文件）

- **全部页面/设计件**：均未 import tn_theme / tn_motion / common_m3 / common_widgets / m3/* / ui/spotify_* / surface/widgets/*；无 TnDims、TnText、TnPageRoute、TnMotionStaggered、SurfaceRegistry、playerProvider、appNavigatorKey、homeTabRequest、themeModeProvider、dynamicThemeProvider 引用。✅
- **`Sp.green` 旧令牌**：仍是现行 tokens.dart 定义（Sp 类，lib/surface/design/tokens.dart:18），非旧令牌残留；被 8 个文件大量使用（playlist/library/search/player/settings/lyrics/home/components）——属现役令牌，不算违规，但硬编码绿色散布各页，建议收敛到主题。⚠️
- **真残留 1 处**：`lib/bridges/bridge_surface.dart:9/13` 仍 import + export `../surface/theme/tn_theme.dart` 的 `tnLightThemeData`，而 app_root.dart 实际用的是 `Sp.theme()`（design/tokens.dart）——tn_theme.dart 已成死代码/旧主题残留，属 L7 内遗留旧系统文件。❌
- 其余 12 文件干净。

## 2. 跨层合规（L7 直连 L1–L5）

逐文件检查全部 import：**13/13 合规**。所有外部依赖均经 `../bridges/bridge_core.dart`、`bridge_logic.dart`、`bridge_session.dart`（lib/session、lib/core、lib/logic 直接 import 数：0）。违规清单：无。✅

## 3. 状态归属（逐页判定）

- **app_root**：纯装配（SurfaceDeps 注入、MaterialApp），无逻辑。✅ 纯控件
- **shell**：纯控件；动态取 registry 生成导航 + mini bar。但**未订阅 NavState**——player_page:163 的 `navState().requestTab('lyrics')` 发出后无人消费，lyrics 页无法被导航到（见问题4）。⚠️
- **mini_bar**：读 `session.snapshot` 渲染，纯控件。✅
- **home_page**：initState 建 4 个 Future（daily/playlist/rank/hot），build 内不建 future（有注释声明）；逻辑仅"取数→展示"，无播放状态机/队列/缓存。✅ 基本纯控件（数据获取在 UI State 内，属灰区但符合"Future 不在 build 创建"规范）
- **search_page**：StatefulWidget 持有 `_resultF/_suggestF`（用户触发时赋值，非 build 内）；纯搜索展示。✅ 基本纯控件
- **playlist_page**：3 处 tab/sheet 各在 initState 建 future；无状态机。✅ 基本纯控件
- **library_page**：initState 拉 profile/favCount；TabController 自建（控件级，可接受）。✅
- **settings_page**：异步拉账号、弹 sheet；纯展示。✅
- **player_page**：消费 `session.snapshot`（:198/:310）与 PlayMode；SeekSlider/FavoriteButton 为控件级 State。✅ 纯控件
- **lyrics_page**：读 `playbackSession().snapshot`（:68/:129）+ ScrollController（控件级）。✅ 纯控件
- 未发现：自建播放状态机 / 队列 / 预读 / 装配图 / DAO 直查。✅

## 4. 契约一致

- 7 个 XPageModule（home/search/playlist/library/settings/player/lyrics）**全部 extends SurfaceModule**，id/route/navEntry/builder 齐全；player、lyrics navEntry=null（不进底栏，符合设计）。✅
- shell.registerModules() 幂等 install 6 个模块到 ModuleRegistry；底栏由 `ModuleRegistry.instance.active()` 动态生成。✅
- L7 播放态统一消费 `PlaybackSession.snapshot`（mini_bar/player/lyrics），无自造。✅
- **契约缺口 ①**：LyricsPageModule 定义了但 shell 未 install → `requestTab('lyrics')` 无目标模块；且 shell 根本没 addListener(navState)，requestTab 全局失效。❌ 必修
- **契约缺口 ②**：playlist 详情走 showModalBottomSheet、player 走 Navigator.push（MaterialPageRoute，非 TnPageRoute —— 新体系无路由令牌，可接受）。⚠️ 可接受

## 5. 删净核对（ls 终检）

- lib/surface/widgets：存在但为**空目录**（0 文件）✅（建议删目录）
- lib/surface/ui、lib/surface/audio：不存在 ✅
- lib/theme、lib/common*、lib/ui：不存在 ✅
- 旧 22 页面：lib/surface/pages 仅 7 个新页面 ✅
- **未删净**：lib/surface/theme/tn_theme.dart（1 个旧 theme 文件存活，且被 bridge_surface 引用）❌

## 结论

**确认已彻底转换：约 95%**。13 个 surface 文件全部走 bridge、全走 snapshot、契约基本齐备；残留仅 2 处（tn_theme.dart + bridge_surface 对它的引用、空 widgets 目录）。

**必修 TOP5**
1. shell 未订阅 NavState（addListener + 切 tab），`requestTab('lyrics')` 静默失效。
2. LyricsPageModule 未在 shell.registerModules() install——lyrics 页不可达。
3. 删除 lib/surface/theme/tn_theme.dart 并去掉 bridge_surface.dart:9/13 的 import/export（app_root 已用 Sp.theme()）。
4. 删除空目录 lib/surface/widgets。
5. 收敛 Sp.green 等颜色到主题级定义（现 8 文件 30+ 处硬编码），为未来主题化留口。
