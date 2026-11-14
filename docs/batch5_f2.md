# 批5-F2 · 通知栏 next/prev + collect fileid 补齐

范围：仅 4 个文件（`surface/audio/audio_service_bridge.dart`、`surface/modules.dart`、
`logic/catalog/collect_logic.dart`、`core/net/endpoints/collect_endpoints.dart`）。
不改 player_controller / assembly / playlist_write_endpoints / tool / CI；不新增网络请求；
不破坏现有公开签名；每个文件 ≤500 行。

## ① surface/audio/audio_service_bridge.dart（154 → 223 行）
- `MinimalAudioHandler` 构造新增可选 `void Function()? onNext/onPrev`；新增字段 `_onNext/_onPrev`
  与 `void bind({required void Function() onNext, required void Function() onPrev})`
  （try/catch + `Log('surface.audio')`）。bridge 不反向依赖 controller，依赖方向不变。
- override `skipToNext()` / `skipToPrevious()`：有回调则调用；未绑定则 `Log.w` 并回落
  `super.skipToNext/skipToPrevious`（不阻断、不抛）。
- `playbackState.controls` 常显补 `MediaControl.skipToPrevious` 与 `MediaControl.skipToNext`
  （audio_service 0.18.19 已在 pub.dev 文档核实存在这两个静态常量；`MediaControl(...)` 自定义
  构造器强制要求 `androidIcon`，故用官方常量而非自造 label 形式）。
- `play/pause/stop/seek` 行为与 metadata 推送完全不变；文件头 TODO(queue) 注释已更新。

## ② surface/modules.dart（168 → 183 行）
- `controllerRef = controller;` 之后新增 `audioHandler?.bind(onNext: () { controller.next(); },
  onPrev: () { controller.prev(); })`，外层 try/catch + `Log('surface.modules')`：
  handler 早于 controller 创建，故只能在 controller 就绪后绑定；队列为空时
  `queue.next()/prev()` 自身已有 Log 兜底。

## ③ core/net/endpoints/collect_endpoints.dart（240 → 261 行）
- `CollectResult` 新增可选字段 `final String? fileId`（copyWith / toMap 同步，默认 null 不破坏
  既有构造调用）。
- `collectSongByHash` 成功时从加歌回执 `data.info[]`（`addSongsToPlaylist` 返回的 rows）首项取
  `fileid`，缺失则兜底 `audio_id`，写入 `CollectResult.fileId`；仍失败返回空串。
- `cancelCollectByHash` 的 fileid 守卫原样保留（无有效 fileid 不发无锚点删除请求），
  其 `albumAudioId` 参数名与签名不变（调用方仅 logic 层，不扩散）。

## ④ logic/catalog/collect_logic.dart（316 → 370 行）
- 新增 `Map<String,String> _fileIds`（hash→fileid）与新持久键 getter `_kFileIdsKey`
  （`favorites.fileids.<uid>`，匿名 `favorites.fileids.anon`，与既有 `_kFavoritesKey` 同风格）。
- `_load()` 先清再读 `_fileIds`（新增 `_loadFileIds()`，JSON 对象 `{"hash":"fileid"}`）；
  `resetLocalMirror()` 同时清 `_fileIds` 并重读（换号隔离）。
- `_flush()` 多写一次 fileid 镜像；旧 `favorites` JSON 数组格式不动。
- toggle 收藏成功：`r.fileId` 非空则 `_fileIds[h] = r.fileId`，为空则 `Log.w`（未建档）。
- toggle 取消：优先把 `_fileIds[h]` 作为 `albumAudioId` 传给 `cancelCollectByHash`；
  缺失时维持现状（回退 `song.albumAudioId`）并 `Log.w`；取消成功后移除该 fileid 记录。
- 旧镜像缺 fileid 时需重新收藏或后续补（本层不强行补旧数据，不臆造 fileid）。

## 风险与边界
1. `MediaControl.skipToNext/skipToPrevious` 依赖 audio_service ^0.18.19（pubspec 已锁），
   已用官方 API 文档核实常量存在。
2. `fileid` 与 `album_audio_id` 口径未实测统一：回执 fileid 优先，缺失才回退，且显式 Log。
3. 未跑分析器、未提交；旧数据不自动补齐，属预期行为。
