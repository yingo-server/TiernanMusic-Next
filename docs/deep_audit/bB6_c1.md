# B6-C1 架构合规视角 · 跨层审查报告

> 审查范围：L7（design/{tokens,components,mini_bar}.dart、theme/tn_theme.dart、app_root.dart、shell.dart、pages/ 全部 12 页）→ L6（theme_controller.dart、nav_state.dart）→ L4（core/algorithms/color_extract.dart）。
> 工具纪律：只读 file_read + shell ls/rg/wc；未改任何源码、未跑 dart/analyze/test。
> 首次落盘：2026-11-17 08:49 LCL

## C1 · lib/core/algorithms/color_extract.dart:4-14,59,143 · P0 · 动态取色链（100% 断）
证据：文件头自承「extractDominant / fromSeed 当前版本未被任何 UI 消费方调用（原封面取色桥 cover_color_bridge.dart 已删除）」。全库 rg 结果：`extractDominant` / `fromSeed` 除自身定义与 bridge_core.dart:47-48 的 re-export 外，无任何调用点；`ColorSeed` / `ThemePalette` 无任何 L6/L7 消费。L6 theme_controller.dart 全文 46 行只有 mode(int) 持久化，无任何 seed/palette/取色字段。
问题：L4 取色能力 → L6 theme_controller → L7 app_root/tokens 三段链路完全断开，卡在 L6——theme_controller 从不接收也不保存主色，L7 Sp.theme() 用固定 `green` 常量（tokens.dart:89,101），动态取色形同虚设，与阶段 A「取色链断，转 B6」及 A4/A6/C3 多次报「100% 断」完全一致。
建议：在 L6 ThemeController 增加 seed/调色板状态（经 bridge_core 调 fromSeed），L7 AppRoot 监听后把动态 scheme 注入 Sp.theme(seed:) 或新 ThemeData 工厂；封面字节来源页（player/library）经 bridge_surface 意图把 RGBA 传入 L4。只写建议未改码。
76 合规：不违反铁律 1（无跨层直连），但违反 §1 分层职责——L4 algorithms 能力无上层消费方，职责链未接通。
> 记录：2026-11-17 08:49 LCL

## C1 · lib/surface/theme/tn_theme.dart:7-11 vs lib/surface/design/tokens.dart:86-167 · P1 · 主题单一事实源（仍分裂）
证据：两套 ThemeData 工厂并存——`spLightThemeData()`（tn_theme.dart:7，仅 `useMaterial3 + ColorScheme.fromSeed(0xFF1DB954)`，经 bridge_surface.dart:10,14 导出，被 init/main.dart:19,126 用于启动失败错误页）；`Sp.theme({dark})`（tokens.dart:86，完整 scheme/文本/组件主题，被 app_root.dart:61-62 用于主应用）。rg 确认两者互不调用。
问题：主应用与错误页各建一套主题，品牌色一个写 0xFF1DB954（tn_theme）、一个走 Sp.green 且 fromSeed 也用 green（tokens），种子与调色板规则分叉；正是阶段 A 所指两套主题构造，本批核确认仍未统一。
建议：错误页改用 Sp.theme(dark:false)（或其轻量变体），删除/废弃 spLightThemeData，主题出口收敛到 tokens.dart 单一工厂，并预留 seed 参数供取色链接入。
76 合规：不直接违反铁律；违背 §1「L7 只有 Widget 与 ThemeData」隐含的单一主题出口约定。
> 记录：2026-11-17 08:49 LCL

## C1 · 全部目标文件 wc -l · P2 · 1500 行门禁（符合）
证据：wc 结果——最大 playlist_page.dart 576、player_page.dart 516、login_sheet.dart 504、search_page.dart 475、home_page.dart 436，tokens 206、components 331、color_extract 240、nav_state 107、theme_controller 46、tn_theme 11；全部远低于 1500。
问题：无超长文件，无需按功能拆分。
建议：无需处理。
76 合规：符合铁律 5（1500 行门禁）。
> 记录：2026-11-17 08:49 LCL

## C1 · lib/surface/pages/*.dart（settings/home/search/library/playlist/player/lyrics/mv/login/ykg）· P1 · L7 职责越界（简要核）
证据：多个 StatefulWidget 内直接持有异步取数/状态机——settings_page.dart:53-64 `_loadAccount()` 直接 `await account.activeAccount()` + setState；player_page.dart:102-116 收藏 toggle 内 `await logic.toggle(...)`；playlist_page.dart:255-260 `await pl.detail/tracks`；mv_page.dart:89-175 `_load()` 内串联 videoIdOfSong→qualities→playUrl 并直接持有/初始化 VideoPlayerController；library_page.dart:206 SongDao 直取；login_sheet.dart:70-96 账号 CRUD、174-347 二维码轮询/验证码、ykg_sheet.dart:64-99 导出导入。
问题：surface 页普遍内嵌「取数 + 业务状态机 + IO 编排」，与 C1 主责（M3/C3 视角主核）一致，A7-C1 已报 ≥10 页越界，本批确认仍在；L7 未做到「只画控件」。
建议：取数/状态机上移 L6 session（暴露快照 + 意图），L7 只 ref.watch + 发意图；此为主责 C3 项，本视角仅备案。
76 合规：违反 §1「L7 仅 UI 控件 / 只有 Widget 与 ThemeData」职责边界。
> 记录：2026-11-17 08:49 LCL

## C1 · lib/session/theme_controller.dart:8-9,15-17 vs lib/surface/design/mini_bar.dart:6-9 · P2 · 桥通道（主题/取色侧合规）
证据：theme_controller.dart 仅 import bridge_core.dart(KeyValueSettings/StoragePaths) 与 bridge_kernel.dart(Log)，无直连 core/algorithms/color_extract.dart；app_root.dart 经 bridge_session.dart 取 ThemeController；页面均经 bridge_*/ 取依赖，`rg "^import" pages/` 无 `lib/core/`、`lib/logic/`、`lib/session/` 越级直连（全走 bridge）；无影子桥。
问题：主题侧跨层调用全部经桥，无越级 import core/algorithms；缺点是「该走的桥走了，但桥那头没有取色实现」，属上条取色链断而非通道违规。
建议：保持经桥；接入取色时新增的 fromSeed 调用也应经 bridge_core（已 export color_extract.dart:47-48），不要在 L6/L7 直 import core 文件。
76 合规：符合铁律 1、4（经桥、不反向/不跨层直连）。
> 记录：2026-11-17 08:49 LCL

## C1 · lib/surface/design/tokens.dart:68-76 vs 全 surface · P2 · 动效令牌定义冗余（9 定义仅 2 处消费）
证据：tokens.dart 定义 9 个动效令牌（fast 200ms / normal 300ms / enter 400ms / screen 500ms / curve / standard / emphasized / decelerate / accelerate），注释宣称「MD3 motion 分级」。全库 rg `Sp.(fast|normal|enter|screen|standard|emphasized|decelerate|accelerate)` 仅 1 处实际使用——lyrics_page.dart:159 `_scroll.animateTo(..., duration: Sp.normal, curve: Sp.curve)`；其余 7 个令牌零引用。页面转场、弹层、底部导航切换均无显式动效（Material 默认），未走 M3 分级令牌。
问题：动效令牌大面积空设，未形成单一动效事实源；非越层问题，属 M3/C3 主责范围，本视角备案。
建议：页面转场/导航切换统一使用 Sp.enter/Sp.screen 与对应曲线，或删除无消费令牌避免误导。
76 合规：符合分层（无越层）；不动效职责错位。
> 记录：2026-11-17 08:49 LCL

## C1 · lib/surface/app_root.dart:64-66 · P1 · 主题四档塌缩为两档（档位语义丢失）
证据：ThemeController 定义 4 档（0 系统/1 亮/2 暗/3 纯黑，theme_controller.dart:5-6,13），AppRoot 映射仅 `1 => light, _ => dark`——档 0（跟随系统）被强制 dark、档 3（纯黑）虽注释「TODO 更深色板」但与档 2 完全相同，无独立纯黑板。
问题：L6 输出的 4 态语义在 L7 渲染接缝处丢失 2 态，「跟随系统」永不随系统，「纯黑」等同普通暗色，属跨层状态不同步。
建议：档 0 用 themeMode=system；档 3 提供独立纯黑板（更接近 0xFF000000），或在 L6 明确降级并同步 UI 文案。
76 合规：符合铁律 1（经桥取 controller）；违反跨层状态语义一致性（职责/契约错位）。
> 记录：2026-11-17 08:49 LCL

## C1 · lib/surface/design/tokens.dart:5-6,14-24 vs 全页面约 218 处 Sp.* 引用 · P2 · 亮色模式颜色硬编码（动态色不可达）
证据：tokens.dart:5-6 自承「Sp.bg/card 等仍为 static const，被 8 个文件 17 处 const 引用；页面 const 色值动态化留批后」；rg 统计页面层 Sp. 深色常量引用合计约 218 处（playlist 30、search 25、player 22、settings 18、library 13、home 13、mv 12 等），多为 `const TextStyle(color: Sp.text)` 形式。Sp.theme() 亮色映射（tokens.dart:92-100）只改 ThemeData.colorScheme，页面直接写死的 Sp.text/Sp.card 仍为深色常量。
问题：即使切到亮色模式，页面大量硬编码深色令牌不随主题变化，亮色 UI 对比度错乱；更关键的是这些 const 引用无法被动态主色替换——这是取色链「接到 L7 也落不了地」的第三重障碍（L4 有算法、L6 无状态、L7 硬编码）。
建议：页面改用 Theme.of(context).colorScheme 派生色，或把 Sp 令牌改为可响应主题的 InheritedWidget；动态取色接入时同步改造这些引用。
76 合规：不违反铁律；违背 §1「L7 只有 Widget 与 ThemeData」下的设计令牌单一事实源精神。
> 记录：2026-11-17 08:49 LCL

## C1 · lib/surface/pages/lyrics_page.dart:40,55,64-66,136-159 / login_sheet.dart:159,186-187,298,331 · P2 · 动画/Timer 归属与生命周期（生命周期正确，归属仍越层）
证据：lyrics_page.dart 用 `Timer.periodic(200ms)` 轮询 playbackSession 位置→推进 `_active` ValueNotifier→`_scroll.animateTo(duration: Sp.normal)`，initState 起、dispose cancel（:64-66）无泄漏；login_sheet.dart 二维码 1500ms 轮询（:186-187）、验证码 60s 倒计时（:331），均在 dispose cancel；library_page.dart TabController、mv_page.dart VideoPlayerController 均正确 dispose。但这些「位置轮询状态机 / 二维码登录状态机 / 倒计时状态机」整体住在 L7 Widget。
问题：Timer 生命周期管理合规、无内存泄漏；但状态机本身应在 L6 session（如 lyrics 行高亮应由 PlaybackSession 暴露 currentLyricIndex，二维码轮询应由 AuthSession 驱动），当前属 L7 越层持有业务状态（与 A7-C1 ≥10 页越界同因）。
建议：位置轮询/二维码轮询/倒计时上移 L6，L7 仅监听快照渲染；保留 dispose 习惯。
76 合规：Timer 生命周期符合规范；状态机归属违反 §1「L7 仅 UI 控件 / 无业务状态机」。
> 记录：2026-11-17 08:49 LCL

## 本视角结论
- 最严重：①动态取色链 100% 断（P0，L4 color_extract 有能力、bridge_core 已 export，但 L6 theme_controller 无任何取色状态，L7 Sp.theme 用固定 green；跨层卡在 L6）。②主题单一事实源仍分裂（P1，Sp.theme() vs spLightThemeData() 两套并存）。③主题四档塌缩为两档 + 约 218 处 const 深色硬编码，使动态色即便接通也落不了地（P1/P2）。
- 桥通道：主题/取色侧所有跨层调用均经 bridge_*/，无越级 import core/algorithms、无影子桥、无反向依赖——通道合规，问题在「桥那头没实现」。
- 1500 行门禁：全部目标文件合规（最大 576 行）。
- L7 职责：普遍存在取数/业务状态机内嵌（含 3 处 Timer），A7-C1 已报越界本批仍在；Timer 生命周期本身正确无泄漏。此为主责 C3 项，本视角仅备案。
- 动效令牌 9 定义仅 2 处消费，未成单一事实源（M3/C3 主责）。

## 未覆盖
- 本批按「架构合规 C1」视角，未逐项复核对取色算法数学正确性（extractDominant 直方图/fromSeed HSL 精度）、M3 组件视觉细节、i18n 文案接入完整性——分属 C2/C3 视角。
- 未运行 analyze/test/门禁（任务纪律禁止），无法确认编译期引用是否全部可达，仅作静态 import/rg 取证。
- tn_theme.dart 经 init/main.dart:126 用于错误页（L1），本批任务书 L7 范围不含 main.dart，仅按 rg 引用事实记录，未深审 L1 错误页分支。

## 76 合规小结
- 铁律 1（经桥跨层）：符合——页面/主题/取色侧 import 全走 bridge_*，无直连 core/logic/session 内部文件。
- 铁律 3（无影子桥）：符合——未发现 lib/bridges/ 之外的桥目录。
- 铁律 4（依赖方向/不反向）：符合——grep 未见 session/logic/core 反向 import surface。
- 铁律 5（1500 行门禁）：符合——全部目标文件远低于 1500。
- §1 分层职责（L7 仅 Widget 与 ThemeData）：违反——多页内嵌取数与业务状态机（含 Timer），主题双工厂分裂。
- §1 职责链（L4 algorithms→L6→L7 接通）：违反——取色链断在 L6，L7 硬编码色值使动态色不可达。
- 跨层状态语义一致性：违反——4 档主题塌缩为 2 档。
- 桥日志 try/catch：基本符合——主题/导航/页面桥调用多处有 try/catch + Log 留痕。
> 收口记录：2026-11-17 08:49 LCL（全 12 页 + L6 两文件 + L4 + L7 设计/主题/根/壳连续读完，结论基于静态取证）
