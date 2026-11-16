# B3 批 · C3 用户痛点专项（播放主链路跨层审查）

> 视角 C3 · 子代理落盘 · **只读审查，append-only**。
> 范围：L7 `player_page.dart`/`mini_bar.dart`/`shell.dart`/`components.dart`/`tokens.dart`；L6 `playback_session.dart`；L5 player 域（playback_service/play_resolver/quality_policy/queue_state/player_state/playback_reducer）；L4 `audio_gateway.dart`/`notification_gateway.dart`/`VerificationLogic`。
> 基线对照：`docs/deep_audit/bA7_c3.md`（MD3 40/100 fail；119 处硬编码中文；Motion 2/10）。阶段 A 修复基线见 `DEEP_AUDIT_PHASE_B_PLAN.md` §2。

---

## 视角 C3 · lib/logic/player/queue_state.dart:73,104-120 · P0 · 播放体验·循环模式失效
证据：`queue_state.dart:8-9` 定义 `PlayMode {sequence, loopOne, shuffle}`；`:73` 注释「loopOne 也前进（单曲循环由播放器负责）」；`next()`(104-120) 对 loopOne 无任何分支，按 `index+1` 前进（`ni>=length→0`）。全仓 `rg 'LoopMode|setLoopMode'` 零命中——`audio_gateway.dart` 从未调用 just_audio 的 `setLoopMode`。`playback_session.dart:onCompleted()` 播完即 `next()`。
问题：用户点「循环」（单曲循环）后，多曲队列里播完当前曲会**跳到下一首而非重播本曲**，单曲循环完全不生效；只有队列仅 1 首时因 wrap 到 index 0 才碰巧「循环」。按钮 `:464-470` 反而是高亮 active 的，造成明显假象。
建议：L6 `onCompleted` 在 `mode==loopOne` 时调用引擎重播当前曲（`_engine.seek(0); resume()` 或 just_audio `setLoopMode(LoopMode.one)`，由 L4 暴露意图）；或在 L5 queue 层为 loopOne 的 `next()` 返回当前曲，二者选一并保证按钮态与行为一致。
76 合规：涉及——模式状态在 L5、循环执行责任却悬空（注释称「播放器负责」但 L4 未实现），L5↔L4 接缝职责错位（§0 第 8 条精神）。

---

## 视角 C3 · lib/session/playback_session.dart:210-215 + lib/logic/auth/verification_logic.dart:65-112 · P0 · 20028 验证卡死
证据：`:213` 遇 `needsVerification` 调 `_verification?.onVerificationRequired(20028, cur.hash)`，`VerificationLogic` 置 `state=required`(`:54-58`)。但 `rg 'VerificationState|verification\?'` 全仓仅命中 `playback_session.dart:213` 一处——**L7 无任何 UI 消费该状态**。`getVerifyInfo()`(`:65-79`) 与 `submitVerification()`(`:91-112`) 均为 `needs probe` 桩，直接 return false，不发请求、不闭环。最终用户只在 `ErrorAction('需要人机验证（20028）')` 里拿到一句硬编码文案（`playback_session.dart:231`）。
问题：匿名/风控用户点歌必然触发 20028 → 状态机停在 required，无验证码 UI、无重试出口，播放彻底卡死且提示只读一句 English-ish 文案，正对应用户「什么功能都用不了」痛点。
建议：L7 增 20028 验证弹层监听 `VerificationLogic.state`，接 captcha 完成后经 `submitVerification`→`markSolved`→原请求重试；端点未实测前至少给「需要验证，暂不可用」的可读空态 + 重试按钮，不要静默停死。
76 合规：涉及——L5 验证门面与 L7 UI 断链（跨层接缝状态无人消费），符合本批重点核验项；分工本身（L5 单一门面）合规。

---

## 视角 C3 · lib/logic/player/playback_reducer.dart:159-163 + lib/surface/pages/player_page.dart:308-395 · P0 · 播放错误不展示
证据：`ErrorAction` 写入 `PlayerState.lastError`（`playback_reducer.dart:159-163`），错误文案如「该曲目需要会员权限」「网络异常，请重试」「未找到可播放源」（`playback_session.dart:229-233`）均为用户可读。但 `rg 'lastError' lib/surface lib/session` **零命中**——播放页 builder 只读 `snap.current/positionMs/durationMs/isPlaying/mode/sourceKind/speed`，从不读 `lastError`。出错时 `current` 仍保留、`status=error`→`isPlaying=false`，UI 显示播放三角，点击 `toggle()`→`engine.resume()` 在失败源上空转。
问题：VIP 曲/无源/网络失败时用户看不到任何原因，进度卡在 00:00，点播放无反应——典型「点不动、不知道为什么」痛点。
建议：播放页在读快照分支 `snap.player.status==error && lastError.isNotEmpty` 时展示错误条/空态（优先接 S.of key），并提供「下一首/重试」出口；`toggle()` 在 error 态改为重新 resolve 当前曲。
76 合规：涉及——L5 产生的错误语义未在跨层 L7 落地（错误态丢失，本批接缝重点）。

---

## 视角 C3 · lib/surface/pages/player_page.dart:176,484-490 + lib/session/playback_session.dart:59,281-290 · P1 · 音质档位显示错误
证据：`_openQualitySheet('128')`（`:488`）把「当前档位」硬编码为 '128'；`setQuality` 从不在 `PlaybackSnapshot` 暴露实际 `_quality`（`playback_session.dart:59` 私有字段，snapshot getter 只有 queue/player/mode/speed/volume）。音质列表打勾判断 `qualityParam(q)==current`（`:185`），因 current 恒 '128'，选了 flac/320 后再打开仍是 128 打勾。下载同样硬编码 `mgr.enqueue(cur, '128')`（`:256`）。
问题：音质档位勾选永远显示 128，与实际播放/下载档位不符；用户误以为设置没生效。VIP 用户选高码率后无从确认是否提档（对应 §2「VIP 恒 false」端到端核验）。
建议：把 `quality` 纳入 `PlaybackSnapshot`，播放页用 `snap.quality` 作为 current；下载档位跟随当前音质或给用户选择，不写死 '128'。
76 合规：涉及——L6 状态未向 L7 暴露完整（快照字段缺失）导致 UI 猜测，接缝信息丢失。

---

## 视角 C3 · lib/surface/pages/player_page.dart:325-345 + lib/surface/design/components.dart:9-40 · P2 · 切歌动画缺失
证据：`AnimatedBuilder` 每帧重建封面 `SpCover(url: song.cover)`（`:337-343`）与标题/歌手 `Text`，无 `AnimatedSwitcher`/`Hero`/crossfade，换曲是硬切。`rg` motion token 消费：全 surface 仅 `lyrics_page.dart:159` 用 `Sp.normal/Sp.curve`；player_page/mini_bar 零消费。tokens 虽已补齐 MD3 分档（`tokens.dart:67-75`: fast200/normal300/enter400/screen500 + standard/emphasized/decelerate/accelerate 曲线），却无人用。
问题：播放页切歌/封面切换生硬跳变，与用户「动画也是、细节都是瑕疵，不经看」直接吻合；进度条除原生 Slider 外无动效。
建议：封面与歌名用 `AnimatedSwitcher` + `Sp.emphasized/Sp.screen`（ValueKey=song.hash）做 crossfade+位移；进度条用统一的 Sp 曲线做平滑；延续 baseline Motion 整改方向。
76 合规：不涉及（纯 L7 表现层）。

---

## 视角 C3 · lib/core/audio/notification_gateway.dart:37-40,143-149 + lib/session/playback_session.dart:117 · P1 · 通知栏 seek 不生效
证据：`NotificationControls` 定义了 `onSeek`（`:32`），但 L6 绑定只传 `onNext/onPrev`（`playback_session.dart:117`: `NotificationControls(onNext: next, onPrev: prev)`），**onSeek 恒 null**。`MusicAudioHandler.seek()`（`:143`）直接调 `_player.seek(position)`，绕过 L6 session → 不改 `PlayerState.positionMs`、不 `notifyListeners`；控制集（`:58-62`/`:85-88`）只有 上一首/播放/暂停/下一首，`systemActions` 声明了 `MediaAction.seek` 却无对应 MediaControl 按钮。
问题：锁屏/通知栏拖动进度条虽写到引擎，但播放页/迷你条进度不刷新（状态不同步）；`onSeek` 回调形同虚设。系统 Actions 与实际控件不一致。
建议：绑定 `NotificationControls(onSeek: seek)`，`seek()` 改为经 `onSeek?.call(ms)` 回 L6 统一走 session.seek；补 `MediaControl` seek 控件或移除不一致的 systemActions 声明。
76 合规：涉及——L4 handler 直驱 `_player` 绕过 L6 编排（反向/越级：控制应经 session），接缝职责错位。

---

## 视角 C3 · lib/session/playback_session.dart:86-87,228,251,266 + lib/logic/player/player_state.dart:36 · P1 · 试听音源标识永不可见
证据：L6 在 `_start` 里设置会话字段 `_sourceKind='mv-audio'/'local'/'kugou'`（`:228/251/266`），并注释「待批3-F2 落盘后随 PlayerState 透传」（`:86`）。但 `_emit` 从不把 `_sourceKind` 传给 `PlayerState`；`PlayerState.sourceKind` 恒为默认 `'kugou'`（`player_state.dart:22/36`）。播放页 `if (snap.player.sourceKind == 'mv-audio')` 显示「试听音源」（`player_page.dart:366-374`）**永远为假**。
问题：MV 音频兜底/本地音源被当作普通酷狗音源，用户看不到「试听音源」提示——批3-F2 声称的透传未真正接通。
建议：`_emit` 构造下一状态时 `copyWith(sourceKind: _sourceKind)`，让标记透传到快照；或删除该死字段与 UI 分支避免误导。
76 合规：涉及——L6 持有应属播放状态的字段却未下沉 L5 PlayerState（层职责/透传断链）。

---

## 视角 C3 · lib/surface/pages/player_page.dart:226-236 + lib/surface/pages/mv_page.dart:36-37 · P1 · MV 入口参数契约（需复核）
证据：播放页「查看 MV」用 `current?.albumAudioId ?? 0`（`:232`）构造 `MvPage(albumAudioId: aid)`（`:235`）；`MvPage` 构造确为 `MvPage({required this.albumAudioId})`（mv_page:37），**调用点字段名一致**。但 L5 `playback_service.dart:285` 用 `song.n` 而非 `albumAudioId` 作 MV 兜底 aid，且 `rg 'albumAudioId' lib/logic/catalog/mv_logic.dart` 走的是 `videoIdOfSong(n)`——MV 链路存在 `albumAudioId` 与 `n` 两套 aid 口径；`albumAudioId==0` 时仍 push MvPage（会进入空态「这首歌暂无可播 MV」）。
问题：MV 入口本身可达（字段名对齐），但 aid 取值口径不统一、0 值无守卫，可能大量歌曲点进去是空 MV；此项属 B4 主责，C3 仅记接缝风险（详见 B4）。
建议：统一 MV aid 来源（albumAudioId vs n），进入前判 `aid>0`，否则提示「暂无 MV」而非进空页。
76 合规：涉及——MV aid 语义在 L4 模型/L5 逻辑/L7 入口三处口径不一（跨层字段契约）。

---

## 视角 C3 · lib/surface/design/mini_bar.dart:12-91 + lib/surface/shell.dart:121,139-153 · P1 · 迷你条常驻与点击体验
证据：`SpMiniBar` 由 shell 置于 `Column` 中、`Scaffold.body`（`shell.dart:121`），非播放页时恒定显示（有 current 即渲染），`AnimatedBuilder(animation: session)` 同步播放态/歌名/封面（`:21-28`）。`InkWell.onTap=onExpand`（`:43`）→ shell `_openPlayer()` push 全屏播放页（`shell.dart:139-153`）。控件：播放/暂停 `:73-81`、下一首 `:82-88`，均标准 IconButton。
问题：正面项——迷你条常驻、点击可进播放页、状态经 session 同步。缺口：① 无「上一首」，只能从播放页操作；② 行高 `Sp.barH`+两个 40+dp 图标，触控目标够但文字区 `bodyMedium/bodySmall` 用 `Theme.of` 文本色，而底色 `Sp.bgElevated` 静态色——浅色主题下文本色可能不匹配（承 baseline Color 2/10）；③ 点击整条与「下一首」IconButton 相邻，`InkWell` 与子 IconButton 点击区需确认不误触（结构上 Material/InkWell 包裹 Row，IconButton 自身消费点击，正常不冲突）。
建议：补上一首按钮；色值改用 `Theme.of(context).colorScheme` 语义角色（消除浅色主题隐患）。
76 合规：不涉及（L7 表现层；状态源 L6 正确消费）。

---

## 视角 C3 · lib/surface/design/components.dart:276-330 · P2 · 播放按钮状态层/触控
证据：`SpPlayButton`(`:276`) 绿底 `Sp.green` + `CircleBorder` + `Colors.black` 图标，64dp；`SpRoundButton`(`:309`) `IconButton` + `VisualDensity.compact`，`color: active ? Sp.green : Sp.text`。二者均无 M3 状态层（pressed/hover/focus 的 8%/16% overlay 未显式构造），active 态仅靠颜色区分，无 `Semantics` 标签/tooltip 依赖外部传入（`SpRoundButton.tooltip` 可选）。
问题：播放/暂停与循环/随机按钮缺少 M3 状态层与明确语义标签，读屏用户难辨当前播放/循环状态；compact density 使触控圆区域偏小（<48dp 风险）。
建议：用 `IconButton` 的 M3 `style` + `states` 构造状态层；active 态补 `Semantics(selected: active)` 或 `Tooltip` 强制；取消 compact density 保证 48dp。
76 合规：不涉及（纯 L7 组件）。

---

## 视角 C3 · lib/surface/pages/player_page.dart（多处）· P1 · 文案接线：播放页大量硬编码中文未接 S.of
证据：`rg '[一-龥]'` 播放页用户可见硬编码中文（非注释）逐行：
- `:92` tooltip「取消收藏/收藏」（FavoriteButton，未接 S.of）
- `:114` SnackBar「收藏失败：$e」
- `:147` SpSectionHeader「播放速度」
- `:176` SpSectionHeader「音质」
- `:204` Text「歌词」
- `:215` Text「评论」
- `:226` Text「查看 MV」
- `:242` Text「下载当前歌曲」
- `:271` SnackBar「下载失败：$e」
- `:279` Text「个人 FM」
- `:289` SnackBar「FM 暂无可用曲目（端点待实测）」←把开发状态暴露给用户
- `:296` SnackBar「FM 启动失败：$e」
- `:321-322` SpStateView「暂无播放/播放队列为空」
- `:357` Text「未知歌手」
- `:369` Text「试听音源」
- `:407/:415` tooltip「收起/更多」
- `:440/:450/:459/:465` tooltip「随机/上一首/下一首/循环」
- `:487` ActionChip「音质」

已接 S.of 仅 6 处：`:99/:107/:109`（favorite*）、`:250/:262/:263`（download*）。`lib/surface/l10n/s.dart` 门面齐备、`S.of(ctx).t(key)` 可用，favoriteUnavailable 等 6 个 key 在 10 份 arb 全覆盖——**接线能力具备，播放页未用**。
问题：播放页约 24 处中文硬编码未接 i18n，切语言不生效，与用户「相关文案也没改」一致；其中「端点待实测」暴露开发态。
建议：上述文案逐一入 arb（10 语）并改 `S.of(context).t(key)`；开发态文案改用户可读占位。
76 合规：涉及——i18n 常量在 L4、门面在 L7，播放页跳过门面硬编码（文案断链，B7 主责）。

---

## 视角 C3 · lib/surface/design/mini_bar.dart:78,84 · P2 · 文案接线：迷你条硬编码中文未接 S.of
证据：`:78` tooltip `playing ? '暂停' : '播放'`；`:84` tooltip「下一首」。全文件零 `S.of`/`.t(` 命中（`mini_bar.dart` 未 import l10n）。
问题：迷你条 3 处控制 tooltip 硬编码，切语言不变（承 baseline「mini_bar 各 1–2 处」）。
建议：入 arb + `S.of(context).t('pause'/'play'/'next')`。
76 合规：涉及——文案断链（B7 主责）。

---

## 视角 C3 · lib/surface/pages/player_page.dart:30-61 + lib/surface/design/tokens.dart:67-75 · P2 · M3/Color 局部：Sp.* 绕过 ColorScheme
证据：`_SeekSlider` 用 `activeColor: Sp.green`/`inactiveColor: Sp.divider`（`:44-45`）；`SpPlayButton` `Sp.green`+`Colors.black`；播放页正文 `color: Sp.text/Sp.textSub/Sp.textFaint` 共约 25 处 `Sp.*` 色引用（`rg` 统计 player_page+mini_bar 命中 25 行）。`Theme.of` 在播放页零命中（仅 mini_bar `:38` 取 textTheme）。承 baseline `bA7_c3.md`：Color 2/10、`Sp` 20 处硬编码色绕过 ColorScheme、浅色主题白底白字。
问题：播放页完全绕过 ThemeData/ColorScheme 消费静态色，深色写死；切浅色主题封面/文字/按钮配色失配（对比度致命风险，承基线）。
建议：播放页改 `Theme.of(context).colorScheme.primary/onPrimary/surface/onSurface`；Slider 用 `sliderTheme` 语义色。
76 合规：不涉及（L7 表现层；仅主题消费方式问题，主题构建合规）。

---

## 视角 C3 · lib/surface/pages/lyrics_page.dart:55,139-159 · P2 · 歌词同步（播放页关联）
证据：歌词定位用 `Timer.periodic(200ms)`（`:55`）轮询 `snap.player.positionMs`（`:139`），`_scroll.animateTo(target, duration: Sp.normal, curve: Sp.curve)`（`:159`）。承 baseline：该 200ms 轮询是业务定时而非过渡动画、无 mounted 保护曾被 C2 记 P1。
问题：歌词滚动靠固定轮询而非播放进度流驱动，200ms 粒度造成歌词高亮/滚动轻微滞后；若 mounted 保护缺失有切页崩溃风险（C2 详审）。
建议：改为监听 session 的 position 流做增量更新，保留 Sp 曲线缓动；确保 dispose 取消 Timer。
76 合规：涉及——L7 Widget 内持有 Timer 轮询（§0「L7 只画控件」越界，承 A7-C1）。

---

## 播放体验走查

| 交互 | 结论 | 证据/痛点 |
|---|---|---|
| 点歌能否立即播 | ⚠️ 部分 | 本地/在线主链通（`playback_session.dart:257-270` resolve→engine.play），但匿名 20028 必卡（P0-2）、VIP/无源错误不展示（P0-3） |
| 进度条拖动跟手 | ✅ 基本达标 | 拖本地预览、松手才 seek（`_SeekSlider`:48-58），reducer 引用稳定防重建（playback_reducer:159-174）；但通知栏 seek 不同步（P1-6） |
| 暂停/继续 | ✅ | toggle→engine.pause/resume+reducer（playback_session:272-294），mini_bar/播放页共享 session |
| 上/下一曲 | ✅ 基本 | next/prev→queue.next/prev→_start（:296-318）；仍走错误兜底路径 |
| 循环/随机模式 | ❌ 循环失效 | loopOne 仅高亮不重播（P0-1）；shuffle 用哈希步进可复现（queue_state:124-140），基本生效 |
| 歌词同步 | ⚠️ | 200ms 轮询驱动，有滞后（P2-11） |
| VIP 曲提示 | ❌ | noPrivilege 文案写入 lastError 但 UI 不读（P0-3） |
| 20028 验证 | ❌ 卡死 | 状态机到 required 但零 UI、端点桩（P0-2） |
| MV 入口 | ⚠️ | 字段契约一致、可 push，但 aid 口径/0 值风险（P1-8，B4 主责） |
| 收藏/下载反馈 | ✅ | FavoriteButton 真 toggle+SnackBar（:96-125）、下载 enqueue+反馈（:244-273）；但档位写死 128（P1-4） |

---

## 文案接线清单（播放主链路，文件:行）

统计口径：用户可见中文串、非注释、未走 `S.of(...).t(...)`。

**player_page.dart（约 24 处）**：`:92`(收藏tooltip) `:114`(收藏失败) `:147`(播放速度) `:176`(音质) `:204`(歌词) `:215`(评论) `:226`(查看MV) `:242`(下载当前歌曲) `:271`(下载失败) `:279`(个人FM) `:289`(FM端点待实测) `:296`(FM启动失败) `:321`(暂无播放) `:322`(播放队列为空) `:357`(未知歌手) `:369`(试听音源) `:407`(收起) `:415`(更多) `:440`(随机) `:450`(上一首) `:459`(下一首) `:465`(循环) `:487`(音质chip)。
**mini_bar.dart（3 处）**：`:78`(暂停/播放tooltip) `:84`(下一首tooltip)。
**已接 S.of（6 处，仅作对照）**：player_page `:99/:107/:109/:250/:262/:263`。

合计播放链路未接 S.of：**约 27 处**（player_page 24 + mini_bar 3）。门面 `lib/surface/l10n/s.dart:31-39` 与 10 份 arb 齐备，接线可行性无障碍。

---

## 本视角结论

1. **3 个 P0 用户可感故障**：单曲循环失效（loopOne 只高亮不重播）、20028 验证零 UI 卡死、播放错误文案写入 lastError 但 UI 完全不读——三者叠加直接兑现「什么功能都用不了」痛点。
2. **通知栏**：元数据（歌名/歌手/封面/时长）在起播成功后正确推送（`playback_session.dart:238-246`/`:274-282`），上一首/下一首/播放/暂停可用；但 **seek 回调未绑定**（onSeek 恒 null）、handler 直驱引擎导致进度不同步，是主要缺口。
3. **循环/随机**：随机（shuffle）用可复现哈希步进基本生效；循环（loopOne）确认失效，需 L4/L6 补 LoopMode。
4. **动画/M3**：MD3 分档 motion token 已在 `tokens.dart:67-75` 补齐，但播放链路零消费——切歌/封面硬切，播放按钮无状态层，Sp.* 静态色绕过 ColorScheme（承 A7 baseline）。
5. **迷你条**：常驻/点击进播放页/状态同步/控件可达均达标（正面），仅缺上一首与浅色主题色值隐患。
6. **文案**：播放链路约 27 处中文硬编码未接 S.of，且「FM 端点待实测」把开发态暴露给用户。
7. 阶段 A 修复核验：收藏/下载按钮已从假按钮改为真 toggle（生效）；20028/MV aid/音质档位透传仍存接缝断点（见上）。

## 未覆盖

- 运行态真实机播放/锁屏控制（需真机；本轮只读静态代码）。
- MV 全链路（B4 主责）：videoIdOfSong→qualities→playUrl→video_player 渲染未逐段追踪，仅记 aid 口径接缝。
- 通知栏封面远程 URL（`artUri` 为 http 链接）在锁屏的实际加载/缓存表现（需真机）。
- 各按钮 48dp 触控目标的精确像素测量（仅据 VisualDensity.compact 做风险判断）。
- 歌词同步的运行时滞后量化（仅静态确认 200ms 轮询机制）。
- 通知栏 seek 在 Android MediaSession 实际的 systemActions/MediaControl 呈现（固件相关，需真机）。

## 76 合规小结

- **职责错位/状态丢失（跨层接缝）**：① 循环责任悬空——L5 注释「播放器负责」但 L4 未实现 LoopMode；② 20028 状态机 L5 产出但 L7 零消费；③ `lastError` L5 产出 L7 不读；④ `sourceKind` L6 私有字段未透传 L5 PlayerState；⑤ 音质档位 L6 私有未入快照致 L7 猜测。
- **反向/越级调用**：通知栏 `MusicAudioHandler.seek/play/pause` 直驱 `_player`（L4 绕过 L6 编排），`onSeek` 定义在 L6 却未绑定——控制流应统一经 session。
- **层归属正确项**：播放会话编排在 L6、reducer/队列/策略在 L5、音频/通知适配在 L4、UI 在 L7，六桥 import（`bridge_core`/`bridge_logic`/`bridge_session`/`bridge_kernel`）使用合规，无影子桥；引擎经注入、无反向 import surface。
- **L7 越界**：歌词页持有 `Timer.periodic` 轮询（承 A7-C1「L7 只画控件」违反）。
- **i18n 归属**：常量/arb 在 L4、门面在 L7 合规，缺口在消费侧（B7 主责）。

---
*落盘完成（append-only）· B3-C3 用户痛点专项视角 · 2026-11-17*
