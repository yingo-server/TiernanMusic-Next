# A6 批 · C3 用户痛点专项视角 · L6 session + 六桥

> 子代理：A6-C3｜视角：用户痛点（播放会话可用性 / 主题动态取色 / YKG 会话落点 / 模块可达性 / 文案 / 桥日志隐私）
> 契约：`docs/DEEP_AUDIT_14_BATCH_PLAN.md` §0 76 原则
> 范围：`lib/session/` 8 文件 + `lib/bridges/` 6 文件，已连续读完（1866 行）；交叉只读检索 L4/L5/L7 佐证。
> 本轮只读，唯一写入为本文件（append）。

---

## 2026-11-16 · 第一批结论：播放会话体验（用户「功能用不了」）

### 视角 C3 · lib/session/playback_session.dart:96-131 · P1 · 播放会话 / 通知栏同步半接
证据：
- `attach()` 在 engine==null 且默认 NullAudioEngine 时构造 `JustAudioEngine` 并调 `initNotification(just.rawPlayer, NotificationControls(onNext: next, onPrev: prev))`（:104-119），成功存 `_notification`。
- `NotificationControls` 定义（`lib/core/audio/notification_gateway.dart:28-32`）有三个回调 `onNext/onPrev/onSeek`；session **只传 onNext/onPrev，未传 onSeek**。
- 但 `MusicAudioHandler` override 的 `seek(Duration)` 直接 `_player.seek(position)`（gateway:128），**不经过 session 的 `_player` 状态机** → 通知栏拖动进度条后，L5 PlayerState.positionMs 不更新，UI 进度与引擎位置脱节。
- `initNotification` 结果 `_notification` 仅在 `_start` 里调 `updateMetadata`（:222-228、:249-255），**播放/暂停状态从 Session 侧不推送**（gateway 自己监听 `just.rawPlayer.playbackEventStream` 同步 playing，走的是引擎事件，不经 reducer）：切歌/暂停时 L7 快照与通知栏靠两条独立链路间接一致，无 Session 侧统一发布点。
问题：通知栏 seek 不回写会话状态；播放控制存在「Engine→gateway 通知」与「Engine→Session reducer→L7」两套并行同步，易漂移。
建议：`NotificationControls(onSeek: (ms) => seek(ms))` 补齐，并在 gateway 的 override seek 中优先调用 onSeek；把播放/暂停状态也经 session 统一推给 notification（单一事实源）。
76 合规：不涉及（跨层均经桥，gateway 在 L4、session 在 L6）。

### 视角 C3 · lib/session/playback_session.dart:83,212,235,246 · P2 · 播放会话 / 状态字段写了不读（伪透传）
证据：`_sourceKind` 在 :83 初始化 `'kugou'`，在 MV 兜底成功设 `'mv-audio'`(:212)、失败复位 `'kugou'`(:235)、正常播放设 `'local'/'kugou'`(:246)，但 **`rg '_sourceKind' lib/session/playback_session.dart` 只有这 4 行，无任何读取点**；注释自称「sourceKind 字段待批3-F2 落盘后随 PlayerState 透传」（:82），实际从不透传给 L7。
问题：源类型（本地/在线/MV 兜底）在会话内被记录却从不暴露，用户无法知道当前播的是 MV 音轨还是本地文件，兜底成功对 UI 不可见。
建议：把 sourceKind 纳入 PlaybackSnapshot（或 PlayerState），L7 在 mini_bar/player 展示「MV 音频/本地/在线」标识。
76 合规：不涉及（属 L6 状态未暴露，无越层）。

### 视角 C3 · lib/session/playback_session.dart:183-240 + lib/logic/player/playback_service.dart:339-341 + lib/logic/auth/verification_logic.dart:1-2 · P0 · 播放会话 / 20028 验证卡死（A5 P0）在 session 侧无出口
证据：
- `resolvePlaySource` 匿名必返 `PlaybackError.needsVerification`（20028，playback_service.dart:339-341）；session `_start` 把该错误 `errKind.contains('needsVerification')` 识别为可兜底（:189-192），随后 `resolveMvAudioFallback` 尝试 MV 音频。
- MV 兜底失败时落 `ErrorAction(src.error.toString())`（:236-240）——把 `PlaybackError.needsVerification` 的 **toString 技术串**显示给用户。
- `appGraph.verification`（VerificationLogic）虽在 bootstrap:185-187 装配并进 graph.dart:133，但 `rg 'VerificationLogic|verification' lib/session/playback_session.dart` **零命中**；VerificationLogic 头注释自认「验证链路未接线，待 play_url 20028 通知接入」。
- 结论：**20028 触发后 session 既不引导人机验证，也不把 `onVerificationRequired` 唤醒**，只做 MV 音频兜底 + 显示黑话错误 → 匿名用户播放永久卡死在错误态（正是 A5 P0 在 L6 的表现）。
问题：会话层缺少 20028 → VerificationLogic 的转接，用户遇到验证 wall 时无可执行下一步。
建议：`_start` 收到 needsVerification 时调 `appGraph.verification?.onVerificationRequired(errcode: 20028, ssaCode: ...)` 并在快照暴露 `needsVerification` 状态供 L7 弹验证引导；失败文案改错误码映射。
76 合规：不涉及（需要在 L6 session 编排，合法）。

### 视角 C3 · lib/session/playback_session.dart:196-225 · P1 · 播放会话 / MV 兜底链在 session 侧接口接对但依赖错误判定
证据：session 通过 L5 `PlaybackService.resolveMvAudioFallback(cur)`（playback_service.dart:274）取 MV 音频 URL，判定 `mv.ok && mv.urls.isNotEmpty` 后 `_engine.play(mvUrl)`（:208-215），并写历史、推通知元数据——**session 侧编排完整**（含 `_mvTriedOnce` 防循环、失败留痕）。
但触发条件用 `errKind = src?.error?.toString()` 字符串 contains('noPrivilege'/'needsVerification'/'notFound')（:187-192）判断，**依赖 enum toString 文本**，脆弱：一旦 L5 `PlaybackError` 枚举名/toString 变更，兜底静默失效。
问题：MV 兜底链 session 侧已接对，但「能否兜底」的判据是字符串匹配，不是类型判断。
建议：L4/bridge_logic 导出 `PlaybackError` 枚举给 session，改为 `if (src.error is PlaybackError && ...)` 类型匹配。
76 合规：不涉及。

### 视角 C3 · lib/session/playback_session.dart:147-149 · P1 · 播放会话 / 引擎错误原文直出 + 中文硬编码（详见文案清单）
证据：`AudioEventType.error → ErrorAction('引擎播放失败')` 硬编码中文（:149）；`:239` fallback 文案；catch 块 `:249 ErrorAction('$e')` 把异常原文直接送给 UI。
问题：错误文案无错误码、无 i18n、无「重试/跳过」动作，用户只看到中文黑话或异常栈文本。
建议：错误码化（engineError/playBlocked/passwordRequired 等），L7 按码取 arb 文案。
76 合规：涉及 —— L6 直接持有用户可见中文文案，违反 L4-l10n 归口（§0 L4 定义「l10n 常量」归 core）。

### 视角 C3 · lib/session/playback_session.dart:112-120,122-131 · P2 · 播放会话 / attach 重复注入时通知栏重复初始化
证据：`attach()` 每次调用（无幂等保护）在 `engine==null && _engine is NullAudioEngine` 时才建 just 引擎；首次后 `_engine` 已非 Null，重复 attach 不再 initNotification（条件处有保护）——**但**若外部先注入 engine 后再 attach(engine:null)，`_engine` 非 Null 也不再建通知栏，导致「注入引擎后通知栏永远不可用」。
问题：注入引擎路径下通知栏能力丢失（测试/替换引擎场景），非主路径但属隐藏断点。
建议：通知栏初始化独立于引擎构造，`attach` 幂等且只要有 rawPlayer 就 initNotification 一次。
76 合规：不涉及。

---

## 2026-11-16 · 第二批结论：主题 / 动态取色接线（用户「UI 不舒服」）

### 视角 C3 · lib/session/theme_controller.dart:12-45 + lib/core/algorithms/color_extract.dart:4 · P0 · 主题 / 动态取色链在 L6 彻底断开
证据：
- `ThemeController` 全部职责：`ValueNotifier<int>` 存 0/1/2/3 模式（系统/亮/暗/纯黑）+ KeyValueSettings 持久化 + notifyListeners（:12-45）。**零 import color_extract、零调 extractDominant/fromSeed、零 ColorSeed/ThemePalette 字段**。
- L4 取色能力 `extractDominant`/`fromSeed`（color_extract.dart:59,143）只经 `bridge_core.dart:48` export，**全仓消费者检索**：`rg 'extractDominant|fromSeed|ColorSeed|ThemePalette' lib/surface` → **仅 tn_theme.dart:10 `ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954))`（固定绿）与 tokens.dart:80**，无任何一处用封面取色结果；color_extract.dart 头注释自认「接线现状（诚实标注，审计B P2-1）：extractDominant/fromSeed 当前版本…」。
- `fetchCoverBytes`（L4 封面取色字节，bridge_core:45）在 surface 侧 `rg` **零调用**。
- 结论：A4「取色链断」在 L6 得到确认——**L4 取色能力 → L6 主题控制器 → L7 主题 三段全断**，ThemeController 只是模式开关，动态色从未产生也从未 notify 主题重建。
问题：用户换封面/设置动态主题无任何效果，theme_controller 没有承接 L4 取色能力；深浅色仅靠固定绿 seedColor，UI「不舒服」的取色根因在此。
建议：ThemeController 增加 `ThemePalette? dynamicPalette` + `applyCoverColor(List<int> rgba, w, h)`，内部经桥调 `extractDominant`→`fromSeed(seed, dark: mode==2/3)` 并存 palette，notifyListeners 带 palette；L7 app_root 监听 palette 重建 ColorScheme。
76 合规：涉及 —— §0 L4「纯算法」与 L6「编排」分层正确，但 L6 编排层未接 L4 门面（能力空转），非越层是断链。

### 视角 C3 · lib/session/theme_controller.dart:33-43 · P1 · 主题 / setMode 通知与 ValueNotifier 重复触发
证据：`setMode()` 先 `value = mode`（:38，ValueNotifier 自动 notifyListeners 一次），随后又显式 `notifyListeners()`（:43）→ **每次切主题发两次通知**。L7 `app_root.dart:57` 用 `ValueListenableBuilder` 监听，双通知触发双帧重建。
问题：主题切换触发重复 rebuild（设置页/L7 两处监听），属 rebuild 风暴细节；与用户「动画/细节不经看」相关。
建议：去掉 `value = mode` 后的显式 `notifyListeners()`，或改用 `value = mode` 单点通知；持久化失败分支可单独 Log 不重建。
76 合规：不涉及。

### 视角 C3 · lib/session/theme_controller.dart:13-15 + lib/surface/app_root.dart:57-66 · P2 · 主题 / 默认暗色与 L7 静态主题可能错位
证据：`ThemeController._() : super(2)` 默认**暗色模式**（2），构造时从 settings 读 `ui.themeMode`（:14-15）；L7 `app_root.dart:64` 按 mode 给 `themeMode: switch(mode){...}`，`tn_theme.dart:10` 亮/暗两套 seedColor 都是固定 `Color(0xFF1DB954)`。
问题：首次安装无持久化时默认暗色，但 L7 两套主题色相同固定绿，深浅切换仅背景/表面色变化、无动态色——用户感知「主题切换没差别」。
建议：主题模式与动态 palette 两条轴分离，palette 变化也触发 L7 重建；默认模式按产品决策明确（亮/跟随系统）。
76 合规：不涉及。

---

## 2026-11-16 · 第三批结论：模块注册与导航（功能可达性）

### 视角 C3 · lib/session/bootstrap.dart:219-227,265-275 + lib/surface/shell.dart:23-30 + lib/surface/pages/mv_page.dart:12-18,30 · P0 · 模块注册 / 占位抢占 id 致 MV 深链不可达（A1 P0 在 L6 的落点确认）
证据：
- bootstrap:219-227 定义 `moduleIds` 含 `'mv'`，循环 `ModuleRegistry.instance.install(_PlaceholderModule(id))`；`_PlaceholderModule.enabled => false`（:272）。
- `registerMvModule()`（mv_page.dart:12-18）有守卫 `if (reg.byId('mv') != null) return;` —— **bootstrap 已用占位模块占了 'mv' id**，所以守卫命中直接返回，**真实 MvPageModule 永远装不进去**。
- shell.dart:30 与 player_page.dart:192 调 `registerMvModule()` 均因此失效；MvPageModule.builder 恒 `(_) => const MvPage(songHash: '')`（mv_page.dart:30）→ 即便装上，深链 `/mv` 也落「缺少歌曲 hash」空态。
- 对照：其他真实模块（Home/Search/…）由 shell.dart:23-29 直接 `install()` 覆盖占位；**MV 因守卫 + 占位占用成为唯一例外** → A1「MV 不可达」根因在 L6 bootstrap 坐实。
问题：`/mv` 路由恒被 enabled=false 的占位模块占据，MV 深链导航与播放页菜单均不可达；用户点名「MV 用不了」的直接机制。
建议：bootstrap 不要为已有真实模块的 id 装占位（或 install 真实模块前无条件覆盖占位）；`registerMvModule` 去掉 `byId!=null` 守卫改为按类型/来源判断；深链 `/mv?songHash=xxx` 从路由参数或 PlaybackSession.snapshot.current.hash 取 hash。
76 合规：不涉及（注册表在 L6、模块实现在 L7，分层合法；属编排缺陷）。

### 视角 C3 · lib/session/nav_state.dart:1-107 · P1 · 导航 / 导航意图状态只广播不消费，深链无落地
证据：`NavState` 提供 `setAlbum/setArtist/requestTab` 与 `albumId/artistId/tabRequest` getter（:15-19,73-103），每次 `_notify()`；`rg 'navState\(\)\.(albumId|artistId|tabRequest)' lib/surface` **零命中**（仅 settings_page.dart:39/43/49/81 订阅 bumpAuth/authVersion）。`requestTab` 无路由落地代码。
问题：专辑/歌手跳转与 tab 请求是「发了没人收」的死信号；用户从歌手/专辑入口点击无反应（导航不可用）。
建议：L7 Shell/AppRoot 监听 NavState，按 albumId/artistId 决定 push 页面；深链解析后统一经 navState 落地并 clearTabRequest。
76 合规：不涉及。

### 视角 C3 · lib/session/auth_session.dart:1-85 + lib/surface/pages/settings_page.dart:39-81 · P1 · 导航 / 登录态双轨：AuthSession 无通知源，实际走 NavState.bumpAuth
证据：`AuthSession.onAuthChanged()` 注释自认「TODO(批2-F2): NavState.bumpAuth 落盘后改为监听 NavState…当前仅本地注册，无触发源」（:51-53）；`notifyAuthChanged()` 自认「仅供 login/logout 流程手动调用」（:71-72），但 `rg 'AuthSession.*notifyAuthChanged|authSession\(\)' lib/surface` **零命中** → `_listeners` 永不触发。
实际登录/登出走的是 `navState().bumpAuth()`（login_sheet.dart:79,95；settings_page.dart:81），L7 settings_page 也只订阅 navState（:39）。
问题：会话层存在两套并行登录态通知（AuthSession 死、NavState 活），消费方接 AuthSession 将永不刷新；`isLoggedIn/userid` 也无人经桥消费（`rg 'AuthSession' lib/surface` 零命中）→ AuthSession 整体是死代码。
建议：统一到 NavState.bumpAuth 单一事实源，删除 AuthSession 的 listener 机制或让它内部订阅 NavState；避免两套 API 误导后续 YKG 登录接线。
76 合规：不涉及。

---

## 2026-11-16 · 第四批结论：YKG 会话落点（用户点名）

### 视角 C3 · lib/session/auth_session.dart:1-85 · P0 · YKG 会话落点 / 无凭据注入接口（盘点断点坐实）
证据：全文 85 行，公开 API 仅 `attach(KugouClient?)`/`isLoggedIn`/`userid`/`onAuthChanged`/`offAuthChanged`/`notifyAuthChanged`（:17-84）。
- `attach()` 只持有 L4 构造好的 `KugouClient` 引用（:18-25），**没有任何把外部 token/cookie 写入 `client.session` 的方法**（无 `injectCredentials`/`applyCookie`/`setToken` 类接口）。
- `rg -ni 'ykg|inject|cookie|token|credential' lib/session` → 仅注释中的「注入引擎/构造器」命中，**零凭据注入实现**（`auth_session.dart:3,18,39` 仅注释）。
- 对照 YKG 设计稿 §7：`凭据写入 session：L5 → 经 bridge_logic → L6 session/auth_session.dart`，要求 session 提供注入口；`account_logic.dart:54-120` + `entities.dart:113-137` 已具备 `token/mid/dfid/cookieBlob` 素材，但**导出/导入编排在 L5 缺失、session 注入口也不存在** → 两端皆空，YKG 链路 100% 未落。
- 另：`AuthSession` 整体无消费者（见上条），即便加了注入口也无 UI 触发路径。
问题：用户明确的 YKG 链接登录「从 app 导出 + 输密码导入 + 凭据注入 client」在 L6 会话层**零落点**；L5 做好导出/导入后无处写入登录态。
建议：在 AuthSession 增加 `Future<bool> applyCredentials({required String cookie, String? token, String? mid, String? dfid, String source='ykg'})`，内部经桥调 L4 写入 `client.session`/settings 并触发单一通知（navState.bumpAuth）；仅接受来自 bridge_logic 的 L5 调用，不自行解析链接/不碰 UI 文案。
76 合规：建议落 L6 session 注入口 + L5 编排，合法（不是越级）；当前「无落点」本身不违规，是能力缺失。

### 视角 C3 · lib/bridges/bridge_session.dart:25-28 + lib/bridges/bridge_logic.dart:1-145 · P2 · YKG 会话落点 / 桥未暴露任何 YKG 或凭据注入门面
证据：`bridge_session.dart` 只 export appGraph/ThemeController/AuthSession，无 `applyCredentials` 类函数；`bridge_logic.dart` 全文 export 列表**零 ykg/exportYkg/importYkg/applyCredentials 符号**（rg -ni 'ykg|export|importYkg' 本桥零命中）。与设计稿 §7「L5 ykg_logic → bridge_logic → L6 auth_session」的通道不存在。
问题：即便 L5 后续新增 ykg_logic，也未在桥层留门面，接线时需同时补两座桥。
建议：预留 `bridge_logic` export YkgLogic、`bridge_session` export AuthSession.applyCredentials 的门面（待实现后补），避免在 session/surface 直连绕桥。
76 合规：不涉及（现状是缺失，不是越层）。

---

## 2026-11-16 · 第五批结论：文案从 L6 漏出（面向用户的中文串）

### 视角 C3 · lib/session/playback_session.dart:149,239,249 · P1 · 文案 / L6 硬编码用户文案 + 异常原文直出
证据（`rg -nP "['\"].*[\x{4e00}-\x{9fff}].*['\"]" lib/session lib/bridges` 全量命中仅 3 行，均在 playback_session）：
- `:149  ErrorAction('引擎播放失败')` —— 引擎错误中文硬编码。
- `:239  ErrorAction(src?.error?.toString() ?? '播放源不可播或需登录')` —— 兜底失败中文黑话 + PlaybackError enum 的 toString 技术串直接上屏。
- `:249  ErrorAction('$e')` —— 异常对象原文（可能含栈/英文/路径）直出 UI。
- 说明：A1-C3 已记 :149/:239；本批补 :249 的异常原文泄漏，且确认整个 session+bridges 14 文件中 **只有 playback_session.dart 有中文硬编码（3 行）**，桥内 0 中文文案 → 文案泄漏集中在播放会话一处。
问题：播放失败时用户看到的是「引擎播放失败」「PlaybackError.needsVerification」或原始异常，既非中文友好也不可 i18n、无重试动作。
建议：L6 只发错误码枚举（engineError/verificationRequired/vipRequired/offline），L7 按码经 TnStrings 取词；禁止 `'$e'` 直出。
76 合规：涉及 —— L6 持有用户可见文案，违反 §0 L4「l10n 常量」归口、L6「只暴露状态/意图」职责（§0 第 8 条精神）。

---

## 2026-11-16 · 第六批结论：桥日志泄漏（用户隐私）

### 视角 C3 · lib/session + lib/bridges（14 文件）· P2 · 隐私 / 未发现 token/cookie 明文直接 Log
证据：`rg -ni 'Log\.[dew].*(token|cookie|password|passwd|secret|ymd5|session)' lib/bridges lib/session` → 命中均为 **方法名/文字描述**（如 `auth_session.dart:44 'userid read failed'`、bridge_boot 的 `'dbOpenFuture unavailable'`），**零条把凭据值拼进 Log 的语句**。
- session/bridge 内 Log 仅打：`attached=${client!=null}`（auth_session:22）、`authVersion=$n`（nav_state:65）、`album=$id`/`tab request=$id`、`quality=$q`、`notification ready=...`、`session ready modules=n` 等**非敏感标量**。
- 风险残留：`playback_session.dart:239` 把 `src.error.toString()` 作为 **UI 错误文案**（非 Log），若 `PlaybackError` 未来携带 URL/签名参数会经 UI 泄漏；`ErrorAction('$e')`（:249）同理。
问题：本层桥日志命中隐私红线为零，合规；但错误对象原文经 UI 直出是潜在敏感信息出口（属文案/隐私交叉）。
建议：保持桥 Log 不打凭据值；将 `'$e'`/`.toString()` 从 UI 路径移除，改错误码。
76 合规：涉及 —— §0 铁律 2「桥函数失败必 Log 留痕」本批 6 桥均遵守（bridge_logic 注释自述「以 export 为唯一通道，调用方负责 Log」，其唯一函数 `LogicFacade.playbackSummary` 也有 try/catch+Log，bridge_kernel 额外有 print 兜底），**无静默吞异常**；隐私维度无违规。

---

## 主题取色接线结论
- **断链坐实**：L4 `color_extract.dart`（extractDominant/fromSeed）与 `cover_color.dart`（fetchCoverBytes）经 bridge_core export 后**无任何消费方**；`rg` 显示 surface 侧只用 `ColorScheme.fromSeed(const Color(0xFF1DB954))` 固定绿。
- `ThemeController`（lib/session/theme_controller.dart:12-45）只是 0/1/2/3 模式开关 + 持久化，**不持有 ThemePalette、不调取色、切换只 notify 模式值**，L4 取色能力从未接入 L6。
- 切换主题经 `notifyListeners` 触发 L7 app_root 重建，但重建用的是静态主题 → 「深浅色可用、动态色不可用」，且 setMode 双通知（:38+:43）造成重复 rebuild。
- 修复要点：ThemeController 增 palette 状态 + applyCoverColor 桥接 L4，L7 用 palette 生成 ColorScheme；`value=mode` 与显式 notifyListeners 二选一。

## YKG会话落点结论
- `AuthSession`（85 行）**无任何凭据注入接口**：只有 `attach(KugouClient?)` 持有引用，无 setToken/applyCookie/injectCredentials；`rg -ni 'ykg|inject|cookie|token' lib/session` 零实现命中。
- `bridge_session`/`bridge_logic` 均未 export 任何 ykg 或注入门面；设计稿 §7 的「L5 ykg_logic → bridge_logic → L6 auth_session」通道两端皆空。
- AuthSession 自身是死代码（无 surface 消费者；登录态实际走 NavState.bumpAuth），即便加注入口也需先统一通知源。
- 建议接口：`AuthSession.applyCredentials({cookie,token,mid,dfid,source:'ykg'})`（L6）经桥由 L5 ykg_logic 调用，写入 client.session + 触发 navState.bumpAuth，不在 session 解析链接或写文案。

## 文案泄漏清单
| 文件:行 | 文案 | 性质 | 处理 |
|---|---|---|---|
| `lib/session/playback_session.dart:149` | `ErrorAction('引擎播放失败')` | 用户可见中文硬编码 | 改错误码 + arb |
| `lib/session/playback_session.dart:239` | `'播放源不可播或需登录'` + `src.error.toString()` | 用户可见中文黑话 + enum 技术串 | 改错误码 + arb |
| `lib/session/playback_session.dart:249` | `ErrorAction('$e')` | 异常原文直出 UI（潜在敏感） | 改错误码，禁止直出 |
- 统计：session 8 文件 + bridges 6 文件内面向用户的中文硬编码 **3 行，全部集中在 playback_session.dart**；桥内 0 行；较 A1 全仓 290 行，本层占比很小但属关键错误路径。

---

## 本视角结论
1. **播放会话主链接通但有三处断点**：通知栏 seek 不回写会话状态（P1）、20028 验证在 session 无出口导致匿名播放永久卡死（P0，A5 P0 的 L6 表现）、MV 兜底链 session 侧编排完整但「能否兜底」靠 `error.toString()` 字符串匹配（P1）。
2. **动态取色 100% 断链**：ThemeController 不接 L4 取色能力，L4 `extractDominant/fromSeed/fetchCoverBytes` 全仓零消费，L7 用固定绿 seedColor；深浅色可用但无动态色（P0）。
3. **MV 不可达根因在 L6 bootstrap**：占位模块抢占 `'mv'` id + `registerMvModule` 的 `byId!=null` 守卫 → 真实 MvPageModule 永不安装，深链恒空 hash（P0，坐实 A1 P0）。
4. **YKG 会话落点为零**：AuthSession 无 token/cookie 注入接口、桥无门面、且 AuthSession 本身无消费者（P0）。
5. **登录态双轨**：AuthSession listener 机制无触发源是死代码，实际走 NavState.bumpAuth；YKG 接线前须先统一（P1）。
6. **导航意图死信号**：NavState 的 albumId/artistId/tabRequest 只广播不消费（P1）。
7. **文案泄漏集中**：session+bridges 仅 3 行中文/异常原文硬编码，全在 playback_session（149/239/249），违反 l10n 归 L4（P1）。
8. **桥日志无隐私泄漏**：6 桥 try/catch+Log 完备，无 token/cookie 明文入 Log（P2 仅错误原文经 UI 直出的交叉风险）。

## 未覆盖
- 未逐行读取 L7 surface 18 文件、L4 color_extract/cover_color 实现细节、L5 ykg_logic（不存在）、L5 playback_service 全文（仅定点检索佐证）——按 A6 范围聚焦 session/bridges，跨层只读检索取证。
- 未验证运行时行为（禁跑 dart/flutter/analyze/test），所有结论基于静态代码与交叉 `rg` 证据。
- `lib/core/audio/notification_gateway.dart` 仅定点读取 28-152 行（initNotification 实现段 152-169 未逐行），通知栏初始化失败路径细节未展开。
- `bridge_boot.dart`/`bridge_kernel.dart` 的 L1-L3 上下游（bootloader/kernel）属 A1 批范围，本视角仅看其桥文件本身与日志职责，未复核被包装实现。

## 76 合规小结
- **越级 import**：本批 session/bridges 的跨层引用**全部经 6 座桥**（session → bridge_core/bridge_logic/bridge_kernel；bridge_session → session 各文件；bridge_surface → surface app_root + session bootstrap；bridge_logic/bridge_core 纯 export）。未发现 session 直连 logic/core 内部非桥文件、未发现 surface→session 直连绕过 bridge_session（shell.dart 用 ModuleRegistry 单例，经 bridge_session export 的同一实例，属合法同层通道边缘，建议核对——本视角未判违规）。
- **反向依赖**：未发现 L6 反向被 L5 依赖、或 session import surface 的反向边。
- **影子桥**：`lib/bridges/` 只有规定的 6 文件，无影子桥目录。
- **职责越界**：
  - `playback_session.dart:149/239/249` 持有用户可见文案并直出异常原文 → 违反 §0 L4「l10n 常量归口」与 L6「只暴露状态/意图」（第 8 条精神）；
  - `theme_controller` 未接 L4 取色门面是**断链**不是越界；`bootstrap` 装占位模块属编排缺陷不是越界。
- **桥日志职责**：6 桥均 try/catch+Log；bridge_kernel 有 print 兜底；bridge_logic 自述「export 通道由调用方 Log」，其唯一函数仍有 Log。**符合铁律 2，无静默吞异常，无凭据日志泄漏**。
- **成熟库**：播放用 just_audio、通知用 audio_service（session attach 内），符合 §0 第 9 条。
- **1500 行**：本批最大文件 playback_session.dart 405 行，均远低于 1500。
