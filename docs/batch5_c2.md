# 批5-C2 · 通知栏 next/prev + collect hash→fileid 方案（只读检查）

检查：`surface/audio/audio_service_bridge.dart`、`surface/modules.dart`、`surface/player_controller.dart`、
`logic/catalog/collect_logic.dart`、`core/net/endpoints/collect_endpoints.dart`、
`core/net/endpoints/playlist_write_endpoints.dart`、`tool/field_truth_test.dart`（收藏/写锚点附近）、
`core/net/endpoints/song_models.dart`。只读，不改码/不跑分析器/不提交。

## 现状（已核实）
- `MinimalAudioHandler` 只有 play/pause/stop/seek；`controls` 仅 `[pause|play, stop]`，**无 next/prev**；文件头 TODO(queue) 自认缺口。
- handler 只拿 `AudioPlayer`（`JustAudioEngine.rawPlayer`），**不知队列** → next/prev 必须外部注入回调。
- `PlayerController` 已有 `next()/prev()/seek(int ms)`（try/catch+Log），seek 走 reducer `SeekTo`+`_engine.seek`，状态同步已在控制器侧 → 控制器零改动。
- `modules.dart`：`controllerRef` 在 controller 构造**后**赋值，`audioHandler` 在构造**前**创建 → 回调只能在 controller 建好后 bind。
- 依赖方向已单向：bridge 不 import player_controller；可继续维持（bridge 只认 typedef）。
- collect：`collectSongByHash` 只回 `CollectResult(ok,count)`，`addSongsToPlaylist` 的回执 `data.info[]{fileid,audio_id,hash(大写)}` **被丢弃**；`cancelCollectByHash` 用 `albumAudioId` 冒充 fileid（注释自认 fileid≠hash）。
- `SongBrief` **无 fileid 字段**，`fromTrackInfo` 忽略歌单曲目 `'fileid'` → 回填拿不到 fileid。
- 收藏镜像持久键 `favorites.<uid>`（旧全局键 `favorites` 一次性迁移），**只存 hash**。
- `field_truth_test.dart` A6-3 已固化回执形态（`info[0].fileid=1`），A6-4 删歌 `{count,list_ver}`；既有锚点行不得改。

## ① 通知栏 next/prev/seek 最小回调接线（只改 2 文件）
`audio_service_bridge.dart`（L6 surface，不 import controller）：
1. typedef `NotifyNext = Future<void> Function();`、`NotifySeek = Future<void> Function(int ms);`。
2. 字段 `_onNext/_onPrev/_onSeek` + `bindControls({onNext,onPrev,onSeek})`（try/catch + `Log('surface.audio')`）。
3. 覆写队列钩子 `@override skipToNext()` → `_onNext?.call()`；`skipToPrevious()` → `_onPrev?.call()`；空回调仅 Log.w 后 `super.*`。
   （若锁定版 audio_service 未暴露 skipTo*，退路：`MediaControl.skipToNext/Previous` + `customAction` 兜底，注释写明。）
4. `seek(Duration)` 优先 `_onSeek?.call(ms)`，回退 `_player.seek(position)`（原行为不断链）。
5. `playerStateStream` 的 `controls` 补 `MediaControl.skipToNext, MediaControl.skipToPrevious`（队列长度未知→常显）。
`modules.dart`（`controllerRef = controller;` 之后）：
```dart
audioHandler?.bindControls(onNext: controller.next, onPrev: controller.prev, onSeek: controller.seek);
```
- 无循环依赖（bridge 不 import controller）；不加 provider/单例/不改 SurfaceRegistry。
- 收益：seek 改走 controller 后 `PlayerState.positionMs` 与通知栏进度不再脱节（现状直连 player 绕过 reducer）。
- 限制：队列空时 next/prev 由 `queue.next()==null→return` 静默兜底（已有 Log）。

## ② collect hash→fileid 镜像最小补齐（改 3 文件）
改：`collect_endpoints.dart`、`collect_logic.dart`、`song_models.dart`；
**`playlist_write_endpoints.dart` 零改动**（回执已足够）。
1. **新持久键** `favorites.fileids.<uid>`（匿名 `favorites.fileids.anon`），值 = JSON `{"<小写hash>": <fileid:int>}`；
   与 `favorites.<uid>` 同维度换号隔离；旧数据无此键 → 视为 fileid 未建档，走 ④ 回填。
2. **add 回执字段**：端点新增纯函数 `Map<String,int> parseAddFileids(List<Map<String,dynamic>> rows)`
   （取 `fileid` int，缺失/0 跳过；`hash` 大写回显 → toLowerCase）；`CollectResult` 增 `fileids` 字段
   （copyWith/toMap 同步）；`collectSongByHash` 把 rows 解析结果填入；`_doToggle` 收藏成功分支
   `_fileids.addAll(r.fileids)` → `_flushFileids()`。
3. **cancel 如何取 fileid**：取消分支先查 `_fileids[hash]`；命中 → `cancelCollectByHash(client, hash, fileId:'$fid')`；
   未命中 → 回退 `song.albumAudioId`（Log.w 标注「fileid 未建档，album_audio_id 兜底」）；
   皆无 → **不发请求**、ok=false（诚实失败）。端点参数 `albumAudioId` **改名 `fileId`**（唯一调用方在 logic，不扩散）。
4. **旧数据如何补**：`refreshCount()` 追加「fileid map 缺条目」分支 → `favoriteListId()`(listid=2) + `playlistTracks()`
   按 hash 回填；前提 `SongBrief` 增 `final int fileid`（`fromTrackInfo` 读 `'fileid'`，缺键如实 0；文件现 286 行，≤500 行内）。
   fileid=0 跳过（无法删歌，Log.w）；回填后 `_flushFileids()`；失败不伪造 fileid。

## ③ 三项验收断言（纯 Dart，追加 `n3c_collect_fileid_truth()`，不改既有锚点行）
- **A1 回执解析**：`parseAddFileids([{fileid:1,hash:'FAB30A43449D8C12528DD9D83A7693E7'}])`
  → `{'fab30a43449d8c12528dd9d83a7693e7':1}`；fileid 缺失条目跳过；hash 大小写归一。
- **A2 cancel 优先级**：纯函数 `resolveCancelFileId(mirror,hash,fallbackAudioId)` → 镜像命中优先；未命中取 fallback；
  皆无返回 0（=不发请求）。
- **A3 键维度隔离**：`collectFileidsKey('123')=='favorites.fileids.123'`、空 uid → `'favorites.fileids.anon'`；
  与 `favorites.<uid>` 不同名 → 不串号。
纯函数须放无 flutter 依赖处（如 `collect_endpoints.dart`），logic 层调用。

## ④ 不能碰的文件（F2 范围外 / 他批范围）
- 批3-F2：`core/net/endpoints/comment_endpoints.dart`、`recommend_endpoints.dart`。
- 网关/签名/加密：`core/net/kugou_client.dart`、`signing.dart`、`crypto_rsa.dart`。
- 桥层 `lib/bridges/**`（唯一通道，只 import）。
- 其他 logic：`lib/logic/**` 除 `logic/catalog/collect_logic.dart`。
- UI/装配：`surface/pages/**`、`surface/widgets/**`、`surface/registry.dart`、`surface/audio/just_audio_engine.dart`。
- 契约文档只读：`docs/API_FIELDS_TRUTH.md`、`ENDPOINT_TRUTH.md`、`PARITY_NOTES.md`。
- `tool/field_truth_test.dart` 既有锚点行只可追加；`pubspec.yaml`/`analysis_options.yaml`/CI 不动。

## 风险
1. `skipToNext/skipToPrevious` 方法名依 audio_service 版本而定，实施须以 pubspec 锁定版源码为准（或走 customAction 兜底）。
2. seek 改走 controller 后，handler 不再直连 player；NullAudioEngine 场景无 player 路径，不受影响。
3. fileid 与 album_audio_id 口径未实测统一；回填失败须显式 Log，不得用 hash 删歌（会无效 fileid 失败）。
