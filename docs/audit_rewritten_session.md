# 重构后 L6 Session 全面审查报告（只读）

审查范围：lib/session/ 全部 6 个 dart 文件、bridges/bridge_session.dart、bridge_surface.dart、init/main.dart、bootloader/bootloader.dart。审查日期：2026-11-15。

## 1. 职责纯度（session 层）

- **playback_session.dart**（314 行）：仅 import `flutter/foundation.dart show ChangeNotifier`（L8-9，注释声明 L6 允许），零 Widget/BuildContext/渲染。持有完整状态机：
  - L5 状态：`QueueState _queue`（L61）、`PlayerState _player`（L62），非空壳。
  - L5 reducer：引擎事件翻译点 `_onEngineEvent`（L93-115）逐事件调 `playbackReducer`；每个意图（seek L268、setVolume L278、setSpeed L288 等）也走 reducer。
  - L4 引擎：`AudioEngine _engine = NullAudioEngine()`（L50），attach 时默认构造 `JustAudioEngine`（L83-86）。
- **bootstrap.dart**：纯 Dart 装配（L1 注释），无 UI import。
- **graph.dart / module_registry.dart / nav_state.dart / contracts.dart**：零 flutter import，nav_state 自实现 listener 列表（L14）。
- contracts.dart L18 `Object? get builder` —— session 只持有不渲染，L7 收窄为 WidgetBuilder，无违规。
- 唯一 close call：playback_session 持通知栏 `MusicAudioHandler`（L57）——属 L4 网关句柄而非 UI，可接受，但见残留清单 R3。

## 2. 启动链

真实调用顺序（逐文件核对）：
1. **main.dart L19-27** `_boot`：path_provider 拿 rootDir（L36-42）。
2. **main L53-55** `registerBootloader()` → `runBoot` → **bootloader.dart L84** `Bootstrap.run`：kernel 装配 → `_assembleCore`（L119：StoragePaths.init → dbOpenFuture staged（L127-137，不 unawaited）→ KugouClient+ResourceCache+InFlight（L122-128）→ 单实例 settings（L130）→ restoreSession）。
3. **main L66-79**：SurfaceDeps **7 dep 全判空**（requiredDeps 含 client/songDao/playlistDao/historyDao/downloadStore/settings/paths），missing 走错误页 —— 完整无缺。
4. **main L82-88**：`deps['dbOpenFuture'] is Future<bool>` → **await**（旧竞态已修）。
5. **main L89-99** → **bridge_surface.dart L22-39** `installServices`：先 `session.bootstrapSession(...)`（L24-32）再 `root.installServices`（L35）。失败 rethrow（L41）。
6. **bootstrap.dart L38-169** bootstrapSession：21 个 logic 单例逐步装配 → CacheService prefetch 绑定（L100-113）→ `PlaybackSession.instance.attach`（L119-123）→ ModuleRegistry 安装 11 个模块 id（L126-134）→ 组装 AppGraph（L136-161）。
7. L7 registerModules：bootstrap 装的是 `_PlaceholderModule`（L169-172，enabled=false）；真实模块由独立 UI 模型经 `ModuleRegistry.instance.install` 覆盖（module_registry L18 幂等覆盖语义支持）。注意：bridge_surface L35 `root.installServices` 若 L7 尚未实现注册真实模块，导航将为空 —— 见必修。

## 3. 旧装配删除对照（lib/surface/ 现仅 app_root/shell/pages/widgets/design/theme，assembly 系文件已删净）

| 旧文件 | 等价逻辑残留？ | 迁移处 |
|---|---|---|
| assembly.dart（491 行装配逻辑） | ✅ 无残留（surface/ 下无 assembly） | bootstrap.dart（21 个 logic 装配 L56-96） |
| assembly_result | ✅ 已迁 | graph.dart `AppGraph`（L50-108）+ bridge_session `appGraph` 导出（L27） |
| deps | ✅ 已迁 | graph.dart `SessionDeps`（L17-44）；启动期仍由 main 用 root.SurfaceDeps 传递（main L92-99），职责清晰 |
| modules | ✅ 已迁 | contracts.dart `SurfaceModule` |
| registry | ✅ 已迁 | module_registry.dart（文件头声明"取代原 surface/registry.dart"） |
| nav_state | ✅ 已迁 | session/nav_state.dart（纯 Dart，self-listener） |
| providers | ✅ 无等价残留 | L7 经 bridge_session 单例访问器（L45-62） |
| player_controller | ✅ 已迁 | playback_session.dart（意图方法 toggle/next/prev/seek/setVolume/setSpeed/setQuality/setMode/playAt/removeAt/insertNext L212-290） |

一处措辞残留：logic/catalog/search_typed_logic.dart L5 注释仍写"由主会话 assembly 注入"——仅注释，无代码残留。

## 4. 缓存 ⊃ 预读

- 独立 PrefetchEngine：**已真删**（全仓 rg 零命中；core/cache/cache_service.dart L4 明示"prefetch() 不是独立调度器，而是 CacheService 的写入策略"）。
- CacheService.prefetch 同时承担缓存写入+预读（cache_service.dart L61-79，CacheOrigin.prefetch L18）。
- bootstrap 接 onQueueChanged：**已接**（bootstrap.dart L102-112，playAll 触发，playback_session L147-149），另启动预热 searchHot（L110-113）。
- **KugouClient 仍用 ResourceCache + InFlight**（bootloader L122-128、kugou_client L44-53）——与 CacheService 属两层：ResourceCache=磁盘 HTTP 资源缓存（cacheable=false 端点已标）、CacheService=内存 LRU+预热。非同一功能重复，但存在双缓存栈，需在文档明确分工（见残留 R1）。

## 5. 播放控制闭环

| 项 | 状态 | 证据 |
|---|---|---|
| 起播 | ✅ | playSong/playAll → _start → resolvePlaySource → engine.play（playback_session L174-206；本地优先 src.localPath ?? urls.first，L196） |
| 通知栏 metadata | ✅ | attach 构造 initNotification（L88-99）；_start 后 updateMetadata(title/artist/artUri/durationMs)（L203-209） |
| 历史落库 | ✅（带保留） | `_history?.recordPlay(cur, 0)` L202 —— 已接但 **未 await**，落库失败仅静默 |
| next/prev 回调 | ✅ | NotificationControls(onNext: next, onPrev: prev) L89-91；next/prev 走 QueueState.next/prev（L218-233） |
| setQuality | ✅ | L296-306：改 _quality 后重 _start 当前曲（未 await，fire-and-forget） |
| 音量/倍速/seek | ✅ | setVolume L278 / setSpeed L288 / seek L268，均 engine 调用+reducer emit |

## 确认已彻底转换

- L6 session 零 Widget 渲染，唯一 flutter 依赖为 ChangeNotifier（声明合规）。
- PlaybackSession 非空壳：QueueState+PlayerState+playbackReducer 状态机、AudioEngine 引擎门面、不可变 PlaybackSnapshot 对 L7。
- 启动链 main→bridge_surface.installServices→bootstrapSession→PlaybackSession.attach 顺序正确；dbOpenFuture 已在 main await；SurfaceDeps 7 dep 判空完整。
- 旧 surface/assembly 系 8 项全部迁净，无代码残留。
- PrefetchEngine 已删，CacheService 统一缓存⊃预读，onQueueChanged 已接。

## 残留清单

- R1 KugouClient 仍持有 ResourceCache+InFlight（bootloader L122-128），与 CacheService 双缓存栈——非 bug，但分工需文档化，避免后续误加第三层。
- R2 bootstrap 队列预读用 `EndpointRegistry.searchHot` + hash 参数（bootstrap L104-108）：端点语义疑似错配（热搜端点接单曲 hash），预读可能全部 miss，且只覆盖 playAll、next/prev 切歌不触发预读。
- R3 recordPlay 未 await、setQuality 重播未 await（playback_session L202/L303）：失败静默，无 Log。
- R4 search_typed_logic.dart L5 注释仍提"assembly"。
- R5 moduleIds 全装 `_PlaceholderModule(enabled:false)`，真实模块注册依赖 L7 install；若 L7 未实现则 ModuleRegistry.active() 恒空、导航为空白。

## 必修 TOP5

1. **预读端点错配**：bootstrap L104-108 用 searchHot 端点传 hash 预读单曲——改为正确的歌曲详情/播放地址预读端点，否则"缓存⊃预读"实际零收益。
2. **next/prev 补预读**：切歌路径不经 onQueueChanged，upcoming 预热断裂；在 next/prev/_start 成功后回调 onQueueChanged（取队列 index+1 起的 hash）。
3. **模块真实注册兜底**：确认 L7 installServices 覆盖 placeholder 的时序；否则首屏导航空白（enabled=false 模块不进 navEntries）。
4. **落库与重播错误可见化**：recordPlay / setQuality 重播 await + try/catch Log，消除静默失败。
5. **双缓存栈文档化**：在 SEVEN_SIX_RULE 标注 ResourceCache（磁盘 HTTP）vs CacheService（内存+预热）边界，删除 search_typed_logic 过期注释。
