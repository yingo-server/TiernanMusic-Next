# B3 批 · C2 实现正确性视角 · 播放主链路跨层审查

> 审查人：阶段 B · B3 · C2。起审 2026-11-17 07:36 LCL。
> 前置：`docs/DEEP_AUDIT_PHASE_B_PLAN.md`（已读全文）；`bA5_summary.md`、`bB1_summary.md`（已读）。
> 工具纪律：全程 `file_read` + shell `ls`/`rg`/`wc`，只读源码；唯一写＝本文件 append。未跑 dart/analyze/test/门禁，未联网，未改源码。
> 范围（逐文件连续读完）：L7 `player_page.dart`(516)/`mini_bar.dart`(92)；L6 `playback_session.dart`(425)/`bootstrap.dart`(297)；L5 `lib/logic/player/` 9 文件；L4 `audio_gateway.dart`/`notification_gateway.dart`/`play_endpoints.dart`/`play_models.dart`。
> 优先级口径：跨层链路断裂且用户可感知＝P0/P1；单点状态不同步/死字段＝P2。

---

## 视角 C2 · bootstrap.dart:118-128 + playback_service.dart:113-165,141-147 · P0 · 权益判定（VIP 提档链未闭环，B1 X1 延续）
证据：
- bootstrap 仅在启动时读一次 settings 快照并注入 final 字段：
  ```dart
  session: <String, Object?>{
    'vip_token': settings.getString('auth.vip_token') ?? '',
    'vip_type': settings.getString('auth.vip_type') ?? '',
  },
  ```
  `PlaybackService` 构造 `final Object? _session;`（final，无更新口）。
- `_hasRights` 只读 `_session`；`_qualityCandidates`：`final start = _hasRights ? 0 : _ladder.indexOf(prefer);`（`_ladder=['flac','320','128']`）。
- 登录回写发生在 `auth_logic.dart:434` / `ykg_logic.dart:154`（`auth.vip_token/vip_type`），均在 `bootstrapSession` 之后。
问题：启动后登录（含 YKG 导入）的 VIP 用户，`_session` 仍是构造时匿名快照，`_hasRights` 恒 false，永远从请求档降而不提档——B1 确认的 P0 跨层未闭环在 B3 播放链复现且无其它补偿路径。
建议：`_session` 改为可注入的 `bool Function()` 实时读 settings，或登录后广播重建 PlaybackService 并 `PlaybackSession.attach` 重绑；同时补「启动前已 restoreSession」与「启动后登录」两条时序回归。
76 合规：合规（L6 装配注入 L5 合法）；属跨层生命周期接缝缺陷，非越级。

---

## 视角 C2 · player_page.dart:166-186 / settings_page.dart:93-98 / quality_endpoints.dart:32-64 / playback_service.dart:136-147 · P1 · 音质档位参数错配（VIP 提档第二断点）
证据：
- L7 菜单用 `vipQualities()` 9 档，`qualityParam(q)` 产出 `'super'/'viper_atmos'/'viper_tape'/'viper_clear'/'multitrack'` 等协议串，直接 `setQuality(qualityParam(q))`。
- `getPlayUrlV5` 只对 magic 6 档（`piano/acappella/subwoofer/ancient/dj/surnay`）补 `magic_$q=1`；对 `'super'/'viper_*'/'multitrack'` 无映射，原样当 `quality` 传服务端。
- `quality_endpoints.dart` 提供了 `toPlayUrlQuality(q)`（去前缀）却无调用点（全仓仅定义+桥导出）；L7 用的是 `qualityParam` 而非它。
- `PlaybackService._ladder` 仅 `flac/320/128`，`_qualityCandidates('super')` → `['super','flac','320']`。
- `_openQualitySheet('128')` 把当前档硬编码为 128：选了高音质重进播放页，勾选标记永远落不到实际档位。
问题：VIP 9 档中只有 128/320/flac/high 真正映射到端点参数；qSuper/蝰蛇3档/多轨被当未知 quality 透传，提档链在参数层二次断裂；且 UI 勾选态恒显示默认 128。
建议：L7 统一走 `toPlayUrlQuality`；端点为 `super`/`viper_*`/`multitrack` 补对应请求参数（或明确标注「暂不可用」勿给可点假档）；`_openQualitySheet(snap.player 的真实档位)` 替换硬编码 `'128'`；把 `high` 纳入 `_ladder`。
76 合规：合规（L7 经桥取档位常量）；参数映射职责应留 L4 端点，当前 L7 直取协议串属接缝契约不一致。

---

## 视角 C2 · playback_session.dart:222-259 / notification_gateway.dart:95-113 · P1 · 通知栏首曲元数据丢失（A4 残留，跨层确认为真）
证据：
```dart
initNotification(...).then((h) { _notification = h; });   // attach 中异步赋值
...
// _start 起播成功后：
_notification?.updateMetadata(NotificationMeta(...));      // 此时 _notification 常为 null
```
- `initNotification` 是 async（`AudioService.init`），`_notification` 在 `attach` 的 `.then` 才赋值；`playAll/playSong` 若在 attach 后立即触发（首页点歌、冷启动恢复播放），`_start` 的 `_notification?.` 空安全短路→**首曲通知栏只有播放状态、无标题/歌手/封面**。
- 之后切歌才更新，故只有第一首丢；`notification_gateway._bind()` 只同步 playbackState，从不补 mediaItem。
问题：初始化竞态导致用户可感知的首曲通知栏元数据丢失，A4 残留问题在播放跨层链上确实影响用户。
建议：`attach` 把 initNotification 的结果（Future）缓存；`_start` 在 `await` 该 Future 后再 updateMetadata，或在 handler ready 时用「当前曲快照」补一次元数据；`MusicAudioHandler.bind` 后主动补推最近一次 meta（session 保留 lastMeta 重放）。
76 合规：合规（L4 网关经 control 回调，不反向 import）；属跨层异步初始化接缝。

---

## 视角 C2 · notification_gateway.dart:26-30,130-145 / playback_session.dart:110-121,262-266 · P2 · onSeek 死字段 + 通知栏 seek 未走会话状态机
证据：
- `NotificationControls` 定义 `onSeek`，但 `attach` 只注入 `NotificationControls(onNext: next, onPrev: prev)`——**onSeek 恒 null**；`MusicAudioHandler.seek()` 直接 `_player.seek(position)` 绕过 session。
- 通知栏拖动进度会改 just_audio 实际位置，但不经 `_onEngineEvent` 之外的会话seek 路径，`PlaybackSession._player.positionMs` 靠 positionStream 回填（能追上，但状态机 SeekTo 语义未参与）；同时 UI 未声明 seek 控件（systemActions 含 seek 却 unimplemented 业务回调）。
问题：onSeek 是死字段，通知栏 seek 与会话层 SeekTo 语义脱节；属状态多跳同步的接缝瑕疵，用户可感知性中等（进度显示最终会追上）。
建议：attach 注入 `onSeek: seek`；`MusicAudioHandler.seek` 转调 `_controls.onSeek`，保持 L6 为唯一翻译点（也符合「L7/L4 无状态机」）。
76 合规：合规但违反「回调应闭合」——定义了未用字段；建议补齐以守住 L6 唯一状态翻译点。

---

## 视角 C2 · queue_state.dart:73-105 / playback_session.dart:315-320,399-413 / audio_gateway.dart 全 · P1 · loopOne 单曲循环无实现（A6 残留，跨层确认）
证据：
- 枚举注释：`// loopOne 单曲（循环由播放器处理，状态机只前进）`；`next()` 中 loopOne 无任何分支，直接 `ni=index+1`（到底回 0）。
- 播放会话 `onCompleted() -> next()`：`void onCompleted(){ _emit(Completed()); next(); }`——播完无条件进下一曲。
- `JustAudioEngine` 无 `setLoopMode`，`AudioEngine` 接口无循环方法；全仓 `rg loopMode|LoopMode` 零命中（仅 UI 按钮 `player_page.dart:464-470` 切 `PlayMode.loopOne`）。
问题：单曲循环按钮点了仅高亮状态，播完仍跳下一曲——A6「loopOne 按钮无实现」跨层确认，用户功能承诺落空。
建议：方案一 `PlaybackSession.onCompleted` 读 `_queue.mode==loopOne` 时用 `_engine.seek(0); _engine.resume()` 重播当前曲；方案二 `AudioEngine` 加 `setLoopMode` 透传 just_audio（`just_audio` 原生支持 LoopMode.one），session 在 setMode/切曲时同步；二选一并补「播完行为」回归。
76 合规：合规（状态机在 L5/L6 正确）；循环是播放控制语义，应落 L5/L6，当前缺实现非越位。

---

## 视角 C2 · playback_session.dart:86-87,228,251,266 + player_state.dart:72-84 / player_page.dart:366 · P2 · sourceKind 死字段（MV 试听标识永不显示）
证据：
- session 持有 `String _sourceKind`，仅在 `_start` 内局部赋值 `'mv-audio'/'local'/'kugou'`；但 `_emit`/`playbackReducer(... Playing())` 从不以 `sourceKind` 调 `copyWith`。
- `PlaybackSnapshot.player` 来自 `_player`，其 `sourceKind` 恒为构造默认 `'kugou'`（`PlayerState` 默认 + reducer 无写入）。
- L7 判断 `if (snap.player.sourceKind == 'mv-audio')` 显示「试听音源」——条件恒 false。
问题：MV 兜底音源在 L6 记录了类型却未透传到 L7 快照，试听标识永不出现；死字段 + 跨层状态未透传。
建议：在 `Playing()`/StartLoad 的 reducer 或 session `_emit` 里把 `_sourceKind` 写入 `PlayerState.copyWith(sourceKind: ...)`，或让 `Playing` action 携带 sourceKind。
76 合规：合规（字段定义在 L5、消费在 L7）；属跨层状态透传遗漏。

---

## 视角 C2 · play_resolver.dart 全 + quality_policy.dart 全 + play_source_parser.dart/url_health.dart · P1 · resolve→play 全链另一套死代码（A5 X5，B3 确认仍在）
证据：
- `play_resolver.dart` 仅 import `play_source_parser`/`quality_policy`/`url_health`；全仓 `rg PlayResolver` 除自身外零命中，bridge 无导出。
- `quality_policy.downgradeChain/decide` 的唯一调用者是 play_resolver；`parse()`/`UrlHealthChecker.firstHealthy` 同理。
- 真正 live 链是 `PlaybackSession._start -> PlaybackService.resolvePlaySource`（playback_service.dart:169+），其内置另一套 `_ladder` 与 `_mapError`，与 quality_policy 的 `kQualityLadder`（含 magic/high）和 decide 语义**不共享**。
问题：存在两套并行音质降级/错误映射逻辑，live 链用 playback_service 内联版，play_resolver 整套（含更完整的 20028/noPrivilege/exhausted 状态机与健康探测）是死代码——重复实现且死代码易误导后续维护，符合 A5「整套 PlayResolver 死代码」结论。
建议：明确废弃方向：要么让 PlaybackService.resolvePlaySource 组合 PlayResolver（复用 decide/downgradeChain/url_health），要么删除该死文件集并在注释声明单一实现；避免两套语义漂移（如 `_ladder` 无 high/magic 而 policy 有）。
76 合规：合规（均 L5 同层）；死代码非架构违规。

---

## 视角 C2 · playback_service.dart:169-230,334-371 / play_models.dart:105-135 · P1 · 20028/noPrivilege 分类在降级循环里的边界偏差
证据：
- `resolvePlaySource` 循环内终止条件：`if (pr.errcode == 20028) break; if (pr.status==2 && pr.privKnown && pr.privStatus==0) break;`，`_mapError` 终判。
- `play_endpoints.dart:243` 已把 `error_code` 折叠进 errcode：`errcode: safeInt(res['errcode'] ?? res['error_code'])`，覆盖 35104。
- 但 `PlayResult.needsVerification`（play_models.dart:110）含 `(status==2 && !privKnown && urls.isEmpty)` 分支，`_mapError` 亦复制此逻辑：`if (pr.status==2 && !pr.privKnown && pr.urls.isEmpty) return needsVerification;`。
- 匿名免费曲无 priv_status（privKnown=false）且 status=2、无 url 时→误判 needsVerification（要求人机验证），而实际可能是 31833 错盐（已映射 network）之外的其它失败；分类口径与三态实测「匿名→20028」强绑定，若服务端改返回形态即漂移。
- 另外 `_mapError` 的 `if (pr.urls.isEmpty && pr.isVipTrack) return noPrivilege`：`isVipTrack` 来源 tracker_through.musicpack_advance==1，仅凭标记+无 url 判无权限，可能是网络/签名失败被误判 noPrivilege。
问题：错误分类在「状态2+priv缺失」与「VIP标记+无url」两处用启发式兜底，存在把非验证/非权限失败误分类风险，影响用户提示与验证 UI 触发。当前三态实测下大体可用，属跨层契约强耦合的健壮性问题。
建议：以 errcode 为主键（20028→needsVerification、31833→network、35104→notFound），priv 仅作辅助；无 errcode 的兜底统一落 notFound/network 并打日志，勿用 isVipTrack 猜 noPrivilege；补三态字段矩阵回归。
76 合规：合规（分类在 L5，端点在 L4）；跨层字段口径需以实测契约对齐。

---

## 视角 C2 · playback_service.dart:177-197 / playback_session.dart:262-266 · P2 · 本地优先判定只认 hash+complete+文件存在，未校验音质档位匹配
证据：
```dart
final rec = _store.getByHash(hash);
if (rec != null && rec.complete) {
  final path = _store.absolutePathOf(rec);
  if (path != null && File(path).existsSync()) {
    return PlaySource(localPath: path, quality: rec.quality); // 离线命中
  }
}
```
- `File(path).existsSync()` 是 IO 直连（A5 X4 已记 6 处 IO 债之一）。
- 本地命中直接返回，不比较 `rec.quality` 与请求的 `preferQuality`：用户切到更高音质或在线重下后，仍可能播旧的低档离线文件。
问题：离线优先链功能本身可达（已下载可播，且文件缺失会正确回退在线，边界防御到位），但跨层语义上「音质选择」对本地文件无效；existsSync 属 logic IO 直连债延续。
建议：命中本地时若 `rec.quality` 与 preferQuality 不一致且期待在线更高档，可提示用户或选择在线；IO 探测下沉 L4（download_store 提供 exists 门面）；属体验瑕疵非断链。
76 合规：部分违反 §0「L5 无 IO 直连」（File.existsSync），继承 A5 X4；建议在 L4 存储门面补 exists 能力。

---

## 视角 C2 · player_page.dart:18-58 / playback_session.dart:336-345 / playback_reducer.dart:113-122 · P2 · 进度条拖动本地预览与 seek 的跨层时序
证据：
```dart
// _SeekSlider.onChangeEnd：
setState(() => _preview = null);
playbackSession().seek(v.round());
// didUpdateWidget：外部位置追上预览(<900ms)才清 _preview 交还真实进度
```
- `seek` → `_engine.seek` (async) 同步紧接 `_emit(SeekTo(ms))` 更新快照 positionMs；just_audio 的 positionStream 随后回推真实位置。
- reducer `Progress` 在 `state.status != playing` 时直接 return state（防旧流覆盖），playing 态下才更新；SeekTo 在 reducer 内截断 `p>d?d:p`。
问题：本地预览设计正确（松手才 seek，避免拖动中反复 seek）；但跨层看，seek 后 engine 是异步 seek，positionStream 可能短暂回推 seek 前的旧位置，`_preview` 已在 onChangeEnd 立刻清空，若 engine seek 尚未生效会出现进度条「回跳一下」再追上；900ms 容差是权宜，非强一致。用户可感知性低。
建议：seek 时保留 `_preview` 直到 engine 回推位置接近目标（监听快照 positionMs 落在目标附近）再交还；或 seek 后短暂 ignore 旧 position 事件。
76 合规：合规（拖动本地态在 L7 Widget 内、seek 意图经 L6）；L7 无播放状态机（预览仅 UI 态），合规。

---

## 视角 C2 · playback_session.dart:170-282 / verification_logic L7 出口（bB1 X2 延续） · P1 · 20028 验证 UI 出口缺失在播放链末端仍卡死
证据：
```dart
if (err == PlaybackError.needsVerification) {
  _verification?.onVerificationRequired(20028, cur.hash);
}
```
- session 正确触发了验证门面状态机（阶段A修复生效），但 `onVerificationRequired` 只置 required 状态；全仓 L7 无验证入口 UI（`rg` 无 verify sheet 消费者）；`verification_logic.getVerifyInfo/submitVerification` 仍 return false 不发请求（bB1 X2）。
- 播放链末端：遇 20028 → 提示「需要人机验证（20028）」→ 用户无任何可操作出口 → 卡死。
问题：跨层链路在 L6 正确上报，但 L7 UI 出口 + L5 端点两段仍断，B1 判定的 P0 未闭环在 B3 播放链末端表现一致。
建议：L7 播放页/错误态提供验证入口（最小可用：明示「验证暂不可用，请稍后重试」避免假卡死）；getVerifyInfo/submitVerification 落实端点；与 B1 修复合并推进。
76 合规：合规（session 只上报，不实现验证）；断点是 L5 端点与 L7 UI，非本层越位。

---

## 视角 C2 · playback_session.dart:218-244 / playback_service.dart:271-327 / player_state.dart:36 · P2 · MV 兜底 isFallback 标记与 _sourceKind 未进快照（试听链路字段空转）
证据：
- `resolveMvAudioFallback` 返回 `PlaySource(isFallback: true, extName:'mp4', quality:'mv-audio-low')`，但 L6 兜底分支只用 `mv?.urls.first` 与时间长度，`PlaySource.isFallback` 从未被读取。
- session 用局部 `_sourceKind='mv-audio'` 记录，但未写入快照（见前述 sourceKind 死字段条）。
- 结果：`isFallback`/`_sourceKind` 两个标记都空转，L7「试听音源」永不显示。
问题：MV 兜底音频能播（功能可达），但兜底身份在跨层传递中两次丢失，用户无从得知当前是 MV 音轨替代源。与 sourceKind 条同源，合并修复即可。
建议：兜底成功后把 isFallback → PlayerState.sourceKind='mv-audio' 一次写入快照；删除冗余的 session 私有 _sourceKind，统一以快照为准。
76 合规：合规；属跨层字段透传遗漏。

---

## 视角 C2 · playback_session.dart:96-121 / player_page.dart:280-320 · P2 · snapshot 无 lastError/状态暴露，播放失败仅靠 flag 无可见文案出口
证据：
- `PlaybackSnapshot` 仅含 queue/player/mode/speed/volume，player 内有 `lastError`；`_start` 失败 `_emit(ErrorAction(errText))` 写 lastError，但 `player_page.dart` build 中未读取 `snap.player.lastError` 展示错误提示（页面只画 slider/controls/badges）。
- 错误态下 AnimatedBuilder 仍按正常页渲染（song 仍在 queue），用户看不到「需要验证/无权限/未找到源」文案，只能看到进度不动。
问题：错误语义在 L6/L5 正确生成文案，但 L7 播放页未消费 lastError → 用户看不到失败原因（与状态机断链互补的「最后一公里」展示缺口）。mini_bar 同样无错误态展示。
建议：PlayerPage/SpMiniBar 在 `snap.player.status==error` 时用 SpStateView 或 SnackBar 展示 `lastError`，并提供重试（调 `_start` 当前曲）。
76 合规：合规（L7 只读快照）；属跨层状态未消费，非越位。

---

## 视角 C2 · playback_session.dart:170-176,309-332,387-396 + queue_state.dart:207-212 · P1 · 每次换曲 _start 重建 QueueState 导致 shuffle/loopOne 模式被重置为 sequence
证据：
```dart
// _start：
final q = song != null
    ? const QueueState().replaceQueue(<SongBrief>[song], 0)
    : const QueueState().replaceQueue(songs, start);   // ← const QueueState() mode=sequence,seed=0
```
- `setMode(shuffle/loopOne)` 通过 `_queue.withMode(mode)` 设置了模式；但随后任何 `next()/prev()/playAt()/setQuality()`（都走 `_start`）都用 `const QueueState()` 重建队列，`replaceQueue` 只带 items+index，**mode 与 seed 丢失，回到 sequence**。
- 具体：选 shuffle 后按下一首 → `_queue.next()` 这一跳确实用 shuffle 算了 index，但 `_start` 重建后 `_queue.mode` 已变回 sequence → 再按下一首就是顺序播放，随机模式一次即失效。loopOne 同理（且 loopOne 本就无实现）。
- `QueueState.replaceQueue` 签名不带 mode/seed，无法保留。
问题：播放模式是会话级状态，却在每次换曲的编排接缝被重置——用户切了随机/循环，播一首就失效。这是跨层状态归属与重建逻辑的正确性缺陷，用户可感知。
建议：`_start` 保留当前模式：`_queue.replaceQueue(songs, start)` 并在 replaceQueue 内透传 mode/seed（新增可选参数），或 `const QueueState().replaceQueue(...).copyWith(mode:_queue.mode, seed:_queue.seed)`；playSong（单曲）是否重置模式需明确语义。
76 合规：合规（状态机在 L5）；属 L6 编排重建时未透传状态的跨层接缝 bug。

---

## 视角 C2 · queue_state.dart:107-125,17 · P2 · shuffle 伪随机固定 seed=0 且非真排列（可重复选曲/每次同序）
证据：
- `seed` 默认 0 且全仓无改写（rg 确认仅定义/透传），`_shuffleStep` 用 `seed ^ base*0x9E3779B9` 的哈希跳转取 target。
- 算法是「按当前 index 哈希跳一格」，非洗牌排列：可能在遍历完所有曲目前重复命中同一首；且 seed 恒 0 → 每次进入 shuffle 的序列完全一致（可复现但用户看来不随机）。
问题：随机播放的「随机性」不达标（确定性同序 + 可能重复），属状态机算法正确性问题，用户可感知（以为随机实则固定顺序）。
建议：进入 shuffle 模式时生成随机 seed（如 `DateTime.now().millisecondsSinceEpoch`），或用 Fisher-Yates 生成真排列缓存于 QueueState，next/prev 沿排列步进保证不重复覆盖。
76 合规：合规（算法在 L5 纯函数，无 IO）；seed 随机源应由 L6 注入以保持 L5 纯净（当前 seed 字段正是为此设计，但未接线）。

---

## 本视角结论

1. **VIP 提档链双断点（延续 B1 P0）**：`bootstrap` 构造时快照注入 + PlaybackService._session final，启动后登录的 VIP 恒匿名音质（P0，未闭环）；且 VIP 9 档中 super/蝰蛇/多轨档位参数无端点映射、UI 勾选态硬编码 128（P1）。两处叠加，VIP 提档实质不可用。
2. **队列/循环模式跨层失真（延续 A6）**：loopOne 按钮无任何实现，播完仍跳曲（P1）；`_start` 每次重建 `const QueueState()` 丢弃 mode/seed，shuffle 切一首即回退顺序（P1）；shuffle seed 恒 0 且非真排列（P2）。
3. **resolve→play 双实现**：live 链走 PlaybackService 内联版，PlayResolver+quality_policy+parser+url_health 整套死代码（P1）；20028/noPrivilege 分类两处启发式兜底有误分类风险（P1）。
4. **通知栏异步竞态**：initNotification 异步赋值导致首曲元数据丢失（P1，A4 残留确认真影响用户）；onSeek 死字段+绕过会话状态机（P2）。
5. **状态透传缺口**：sourceKind/isFallback 两个兜底标识未进快照，L7「试听音源」永不显示（P2）；L7 未消费 lastError，播放失败用户看不到原因（P2）。
6. **进度与歌词同步基本正确**：_SeekSlider 本地预览设计对，歌词 200ms 轮询按 hash 触发重载、只更新行索引，跨层同步无明显断裂；仅 seek 后短暂回跳为低风险时序瑕疵（P2）。
7. **本地下载优先功能可达**：hash+complete+文件存在三重判定，文件被清理能正确回退在线（边界防御到位）；但音质档位不匹配时仍播旧文件、existsSync 属 logic IO 直连债延续（P2）。
8. **共性**：异常 try/catch+Log 普遍到位，无静默吞；主要问题集中在「跨层接缝状态未透传/未刷新」而非单层算法错误，印证阶段 B「单点修对≠链路通」的价值。

发现总数：**14 条**（P0×1、P1×6、P2×7）。

## 未覆盖

- 未跑任何 dart/flutter/analyze/test/门禁（纪律禁止），所有结论为静态取证，运行态时序（如首曲元数据竞态、seek 回跳）以代码推断，未经真机复现。
- 未读 `verification_logic.dart`/`auth_logic.dart` 完整实现（仅按 bB1 摘要与 rg 命中举证 20028/登录回写），其端点实测状态沿用 B1 结论未独立复核。
- 未深挖 `AudioService` 原生后台保活/MEDIA_BUTTON 等平台通道行为（属 C1/架构与真机范畴）。
- 未审 B4 MV 播放页链路（本批 B3 范围，MV 仅作 audio 兜底角）；未审下载/收藏入口（B5）。
- 前置要求读的三份文档：计划全文与两份 summary 均已读；但任务正文提到的「A4 通知栏残留」「A6 loopOne」原始报告未单独调阅，仅依据 bA5/bB1 summary 与源码事实定位。
- 文件均经连续通读；`player_page.dart` 分两段（1-465/466-516）读完，无跳读。

## 76 合规小结

- 依赖方向（L7→L6→L5→L4）、六桥通道、状态机归属（播放/队列状态机在 L5、会话翻译在 L6、L7 零状态机）、端点分文件、1500 行门禁：本批范围**全部合规**，无反向依赖、无越级 import、无影子桥。
- 主要 76 债：`playback_service.dart`/`url_health.dart` 的 `dart:io` + `File.existsSync()` 属 §0「L5 无 IO 直连」（继承 A5 X4，非本批新增）；建议 L4 存储/网络门面补 exists/health 能力后下沉。
- 职责接缝：通知栏 onSeek 未闭合、VIP 权益快照生命周期、播放模式在编排重建中丢失——均属「跨层状态归属/刷新」问题，按 76 §0 第 8 条（播放控制归 L6/L5、L6 只暴露状态/回调）应在 L5/L6 内修正，不涉及层职责越位。
- L7 经 `bridge_core` 取 `qualityParam/vipQualities` 常量属合法；但档位协议映射职责应留 L4 端点，当前 L7 直接取协议串透传是接缝契约不一致（非越级，建议收敛）。
