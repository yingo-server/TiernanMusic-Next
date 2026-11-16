# B3 · C1 架构合规视角 · 播放主链路跨层审查

> 审查时间：2026-11-17 · 视角：C1 架构合规 · 依据：DEEP_AUDIT_PHASE_B_PLAN.md + SEVEN_SIX_RULE.md (76原则 V2)
> 纪律：只读；逐文件连续读完；每条结论 append 带时间戳；严禁覆盖。
> 范围：L7 player_page/mini_bar → L6 playback_session/bootstrap → L5 logic/player 全9文件 → L4 audio_gateway/notification_gateway/play_endpoints/play_models

---

## 视角 C1 · lib/session/playback_session.dart:80-81,146-420 · P1 · 状态机归属（§0-8 / §4）
证据：L6 会话直接持有状态机实例 `QueueState _queue = const QueueState();`（:80）、`PlayerState _player = const PlayerState();`（:81）；全文 `playbackReducer(...)` 调用 18 处（:146/149/155/199/230/260/268/283/291/294/304/363/372/381/401/413/420 + import :41），另有队列变更直驱 `_queue.next()/prev()/removeAt()/insert()/withMode()/replaceQueue()`（:312/322/337/346/354/195-196）。阶段 A6 报「≥10 处未修」属实且已增至 18 处。
问题：播放状态机的状态实例与驱动逻辑仍越界滞留在 L6 session，未下沉到 L5 logic/player；`playbackReducer` 函数体虽在 L5，但状态持有者/调用者均在 L6，违背「状态机/队列/reducer 属 L5，L6 只编排」。
建议：将 `_queue/_player` 及 reducer 驱动封装为 L5 的 `PlaybackController`（持有状态、emit action、暴露不可变快照），L6 playback_session 仅保留 resolve→engine→历史→通知→预读触发的编排并调用该 controller 的意图方法。
76 合规：违反第 8 条（播放控制不得放进 L6）；与 §1 表「L6 播放编排」边界重叠，规则文本本身 L6/L7 措辞不一，但实例持有+驱动确在 L6。

---

## 视角 C1 · lib/session/bootstrap.dart:245-249 · P2 · 预读触发接缝（§3 缓存⊃预读）
证据：`PlaybackSession.instance.onQueueChanged = (hashes) { Log.d(...'queue changed n=${hashes.length} (cache keeps LRU warm)'); };` 回调体只有一行 Log，未调用已创建好的 `cacheService.prefetch(...)`；而 `playback_session.playAll`（:170-174）确实在队列变化时 `onQueueChanged?.call(hashes)`。
问题：76 原则 §3 规定「预读触发（队列 upcoming 窗口）由 L6 决定预测哪些键、L4 CacheService 执行写入」，但 L6→L4 的预读执行接缝在此处断开——触发了却无人执行，注释声称「保活」实为纯日志，注释与实现不符。
建议：要么在回调内对 upcoming 键调用 `cacheService.prefetch`（执行权仍在 L4），要么删除该回调并明确此处不做预读，勿留误导性 no-op 接缝。
76 合规：部分符合（触发在 L6、执行权归 L4 的方向正确），但接缝未真正连通，属职责空转。

---

## 视角 C1 · lib/logic/player/play_resolver.dart:71-196（及 play_source_parser/quality_policy/url_health）· P1 · 死代码／职责重复（§0-8 精简职责）
证据：全仓 `rg 'PlayResolver\s*\('` 仅命中 `tool/resolve_contract_test.dart:66`（仅 `read('...play_resolver.dart')` 读文本，非实例化）；`PlayResolver` 未被 bridge_logic.dart 导出（该文件 :10-17 只导出 PlaybackService/HistoryRecorder/queue_state/player_state/playback_reducer）；play_source_parser/quality_policy/url_health 仅被 play_resolver.dart 内部互相 import（:16-18），无外部生产调用方。真正在线主链走 `PlaybackService.resolvePlaySource`（playback_service.dart:181，被 playback_session.dart:201 与 download_manager.dart:297 调用）。
问题：阶段 A5 报的「整套 PlayResolver 死代码」至今未清——四个文件（play_resolver/play_source_parser/quality_policy/url_health，合计 681 行）构成一套与 PlaybackService 平行且更完善的解析／降级／健康检查实现（含 `checkHealth`/`firstHealthy` 可达性探测、`PlayDecision` 三态判定），却完全不接生产链路；真实链路在 PlaybackService 里重复手写降档链 `_qualityCandidates`（:170）与错误映射 `_mapError`（:340），且真实链路缺失 url_health 的健康检查能力。
建议：二选一——(a) 让 PlaybackService.resolvePlaySource 经 bridge_logic 复用 PlayResolver（注入 fetch=getPlayUrlV5、真正启用 url_health），删去重复降档/映射；(b) 若确认不用，删除 play_resolver+play_source_parser+quality_policy+url_health 及 contract test，避免两套语义漂移。
76 合规：符合分层（均在 L5，未越级），但违反「职责单一/无冗余」精神，属死代码与能力倒挂。

---

## 视角 C1 · lib/session/playback_session.dart:87,228,251,266 ↔ lib/logic/player/player_state.dart:22,36 · P1 · 状态字段双写/不同步（§0-8 状态归属）
证据：会话内自持私有字段 `String _sourceKind = 'kugou'`（:87），在 MV 兜底/:228、失败/:251、在线/:266 处赋值；L5 `PlayerState` 另有权威不可变字段 `sourceKind`（player_state.dart:22/36，copyWith :72/84）；L7 播放页读的是 `snap.player.sourceKind`（player_page.dart:366）。但全仓 `_emit(playbackReducer(...))` 序列无任何一处将 `_sourceKind` 写进 `PlayerState.copyWith(sourceKind: ...)`——`_sourceKind` 只写不读（除赋值无消费者），`PlayerState.sourceKind` 只保持默认 `'kugou'`。
问题：音源类型在 L6 私有字段与 L5 状态里双份存在且永不同步，导致 MV 兜底（实际播 mv-audio）或本地播放（local）时，UI 依据 `snap.player.sourceKind` 判断的「试听音源」提示（player_page.dart:366）永远不显示；跨层状态接缝断裂。
建议：删除 L6 私有 `_sourceKind`，将音源类型作为 `PlaybackAction`（如 `SourceChanged('mv-audio')`）经 playbackReducer 写入 `PlayerState.sourceKind`，L7 只读快照字段；单一数据源。
76 合规：违反第 8 条精神与「L6 只编排不持状态」——L6 持有并驱动一份与 L5 重复的状态。

---

## 视角 C1 · lib/logic/player/url_health.dart:8,54,114 · P2 · IO 直连越界（§1 L5 禁 IO 直连 / §0-9 成熟库边界）
证据：`import 'dart:io';`（:8），`HttpClient()` 直接构造（:54 `_newClient`），`client.openUrl(head?'HEAD':'GET', Uri.parse(url))`（:114）——url_health 在 L5 logic/player 内直接发起网络 IO，未走 L4 core/net 的 KugouClient/EndpointRegistry 门面，也未走桥。
问题：76 原则 §1 明确 L5「禁 IO 直连」，§0-9 网络属 L4 core；可达性探测的 HTTP 实现本应下沉 L4（或作为注入的纯回调）。当前实现违反分层（虽属已死的 PlayResolver 链，故降为 P2）。
建议：把 HttpClient 探测迁移到 L4 core/net（如 `UrlProbeGateway`），L5 只保留 `UrlHealthChecker` 的决策逻辑并注入 `probe` 回调；或随死代码一并删除。
76 合规：违反第 4 条（跨层须经桥、L5 不得直连 L4 网络能力）与 §1「L5 禁 IO 直连」。

---

## 视角 C1 · lib/session/playback_session.dart:106-114 ↔ lib/core/audio/notification_gateway.dart:29,32,127-147 · P2 · 通知栏控制接缝不完整（跨层意图通道）
证据：L6 attach 里 `initNotification(just.rawPlayer, NotificationControls(onNext: next, onPrev: prev))`（:106-109）只绑定 next/prev，未绑 `onSeek`；L4 `NotificationControls` 声明了 `onSeek`（notification_gateway.dart:32）却全仓无任何赋值（`rg onSeek` 仅命中声明与 :29）；且 `MusicAudioHandler.seek(Duration)`（:139）直接 `_player.seek(position)` 自己操作引擎，不经 L6 的 `playbackSession.seek` → 不触发 `playbackReducer(SeekTo)`。
问题：通知栏拖动进度虽然能改引擎位置，但绕过 L6 状态机，导致 `PlayerState.positionMs` 与引擎实际位置不同步；`onSeek` 通道声明后悬空未接，是跨层意图通道的死接缝。
建议：attach 时补 `onSeek: seek`，MusicAudioHandler 的 seek/skipToNext 统一转发到 `NotificationControls` 回调（next/prev/seek 全部由 L6 驱动），L4 不直接改引擎状态。
76 合规：部分违反第 8 条（L6 应独占播放控制意图）——L4 网关越权直接 seek 引擎，L6 意图通道缺 onSeek 一环。

---

## 视角 C1 · lib/surface/pages/player_page.dart:1-16,318-329,431-470 · lib/surface/design/mini_bar.dart:1-20 · 合规 · L7 零状态机（§0-8 / §2）
证据：两文件仅 `import '../../bridges/...'`（player_page.dart:3-10、mini_bar.dart:4-7），无任何直连 core/logic/session 的非桥 import（`rg` 命中 0）；播放器只 `final snap = session.snapshot` 后读字段（player_page.dart:322、mini_bar.dart:23）并调意图 `playbackSession().toggle()/next()/prev()/seek()/setSpeed()/setQuality()/setMode()`（:431-470、:45-57）；全文无 `QueueState/PlayerState/playbackReducer` 或状态字段。
问题：无。L7 严格「watch 快照 + 发意图」，零状态机、零跨级 import，符合契约。
建议：保持；注意 FavoriteButton 内 `appGraph.collect`、下载/MV 菜单虽直连 appGraph，但均经 bridge_session 暴露的门面（:11-13），属合法。
76 合规：符合第 8 条、第 1 条、§2 六桥通道。

---

## 视角 C1 · lib/session/playback_session.dart:6-42 · 合规 · 六桥通道（§0-铁律1 / §2）
证据：L6 仅经 `bridge_core`（AudioEngine/JustAudioEngine/NotificationMeta/initNotification）与 `bridge_logic`（PlaybackService/reducer/QueueState/HistoryRecorder/VerificationLogic）取下层能力（:6-42），无 `import '../core/...'` 或 `import '../logic/...'` 直连；L7→L6 经 bridge_session 的 `playbackSession()`/`appGraph`/`navState`（已核）。未发现越级/反向 import。
问题：无越级。分层依赖方向 surface→session→logic→core 成立。
建议：保持。
76 合规：符合第 1、4 条与 §2 六桥通道。

---

## 视角 C1 · lib/core/audio/audio_gateway.dart:1-11 · lib/core/audio/notification_gateway.dart:1-8 · 合规 · 成熟库边界（§0-9 / §1）
证据：just_audio 仅出现在 `core/audio/audio_gateway.dart`（`import 'package:just_audio/just_audio.dart'`，:5），封装为 `AudioEngine` 接口 + `JustAudioEngine` 纯 IO 适配（零 Widget）；audio_service 仅出现在 `core/audio/notification_gateway.dart`（:4-5），`MusicAudioHandler`/`initNotification` 为通知栏网关；二者经 bridge_core 导出（:55-67）。
问题：无。成熟库封装在 L4 core/audio、通知栏网关归属正确，符合 §0-9（能用成熟库就用）。
建议：保持成熟库边界，勿让 audio_service/just_audio 泄漏到 L5/L7。
76 合规：符合第 9 条、§1「core/audio 引擎封装」职责。

---

## 视角 C1 · 全链路 wc · 合规 · 1500 行门禁（§0-5）
证据：`wc -l` 目标文件均远低于 1500：player_page 516、playback_session 425、playback_service 378、play_endpoints 362、queue_state 219、playback_reducer 204、url_health 203、audio_gateway 202、play_resolver 196、quality_policy 143、play_source_parser 139、play_models 179、mini_bar 92、history_recorder 64、notification_gateway 169、player_state 104。（任务书给的 405/376 与实测 425/378 略有出入，以实测为准，均不触门禁。）
问题：无超行。
建议：无。
76 合规：符合第 5 条（1500 行门禁）。

---

## 视角 C1 · lib/bridges/bridge_session.dart:41-68 · 合规 · 桥日志（§0-铁律2）
证据：播放相关桥函数 `playbackSession()`/`navState()`/`moduleRegistry()` 均 try/catch + `Log.e('bridge_session', ...)`（:48-66）；bridge_logic/bridge_core 以 export 门面为主，无逻辑函数需包裹。播放会话自身的 attach/_onEngineEvent/_emit/各意图方法也普遍 try/catch+Log（playback_session.dart:98-117 等）。
问题：无静默吞。桥与会话日志留痕到位（唯 `:87 _sourceKind` 赋值无日志，属前述字段问题非日志缺失）。
建议：保持。
76 合规：符合铁律 2（桥函数捕获+Log）。

---

## 本视角结论
B3 播放主链路在**分层与桥通道（六桥、L7 零状态机、成熟库边界、1500 行门禁、桥日志）上整体合规**；但**状态机归属这一核心铁律（§0-8）仍未落地**，且有一批跨层接缝缺陷：
- **P1（最重）**：L6 `playback_session` 仍持有并驱动播放状态机（18 处 `playbackReducer` + 队列直驱），阶段 A6 报的「≥10 处」未修反增——状态机未下沉 L5，L6 职责越界（finding 1）。
- **P1**：整套 PlayResolver 解析/降级/健康检查四件套（681 行）为死代码，真实链路在 PlaybackService 里重复手写且缺失 url_health 能力（finding 3）。
- **P1**：`sourceKind` 在 L6 私有字段与 L5 `PlayerState` 双写且永不同步，致 UI「试听音源」提示恒不显示（finding 4）。
- **P2**：预读接缝 no-op（finding 2）、L5 url_health 直连 HTTP IO（finding 5）、通知栏 onSeek 悬空且 L4 越权直 seek 引擎致进度状态不同步（finding 6）。
建议主会话阶段 B 收口后统一修复：优先做状态机下沉 L5（finding 1）+ 状态单源（finding 4），再清理死代码（finding 3）与接缝（finding 2/5/6）。

## 未覆盖
- 未核验 20028 验证门面端到端 UI（VerificationLogic→L7 验证出口，属 B1/B7 交叉范围）。
- 未核验 bootstrap 中 VIP 凭据注入后音质提档的端到端效果（仅见注入 Map，未追登录回写链）。
- 未运行任何 dart/analyze/test/门禁（纪律禁止），行号/调用关系均基于静态文本与 rg。
- play_endpoints.dart:1-190/190-362 已读，但 getPlayUrlV5 的签名加密端到端正确性（AES Rcon）非本视角（C1 架构）职责，未深入。
- bridge_core 完整导出清单未逐条核对（仅核播放相关导出）。

## 76 合规小结
| 条款 | 结论 | 证据落点 |
|---|---|---|
| 第1条 跨层必经桥 | 符合 | L7/L6 仅 import bridge_*，零越级直连 |
| 第2条 桥函数 try/catch+Log | 符合 | bridge_session:41-68 |
| 第4条 只依赖下层门面/禁反向 | 基本符合；url_health IO 直连属 L5→L4 能力越界 | url_health.dart:8,54,114 |
| 第5条 1500行门禁 | 符合 | 全链路最大 516 行 |
| 第8条 播放控制/状态机不得放 L6、L7 零状态机 | **L7 符合；L6 违反**（18 处 reducer + 队列直驱） | playback_session:80-81,146-420 |
| 第9条 成熟库边界 | 符合 | core/audio 封装 just_audio/audio_service |
| §2 六桥通道 | 符合 | playbackSession/navState/appGraph 经桥 |
| §3 缓存⊃预读 | 触发在 L6 方向对，但接缝 no-op | bootstrap.dart:245-249 |
| §4 编排归 session | 编排归 L6 正确，但状态机滞留 L6、通知 seek 越权 | playback_session:106-114, notification_gateway:139 |
| 死代码/职责单一（精神） | 违反 | PlayResolver 四件套 681 行死代码 |

总体：**桥与分层骨架合规，核心症结是状态机未下沉（铁律 8）+ 死代码堆积 + 若干接缝不同步**。

证据：全仓 `rg 'PlayResolver\s*\('` 仅命中 `tool/resolve_contract_test.dart:66`（仅 `read('...play_resolver.dart')` 读文本，非实例化）；`PlayResolver` 未被 bridge_logic.dart 导出（该文件 :10-17 只导出 PlaybackService/HistoryRecorder/queue_state/player_state/playback_reducer）；play_source_parser/quality_policy/url_health 仅被 play_resolver.dart 内部互相 import（:16-18），无外部生产调用方。真正在线主链走 `PlaybackService.resolvePlaySource`（playback_service.dart:181，被 playback_session.dart:201 与 download_manager.dart:297 调用）。
问题：阶段 A5 报的「整套 PlayResolver 死代码」至今未清——四个文件（play_resolver/play_source_parser/quality_policy/url_health，合计 681 行）构成一套与 PlaybackService 平行且更完善的解析／降级／健康检查实现（含 `checkHealth`/`firstHealthy` 可达性探测、`PlayDecision` 三态判定），却完全不接生产链路；真实链路在 PlaybackService 里重复手写降档链 `_qualityCandidates`（:170）与错误映射 `_mapError`（:340），且真实链路缺失 url_health 的健康检查能力。
建议：二选一——(a) 让 PlaybackService.resolvePlaySource 经 bridge_logic 复用 PlayResolver（注入 fetch=getPlayUrlV5、真正启用 url_health），删去重复降档/映射；(b) 若确认不用，删除 play_resolver+play_source_parser+quality_policy+url_health 及 contract test，避免两套语义漂移。
76 合规：符合分层（均在 L5，未越级），但违反「职责单一/无冗余」精神，属死代码与能力倒挂。

---

证据：`PlaybackSession.instance.onQueueChanged = (hashes) { Log.d(...'queue changed n=${hashes.length} (cache keeps LRU warm)'); };` 回调体只有一行 Log，未调用已创建好的 `cacheService.prefetch(...)`；而 `playback_session.playAll`（:170-174）确实在队列变化时 `onQueueChanged?.call(hashes)`。
问题：76 原则 §3 规定「预读触发（队列 upcoming 窗口）由 L6 决定预测哪些键、L4 CacheService 执行写入」，但 L6→L4 的预读执行接缝在此处断开——触发了却无人执行，注释声称「保活」实为纯日志，注释与实现不符。
建议：要么在回调内对 upcoming 键调用 `cacheService.prefetch`（执行权仍在 L4），要么删除该回调并明确此处不做预读，勿留误导性 no-op 接缝。
76 合规：部分符合（触发在 L6、执行权归 L4 的方向正确），但接缝未真正连通，属职责空转。

---

证据：L6 会话直接持有状态机实例 `QueueState _queue = const QueueState();`（:80）、`PlayerState _player = const PlayerState();`（:81）；全文 `playbackReducer(...)` 调用 18 处（:146/149/155/199/230/260/268/283/291/294/304/363/372/381/401/413/420 + import :41），另有队列变更直驱 `_queue.next()/prev()/removeAt()/insert()/withMode()/replaceQueue()`（:312/322/337/346/354/195-196）。阶段 A6 报「≥10 处未修」属实且已增至 18 处。
问题：播放状态机的状态实例与驱动逻辑仍越界滞留在 L6 session，未下沉到 L5 logic/player；`playbackReducer` 函数体虽在 L5，但状态持有者/调用者均在 L6，违背「状态机/队列/reducer 属 L5，L6 只编排」。
建议：将 `_queue/_player` 及 reducer 驱动封装为 L5 的 `PlaybackController`（持有状态、emit action、暴露不可变快照），L6 playback_session 仅保留 resolve→engine→历史→通知→预读触发的编排并调用该 controller 的意图方法。
76 合规：违反第 8 条（播放控制不得放进 L6）；与 §1 表「L6 播放编排」边界重叠，规则文本本身 L6/L7 措辞不一，但实例持有+驱动确在 L6。

---
