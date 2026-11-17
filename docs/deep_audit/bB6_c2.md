# B6 批 · C2 实现正确性视角 · UI / M3 / 主题 / 动画 / 动态取色跨层审查

> 审查人：C2 子代理 · 只读证据 · 时间基准 2026-11-17（Asia/Shanghai）
> 范围：L7 tokens/components/mini_bar/tn_theme/app_root/shell + 12 页面；L6 theme_controller/nav_state；L4 color_extract。
> 纪律：append 写入；只写本视角；每条带 文件:行 证据。

---

## C2 · lib/core/algorithms/color_extract.dart:1-240 + lib/session/theme_controller.dart:1-46 + lib/surface/design/tokens.dart:78-148 · P0 · 动态取色链（用户「UI 不舒服」核心）仍 100% 断

证据：
```dart
// L4 color_extract.dart:5-9 自述
// ⚠ 接线现状（诚实标注，审计B P2-1）：extractDominant / fromSeed 当前版本
// 未被任何 UI 消费方调用（原封面取色桥 cover_color_bridge.dart 已删除）。
ColorSeed extractDominant(List<int> rgbaBytes, int width, int height) {...}   // :61
ThemePalette fromSeed(ColorSeed seed, {bool dark = false}) {...}             // :137

// L6 theme_controller.dart:5-45 全程只有 int 档位，无任何取色/调色板字段
class ThemeController extends ValueNotifier<int> {        // :13
  ThemeController._() : super(2) {...}                     // :15 只读存档位
  void setMode(int mode) { value = mode; ...setInt(...); notifyListeners(); } // :32-45
  // 无 extractDominant / fromSeed / ColorSeed / ThemePalette 任何引用
}

// L7 tokens.dart:78-82 主题工厂 seed 恒为硬编码品牌绿
final scheme = ColorScheme.fromSeed(
  seedColor: green,   // green = Color(0xFF1DB954) 静态常量 :17
  brightness: dark ? Brightness.dark : Brightness.light,
).copyWith(...);
```

问题：整条「L4 提取主色 → L6 控制器 → L7 生成 ColorScheme」链路完全不存在——L4 `extractDominant`/`fromSeed` 全仓无调用方，L6 `ThemeController` 是个纯 `ValueNotifier<int>` 只存/持久化主题档位（0/1/2/3），L7 `Sp.theme()` 的 `seedColor` 恒为硬编码 `#1DB954`。阶段A仅修了 motion 令牌（P1-7）与 tonal pairing（P1-8），取色链本身一行未接。用户切歌/换封面时主色永不变化，动态取色能力形同虚设。

建议：在 L6 `ThemeController` 增加 `ValueNotifier<int> seedArgb`（或 `ColorSeed`），提供 `updateFromCover(RGBA字节)` 调 `extractDominant`+`fromSeed`；L7 `AppRoot` 同时监听档位与 seed，`Sp.theme({int? seedArgb})` 用 `Color(seedArgb)` 作 `fromSeed` 种子（dark 档再由 palette 派生），封面变更时经 L6 门面推 seed。保留品牌绿作 fallback。

76 合规：L4 算法在 core 合规；取色编排应属 L6 session；L7 只消费 ColorScheme。当前 L6 缺位导致职责真空（非越级，是断链）。

---

## C2 · lib/surface/app_root.dart:56-70 · P0 · 主题切换档位 0/2/3 全塌缩为 dark，0(系统)与3(纯黑)不可达

证据：
```dart
// app_root.dart:57-70
return ValueListenableBuilder<int>(
  valueListenable: ThemeController.instance,
  builder: (context, mode, _) => MaterialApp(
    theme: Sp.theme(dark: false),
    darkTheme: Sp.theme(dark: true),
    themeMode: switch (mode) {
      1 => ThemeMode.light,
      _ => ThemeMode.dark,   // ← mode 0(系统)/2(暗)/3(纯黑) 全部落这里
    },
    home: const AppShell(),
  ),
);
```

问题：档位 0（跟随系统）被错误映射为强制 dark，系统亮色时不会跟亮；档位 3（纯黑）被注释「暂用暗色板，TODO」直接复用暗色板，纯黑（#000000）档位无实际效果。四档只有 1/2 真正可区分。用户设置「系统」实为「强制暗」，设置「纯黑」实为「普通暗」。

建议：`themeMode: switch(mode){0=>ThemeMode.system,1=>ThemeMode.light,2=>ThemeMode.dark,3=>ThemeMode.dark}`；档位 3 另建 `Sp.theme(dark:true, pureBlack:true)` 把 surface/scaffold 置 `#000000`，AppRoot 按 mode 选择 darkTheme。

76 合规：档位语义定义（L6 ThemeController）与消费（L7 AppRoot）不一致，属跨层契约不同步。

---

## C2 · lib/init/main.dart:126 + lib/surface/theme/tn_theme.dart:7 + lib/surface/design/tokens.dart:78 · P1 · 两套 ThemeData 单一事实源分裂（错误页 vs 主页配色不一致）

证据：
```dart
// tn_theme.dart:7-11 独立浅色主题
ThemeData spLightThemeData() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954)),
);

// app_root.dart:61-62 主应用主题（Sp.theme，fromSeed 后大段 copyWith 覆盖 surface/primary 等）
theme: Sp.theme(dark: false),
darkTheme: Sp.theme(dark: true),

// main.dart:126 错误页用另一套
theme: spLightThemeData(),
```
问题：`spLightThemeData()` 与 `Sp.theme(dark:false)` 是两套独立构造——前者 primary=`#1DB954`、`surface` 为 fromSeed 默认浅色；后者 `Sp.theme` 把 surface/onSurface/primary/onPrimary 等全 `copyWith` 覆盖成自定义值（primary 仍绿但 onPrimary=黑、surface=含绿底等）。错误页（启动失败）与主页在亮色下 primary/onPrimary/surface/textTheme 全部不一致。阶段A未收敛此分裂，与 A7-C3「单一事实源分裂」结论一致。

建议：删除 `spLightThemeData()`，错误页统一用 `Sp.theme(dark:false)`（或让 tn_theme 仅 re-export Sp.theme），全应用只留一个 ThemeData 工厂。

76 合规：ThemeData 构建在 L7 合规；但两个 L7 工厂并存违反「唯一真源」，属职责重复。

---

## C2 · lib/surface/pages/*.dart（172 处 Sp.* 色令牌 / 页面层 colorScheme 引用 = 0）· P0 · 亮色主题下页面色不跟随，仍是深色静态常量（对比度/破图）

证据：
```dart
// rg 统计：页面层 Sp.(bg|card|text|green|...) 消费 172 处；Theme.of(context).colorScheme 在 12 页面 = 0 处
// 代表：
home_page.dart:121  backgroundColor: Sp.bg,           // Sp.bg=0xFF0E0F12 近黑（静态 const）
home_page.dart:134  color: Sp.text,                     // Sp.text=0xFFEDEFF2 近白（静态 const）
lyrics_page.dart:137 backgroundColor: Sp.bg,
search_page.dart:141 backgroundColor: Sp.bg,
playlist_page.dart:37 backgroundColor: Sp.bg,
playlist_page.dart:463 style: const TextStyle(fontSize: Sp.fItem, color: Sp.text),
// tokens.dart:10-17 Sp.* 全为 static const 深色值；:24-31 亮色映射仅 ThemeData 工厂内部用
```
问题：阶段A把亮色映射（`_bgLight/_textLight` 等）只接进了 `Sp.theme()` 的 ThemeData，但**页面层直接用 `Sp.bg/Sp.text` 静态深色常量**，绕过 `Theme.of(context).colorScheme`。切到亮色档（mode=1）后，MaterialApp 给的是浅色 scaffold，但页面 Scaffold/文字仍写死近黑底+近白字：`Sp.text=0xFFEDEFF2`（近白）配浅色区域→**白底白字**；`Sp.bg` 近黑配深色文字→对比度错乱。这是 A7-C3「亮色白底白字」根因，阶段A修了令牌却没让页面消费，痛点未解。

建议：页面层 `Sp.bg/Sp.text/Sp.card/...` 全量替换为 `Theme.of(context).colorScheme.surface/onSurface/surfaceContainer*/primary`（B6 页面级 MD3 专项）；`Sp` 只留间距/形状/时长。或短期在 `Sp` 改为 `BuildContext` 取色方法（非 const），但须逐页去掉 const 构造。

76 合规：颜色语义应属 L7 ThemeData/ColorScheme；页面静态常量架空主题层，属同层内消费错位+跨层（L7 内部）造重复真源。

---

## C2 · lib/surface/design/tokens.dart:67-75 + lib/surface/pages/lyrics_page.dart:159 · P1 · 阶段A新增 6 档 motion 令牌几乎零消费（仅 1 处旧令牌）

证据：
```dart
// tokens.dart:67-75 阶段A新增
static const Duration fast=200ms, normal=300ms, enter=400ms, screen=500ms;
static const Curve curve=easeOutCubic, standard=ease, emphasized=easeOutCubic,
              decelerate=decelerate, accelerate=easeIn;
// 全 surface 检索（排除定义处）唯一消费点：
lyrics_page.dart:159 _scroll.animateTo(target, duration: Sp.normal, curve: Sp.curve);  // 仍是旧 normal/curve
```
问题：阶段A P1-7 引入的 `enter/screen/standard/emphasized/decelerate/accelerate` 六个令牌**无任何页面使用**，唯一动画消费还是旧的 `Sp.normal/Sp.curve`。窗口过渡/Hero/容器变换仍是默认曲线，用户「动画不经看」痛点未因阶段A修复而改善。另注意令牌值本身与注释错位：`standard=Curves.ease`（注释写 cubic-bezier(0.2,0,0,1) 实为 MD3 emphasized 曲线），`emphasized=easeOutCubic`（注释写另一条）——命名/注释/取值三者不自洽。

建议：在页面转场（Navigator/MaterialPageRoute）、列表进入、播放页控件切换处用 `Sp.enter/Sp.screen` + `Sp.emphasized/Sp.decelerate`；订正曲线注释与取值使之匹配（MD3 emphasized ≈ cubicBezier(0.2,0,0,1)，decelerate ≈ (0,0,0,1)，accelerate ≈ (0.3,0,1,1)）。

76 合规：动效令牌定义（L7 design）合规；零消费属页面层未接入，非越级。

---

## C2 · lib/surface/shell.dart:78-86 + lib/surface/pages/player_page.dart:206-217 · P1 · 导航 tabRequest 对 'lyrics'/'comment' 死链：非底栏模块无法被选中，点「歌词/评论」无反应

证据：
```dart
// shell.dart:78-86  _modules 只取「有 navEntry 的模块」
List<SurfaceModule> get _modules => ModuleRegistry.instance.active()
    .where((m) => m.navEntry != null).toList();
void _onNavState() {
  final req = NavState.instance.tabRequest;   // 'lyrics' / 'comment' / 'search'
  final modules = _modules;                   // 仅 home/search/library/settings（lyrics/comment navEntry=null）
  final i = modules.indexWhere((m) => m.id == req);
  if (i >= 0 && mounted) setState(() => _index = i);   // i=-1 → 什么都不发生
  NavState.instance.clearTabRequest();
}
// player_page.dart:206  requestTab('lyrics')；:217 requestTab('comment')
// lyrics_page.dart navEntry=>null；comment 模块全仓未注册（rg 命中仅 player_page 的 requestTab）
```
问题：播放页 ⋮ 菜单点「歌词」发 `requestTab('lyrics')`，但 lyrics 模块 `navEntry=null`，不在 shell 的 `_modules` 里，`indexWhere` 恒 -1，永不切换/打开歌词页；「评论」更是连模块都未注册。两个菜单项实际是死按钮。`requestTab('search')`（home_page:112）因 search 有 navEntry 才有效。tabRequest 深链只对底栏模块有效，对"非底栏直达页"设计失效。

建议：在 shell `_onNavState` 对非底栏模块改为 push 路由（`ModuleRegistry.byId(req)?.builder`），而非在 `_modules` 里 indexWhere；comment 模块若未实现应隐藏菜单项而非留死链；统一用 `navState()`/`NavState.instance`（当前当前单例一致，但混用易错）。

76 合规：导航编排属 L6 NavState + L7 shell；消费端只处理了底栏子集，属跨层契约不完整。

---

## C2 · lib/session/nav_state.dart:13-16,80-92 + lib/surface/pages/playlist_page.dart:371 / search_page.dart:132 · P2 · NavState.albumId/artistId 只写不读（死字段），专辑/歌手深链未接通

证据：
```dart
// nav_state.dart
String _albumId=''; String _artistId='';
void setAlbum(String id){ _albumId=id; _notify(); }   // :80
void setArtist(String id){ _artistId=id; _notify(); }
// 生产者：
playlist_page.dart:371  NavState.instance.setAlbum(items[i].albumId);
search_page.dart:132   NavState.instance.setAlbum(albumId);
// 消费者：rg '\.albumId|\.artistId' 在 lib/surface 全仓 → 0 个读取 NavState 相册/歌手值的导航跳转
```
问题：albumId/artistId 被写入并广播，但没有任何页面监听后跳转到专辑/歌手详情；setAlbum 后只是 `_notify()`，各监听器（settings 的 _onAuthChanged 等）重读自身数据，不会导航。用户点专辑/歌手实际无跳转，深链字段形同虚设（与 A7「深链 MV 不可达」同类断链）。

建议：在 shell 或专用监听者消费 albumId/artistId → push 对应详情页（playlist_page 已有 album 态可复用），或移除死字段避免误导；补端到端深链测试。

76 合规：导航意图应 L6 声明、L7 消费；当前 L6 声明了但 L7 无消费者，属链断（非越级）。

---

## C2 · lib/surface/pages/lyrics_page.dart:55,131-149 · P1 · 歌词 200ms Timer 的 _tick 无 mounted 保护 + 切歌重入竞态（A7 已报，阶段A未修）

证据：
```dart
// :55  Timer.periodic(200ms, (_) => _tick());   dispose(:63) 里 cancel，正确
// :131-149 _tick() 全程无 mounted 判断：
void _tick() {
  final snap = playbackSession().snapshot;
  ...
  if (song.hash != _hash) { _load(); return; }   // :136 切歌触发异步 _load，无防抖
  ...
  _active.value = idx;   // ValueNotifier 未在 dispose 前判定
  _scrollTo(idx);        // animateTo 在 dispose 窗口可能作用在已释放 ScrollController
}
// 对比 _load() 内部有 if(!mounted)return（:114/:122），但 _tick 本身无
```
问题：dispose 与 Timer 回调之间存在竞态窗口——Timer 在 dispose 同帧触发 `_tick` 时，`_scroll.animateTo`/`_active.value` 可作用于已 dispose 的 controller/notifier（A7-C2 P1 原文即报此点，阶段A仅修令牌未修生命周期）。另 `_tick` 200ms 高频调用 `playbackSession().snapshot` 并遍历全部行，切歌瞬间 `_load()` 可被连续多帧重入（`_hash` 在 _load 内异步赋值 :76），有重复取数风暴。

建议：`_tick` 开头加 `if (!mounted) return;`；切歌重入用 `_loading` 守卫（_load 开头 `if(_loading) return`）或把 `_hash` 赋值提前到 await 之前；滚动动画改 `_scroll.animateTo` 前再判 `_scroll.hasClients && mounted`。

76 合规：定时轮询属 L7 Widget 生命周期职责（可接受），但缺 dispose 保护是正确性缺陷；数据取数经桥 L5 合规。

---

## C2 · lib/surface/design/mini_bar.dart:21 + player_page.dart:313 + settings_page.dart:156 · P2 · AnimatedBuilder 绑定整播放会话广播，任意 snapshot 字段变化重建整个子树（局部 rebuild 失效）

证据：
```dart
mini_bar.dart:21  AnimatedBuilder(animation: session, builder:...)  // session=PlaybackSession(ChangeNotifier)
player_page.dart:313 AnimatedBuilder(animation: session, ...)      // 整页 Column/ListView 随任意 notify 重建
settings_page.dart:156 AnimatedBuilder(animation: session, ...)    // 仅取 speed，却因 session 任意变更重建整个 ListView
```
问题：三处 AnimatedBuilder 监听的是整个 `PlaybackSession`（progress/播放态/队列/音量/倍速任一变化都 notifyListeners），builder 内重建大片子树。尤其 settings_page 只需 `snapshot.speed` 却整页重建，lyrics 每 200ms 取 position 也经同一 session。虽然 lyrics 用 ValueListenable 做了局部优化，但 player/mini_bar/settings 仍是粗粒度广播重建，播放中进度频繁推进时可引发 rebuild 风暴（用户「动画卡/不经看」的次因）。

建议：为 speed/playing/current 等拆独立 `ValueNotifier` 或用 `selector`/`ValueListenableBuilder` 精确订阅；settings 页 speed 改用局部 ValueListenableBuilder，避免整页 AnimatedBuilder。

76 合规：播放态源于 L6 session（合规）；L7 订阅粒度不当属实现正确性，非层级越界。

---

## C2 · lib/surface/design/tokens.dart:99-106 · P2 · 阶段A tonal pairing 修复不完整：onPrimary/onPrimaryContainer 语义反配，亮色仍不可达可读

证据：
```dart
// tokens.dart:99-106（阶段A P1-8 补的 pairing）
primary: green,                 // #1DB954 饱和品牌绿（非 tonal）
onPrimary: Colors.black,        // 绿底黑字——对比度尚可，但 MD3 要求 primary 为 tonal 色
primaryContainer: greenDim,     // #14833C 深绿容器（暗色）
onPrimaryContainer: text,       // ← 亮色时 text=_textLight=#111111（深字）配深绿容器 greenDim=#14833C → 对比度严重不足
error: red,
onError: Colors.white,
// 且 primary 恒 green 不随 dark/light 变化，primaryContainer 恒 greenDim 不随主题分流
```
问题：阶段A P1-8 虽补齐 `primaryContainer/onPrimaryContainer/onError` 键名，但配对语义错误：① `onPrimaryContainer: text` 在亮色档取深色 `#111` 却配深绿容器 `#14833C`，对比度远低于 4.5:1；② `primary`/`primaryContainer` 不随 dark 分流（亮暗都同一绿/深绿），违反 tonal pairing「成对随亮度反转」原则；③ `primary=green=#1DB954` 仍是非 tonal 饱和品牌绿，阶段A并未真正把 primary 改为 `fromSeed` 派生 tonal 色（因为 copyWith 把它覆盖回 green 了）。属"键补齐但语义未达标"。

建议：亮色 `primaryContainer` 用浅绿 tonal（如 #C8F2D4）、`onPrimaryContainer` 用深绿（#004D1A）；暗色反之。`primary` 不要 copyWith 覆盖 fromSeed 派生的 tonal 值（或显式为每档定义成对 primary/onPrimary/container/onContainer）。

76 合规：ColorScheme 语义角色应成对（L7 ThemeData 职责）；键齐但配对错位属实现正确性，非越级。

---

## 本视角结论（C2 实现正确性）

**发现 11 条：P0 ×3、P1 ×5、P2 ×3。** 核心裁定：

1. **动态取色链 100% 仍断（P0，头号）**：L4 `color_extract`（extractDominant/fromSeed）全仓无调用；L6 `ThemeController` 仅 `ValueNotifier<int>` 存档位、零取色；L7 `Sp.theme` seed 恒 `#1DB954`。阶段A只改令牌/pairing，取色链一行未接——用户「UI 不舒服」根因未触及。
2. **主题切换残废（P0）**：档位 0(系统)误映射强制 dark、3(纯黑)复用暗板不可达；亮色档下 172 处页面 `Sp.*` 静态深色常量绕过 ColorScheme，白底白字/对比度错乱（页面层 colorScheme 引用 = 0）。阶段A的亮色映射只进 ThemeData、没进页面。
3. **两套 ThemeData 分裂（P1）**：错误页 `spLightThemeData()` vs 主页 `Sp.theme()` 双事实源，亮色配色不一致。
4. **阶段A motion 令牌近乎零消费（P1）**：新增 6 档仅定义、唯一动画点仍用旧 `Sp.normal/Sp.curve`，且曲线值/注释/命名三者不自洽；tonal pairing 键补齐但语义反配（P2）。
5. **动画/生命周期**：login 轮询有 mounted+dispose 保护（正面）、MV controller 生命周期完善（正面）；但 lyrics 200ms Timer `_tick` 无 mounted + 切歌重入（P1，A7 已报未修）；player/mini_bar/settings 粗粒度 AnimatedBuilder rebuild 风暴（P2）。
6. **导航**：tabRequest 对非底栏模块（lyrics/comment）死链、albumId/artistId 只写不读（P1/P2）；底栏切换本身（home/search/library/settings indexWhere）可用。

**阶段A修复验证结论**：P1-7(motion)/P1-8(pairing) 仅"令牌层改对"，跨层到页面/运行时未生效；取色链（转 B6）确认完全未修。与 A7-C3「40/100 fail、主题数据被 Sp.* 架空」基线一致，本视角独立确认其实现正确性根因。

## 未覆盖

- 精确 WCAG 对比度数值测量（需真机/工具，本视角只做定性判定）。
- 运行时动画帧率/过渡观感观察（只读静态代码，未跑 dart/flutter——按纪律禁止）。
- 12 页面中 home_state_views/login_account_section/search_tile_widgets/ykg_sheet 未逐行连续读完（仅 rg 抽样 + 关键页精读）；library/home/playlist 以 rg + 关键段为准，未逐行全读。
- `Sp.theme()` 里 splashFactory=InkSparkle、chipTheme/listTileTheme 等子主题在各页的实际视觉呈现（需运行）。
- search_page `_resultF/_suggestF` Future 竞态（旧请求覆盖新结果）仅观察未深挖，留 B2/C1。

## 76 合规小结

- **层级归属**：取色算法在 L4（合规）、主题档位/导航意图在 L6（合规）、ThemeData/页面在 L7（合规）——本次多数问题是**断链与消费错位**，不是越级。
- **跨层接缝问题**：① L6 ThemeController 档位语义 ↔ L7 AppRoot 映射不一致（0/3 塌缩）；② L6 NavState tabRequest/albumId ↔ L7 shell/页面消费者不完整（死链/死字段）；③ L4 取色能力 ↔ L6 控制器 ↔ L7 主题 三段全断；④ L7 双 ThemeData 工厂并存违反单一真源。
- **L7 职责**：页面层用 `Sp.*` 静态色自建配色真源、粗粒度 AnimatedBuilder 持有广播订阅，仍带阶段A已登记的「L7 Widget 内持有状态/定时器/编排」架构债；取色/深链的编排应下沉 L6，本视角仅记录不越权修改。
- **i18n/文案、Layout 自适应、触控目标**属 C1/C3 及其他视角，本视角（实现正确性）未展开。
