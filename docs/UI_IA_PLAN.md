# TiernanMusicNext · UI 信息架构与组件规划（UI_IA_PLAN）

> 状态：**设计规划文档（纯设计，不含 Dart 实现）**
> 版本：v0.1（对应用户给定色彩规范 v0.1）
> 适用范围：`lib/surface/` 全量重写（L7 surface）
> 依赖契约：`docs/SEVEN_SIX_RULE.md`（76 原则：L7 只画控件，不做状态机 / 取数 / IO）
> 现状基线：已通读 `lib/surface/` 全部 20 个文件（design/ 3、shell/app_root 2、pages/ 12、l10n/s.dart、theme/tn_theme.dart）

---

## 0. 现状审计结论（重写的起点）

### 0.1 现状事实

| 现状 | 位置 | 问题 |
|---|---|---|
| 令牌是 **static const 深色值**（`Sp.bg=#0E0F12`、`Sp.text=#EDEFF2`、`Sp.green=#1DB954`） | `design/tokens.dart` | 与给定森林翡翠绿规范完全不符；且 `const` 化导致主题切换只对 `context.cs.*` 生效，硬编码 `Sp.*` 的地方不跟随 |
| 主题靠 `ColorScheme.fromSeed(seed)` 派生 + 动态取色 | `design/tokens.dart` / `app_root.dart` | 用户要求"一套内部设计语言"，不做动态取色；语义 token 与 fromSeed 派生混用 |
| 外壳 **硬编码深色底栏**（`_buildBottomBar` 内构造一份独立 `ColorScheme.fromSeed`） | `shell.dart` | 亮色模式下底栏仍是深色（已知"底栏浅色块"回归的根因之一） |
| 底栏 = `NavigationBar` 5 项（home/search/playlist/library/settings） | `shell.dart` + 各页 `NavEntry` | 结构已符合"底栏 5 tab"，但由 `ModuleRegistry` 顺序驱动、不可控 |
| 自写控件 9 个 | `design/components.dart`、`design/mini_bar.dart` | `SpCover / SpSongTile / SpSectionHeader / SpSkeleton / SpListSkeleton / SpStateView / SpPlayButton / SpRoundButton / SpMiniBar` |
| 页面内自写控件 ~15 个 | `pages/*` | `HomeSkeletonBox/HomeEmptyBox/HomeErrorRetry`、`SearchSongTile/SearchEmptyBox/SearchErrorRetry`、`PlaylistGridCard/PlaylistEmptyBox/PlaylistErrorRetry`、`_Cover/_SongCard/_RankCard/_MineRow/_TrackRow`、`FavoriteButton`、`_SeekSlider`、`AccountSection` |
| 弹层型"详情"（歌单详情） | `playlist_page.dart` `PlaylistDetailSheet` | 桌面端用 bottom sheet 承载详情不合适 → 应升级为路由页 |
| 播放页/歌词页/错误页 | `player_page.dart`、`lyrics_page.dart`、`init/main.dart` `_BootErrorApp` | 歌词页被 `navState().requestTab('lyrics')` 调用，但 `LyricsPageModule.navEntry == null` → **现有链路有断点**，本规划改为正式路由 |
| 拖拽 seek | `_SeekSlider` | 逻辑正确（拖动预览、松手 seek），可保留为官方 `Slider` + `onChanged/onChangeEnd` |
| 无键盘/焦点处理 | 全局 | 桌面端 Tab 顺序、快捷键、焦点环全部缺失 |

### 0.2 新增依赖（本次重写必须新增，`pubspec.yaml` 现无）

- `get: ^4.6.6`（GetWidget：`GetMaterialApp` / `Get.to` / `Obx` / `Get.snackbar` / `Get.bottomSheet` / `Get.put` / `Get.find`）
- `bitsdojo_window: ^0.11.0`（仅桌面端；`bitsdojo_window` 提供 `WindowTitleBar` 控件与 `windowManager` 能力）

> 76 原则适配：`get` 的 Controller **不放 L7**。Controller 由 L6 `session` 层定义并经 `bridge_session` 暴露；L7 只做 `Obx(() => ...)` 绑定与 `Get.toNamed` 等导航调用。

---

## 1. 信息架构（IA）

### 1.1 全平台统一的路由表

所有平台共用一套命名路由（GetX `getPages`）。移动端与桌面端**路由图完全一致**，只有导航容器形态不同。

| 路由名 | 页面 | 容器归属 | 进入方式 | 返回方式 |
|---|---|---|---|---|
| `/home` | 首页 | 主 tab | 启动默认 / 底栏 1 / 侧栏 1 | 不可返回（根） |
| `/search` | 搜索 | 主 tab | 底栏 2 / 侧栏 2 / 首页搜索按钮 / `Ctrl+F` | 不可返回（根） |
| `/playlist` | 歌单（推荐/我的） | 主 tab | 底栏 3 / 侧栏 3 | 不可返回（根） |
| `/library` | 音乐库（本地/最近/下载） | 主 tab | 底栏 4 / 侧栏 4 | 不可返回（根） |
| `/settings` | 设置 | 主 tab | 底栏 5 / 侧栏 5 | 不可返回（根） |
| `/player` | 播放页 | 非底栏（模态） | 迷你条点击 / 歌单行双击 / `Space` 后 `Enter` | `Get.back()` / `Esc` |
| `/lyrics` | 歌词页 | 非底栏（模态） | 播放页 ⋮→歌词 / 播放页歌词图标 / `Ctrl+L` | `Get.back()` / `Esc` |
| `/mv` | MV 页 | 非底栏（模态） | 播放页 ⋮→查看 MV | `Get.back()` / `Esc` |
| `/playlist/detail` | 歌单详情 | 非底栏（层级页） | 首页推荐卡 / 歌单页网格卡 / 搜索结果 | `Get.back()` / `Esc` |
| `/account` | 账号与登录 | 非底栏（层级页） | 设置页"扫码登录"/ 音乐库页账号卡 | `Get.back()` / `Esc` |
| `/error` | 错误页 | 独立（无导航壳） | 启动失败 / 路由守卫失败 | 仅"重试"/"退出" |

### 1.2 底栏 5 tab 的层级关系

```
AppShell (Scaffold + 导航容器)
├── Tab 内容区 (IndexedStack / GetX offstage)
│   ├── /home    首页
│   ├── /search  搜索
│   ├── /playlist 歌单(TabBar: 推荐 / 我的)
│   ├── /library 音乐库(TabBar: 本地曲库 / 最近播放 / 下载管理)
│   └── /settings 设置
└── NowPlayingBar（迷你播放条）
    └── 点击 → /player (模态)

非底栏页栈（Navigator 嵌套于 Tab 内容之上）
/player ──┬── /lyrics
          └── /mv
/playlist/detail
/account
```

**现状偏差修正（必须做）**：
- 现状用 `MaterialPageRoute` + `Navigator.push` 混用 `showModalBottomSheet` 承载歌单详情。新规划统一为 GetX 命名路由 + `Get.toNamed`。
- 现状 `navState().requestTab('lyrics')` 对非底栏模块无效 → 新规划中 `lyrics` 为独立路由。

### 1.3 移动端 vs 桌面端的 IA 差异

**结论：移动端用底栏（`NavigationBar`），桌面端用左侧 `NavigationRail`（≥1000 宽时 `extended: true`），不做"桌面也用底栏"。**

理由：
1. **桌面端指针优先**：鼠标有精确 hover/右键/悬停预览，底栏把 5 个高频入口挤在屏幕最底部、鼠标必须"下坠"，是移动端手势范式；`NavigationRail` 是桌面应用通行范式（VS Code / JetBrains / Figma 均为左栏）。
2. **桌面端窗口可缩放**：底栏 80dp 在最小窗口高度（600px）下会吃掉 13% 垂直空间；左栏只吃 80dp **宽度**，垂直空间完整留给内容与迷你条。
3. **桌面端窗口标题栏已占用顶部 32-36dp**，左栏正好承接"导航"，右侧留给内容；形成"标题栏 → 侧栏 → 内容"三段式，符合 Windows/macOS 桌面心智。
4. **键盘可达性**：`NavigationRail` 目的地是标准 `FocusableActionDetector` 焦点节点，Tab 序列自上而下，符合桌面读屏顺序；底栏 5 个 tab 在 Tab 序列里横排且离内容区远。
5. **Web 折叠**：`NavigationRail` 在窄窗口可自动退化为 `NavigationBar`（见 §5 断点），一套组件两种形态，无需维护两套导航。

| 维度 | 移动（compact <600） | 桌面（expanded >1000） |
|---|---|---|
| 主导航 | `NavigationBar`（bottom，5 项，80dp） | `NavigationRail`（left，80dp 收窄 / ≥1240 展开 200dp） |
| 迷你播放条 | 底栏**上方**吸底横条（56dp） | 底栏整宽横条（64dp，含进度条与更多控制），**不遮挡内容**（内容 padding 预留） |
| 播放页 | 全屏模态（`fullscreenDialog`，从下滑落） | **右侧分栏面板**（宽 380-420dp）而非全屏模态；`/player` 以 `Get.to` 打开分栏而非覆盖全屏 |
| 歌词页 | 全屏模态 | 右侧分栏内切换（Tab：信息 / 歌词 / 队列） |
| 歌单详情 | 全屏路由页（从底部推入） | 居中路由页 / 宽内容区（最大 1200dp） |
| 标题栏 | 系统原生 | **自绘标题栏**（bitsdojo_window） |
| 模态呈现 | `showModalBottomSheet`（Drag） | `Dialog`（居中，最大 560dp） |

> **建议（结论性）**：桌面端**保留底栏**的替代方案是"底栏 + 右侧 Now Playing 面板"，但会造成"导航在底部、播放在右侧"的割裂；本规划选择 **左栏 NavigationRail + 底部 Now Playing 横条**，两端对称、符合桌面规范。

---

## 2. 页面组件树（伪代码 · 官方 M3 控件 + GetWidget 能力）

> 标注约定：
> `[M3:控件名]` = Flutter 官方 Material 3 控件
> `[Get:能力]` = get 包能力（`GetMaterialApp` / `Obx` / `Get.toNamed` / `Get.snackbar` / `Get.bottomSheet` / `Get.dialog` / `Get.find<T>()`）
> `[token:名称]` = 消费的语义 token（见 §2.0）
> `[L6:门面]` = 数据来源（L6 session，经 bridge_session），L7 不取数

### 2.0 语义 token 契约（重写后的 `design/tokens.dart` 目标形态）

**唯一事实源：`design/tokens.dart` 内的 `TnTokens`（Light/Dark 成对 `ThemeExtension` 或两套 `ColorScheme` 工厂）。**

Primitive（仅供语义层引用，不直接进页面）：
```
green-900 #0B1F14  green-800 #102A18  green-700 #1B5E20  green-600 #2F5D50
green-500 #52B788  green-300 #B7E4C7  green-200 #D8F3DC  green-100 #E8F5EC
green-50  #F1F8F4  neutral-0 #FFFFFF  neutral-900 #0B1F14
```

语义 token → M3 `ColorScheme` 角色映射（**页面只认 M3 角色名，token 是角色的中文别名**）：

| 语义 token | Light | Dark | M3 角色 |
|---|---|---|---|
| bg.canvas | #F1F8F4 | #0B1F14 | `scaffoldBackgroundColor` / `surface`（低层） |
| bg.surface | #FFFFFF | #102A18 | `surface` |
| bg.container | #D8F3DC | #17332A | `surfaceContainer` |
| bg.containerHigh | #B7E4C7 | #1F4432 | `surfaceContainerHigh` |
| primary | #1B5E20 | #A7F3D0 | `primary` |
| onPrimary | #FFFFFF | #0B1F14 | `onPrimary` |
| secondary | #52B788 | #52B788 | `secondary`（`onSecondary` = #0B1F14 双档） |
| text.primary | #102A18 | #E8F5EC | `onSurface` |
| text.secondary | #4A6B55 | #A8C5B2 | `onSurfaceVariant` |
| text.disabled | #9BB5A3 | #5C7A66 | `onSurface` @ 38% 透明度 **或** `outline` |
| outline | #6B8F76 | #4F6F5A | `outline` / `outlineVariant`(#6B8F76 @ 40%) |
| focus | #2F5D50 | #A7F3D0 | `focusColor`（自建 `FocusTheme`） |
| success | #2F7D4A | #7DD3A0 | `tertiary` |
| warning | #9A6700 | #F5C542 | `tertiaryContainer`（浅档） |
| error | #B3261E | #F2B8B5 | `error` |
| info | #0B6BCB | #8EC5FF | `secondaryContainer` |
| onError | #FFFFFF | #601410 | `onError` |

标题栏独立 token（**不进 ColorScheme，独立 `TitleBarTheme` / `TitleBarTokens`**）：
```
titlebar.bg          #1B5E20 / #0B1F14
titlebar.fg          #E8F5EC / #A7F3D0
titlebar.button.hover #2F5D50 / #17332A
titlebar.close.hover  #B3261E / #F2B8B5
titlebar.inactive    #6B8F76 / #4F6F5A
```

**强制规则**：
- 页面中出现的**任何**颜色必须来自 `Theme.of(context).colorScheme` 或 `TnTokens.of(context)`，禁止字面量（现状 `_RankCard` 的 `Colors.black`、search 的 `Colors.black`、`_PlayButton` 的 `Colors.black` 全部要清除）。
- 深色档不出现纯黑 `#000000`（除 OLED 档可选，本次不设 AMOLED 档）；浅色档不出现纯白 `#FFFFFF` 之外的 `surface` 纯白块以外无纯白底。**浅色 `bg.surface = #FFFFFF` 是允许且必需的**（规范给定）。
- 语义状态色不得单独承担语义，必须配图标或文案。

### 2.1 AppRoot（应用根）

```
AppRoot (StatefulWidget)                         [L6:ThemeController / LocaleController 广播]
└── GetMaterialApp                               [Get:GetMaterialApp]
    ├── title: 'TiernanMusicNext'
    ├── theme:     TnTheme.light                  [token:bg.canvas/#FFFFFF …]
    ├── darkTheme: TnTheme.dark                   [token:bg.canvas/#0B1F14 …]
    ├── themeMode: ThemeMode.light/dark           [无「纯黑」档；无动态取色]
    ├── locale: LocaleController 派生
    ├── initialRoute: '/home'
    ├── getPages: [ /home /search /playlist /library /settings
    │               /player /lyrics /mv /playlist/detail /account /error ]
    ├── unknownRoute: GetPage('/error', 404)      [M3: Scaffold + 错误态]
    └── defaultTransition: Transition.cupertino    [移动端]
        desktop/tablet: Transition.fadeIn
```

- **现状差异**：现状 `themeMode` 有 4 档（0 默认暗 / 1 亮 / 2 暗 / 3 纯黑），且"默认"档强制暗色 → 新规划改为**两档**（跟随系统 / 强制亮 / 强制暗 共 3 档，取消纯黑），符合"明暗双主题"。
- 主题切换无闪烁：`MaterialApp` 的 `theme/darkTheme` 切换由 Flutter 内部 `AnimatedTheme` 处理；**要求** `ThemeController` 变更后不重建 `GetMaterialApp` 本体（避免路由栈重建），仅替换 `theme`/`darkTheme` 引用。

### 2.2 AppShell（外壳 · 底栏/侧栏 + 迷你条）

```
AppShell (StatefulWidget)
└── Scaffold                                      [M3:Scaffold]  backgroundColor: cs.surface(=bg.canvas)
    ├── body: SafeArea(bottom:false)
    │   └── Row                                  [仅 expanded]
    │       ├── NavigationRail                   [M3:NavigationRail]  extended: width>=1240
    │       │   ├── labelType: extended|none
    │       │   ├── backgroundColor: cs.surface  [token:bg.surface]
    │       │   ├── indicatorColor: cs.primaryContainer [token:bg.containerHigh]
    │       │   └── destinations: 5 × NavigationRailDestination
    │       │       icon / selectedIcon / label / padding
    │       └── Expanded:
    │           └── GetX<ShellController>        [Get:GetX + Obx]
    │               └── Obx(() => IndexedStack(   [M3:IndexedStack] 保持各 tab 状态
    │                     index: shellController.tabIndex,
    │                     children: [HomePage, SearchPage, PlaylistPage, LibraryPage, SettingsPage]))
    │   └── Column                              [仅 compact]
    │       ├── Expanded(IndexedStack 同上)
    │       └── NowPlayingBar                    [M3: Material + InkWell]  ← 替换 SpMiniBar
    │           ├── Container(color: cs.surfaceContainer)  [token:bg.container]
    │           ├── Row: Cover(40dp) + 歌名/歌手 + IconButton(play/pause) + IconButton(next)
    │           └── 整条 InkWell onTap → Get.toNamed('/player')  [M3:InkWell ripple]
    └── bottomNavigationBar: NavigationBar      [仅 compact]
        ├── selectedIndex / onDestinationSelected → shellController.setTab(i)
        ├── backgroundColor: cs.surface          [token:bg.surface]
        ├── indicatorColor: cs.primaryContainer  [token:bg.containerHigh]
        └── destinations: 5 × NavigationDestination
```

**关键修正**：现状 `shell.dart` 用 `Theme(data: ThemeData(...dark...))` 局部锁死深色底栏 → **删除**，改为全量走 `cs.*`，亮色模式下底栏为 `bg.surface=#FFFFFF`、指示器 `bg.containerHigh=#B7E4C7`、文字 `text.primary`。
**现状 `backgroundColor: const Color(0xFF0E0F12)` 硬编码 → 改 `cs.surface`。**

### 2.3 HomePage（首页）

```
HomePage (StatefulWidget)                        [L6:HomeController 经 bridge]
└── Scaffold(backgroundColor: cs.surface)        [token:bg.canvas]
    ├── AppBar                                    [M3:AppBar]  bg=cs.surface, elevation=0
    │   ├── title: Text('首页', headlineSmall)    [token:text.primary]
    │   └── actions: IconButton(Icons.search, tooltip:'搜索')
    │              → Get.find<ShellController>().setTab(1) / Get.toNamed('/search')
    └── body: CustomScrollView                   [M3:CustomScrollView]
        ├── SliverToBoxAdapter → SectionHeader('每日推荐')   [替换 SpSectionHeader]
        │     └── Row: Expanded(Text(titleLarge, text.primary))
        │              + TextButton('更多', style: TextButton.styleFrom(foregroundColor: cs.primary))
        ├── SliverToBoxAdapter → Obx(() => ...) 三区块横滑
        │   ├── loading → SliverToBoxAdapter(SkeletonList)  [M3 方案见 §2.3.1]
        │   ├── error   → SliverToBoxAdapter(ErrorBanner)    [M3:Card + Icon + Text + TextButton('重试')]
        │   ├── empty   → SliverToBoxAdapter(EmptyState)    [M3: 见 §3]
        │   └── data    → SliverToBoxAdapter(SizedBox(h:176, child: ListView(horizontal)))
        │                └── SongCard × N   [M3:Card + InkWell + ClipRRect(Image.network)]
        │   ├── SectionHeader('推荐歌单') → PlaylistCard(150dp 宽, AspectRatio 1 封面)
        │   └── SectionHeader('排行榜')   → RankCard(120×110, InkWell)
        └── SliverPadding(bottom: 24)
```

**2.3.1 三态官方控件方案（全局统一，全页复用）**

| 状态 | 官方控件组合 | 表达方式 |
|---|---|---|
| 加载 | `[M3:LinearProgressIndicator]`（列表级，贴顶 2dp）+ `[M3:Skeleton]`（**Flutter 3.16+ 无官方 Skeleton 控件**）→ 用 `[M3:CircularProgressIndicator]` + `[M3:ListTile]`/`[M3:Card]` 占位或 `[M3:RefreshProgressIndicator]` | 列表区：占位卡片用 `Card` + `cs.surfaceContainer` 底色 + `LinearProgressIndicator` 顶部条；整页等待：`Scaffold` + 居中 `CircularProgressIndicator` |
| 空 | `[M3:Icon]` + `[M3:Text]` + `[M3:TextButton]/[M3:FilledButton]` 居中列 | 语义 token `text.secondary`；图标 40dp |
| 错误 | `[M3:Icon(Icons.error_outline)]` + `[M3:Text]`（`cs.error`）+ `[M3:TextButton('重试')]` | **错误色必配图标**，不只靠颜色 |

> Flutter 官方**没有** Skeleton 控件，因此"骨架屏"必须由官方控件组合实现：`Card`/`Container` + `cs.surfaceContainer` 填充 + `LinearProgressIndicator`。这属于"用官方控件组合"，不算自绘控件。`SpSkeleton/SpListSkeleton/HomeSkeletonBox` 因此删除。

### 2.4 SearchPage（搜索）

```
SearchPage (StatefulWidget)                       [L6:SearchController]
└── Scaffold(backgroundColor: cs.surface)
    ├── body: Column
    │   ├── Padding(top:12, l/r:16)
    │   │   └── Row
    │   │       ├── Expanded → SearchBar                       [M3:SearchBar]  ★替换手写 Container+TextField
    │   │       │   ├── hintText: '搜索歌曲、歌单、歌手'   [token:text.secondary]
    │   │       │   ├── leading: Icon(Icons.search)          [token:text.secondary]
    │   │       │   ├── trailing: [M3:IconButton] × N (清空/语音)
    │   │       │   ├── onChanged: controller.suggest(text) → Obx 拉建议
    │   │       │   └── onSubmitted: controller.search(q)
    │   │       └── SizedBox(48) → IconButton.filled            [M3:IconButton.filled]
    │   │               icon: Icons.arrow_forward
    │   │               style: IconButton.styleFrom(backgroundColor: cs.primary,
    │   │                                          foregroundColor: cs.onPrimary)
    │   ├── Obx(() => suggest.isEmpty ? SizedBox.shrink()
    │   │        : ConstrainedBox(maxHeight:208,
    │   │            child: ListView(children: [M3:ListTile] × N  ← SearchSongTile 替换)))
    │   └── Expanded → Obx(() {
    │         if (query.isEmpty) → IdleBody
    │         else → Column
    │           ├── TabBar / SegmentedButton                    [M3:TabBar]  5 段：歌曲/歌单/专辑/歌手/歌词
    │           │     indicator: cs.primary, label: text.primary, unselected: text.secondary
    │           └── Expanded → 结果 ListView
    │                 └── M3:ListTile (leading: ClipRRect 48dp 封面,
    │                                  title: 歌名, subtitle: 歌手,
    │                                  trailing: Row[IconButton(album), Text(duration)])
    │        })
    └── 底部：热门分类 Wrap( ActionChip × 8 ) / 历史记录 Wrap( ActionChip × N + TextButton('清空') )
```

- **替换要点**：现状手写的 `Container(borderRadius: rFull)+Row+TextField` → **`M3:SearchBar`**；手写圆形 `Material+InkWell+Icon` → **`M3:IconButton.filled`**；`ChoiceChip` 横排 → **`M3:TabBar`**（分段切换，`M3:SegmentedButton` 备选，宽度不足时用 TabBar）。
- 现状 `ChoiceChip` 的 `Colors.black` 文字 → 改 `cs.onPrimary`。

### 2.5 PlaylistPage（歌单 · 主 tab 3）

```
PlaylistPage
└── DefaultTabController(length:2)                 [M3:DefaultTabController]
    └── Scaffold(backgroundColor: cs.surface)
        ├── TabBar                                  [M3:TabBar]  indicator: cs.primary(3dp)
        │   ├── Tab('推荐')  Tab('我的')
        └── Expanded → TabBarView
            ├── _RecommendTab
            │   ├── Obx 三态：
            │   │   ├── loading → M3:CircularProgressIndicator
            │   │   ├── error   → ErrorState(Icon + Text(cs.error) + TextButton('重试'))
            │   │   ├── empty   → EmptyState(Icon(Icons.queue_music) + Text)
            │   │   └── data    → GridView.builder
            │   │         └── PlaylistCard  [M3:Card + InkWell + ClipRRect(AspectRatio 1 封面)
            │   │                                 + Text(name) + Text(count, text.secondary)]
            │   └── 点击 → Get.toNamed('/playlist/detail', arguments: playlistId)
            └── _MineTab
                └── ListView → M3:ListTile(leading 封面 48dp, title, subtitle 'N 首',
                                           trailing: Icon(Icons.chevron_right))
```

### 2.6 PlaylistDetailPage（歌单详情 · 非底栏）

```
PlaylistDetailPage(route '/playlist/detail')
└── Scaffold(backgroundColor: cs.surface)
    ├── SliverAppBar(expandedHeight: 240)          [M3:SliverAppBar] pinned: true
    │   ├── FlexibleSpaceBar(background: 封面大图 + 渐变遮罩,
    │   │                     title: 歌单名, titleStyle: text.primary)
    │   └── actions: IconButton(Icons.more_vert)   [M3:IconButton]
    └── body: Obx 三态
        ├── loading → M3:CircularProgressIndicator
        ├── error/empty → ErrorState / EmptyState
        └── data → ListView.builder
              └── M3:ListTile(leading: SizedBox(28, Text('#${index+1}')),
                               title: 歌名, subtitle: 歌手,
                               trailing: IconButton(album))
```

- **与现状差异**：现状 `PlaylistDetailSheet`（`DraggableScrollableSheet`）**只在移动端保留为全屏路由**；桌面端用本页居中布局（最大宽 1200dp 居中）。
- 歌单详情的**操作条**：`[M3:FilledButton.icon(Icons.play_arrow,'播放全部')]` + `[M3:OutlinedButton.icon(Icons.download,'下载')]` + `[M3:IconButton(shuffle)]`。

### 2.7 LibraryPage（音乐库 · 主 tab 4）

```
LibraryPage
└── Scaffold(backgroundColor: cs.surface)
    ├── body: Column
    │   ├── AccountHeaderCard                       [M3:Card]  ★替换 _accountCard 手写
    │   │   ├── leading: ClipOval(48dp 头像, fallback Icon(Icons.person, cs.surfaceContainerHigh))
    │   │   ├── title: Text(昵称, titleMedium)
    │   │   ├── subtitle: Text('ID xxx · 我喜欢 N', bodySmall, text.secondary)
    │   │   └── trailing: M3:FilledButton / M3:TextButton → Get.toNamed('/account')
    │   ├── TabBar                                  [M3:TabBar]
    │   │   ├── Tab('本地曲库') Tab('最近播放') Tab('下载管理')
    │   └── Expanded → TabBarView
    │       ├── 本地曲库 / 最近播放 → 统一三态列表
    │       │   ├── loading → M3:LinearProgressIndicator
    │       │   ├── error   → ErrorState(Icon + Text(cs.error) + TextButton('重试'))
    │       │   ├── empty   → EmptyState(Icon + title + subtitle)
    │       │   └── data    → ListView.builder(M3:ListTile × N)
    │       └── 下载管理 → ListView.builder(M3:ListTile(
    │                 leading: 48dp 封面,
    │                 title: 文件名, subtitle: '音质 · 状态',
    │                 trailing: SizedBox(width:48, child: M3:LinearProgressIndicator(value))))
```

### 2.8 SettingsPage（设置 · 主 tab 5）

```
SettingsPage
└── Scaffold(backgroundColor: cs.surface)
    └── body: ListView(padding: v12)                [M3:ListView]
        ├── SectionHeader('账号')                    [M3:ListTile 组成的 group 卡]
        │   └── _GroupCard → M3:ListTile(leading Icon, title '已登录/未登录',
        │                                   subtitle, trailing FilledButton('扫码登录')/TextButton('登出'))
        ├── SectionHeader('外观')
        │   └── _GroupCard
        │       ├── Text('主题模式')
        │       ├── M3:SegmentedButton<int>(segments: 跟随系统 / 亮 / 暗)   [M3:SegmentedButton]
        │       ├── Text('界面语言')
        │       └── M3:DropdownMenu<String>  或  M3:DropdownButtonFormField
        ├── SectionHeader('播放')
        │   └── _GroupCard → M3:ListTile('音质', trailing Icon(chevron_right))
        │                      → M3:ListTile('倍速', trailing Icon(chevron_right))
        ├── SectionHeader('存储')
        │   └── _GroupCard → M3:ListTile('清理缓存', trailing M3:FilledButton('清理'))
        └── SectionHeader('关于')
            └── _GroupCard → M3:ListTile('版本', trailing Text(kAppVersion))
```

- **官方化**：`_group()` 的 `Container+BoxDecoration` 分组卡 → **`M3:Card`**（`Card.filled` / `Card.outlined`，`color: cs.surfaceContainer`，`shape: RoundedRectangleBorder(radius 12)`）。
- 音质/倍速弹层：`M3:ListTile` + `trailing: Icon(Icons.check, cs.primary)` 选中标记；容器用 `M3:AlertDialog`（桌面）或 `M3:ModalBottomSheet`（移动）。
- 主题分段：现状 4 档（默认/亮/暗/纯黑）→ **3 档（跟随系统/亮/暗）**。

### 2.9 PlayerPage（播放页 · 非底栏）

```
PlayerPage                                          [L6:PlaybackSession 快照]
└── Scaffold(backgroundColor: cs.surface)
    ├── AppBar (mobile) / 自定义顶栏
    │   ├── IconButton(Icons.keyboard_arrow_down, tooltip:'收起') → Get.back()
    │   ├── Spacer
    │   ├── FavoriteButton  → M3:IconButton(favorite / favorite_border,
    │   │                      color: collected? cs.primary : cs.onSurfaceVariant)
    │   └── IconButton(Icons.more_vert) → M3:showModalBottomSheet / M3:showDialog
    │         └── M3:ListTile × 5 (歌词/评论/查看MV/下载/个人FM)
    ├── Obx(() => snap.error.isEmpty ? SizedBox.shrink()
    │      : Card(color: cs.surfaceContainerHigh)                  [token:bg.containerHigh]
    │          Row[ Icon(Icons.error_outline, cs.error)             ← 错误色必配图标
    │               Expanded(Text(errText))
    │               TextButton('重试', foregroundColor: cs.primary) ])
    ├── Expanded
    │   └── Column
    │       ├── Hero 封面  → ClipRRect(radius 20) + Image.network
    │       │                 placeholder/err: cs.surfaceContainerHigh
    │       ├── Text(歌名, headlineSmall, text.primary)
    │       ├── Text(歌手, bodyMedium, text.secondary)
    │       ├── SeekSlider                            [M3:Slider]  ★替换 _SeekSlider
    │       │   ├── value/max: 播放位置/总时长
    │       │   ├── activeColor: cs.primary, inactiveColor: cs.outlineVariant
    │       │   ├── onChanged: 本地预览值（不 seek）    ← 保留现状正确设计
    │       │   └── onChangeEnd: controller.seek(v)
    │       ├── Row [Text(位置, text.secondary), Spacer, Text(时长, text.secondary)]
    │       ├── Controls Row
    │       │   ├── M3:IconButton(shuffle, selected? cs.primary)     ← SpRoundButton 替换
    │       │   ├── M3:IconButton(skip_previous)
    │       │   ├── M3:IconButton.filled(size: 64, shape: Circle)    ← SpPlayButton 替换
    │       │   │     icon: play_arrow / pause, bg: cs.primary, fg: cs.onPrimary
    │       │   ├── M3:IconButton(skip_next)
    │       │   └── M3:IconButton(repeat, selected? cs.primary)
    │       └── Badges Row: M3:ActionChip(倍速) + M3:ActionChip(音质)
    └── 桌面：Expanded 后并列右侧面板 Column[ 信息 / 歌词 / 队列 TabBar ]
```

> `SpPlayButton` 现状 `Colors.black` → 改 `cs.onPrimary`；`SpRoundButton` 的 `active` 态 → `IconButton.styleFrom(foregroundColor: cs.primary)`。

### 2.10 LyricsPage（歌词页 · 非底栏）

```
LyricsPage                                          [L6:LyricsController]
└── Scaffold(backgroundColor: cs.surface)
    ├── AppBar / 顶栏
    │   ├── IconButton(Icons.arrow_back_ios_new) → Get.back()
    │   └── M3:SegmentedButton<bool>(原文 / 翻译)   [无译文时 onSelectionChanged: null → 禁用态]
    └── body: Obx 三态
        ├── loading → M3:LinearProgressIndicator + 占位行 Card × 8
        ├── error   → ErrorState(Icon(Icons.lyrics_outlined) + Text + TextButton('重试'))
        ├── empty   → EmptyState(Icon + '暂无歌词')
        └── data → ListView.builder(controller: scrollCtrl, itemExtent≈44)
              └── ValueListenableBuilder<int>(activeIndex)   [局部重绘，避免整页 200ms 重建]
                    Text(line, 当前行: titleMedium/w700/cs.primary；
                                其他行: bodyMedium/cs.onSurfaceVariant)
                    + 译文行（双语模式）
```

- **性能契约（保留现状设计）**：200ms 轮询位置 → 只更新"当前行索引" `ValueNotifier`；`ValueListenableBuilder` 局部重绘。
- **滚动**：`animateTo(idx*44 - 160)`，`duration: 300ms`，`curve: Curves.easeOutCubic`。

### 2.11 MvPage（MV 页 · 非底栏）

```
MvPage                                               [L6:MvController]
└── Scaffold(backgroundColor: cs.surface)
    ├── AppBar(title: Text('MV'), bg: cs.surface)
    └── body: Obx(_phase)
        ├── loading → Column[ M3:CircularProgressIndicator, Text('正在加载 MV…') ]
        ├── empty   → EmptyState(Icon(Icons.movie) + Text + TextButton('重试'))
        ├── error   → ErrorState(Icon(Icons.error_outline) + Text(cs.error) + TextButton('重试'))
        └── ready → Column
            ├── ClipRRect(radius 12) → AspectRatio(videoAspect) → M3:VideoPlayer
            ├── M3:VideoProgressIndicator(played: cs.primary, background: cs.outlineVariant)
            └── Row[ M3:IconButton(play/pause, cs.primary), Text('档位 xxx', text.secondary) ]
```

### 2.12 AccountPage（账号与登录 · 非底栏）

```
AccountPage (route '/account')
└── Scaffold(backgroundColor: cs.surface)
    ├── AppBar(title: Text('账号'), leading: IconButton(back))
    ├── TabBar                                      [M3:TabBar] 4 段
    │   ├── Tab('扫码登录') Tab('验证码') Tab('密码') Tab('YKG 链接')
    ├── TabBarView
    │   ├── _QrTab
    │   │   ├── Center(Image.memory(qr, 200×200) | 占位 Card + CircularProgressIndicator)
    │   │   ├── Text(_hint, bodyMedium, text.secondary)   ← 扫码四态文案
    │   │   └── M3:TextButton('刷新二维码')
    │   ├── _SmsTab
    │   │   ├── M3:TextField(手机号, keyboardType: phone)  [M3:TextField/InputDecoration]
    │   │   ├── Row[ Expanded(M3:TextField(验证码, number)),
    │   │   │         M3:TextButton(倒计时 '59s' / '发送验证码', onPressed: null 倒计时中)]
    │   │   └── M3:FilledButton('登录')
    │   ├── _PwdTab
    │   │   ├── M3:TextField(账号) / M3:TextField(密码, obscureText, suffixIcon: 显示/隐藏)
    │   │   └── M3:FilledButton('登录')
    │   └── _YkgTab → M3:FilledButton.icon(导入) + M3:OutlinedButton.icon(导出)
    │              + 风险提示 Card(cs.surfaceContainerHigh + Icon(warning, cs.error) + Text)
    └── AccountSection（已登录账号列表）
        └── M3:ListTile(leading Icon(person/person_outline, active? cs.primary : text.secondary),
                        title: displayName, subtitle: '账号 xxx',
                        trailing: M3:IconButton(delete_outline, tooltip:'移除账号'))
```

- **移动端形态**：现状是 `showModalBottomSheet(height: 70%)`；新规划在移动端保留"底部弹层 + 内部 TabBar"，在桌面端用 **`M3:Dialog`（maxWidth 560）**。为避免两套代码，**统一用 `/account` 路由 + 移动端用 `Get.bottomSheet` 包装同一 `AccountPanel` Widget**。
- **凭据安全**：手机号脱敏 `138****1234`（保留现状 `login_sheet.dart` 的 `_maskPhone`），token 不回显。

### 2.13 ErrorPage（错误页）

```
ErrorPage(route '/error')
└── Scaffold(backgroundColor: cs.surface)
    └── Center → ConstrainedBox(maxWidth: 480)
        └── Column
            ├── Icon(Icons.error_outline, size: 48, color: cs.error)   ← 错误必配图标
            ├── Text(title '出错了', headlineSmall, text.primary)
            ├── Text(detail, bodyMedium, text.secondary, textAlign: center)
            └── Row[ M3:FilledButton('重试'), M3:TextButton('退出') ]
```

- **启动失败页**：现状在 `lib/init/main.dart` 的 `_BootErrorApp`（L1 层）。新规划：L1 仍保留兜底，但改为复用同一 `ErrorPage` 视觉规范（L1 允许 import `bridge_surface` 的错误页工厂，不破坏分层）。
- **路由 404**：`GetMaterialApp.unknownRoute` → `/error`。

### 2.14 桌面标题栏（DesktopTitleBar）

```
DesktopTitleBar                                      [仅桌面平台；bitsdojo_window]
└── WindowTitleBar                                  [bitsdojo_window:WindowTitleBar]
    ├── setTitleBarStyle(TitleBarStyle(titleBarHeight: 36, buttonBackgroundColors: …))
    ├── Row
    │   ├── SizedBox(width: 8)
    │   ├── Icon(logo 16dp) + Text('TiernanMusicNext', titleSmall)
    │   │       color: cs.titlebarFg           [token:titlebar.fg]
    │   ├── Expanded → GestureDetector(onHorizontalDrag → windowManager.startMove())  ← 可拖拽区
    │   │       + 可选：当前页标题 Text
    │   ├── WindowButton(minimize)               [bitsdojo_window:WindowButton]
    │   ├── WindowButton(maximize/restore)       [bitsdojo_window:WindowButton]
    │   └── WindowButton(close)                  [bitsdojo_window:WindowButton]
    │           hover 背景: cs.titlebarCloseHover  [token:titlebar.close.hover]
    └── 背景: cs.titlebarBg                     [token:titlebar.bg]
        失焦时: cs.titlebarInactive             [token:titlebar.inactive]
```

详见 §6。

---

## 3. 交互逻辑（三态 / 操作序列 / 手势 / 键盘 / 滚动）

### 3.1 三态统一规范

| 状态 | 判定 | 呈现（官方控件） | 颜色 token | 可用操作 |
|---|---|---|---|---|
| 加载 | Future 未完成 / `ConnectionState != done` | 整页：`CircularProgressIndicator` 居中；列表：`LinearProgressIndicator` + `Card` 占位块；可下拉刷新时加 `M3:RefreshIndicator` | `cs.primary` | 无 |
| 空 | 数据到达且长度为 0 | `Icon(40dp, cs.onSurfaceVariant)` + `Text(title, titleMedium, text.primary)` + `Text(subtitle, bodySmall, text.secondary)` + 可选 `FilledButton` | `text.secondary` | 可选行动按钮 |
| 错误 | `snap.hasError` | `Icon(Icons.error_outline, cs.error)` + `Text(message, cs.error)` + `TextButton('重试')` | `cs.error` | **重试**（必配图标，不只靠颜色） |
| 受限/未装配 | 能力未注入（`appGraph.x == null`） | 同"空"，但文案为"xx 未装配" | `text.secondary` | 无 |

**统一实现位置**：新建 `design/states.dart`，暴露三个纯函数式 Widget：`AsyncStateView`（含 loading/empty/error 三分支）、`SectionHeader`、`AsyncAction`。这是**官方控件的组合封装**，不是自绘控件（无自绘形状、无自绘交互）。

### 3.2 逐页操作序列

| 页面 | 用户操作 | 结果 |
|---|---|---|
| 首页 | 点搜索图标 | 切到 `/search` tab 并聚焦搜索框（`SearchBar` autofocus） |
| 首页 | 点歌曲卡 | `playAll(songs, i)` → 迷你条出现（`Obx` 响应） |
| 首页 | 点歌单卡 | `Get.toNamed('/playlist/detail', arguments: id)` |
| 首页 | 点榜单卡 | 取榜单曲目 → `playAll` |
| 首页 | 点"更多" | 同 tab 内锚点滚动（`Scrollable.ensureVisible`） |
| 搜索 | 输入文字 | `SearchBar.onChanged` → 建议列表下拉（`Obx`） |
| 搜索 | 回车 / 点箭头 | `search(q)` → Tab 出现 → 结果列表 |
| 搜索 | 切分段（歌曲/歌单/专辑/歌手/歌词） | 换 `SearchType` 重查（保留当前关键词） |
| 搜索 | 点历史 chip | 回填输入框并立即搜索 |
| 搜索 | 点"清空" | 清历史（`Get.snackbar` 提示可撤销？） |
| 歌单 | 点网格卡 | `/playlist/detail` |
| 歌单 | 切"我的" tab | 读本地镜像歌单列表 |
| 歌单详情 | 点行 | `playAll(tracks, i)` |
| 歌单详情 | 点"播放全部" | `playAll(tracks, 0)`，随机则 `shuffle` |
| 歌单详情 | 点 ⋮ | `showModalBottomSheet`（收藏/下载/分享） |
| 音乐库 | 点账号卡 | `/account` |
| 音乐库 | 切 tab | 本地/最近/下载 |
| 音乐库 | 下载管理行 | `LinearProgressIndicator` 实时（`appGraph.downloads.onTask`） |
| 设置 | 切主题档 | `ThemeController.setMode` → `GetMaterialApp.theme` 切换，**不重建路由栈** |
| 设置 | 切语言 | `LocaleController.setLocale` → `GetMaterialApp.locale` 更新 |
| 设置 | 点"清理缓存" | `cache.invalidateSession()` + `Get.snackbar('已清理会话缓存')` |
| 播放页 | 点播放/暂停 | `playbackSession.toggle()` |
| 播放页 | 拖进度条 | 只改本地预览；松手 `seek` |
| 播放页 | 点收藏 | 真接口 `collect.toggle`，失败 `Get.snackbar` |
| 播放页 | 点 ⋮→歌词 | `Get.toNamed('/lyrics')` |
| 播放页 | 点 ⋮→查看 MV | `Get.toNamed('/mv', arguments: albumAudioId)` |
| 播放页 | 桌面右侧面板 Tab | 切"信息/歌词/队列" |
| 歌词 | 点"翻译" | 切双语（无译文 → 按钮禁用 `onSelectionChanged: null`） |
| 歌词 | 播放推进 | 当前行高亮 + 自动居中滚动 |
| MV | 点播放/暂停 | `VideoPlayerController.play/pause` |
| MV | 拖进度 | `VideoProgressIndicator.allowScrubbing` |
| 账号 | 扫码 | 出码 → 1.5s 轮询（等待扫码/等待确认/过期/成功） |
| 账号 | 验证码 | 60s 倒计时（按钮禁用） |
| 账号 | 选已登录账号 | `switchTo` → `navState.bumpAuth()` → `Get.snackbar` |

### 3.3 手势与 M3 反馈

| 手势 | 位置 | 行为 | M3 反馈 |
|---|---|---|---|
| 点按 | 所有可点项 | 动作 | `[M3:InkWell]` / `[M3:ListTile]` / `[M3:IconButton]` → `InkSparkle`（`splashFactory: InkSparkle.splashFactory`） |
| 按下 | 卡片/行 | 状态层 8% `cs.onSurface` | M3 状态层（`WidgetStateProperty`） |
| 横向滑动 | 首页横滑区 | 滚动 | `[M3:Scrollbar]`（桌面显示，移动隐藏） |
| 纵向滑动 | 主列表 | 滚动；**移动端下拉露出迷你条**（见 §3.5） | `Scrollbar` + `ScrollController` 监听 |
| 长按 | 歌曲行 / 歌单卡 | 弹出操作菜单（播放下一首/收藏/下载/查看MV） | `showModalBottomSheet` / `showDialog` |
| 拖拽 | 播放页进度条 | 预览进度（不 seek） | `Slider` 的 `thumbShape` 放大反馈 |
| 双指缩放 | 歌词页 | 调整歌词字号（12→24） | `InteractiveViewer`（scaleEnabled, 无 pan） |
| 下滑 | 移动端播放页 | 关闭播放页 | `DraggableScrollableSheet` / `PageRoute` 反向手势 |
| 横向拖拽 | 移动端播放页 | 切歌 | `PageView`（可选，需与 Slider 竖向手势共存） |

### 3.4 键盘与焦点（桌面端必须完整）

**焦点环**：`Focus` 高亮用 `token:focus`（Light #2F5D50 / Dark #A7F3D0），2dp 实线描边 + 2dp 外扩，作用于所有可聚焦控件。通过 `ThemeData.focusColor` + 自定义 `FocusTheme`（`focusColor`, `focusHighlightColor`）实现；`:focus-visible` 语义由 Flutter 的 `Focus` 自动处理（键盘 Tab 聚焦才显示）。

**Tab 顺序（桌面端，expanded）**：
```
1. 窗口按钮（最小化/最大化/关闭）
2. 侧栏 5 个 NavigationRail 目的地（自上而下）
3. 页面标题栏操作（搜索/收藏/更多）
4. 页面主内容（自上而下、逐行）
5. Now Playing 条控件（播放/暂停/下一首）
6. 底部动作按钮
```
规则：**不允许焦点"跳到屏幕外"**——`Scaffold` 的内容区必须给底部 Now Playing 条预留 padding（见 §3.5），否则 Tab 到最后一屏元素会被遮住。

**快捷键（桌面端全局，`Shortcuts` + `Actions` 或 `CallbackShortcuts`）**：

| 快捷键 | 动作 |
|---|---|
| `Ctrl/⌘ + F` | 聚焦搜索框并切到 `/search` tab |
| `Ctrl/⌘ + L` | 聚焦搜索框但**不**切 tab（当前页内搜索，如歌单详情内过滤） |
| `Ctrl/⌘ + K` | 打开命令面板（快速跳转：跳到搜索/设置/库） |
| `Space` | 播放 / 暂停 |
| `→` / `←` | 下一首 / 上一首 |
| `↑` / `↓` | 音量 ±5%（长按 Shift 为 ±1%） |
| `Ctrl/⌘ + →/←` | 快进 / 快退 5s |
| `Ctrl/⌘ + ↑/↓` | 切歌单/音量（与系统媒体键一致） |
| `Esc` | 返回上一层 / 关闭弹层 / 关闭播放页 |
| `Enter`（播放页聚焦时） | 展开播放页 |
| `F11` | 全屏（桌面） |
| `Tab` / `Shift+Tab` | 焦点前进 / 后退 |
| `↑/↓`（搜索框内） | 移动建议列表高亮，`Enter` 选中 |

**冲突处理**：`Space` 在 `TextField` 聚焦时必须输入空格（`Shortcuts` 需排除文本框场景）；`↑/↓` 在 `TextField` 内归文本框所有。

**语义标签（Semantics）**：
- 封面图：`Semantics(label: '封面：${歌名}', image: true, excludeSemantics: true)`
- 播放按钮：`Semantics(label: playing ? '暂停' : '播放', button: true)`
- 迷你条：`Semantics(container: true, label: '正在播放 ${歌名} - ${歌手}')`
- 错误/空态：`Semantics(liveRegion: true, label: '加载失败')`
- 封面/列表项：提供 `label` 与 `hint`（如"第 3 首，共 20 首"）

### 3.5 滚动行为（底栏隐藏 / 迷你条吸底）

- **迷你条吸底**：迷你条位于 `Scaffold.body` 的 Column 末尾（现状已是），**不悬浮遮挡内容**——内容区 `Expanded` 独立占位，因此滚动列表最后一项不会被遮挡。这是"吸底"而非"覆盖"。
- **移动端底栏隐藏**：底栏 **常驻不隐藏**（现状即如此）。理由：音乐 App 底栏是全局切换锚点，隐藏会破坏 IA 一致性；滚动时仅隐藏的是 **AppBar 的标题区**（`SliverAppBar` + `floating` + `snap`）。
- **桌面端迷你条**：改为**全宽底部条**（高 64dp），内含：封面 + 歌名/歌手 + 进度条（细，2dp）+ 上/下/播放/收藏/音量/队列。内容区 `padding.bottom` 预留 64dp。
- **桌面端播放页 = 右侧分栏**（宽 380-420dp），不覆盖主内容；此时迷你条仍显示，但点击展开分栏而非全屏。

---

## 4. 自写控件 → 官方 Material 3 控件替换映射表

> 目标：**`lib/surface/design/components.dart` 与 `design/mini_bar.dart` 中的自写控件全部删除**；页面级自写控件一并替换。替换后 `design/` 只保留 `tokens.dart`（token 唯一事实源）与 `states.dart`（官方控件的三态组合封装）。

### 4.1 design/ 共享控件（9 个）

| # | 现状自写控件 | 文件 | 官方等价替代 | 视觉差异如何用 token 补齐 |
|---|---|---|---|---|
| 1 | `SpCover` | components.dart | `[M3:ClipRRect]` + `[M3:Image.network]`（`loadingBuilder`/`errorBuilder` → `cs.surfaceContainer` 占位）；无 URL 时 `[M3:Icon(Icons.music_note, cs.onSurfaceVariant)]` | 占位底色 `cs.surfaceContainer`（bg.container）；圆角 `rS=4/rM=8/rCard=12` → M3 `shape` token 化 |
| 2 | `SpSongTile` | components.dart | `[M3:ListTile]`（`leading` 封面 / `title` / `subtitle` / `trailing` IconButton） | ListTile 默认 `contentPadding` 24 → 改为 `EdgeInsets.symmetric(horizontal:16)`；图标色 `cs.onSurfaceVariant`；ListTileTheme 统一在 `ThemeData.listTileTheme` |
| 3 | `SpSectionHeader` | components.dart | `[M3:Text]`（titleLarge）+ 可选 `[M3:TextButton]` 组成的行；**不封装自绘** | 标题 `text.primary`；"更多"用 `TextButton.styleFrom(foregroundColor: cs.primary)` |
| 4 | `SpSkeleton` | components.dart | 无官方 Skeleton → 用 `[M3:Card]`/`Container(color: cs.surfaceContainer)` + `[M3:LinearProgressIndicator]`；或整页 `[M3:CircularProgressIndicator]` | 占位块色 `cs.surfaceContainer`（bg.container），半径 4-8 |
| 5 | `SpListSkeleton` | components.dart | 同上：ListView + `Card` 占位行 + 顶部 `LinearProgressIndicator` | 同上 |
| 6 | `SpStateView` | components.dart | `[M3:Icon]` + `[M3:Text]` + `[M3:FilledButton]`（组合封装为 `AsyncStateView`，非自绘） | 图标 `cs.onSurfaceVariant`（错误态 `cs.error`）；主文案 `text.primary`；副文案 `text.secondary` |
| 7 | `SpPlayButton` | components.dart | `[M3:IconButton.filled]`（`style: IconButton.styleFrom(shape: CircleBorder(), backgroundColor: cs.primary, foregroundColor: cs.onPrimary, minimumSize: Size(64,64))`） | 现状 `Colors.black` 图标 → `cs.onPrimary`（Light #FFFFFF / Dark #0B1F14），满足 ≥3:1 |
| 8 | `SpRoundButton` | components.dart | `[M3:IconButton]`（`iconSize:24`，`tooltip`），选中态 `styleFrom(foregroundColor: cs.primary)` | `active` → `cs.primary`；未选中 `cs.onSurface`；`tooltip` 保留 |
| 9 | `SpMiniBar` | mini_bar.dart | `[M3:Material]` + `[M3:InkWell]` + `[M3:ListTile]`/`[M3:Row]` + `[M3:IconButton]`（组合封装 `NowPlayingBar`） | 底色 `cs.surfaceContainer`（bg.container）；高度 56（移动）/64（桌面）；播放/下一首按钮 `cs.onSurface` |

### 4.2 页面级自写控件（15 个）

| # | 现状自写控件 | 文件 | 官方替代 | token 补齐 |
|---|---|---|---|---|
| 10 | `HomeSkeletonBox` | home_state_views.dart | `Card` 占位 + `LinearProgressIndicator`（归入 `AsyncStateView`） | `cs.surfaceContainer` |
| 11 | `HomeEmptyBox` | home_state_views.dart | `Icon` + `Text`（`AsyncStateView` 空分支） | `cs.onSurfaceVariant` |
| 12 | `HomeErrorRetry` | home_state_views.dart | `Icon(Icons.error_outline, cs.error)` + `Text(cs.error)` + `TextButton('重试')` | `cs.error` |
| 13 | `_Cover`（首页私有） | home_page.dart | `ClipRRect` + `Image.network`（与 #1 合并为一个共享 `TnCover`） | `cs.surfaceContainerHigh` |
| 14 | `_SongCard` | home_page.dart | `[M3:Card]` + `[M3:InkWell]` + `ClipRRect` 封面 + 两行 `Text` | 文字 `text.primary` / `text.secondary` |
| 15 | `HomePlaylistCard` | home_page.dart | `[M3:Card]` + `InkWell`（同上） | 同上 |
| 16 | `_RankCard`（自绘渐变） | home_page.dart | `[M3:Card]` + `[M3:DecoratedBox]` 线性渐变（primary → primaryContainer），**文字色必须随背景取 `cs.onPrimary`/`cs.onPrimaryContainer`** | 现状硬编码 `Colors.black`/`Colors.black87` → 改 `cs.onPrimary`；渐变两端 `cs.primary` → `cs.primaryContainer`（避免暗色下半截浅块） |
| 17 | `SearchSongTile` | search_tile_widgets.dart | `[M3:ListTile]` | 同 #2 |
| 18 | `SearchEmptyBox` | search_tile_widgets.dart | `AsyncStateView` 空分支 | 同 #11 |
| 19 | `SearchErrorRetry` | search_tile_widgets.dart | `AsyncStateView` 错误分支 | 同 #12 |
| 20 | 手写搜索框（Container+TextField） | search_page.dart | **`[M3:SearchBar]`** | `hintText` `text.secondary`；`leading` icon `text.secondary` |
| 21 | 手写圆形提交按钮 | search_page.dart | **`[M3:IconButton.filled]`** | `cs.primary` / `cs.onPrimary`（现状 `Colors.black` → `cs.onPrimary`） |
| 22 | `PlaylistGridCard` | playlist_page.dart | `[M3:Card]` + `InkWell` | 同 #14 |
| 23 | `PlaylistEmptyBox` / `PlaylistErrorRetry` | playlist_page.dart | `AsyncStateView` | 同 #11/#12 |
| 24 | `PlaylistDetailSheet`（DraggableScrollableSheet） | playlist_page.dart | **`[M3:SliverAppBar]` + 路由页 `/playlist/detail`**；移动端可用 `[M3:DraggableScrollableSheet]` 表现但底色 `cs.surface` | `cs.surface` |
| 25 | `_MineRow` / `_TrackRow` | playlist_page.dart | `[M3:ListTile]` | `cs.onSurfaceVariant` |
| 26 | `_accountCard`（音乐库） | library_page.dart | **`[M3:Card]`** + `ClipOval` 头像 + `Text` | 卡片 `cs.surfaceContainer`；头像占位 `cs.surfaceContainerHigh` |
| 27 | `FavoriteButton` | player_page.dart | `[M3:IconButton]`（收藏态 `cs.primary`），内部逻辑不变（走真接口） | `cs.primary` / `cs.onSurfaceVariant` |
| 28 | `_SeekSlider` | player_page.dart | **`[M3:Slider]`**（`onChanged` 预览 / `onChangeEnd` seek 的正确设计保留） | `activeColor: cs.primary`，`inactiveColor: cs.outlineVariant` |
| 29 | `AccountSection` | login_account_section.dart | `[M3:ListTile]` × N（外层 `Container` → `[M3:Card]`/`[M3:Divider]`） | `cs.surfaceContainer`；当前账号图标 `cs.primary` |
| 30 | `_group()`（设置分组卡） | settings_page.dart | **`[M3:Card]`**（filled/elevated） | `cs.surfaceContainer`，圆角 12 |
| 31 | `ValueListenableBuilder` 直用 | settings_page.dart | 保留（`ValueListenableBuilder` 是官方控件），但推荐改 `GetX<SettingsController>` + `Obx` | — |

### 4.3 硬编码色值清理清单（必须清零）

| 位置 | 现状硬编码 | 改为 |
|---|---|---|
| `tokens.dart` `Sp.bg/bgElevated/card/...`（全部 const） | Spotify 灰黑系 | 删除 `Sp` 的色彩常量，只留间距/圆角/字号/动效；颜色一律走 `ColorScheme` |
| `shell.dart` `backgroundColor: const Color(0xFF0E0F12)` | #0E0F12 | `cs.surface`（bg.canvas） |
| `shell.dart` `_buildBottomBar` 内 `darkBar/barText/barTextDim/barIndicator` | 一整套深色 | 删除局部 Theme，直接用 `cs.*` |
| `app_root.dart` `_applySystemBarStyle` `Color(0xFF0E0F12)` | 固定暗色 | 随主题切换：亮色 → `bg.canvas` + `systemNavigationBarIconBrightness: dark` |
| `components.dart` `SpPlayButton` `Colors.black` | 黑图标 | `cs.onPrimary` |
| `search_page.dart` `ChoiceChip` `Colors.black` / 圆形按钮 `Colors.black` | 黑 | `cs.onPrimary` |
| `home_page.dart` `_RankCard` `Colors.black` / `Colors.black87` | 黑 | `cs.onPrimary` / `cs.onPrimary` @ 80% |
| `theme/tn_theme.dart` `spErrorThemeData()` 独立主题 | 第二套 ThemeData | 复用 `TnTheme.dark()`，保证单一事实源 |

### 4.4 替换后 `design/` 目录目标形态

```
lib/surface/design/
├── tokens.dart   # TnTokens（语义 token 唯一事实源）+ TnTheme.light()/dark()
├── states.dart   # AsyncStateView（loading/empty/error 的官方控件组合）
├── cover.dart    # TnCover（ClipRRect + Image.network 占位）
└── now_playing_bar.dart  # NowPlayingBar（M3 组合）
```
`components.dart` / `mini_bar.dart` **删除**（全部控件已被官方控件取代）。

---

## 5. 响应式与断点

### 5.1 断点定义

| 断点 | 宽度 | 设备对应 | 导航形态 |
|---|---|---|---|
| **compact** | `< 600` | 手机竖屏、窄窗口 | `NavigationBar`（底栏 80dp） |
| **medium** | `600 – 1000` | 平板竖屏/横屏、小窗桌面、折叠展开态 | `NavigationRail` 收窄（80dp）**或** 底栏 + 内容双列；推荐 **Rail 收窄** |
| **expanded** | `> 1000` | 桌面 | `NavigationRail` 收窄（80dp） |
| **xlarge** | `≥ 1240` | 大屏桌面 | `NavigationRail` **展开**（200dp，带文字标签） |

宽度取自 `MediaQuery.sizeOf(context).width`（或 `LayoutBuilder`），统一走一个 `Breakpoints` 工具函数；页面不允许自行写数字阈值。

### 5.2 逐页布局差异

| 页面 | compact (<600) | medium (600–1000) | expanded (>1000) | xlarge (≥1240) |
|---|---|---|---|---|
| **外壳** | 底栏 `NavigationBar` 80dp；内容单列，页边距 16 | 左 `NavigationRail` 80dp；内容单列，边距 24 | 左 `NavigationRail` 80dp；内容边距 32 | 左 `NavigationRail` **expanded 200dp**；内容边距 40 |
| **首页** | 每日推荐横滑，封面 **124**；歌单卡宽 **150**；榜单卡 **120×110** | 封面 **144**；歌单卡 **170**；榜单 **136×120** | 封面 **160**；歌单卡 **180**；榜单 **150×132**；区块间距 32 | 同 expanded，但内容最大宽 **1200dp 居中** |
| **搜索** | 搜索框全宽 + 圆形提交按钮；结果单列 | 同 compact，搜索框与提交按钮同一行 | 搜索框最大宽 **560dp**；结果**双列**（`GridView` crossAxisCount=2） | 搜索框 640dp；结果**三列** |
| **歌单（推荐）** | `GridView` **2 列**（含文字块高，childAspectRatio 0.72） | **3 列** | **4 列** | **5 列** |
| **歌单详情** | 全屏，封面高 **200** | 封面高 **260**，曲目双列?（否，保持单列 + 右侧信息栏 280dp） | 封面高 **300**；左侧曲目列表 + 右侧 320dp 信息/操作栏 | 内容最大宽 **1200dp** 居中 |
| **音乐库** | 账号卡纵向；3 tab；列表单列 | 账号卡横向；列表单列 | 账号卡横向 + 右侧统计栏 280dp；下载管理表格化（`M3:DataTable`） | 同上 + 最大宽 1200dp |
| **设置** | 单列分组卡 | 单列，分组卡最大宽 **560dp** 居中 | **双列**：左列「账号/外观」，右列「播放/存储/关于」 | 同上，两列最大宽 **960dp** |
| **播放页（移动）** | 全屏模态；封面 **280**；控件单行 | 封面 **320** | 右侧分栏 **400dp**，内部封面 **220** | 右侧分栏 **420dp** |
| **播放页（桌面）** | — | — | 右侧面板含 3 个 Tab：信息 / 歌词 / 队列 | 同上 |
| **歌词页** | 字号 16（当前行 20）；左对齐边距 16 | 字号 18 | 歌词 + 右侧信息 320dp | 同上 |
| **MV 页** | 16:9 全宽视频 | 视频最大宽 720dp 居中 | 视频最大宽 **960dp** 居中 + 下方档位/控制栏 | 同上 |
| **账号页** | 底部弹层 70% 高 / 全屏路由 | `Dialog` maxWidth **560dp** | `Dialog` maxWidth **560dp** | 同左 |
| **Now Playing 条** | 高 **56**，含封面/歌名/播放/下一首 | 高 **64**，加进度条 | 高 **64**，加 音量/队列/收藏 | 高 **64** 同左 |

### 5.3 边距与间距数值

| Token | 值 | 用处 |
|---|---|---|
| `pagePad` | 16 (compact) / 24 (medium) / 32 (expanded) / 40 (xlarge) | 页面左右边距 |
| `gapXS/S/M/L/XL` | 4 / 8 / 12 / 16 / 24 | 组件间距（保留现状） |
| 区块间距 | 24 (compact) / 32 (medium+) | Section 之间 |
| 网格列间距 | 12 (compact) / 16 (medium+) | GridView `crossAxisSpacing` |
| 卡片圆角 | `rS 4` / `rM 8` / `rCard 12` / `rXL 20` | 保留现状 |
| 触控目标 | 最小 **48×48dp** | 所有 IconButton / 触控 chip |

### 5.4 卡片/图片尺寸速查（每断点）

| 元素 | compact | medium | expanded | xlarge |
|---|---|---|---|---|
| 列表封面 | 48 | 48 | 48 | 48 |
| 首页歌曲卡封面 | 124 | 144 | 160 | 160 |
| 歌单网格卡封面 | 1:1（列宽自适应） | 同 | 同 | 同 |
| 榜单卡 | 120×110 | 136×120 | 150×132 | 同 expanded |
| 播放页封面 | 280 | 320 | 220（分栏） | 220（分栏） |
| 歌单详情头图 | 200 | 260 | 300 | 300 |

---

## 6. 桌面标题栏方案（bitsdojo_window）

### 6.1 平台适用性

| 平台 | 原生标题栏 | 方案 |
|---|---|---|
| Windows | Win32 非客户区标题栏 | **隐藏原生**，使用 bitsdojo_window 自绘 |
| macOS | 原生红绿灯 | **保留原生**（macOS 平台规范要求红绿灯在左上角，自绘会与系统习惯冲突）→ 但内容区顶部用 `titlebar.bg` 留出 28dp 的"标题栏视觉区"，与 Windows/Linux 自绘栏视觉对齐 |
| Linux (Ubuntu 22.04 AppImage) | GTK 标题栏 | **隐藏原生**，自绘（与 Windows 一致） |
| Android / iOS / Web | 系统级 | 不显示（移动端用 `AppBar`） |

> **取舍结论**：
> - **Windows / Linux**：隐藏原生标题栏 → 用 bitsdojo_window 自绘。收益：视觉完全可控、可用 `titlebar.*` token、品牌一致、跨 Win/Linux 视觉统一。代价：需自行实现拖拽/最小化/最大化/关闭、双击标题栏最大化、右键系统菜单（bitsdojo_window 不提供右键菜单 → 需自建 `PopupMenuButton` 或放弃）。
> - **macOS**：保留原生红绿灯（系统规范强制），仅把内容区顶部做成 `titlebar.bg` 色的 28dp 视觉条，与其他平台对齐。
> - **Web**：使用浏览器原生标题栏（无系统级控制权），但**在内容区顶部保留 `titlebar.bg` 视觉条**保持品牌一致。

### 6.2 布局

```
┌────────────────────────────────────────────────────────────────┐
│ [logo16] TiernanMusicNext   │◄── 可拖拽区 ──►│      [─] [□] [×] │  36dp
└────────────────────────────────────────────────────────────────┘
 bg: titlebar.bg (#1B5E20 亮 / #0B1F14 暗)
 失焦: titlebar.inactive (#6B8F76 / #4F6F5A)  ← 文字与图标降对比
 按钮 hover: titlebar.button.hover (#2F5D50 / #17332A)
 关闭 hover: titlebar.close.hover (#B3261E / #F2B8B5)
 文字/图标: titlebar.fg (#E8F5EC / #A7F3D0)
```

| 区域 | 元素 | 宽度 | 说明 |
|---|---|---|---|
| 左 | Logo（16dp）+ 应用名（titleSmall, w600） | 自适应 | 点击 = 聚焦窗口；双击 = 最大化 |
| 左 | 当前页面标题（可选，bodySmall, titlebar.fg @70%） | 自适应 | 桌面端显示，移动端不显示 |
| 中 | **可拖拽区** `Expanded` | 弹性 | `GestureDetector(onHorizontalDragStart → windowManager.startMove())`；双击 = 最大化/还原 |
| 右 | 最小化 | 46×36 | `WindowButton(minimize)` |
| 右 | 最大化/还原 | 46×36 | `WindowButton(maximize)`（还原时图标切换） |
| 右 | 关闭 | 46×36 | `WindowButton(close)`；hover 底色 `titlebar.close.hover`，图标 `titlebar.fg` |

### 6.3 交互与状态

| 交互 | 行为 | 反馈 |
|---|---|---|
| 悬停按钮 | 显示背景 | `titlebar.button.hover`；关闭按钮 `titlebar.close.hover` |
| 按下按钮 | 背景加深 8% | 状态层 |
| 拖拽标题栏空白 | 移动窗口 | bitsdojo_window `startMove()` |
| 双击标题栏 | 最大化/还原 | |
| 窗口失焦 | 整条标题栏降对比 | `titlebar.inactive`（标题文字 + 按钮图标）；按钮 hover 底色也降一档 |
| 窗口聚焦 | 恢复 | `titlebar.fg` / `titlebar.button.hover` |
| `Alt+Tab` / 任务栏预览 | 系统绘制，无边框 | 需 `titlebar.bg` 与系统 DWM 颜色协调 |

### 6.4 与内容区的分层

- 标题栏是**独立的 Scaffold 区域**，不参与主 `Scaffold` 的滚动；用 `Column[DesktopTitleBar(h:36), Expanded(Scaffold(...))]`。
- 标题栏底色 **不跟随内容区滚动**，永远 `titlebar.bg`。
- 标题栏内的文字使用 `titlebar.fg`，**不使用** `text.primary`（防止亮色主题下白底白字）。
- 内容区顶部在 macOS/Web 下留 **28dp 的 `titlebar.bg` 视觉条**（仅色带，无控件），使三平台顶部视觉一致。

---

## 7. 无障碍与键盘

### 7.1 对比度底线（硬性）

| 元素 | 要求 | 校验方式 |
|---|---|---|
| 正文（bodyMedium/bodySmall） | ≥ **4.5:1** | text.primary #102A18 on bg.canvas #F1F8F4 → 13.9:1 ✓；#E8F5EC on #0B1F14 → 15.9:1 ✓ |
| 次要文字 text.secondary | ≥ 4.5:1 | #4A6B55 on #F1F8F4 → 6.1:1 ✓；#A8C5B2 on #0B1F14 → 8.6:1 ✓ |
| 图标 / 大字（≥18.66px bold 或 24px） | ≥ **3:1** | cs.primary #1B5E20 on #F1F8F4 → 6.9:1 ✓；#A7F3D0 on #0B1F14 → 12.9:1 ✓ |
| UI 边界（outline / 分隔线） | ≥ **3:1** | outline #6B8F76 on #F1F8F4 → 3.4:1 ✓；#4F6F5A on #0B1F14 → 3.1:1 ✓ |
| 焦点环 focus | ≥ **3:1** vs 相邻底色 | #2F5D50 on #F1F8F4 → 7.0:1 ✓；#A7F3D0 on #0B1F14 → 12.9:1 ✓ |
| 禁用态 text.disabled | 可读（非必要操作） | #9BB5A3 on #F1F8F4 → 2.4:1 —— **禁用态豁免 4.5:1，但必须同时有"视觉禁用 + 不可交互"双信号**（降低透明度 + `onPressed: null` + `Semantics(enabled: false)`） |
| 状态色 success/warning/error/info | 文字前景按 §2.0 成对取色 | success #2F7D4A on #F1F8F4 → 4.6:1 ✓；warning #9A6700 → 4.6:1 ✓；error #B3261E → 5.9:1 ✓ |

### 7.2 焦点环

- 全局焦点色：`cs.focus`（自定义 `FocusTheme`），**2dp 实线描边 + 2dp 外扩**，形状跟随控件（圆形按钮 = 圆形环）。
- 焦点环必须同时在**亮/暗**两套下可见；不得被容器裁剪（`ListTile`/`Card` 内需 `clipBehavior: Clip.none` 或保证 2dp 内缩）。
- 键盘焦点移动用 `FocusTraversalGroup` + `NumericFocusOrder` 保证顺序稳定（不随列表增删跳序）。

### 7.3 Semantics 清单

| 元素 | Semantics |
|---|---|
| 封面图 | `label: '封面：$歌名'`, `image: true`, `excludeSemantics: true` |
| 歌曲行 | `label: '$歌名，$歌手'`, `hint: '双击播放'`, `button: true` |
| 列表位置 | `label: '第 $i 首，共 $n 首'` |
| 播放/暂停按钮 | `label: '播放' / '暂停'`, `button: true`, `toggled: playing` |
| 随机/循环按钮 | `label: '随机播放'`, `toggled: isShuffle` |
| 迷你条 | `container: true`, `label: '正在播放 $歌名 - $歌手'`, `hint: '打开播放页'` |
| 加载中 | `liveRegion: true`, `label: '加载中'` |
| 错误态 | `liveRegion: true`, `label: '加载失败，$message'` |
| 空态 | `label: '暂无内容'` |
| 进度条 | `label: '播放进度'`, `value: '$pos / $dur'` |
| 主题分段 | `SegmentedButton` 自带 `selected` 语义，无需额外 |
| 窗口按钮 | `label: '最小化' / '最大化' / '关闭'` |

### 7.4 屏幕阅读器顺序

1. 桌面：窗口按钮 → 侧栏 5 项 → 页面标题 → 内容自上而下 → Now Playing 条。
2. 移动：状态栏 → AppBar（标题 + 动作）→ 内容 → 迷你条 → 底栏。
3. **迷你条必须位于底栏之上但语义上排在底栏之后**，与视觉顺序一致。
4. 弹层打开时焦点移入弹层，关闭后焦点回到触发元素（`FocusScope` + `Navigator` 默认行为）。

### 7.5 触控目标 ≥48dp 的落实点

| 控件 | 落实 |
|---|---|
| `IconButton`（底栏/播放页/迷你条） | `IconButton` 默认 48×48（含 padding）；播放页大按钮 64×64 |
| `IconButton` 紧凑密度 | **禁用** `VisualDensity.compact`（现状 `SpSongTile`、`SpRoundButton` 用了 compact → 移除） |
| 表格/行内的 `trailing` IconButton（专辑/更多） | `constraints: BoxConstraints(minWidth:48, minHeight:48)` |
| `Chip`（ActionChip/ChoiceChip） | `materialTapTargetSize: MaterialTapTargetSize.padded`（默认即 padded） |
| 首页横滑卡 | 整卡可点，卡高 ≥ 176 |
| 榜单卡 120×110 | ≥48 ✓ |
| 搜索框 | 高 56（`SearchBar` 默认） |
| 列表行 `ListTile` | 默认 minVerticalPadding 8 + 48dp 目标 ✓ |
| 设置页 `TextButton('登出')` | `minimumSize: Size(48, 48)` |

---

## 8. 验收清单

### 8.1 令牌与主题

- [ ] `lib/surface/design/tokens.dart` 是**唯一**颜色事实源；页面 0 处字面量颜色
- [ ] 全部颜色来自语义 token（bg.canvas / bg.surface / bg.container / bg.containerHigh / primary / onPrimary / secondary / text.primary / text.secondary / text.disabled / outline / focus / success / warning / error / info / onError）
- [ ] Light / Dark 两套**逐项成对**，无"只有亮色有"的 token
- [ ] Primitive 层级（green-900…green-50）只被语义层引用，页面不直接用
- [ ] 标题栏 token（titlebar.bg / fg / button.hover / close.hover / inactive）**独立于** ColorScheme
- [ ] 主题档位为 3 档（跟随系统 / 亮 / 暗），**取消纯黑 AMOLED 档**
- [ ] **深色无纯黑**（除 tokens 允许的 #0B1F14 系），**浅色无纯白大块底**（`bg.surface #FFFFFF` 允许）
- [ ] 取消动态取色（fromSeed 派生），改为固定内部设计语言
- [ ] `shell.dart` 不再有局部硬编码深色 Theme
- [ ] `app_root.dart` 系统栏颜色随主题切换

### 8.2 控件官方化

- [ ] `design/components.dart`、`design/mini_bar.dart` **已删除**
- [ ] 自写控件清单 §4.1 + §4.2 共 31 条**逐条替换完成**
- [ ] 页面中 0 处 `GestureDetector` 用于代替 `InkWell`（除拖拽区）
- [ ] 页面中 0 处自绘 `Container+BoxDecoration` 圆角按钮（全部 `IconButton`/`FilledButton`/`Card`）
- [ ] 错误/空/加载三态统一走 `AsyncStateView`（官方控件组合）
- [ ] 骨架屏由 `Card` 占位 + `LinearProgressIndicator` 实现

### 8.3 对比度与可读性

- [ ] 正文 text.primary / text.secondary 对 bg.canvas 与 bg.surface 均 ≥4.5:1
- [ ] 图标、大字、UI 边界 ≥3:1
- [ ] 状态色 success/warning/error/info **均配图标或文案**，不单独靠颜色
- [ ] 禁用态：视觉降透明 + `onPressed: null` + `Semantics(enabled:false)` 三重表达
- [ ] 错误文案用 `cs.error` 且带 `Icons.error_outline`

### 8.4 导航与 IA

- [ ] 底栏/侧栏 5 tab 顺序固定：首页 / 搜索 / 歌单 / 音乐库 / 设置
- [ ] 移动端 `NavigationBar`，桌面端 `NavigationRail`（≥1000）
- [ ] 迷你播放条吸底不遮挡内容
- [ ] `/player`、`/lyrics`、`/mv`、`/playlist/detail`、`/account`、`/error` 为正式路由
- [ ] 歌词页不再用 `navState().requestTab('lyrics')`（现状断点已修）
- [ ] 歌单详情从 bottom sheet 升级为路由页（桌面端）

### 8.5 桌面标题栏

- [ ] Windows / Linux 隐藏原生标题栏，改用 bitsdojo_window
- [ ] macOS 保留原生红绿灯，顶部保留 `titlebar.bg` 视觉条
- [ ] 最小化 / 最大化 / 关闭三按钮齐全，尺寸 46×36
- [ ] 标题栏中部为可拖拽区，双击最大化
- [ ] 按钮 hover 用 `titlebar.button.hover`，关闭按钮用 `titlebar.close.hover`
- [ ] 窗口失焦时标题栏降对比为 `titlebar.inactive`
- [ ] 标题栏内容使用 `titlebar.fg`，不使用 `text.primary`

### 8.6 无障碍与键盘

- [ ] 焦点环 2dp + 2dp 外扩，用 `cs.focus`，亮/暗均可见
- [ ] Tab 顺序稳定，焦点不会被底栏/迷你条遮挡
- [ ] 快捷键：`Ctrl+F`、`Ctrl+L`、`Ctrl+K`、`Space`、`←/→`、`↑/↓`、`Ctrl+←/→`、`Esc`、`Tab`
- [ ] 文本框内 `Space`/`↑/↓` 不被全局快捷键劫持
- [ ] 所有图标按钮有 `tooltip` 与 `Semantics(label)`
- [ ] 所有可点元素 ≥48×48dp；移除 `VisualDensity.compact`
- [ ] 加载/错误/空态为 `liveRegion`
- [ ] 状态色信息不依赖颜色单独表达

### 8.7 响应式

- [ ] 断点 600 / 1000 / 1240 统一由 `Breakpoints` 工具提供，页面不写魔法数
- [ ] 歌单网格列数：2 / 3 / 4 / 5
- [ ] 搜索结果列数：1 / 1 / 2 / 3
- [ ] 桌面端播放页为右侧分栏（400dp），非全屏模态
- [ ] 设置页桌面端双列
- [ ] 内容最大宽 1200dp 居中（xlarge）

### 8.8 稳定性

- [ ] 主题切换不重建路由栈、不闪白/闪黑
- [ ] 语言切换实时生效（10 语），文案全部走 `S.of(context).t(...)`，页面 0 处硬编码中文串
- [ ] 页面 `build` 内不新建 Future
- [ ] L7 只画控件：数据全部来自 L6（经 `bridge_session`），0 处 `appGraph` 直连 IO
- [ ] `get` 的 Controller 定义在 L6 并经桥暴露，L7 只做 `Obx` 绑定
- [ ] 播放页进度条：拖动只预览，松手才 seek
- [ ] 收藏按钮走真实接口，失败有 `Get.snackbar` 反馈

---

## 9. 未覆盖 / 后续项

1. **评论页**（现状 `navState().requestTab('comment')` 无对应模块）—— 本规划未含评论页 IA，需在 `lib/core/net/endpoints/comment_endpoints.dart` 就绪后补。
2. **专辑页 / 歌手页**（现状 `navState().setAlbum/setArtist` 无落地页面）—— 同样未在 IA 中展开。
3. **YKG 链接页**（现状 `ykg_sheet.dart` 有 `showYkgSheet` 但无调用方，`login_sheet.dart` 里也是 `showYkgImport/Export` 交叉调用，命名有误）—— 规划中按"账号页第 4 个 Tab"处理，具体调用链待实现期确认。
4. **队列页**（桌面右侧面板的"队列"Tab）—— 数据源 `PlaybackSession` 的队列能力需确认是否已暴露。
5. **bitsdojo_window 的右键系统菜单**—— 官方库不提供，需决定自建还是省略。
6. **本地化**：现有 10 语 `arb` 需补齐本规划新增的全部文案 key（错误态文案、快捷键说明、桌面标题栏文案）。
7. **国际化长度**：英文/俄文下标题栏、Tab 标签的截断策略未逐项验证。
8. **Web 端键盘**：浏览器 `Ctrl+F` 会与页面内搜索框冲突，需在 Web 上让 `Ctrl+F` 阻止默认行为（或只在 Web 绑定 `Ctrl+/`）。
9. **深色下 `outline` 3:1 的边界值**（#4F6F5A on #0B1F14 ≈ 3.1:1）非常接近阈值，实际渲染需复测。

---

*（文档结束 · 本文件为纯设计规划，不含 Dart 实现；实施时应逐节对照 §4 映射表与 §8 验收清单执行）*
