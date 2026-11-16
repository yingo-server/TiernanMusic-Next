
---
## [2026-11-16 A5-C1] 进度启动 · L5 logic 全量 34 文件架构合规

- 已完整读 DEEP_AUDIT_14_BATCH_PLAN.md / SEVEN_SIX_RULE.md。
- `rg --files lib/logic -g '*.dart'` = 34 文件，`wc -l` 全部 < 1500（最大 auth_logic.dart 463 行、download_manager.dart 506 行、playback_service.dart 376 行）→ §0-5 单文件行数门禁**全部符合**。
- 静态扫描：无 `session/`/`surface/` 反向 import（§0-4 依赖方向符合）；无 `package:flutter`/`BuildContext`/`Widget` 出现（仅 2 处注释提及 flutter，非代码，§0 L5 无 UI 符合）。
- 静态扫描发现 IO 直连线索（dart:io / HttpClient / File）：lyrics_logic、download_commit、download_paths、download_manager、url_health、playback_service —— 逐文件取证中。

## 视角 C1 · lib/logic/auth/*（3 文件） · P2 · 组结论：合规
证据：
- account_logic.dart:5-6 / auth_logic.dart:12-23 / verification_logic.dart:11-12 均只 import `bridges/bridge_kernel.dart`(Log) 与 `bridges/bridge_core.dart`(core 门面)；account_logic.dart:9-15 同层 import auth_logic 常量（合法）。
- 三文件均无 dart:io / http / flutter / session / surface import；每公开方法 try/catch + Log（如 auth_logic.dart:104-106、verification_logic.dart:53-62）。
问题：无架构合规问题；auth 域纯后端逻辑、桥通道单一、脱敏日志到位。
建议：无需改动。
76 合规：符合第 1/2/4/5 条（桥通道、依赖方向、日志留痕、行数）。

## 视角 C1 · lib/logic/catalog/*（13 文件） · P2 · 组结论：合规（桥通道/依赖方向）
证据：
- 13 文件 import 一律经 `bridges/bridge_kernel.dart`(Log) + `bridges/bridge_core.dart`(端点/缓存/settings/dao 门面)：album:3-16、artist:8-24、collect:9-19、comment:7-8、fm:12-16、mv:5-9、playlist:6-7、playlist_write:8-9、rank:4-6、recommend:8-12、search:6-7、search_typed:8-12、user:5-7。
- 无 dart:io / package:http / HttpClient / BuildContext / Widget / session / surface import；每公开方法 try/catch + Log（如 collect_logic.dart:112-137 toggle、mv_logic.dart:62-120 playUrl、playlist_logic.dart:167-201 addSongsToKugouPlaylist）。
- collect_logic.dart:1 的 `dart:convert`（jsonEncode/jsonDecode）为纯算法，非 IO，合规；playlist_logic.dart:6-7 用 LruCache/PlaylistDao 均来自 bridge_core 门面，无直连 non-桥 core 文件。
问题：架构通道层面无越级/反向/影子桥；缓存、dao、端点全经桥门面注入。
建议：无需改动。
76 合规：符合第 1/2/4/5 条。

## 视角 C1 · lib/logic/download/download_manager.dart:14,344-404 · P1 · L5 IO 直连（网络）
证据：
```
14: import 'dart:io';
344: final http = HttpClient() ..userAgent='TiernanMusicNext' ..connectionTimeout=...
351: final req = await http.getUrl(Uri.parse(url));
352: req.headers.set('Range','bytes=0-');
353: final res = await req.close();
...
404: http.close();
```
问题：L5 逻辑层直接用 dart:io HttpClient 发起下载网络流、解析 statusCode/contentLength、写 IOSink，网络 IO 应属 L4 core/net 并由 bridge_core 暴露门面；此处绕过 core 网络层与桥，直接跨层持有底层 IO。
建议：把分块下载/Range/流落盘下沉为 L4 core（如 DownloadTransport），经 bridge_core 暴露；L5 只调用门面拿进度事件，不持有 HttpClient/File。
76 合规：违反第 1 条（跨层须经桥）、§0「L5 无 IO 直连」、第 4 条（只依赖下层经桥门面）。

## 视角 C1 · lib/logic/download/download_paths.dart:6,12,42-43 / download_commit.dart:5,41-63 / download_manager.dart:359-361,495-503 · P1 · L5 文件 IO 直连
证据：
```
download_paths.dart:6  import 'dart:io';
download_paths.dart:16 return Directory.systemTemp.path;   // 系统临时目录解析
download_paths.dart:42-43 if (part != null && part.existsSync()) part.deleteSync();  // 直接删文件
download_commit.dart:41  final part = File('${_storeDir()}...$hash.dlpart');
download_commit.dart:45,52,66 cleanupPartFile(part);
download_commit.dart:48  final data = await part.readAsBytes();  // 直接读字节
download_manager.dart:359-361 part = File(...); if(part.existsSync()) part.deleteSync(); sink=part.openWrite();
download_manager.dart:497-503 final part=File(...); if(part.existsSync()) part.deleteSync();
```
问题：L5 层直接 File 读写/删除/.dlpart 存在性判断、Directory.systemTemp 解析、IOSink 落盘；文件与存储操作应属 L4 core/storage 或 DownloadStore 门面，当前 logic 侧越过桥直接操作文件系统。
建议：将分片落盘、临时文件清理、目录解析统一收敛到 L4 DownloadStore（commitDownload/临时文件 API），bridge_core 暴露；L5 只传 hash/bytes 与拿到 DownloadRecord。
76 合规：违反 §0「L5 无 IO 直连」、第 1/4 条（跨层须经桥、只依赖下层经桥门面）。注：download_paths.dart:4 注释自称"仅依赖 core 桥与 dart:io"，与 §0 冲突，属已知刻意保留的 IO 下沉缺失。

## 视角 C1 · lib/logic/download/*（6 文件） · P2 · 其余架构维度合规
证据：
- download_models.dart:5-6 / download_song_sync.dart:5-6 / download_job.dart:4 均经桥或纯数据（download_job 仅 dart:async），无跨层 IO；download_manager.dart:12-17 / download_commit.dart:8-12 同层互调合法。
- 构造注入 PlaybackService(logic 同层)、SongDao/DownloadStore(bridge_core)；无 session/surface/flutter import；每方法 try/catch + Log（如 enqueue:98-113、cancel:143-190、_downloadUrl:341-407）。
- enqueue 实现完整（去重/状态/回调/调度），logic 侧功能闭环；上层是否调用不在本视角结论范围（A1/A3 已报上层零调用）。
- 行数：download_manager.dart 506（<1500），其余均 <1500。
问题：除上述 IO 直连外，桥通道、状态机归属、依赖方向均合规；下载状态机/队列属 L5 正确。
建议：保留并发调度与状态机在 L5，仅把 IO 下沉。
76 合规：状态机归属符合 §0-8/§4；IO 部分违反第 1/4 条。

## 视角 C1 · lib/logic/lyrics/lyrics_logic.dart:6,33-62,160-166 · P1 · L5 文件 IO 直连（歌词文件缓存）
证据：
```
6:  import 'dart:io' show File;
33: File _lyricFile(String hash) => _paths.fileIn('lyrics', '$hash.lrc');
36-46: _writeFile: if(!f.parent.existsSync()) f.parent.createSync(recursive:true); f.writeAsStringSync(text, flush:true);
50-62: _readFile: if(!f.existsSync()) return null; final text = f.readAsStringSync();
160-166: clearFileCache: final f=_lyricFile(h); if(f.existsSync()) f.deleteSync();
```
问题：L5 逻辑层直接用 dart:io File 做歌词目录创建、文本读写、删除；StoragePaths 虽来自 bridge_core，但拿到的 File 由 logic 侧直接 IO，文件读写应属 L4 core/storage 门面。三级缓存(内存→文件→网络)的「文件层」在 L5 直接落地，越过桥。
建议：把歌词文件缓存读写/删除下沉为 L4 门面（如 LyricsFileStore.read/write/delete，经 bridge_core 暴露），L5 只编排缓存命中策略；StoragePaths 仅保留取路径，不返回可 IO 的 File 给 L5。
76 合规：违反 §0「L5 无 IO 直连」、第 1/4 条（跨层须经桥、只依赖下层门面）。

## 视角 C1 · lib/logic/lyrics/*（另 2 文件） · P2 · 合规
证据：
- lyrics_parser.dart:4 仅 import bridge_kernel(Log)，为纯函数解析器（parseLyrics/applyOffset/findLineIndex），无 IO/flutter/跨层，符合"纯算法可放 L5 或 L4"边界。
- translation_logic.dart:5-13 经 bridge_kernel + bridge_core(LruCache/embedding 抽取/对齐)；LruCache 由构造注入，无 IO；每方法 try/catch+Log。
问题：无架构合规问题。
建议：无需改动。
76 合规：符合第 1/4 条与 §0 L5 职责。

## 视角 C1 · lib/logic/player/playback_service.dart:10,194 · P1 · L5 文件 IO 直连
证据：
```
10: import 'dart:io';
194: if (path != null && File(path).existsSync()) { ... return PlaySource(localPath: path, quality: rec.quality); }
```
问题：L5 播放源编排器直接用 dart:io File.existsSync() 判断本地下载文件是否存在；这是文件 IO 直连，实体文件存在性校验应经 L4 DownloadStore 门面（如 store.isFileComplete(rec)）。
建议：在 bridge_core 的 DownloadStore 暴露 `exists(rec)`/`absolutePathOf(rec)` 组合校验，L5 不 import dart:io。
76 合规：违反 §0「L5 无 IO 直连」、第 1/4 条。

## 视角 C1 · lib/logic/player/url_health.dart:8,53-54,110-180 · P1 · L5 网络 IO 直连（URL 健康探测）
证据：
```
8:  import 'dart:io';
54: final c = clientFactory != null ? clientFactory!() : HttpClient();
110: HttpClient? client; 115: client = _newClient();
116: final req = await client.openUrl(head ? 'HEAD' : 'GET', Uri.parse(url))...
```
问题：L5 logic 直接用 dart:io HttpClient 做 HEAD/GET+Range 可达性探测、重定向链、header 读取；网络探测属 L4 core/net 门面职责，此处跨层直连底层 IO（虽有 clientFactory 注入便于测试，但默认仍自建 HttpClient）。
建议：把 UrlHealthChecker 下沉到 L4 core/net，经 bridge_core 暴露 `probeUrls`（PlayResolver 已通过注入 healthChecker 使用，切换成本低）；L5 不持有 HttpClient。
76 合规：违反 §0「L5 无 IO 直连」、第 1/4 条。

## 视角 C1 · lib/logic/player/*（其余 7 文件） · P2 · 合规（状态机归属正确）
证据：
- player_state.dart:3-4 / playback_reducer.dart:4-6 / queue_state.dart:3-4 为不可变状态+纯 reducer，经 bridge_kernel/bridge_core(SongBrief)，零 IO/flutter；play_source_parser.dart / quality_policy.dart / play_resolver.dart / history_recorder.dart 均为纯逻辑或经桥门面注入。
- play_resolver.dart:15 只 import bridge_kernel + 同层 parser/policy/health；resolve() 通过 `fetch`/`healthChecker` 注入执行 IO（:84-86），本身不直连网络——架构边界处理正确（唯一瑕疵是注入的 healthChecker 默认实现 url_health.dart 本身在 L5 直连 IO）。
- 状态机/队列/reducer 全部在 L5 logic/player（player_state / queue_state / playback_reducer），符合 §0-8 与 §4「播放状态机属 L5」；未发现播放编排装配图/预读调度误入 L5（编排器 playback_service 只做 resolve，编排由 L6 session 负责，符合§4）。
- 行数全部 <1500（最大 playback_service.dart 376）。
问题：无其他架构问题。
建议：无需改动。
76 合规：符合第 1/2/4/5 条与 §0-8、§4（状态机归属）。

## 视角 C1 · lib/logic 全局扫描 · P2 · 桥通道与死代码/占位结论
证据：
- `rg '^import .*core/' lib/logic` = NONE；所有 core 能力均经 `bridges/bridge_core.dart` 门面（34 文件中 27 文件 import bridge_core，7 文件仅 bridge_kernel 或纯数据）。无影子桥、无跨层直接 import 非桥文件。
- 反向依赖：`rg '^import .*(session|surface|init|bootloader)' lib/logic` = NONE。
- TODO/占位：无代码级 TODO/PLACEHOLDER 违规；`needs probe`/`端点待实测` 均为端点契约留痕的 Log.w/注释（verification_logic.dart:67-102、fm_logic.dart:6-145），属合理降级非架构占位。CollectLogic.toggle（collect_logic.dart:112）logic 侧实现完整（防重锁/镜像/计数/回调），download enqueue（download_manager.dart:97）实现完整；上层调用属 A1/A3 视角。
建议：无需改动。
76 合规：符合第 1/3/4 条（桥唯一、无影子桥、无反向依赖）。

## 本视角结论
1. **34 文件全部读完，行数门禁（<1500）全部符合**（最大 download_manager.dart 506 行）。
2. **依赖方向与桥通道总体良好**：零 session/surface 反向 import、零直连非桥 core 文件、零 flutter/BuildContext/Widget、零影子桥；core 能力一律经 bridge_core 门面注入，日志一律经 bridge_kernel.Log。
3. **状态机归属正确**：播放状态机/队列/reducer 全在 L5 logic/player，编排在 L6 session，符合 §0-8/§4；未见播放装配图/预读调度误入 L5。
4. **最严重系统性问题：L5 IO 直连（共 6 文件）**——dart:io HttpClient 网络下载/探测（download_manager、url_health）、File 读写删/目录（download_paths、download_commit、lyrics_logic、playback_service），违反 §0「L5 仅后端逻辑、无 IO 直连」及铁律 1/4。建议统一下沉 L4 core 并经 bridge_core 暴露门面。
5. 死代码/占位：CollectLogic.toggle、download enqueue 的 logic 侧实现完整，无代码级 TODO 违规；端点 needs probe 为合理留痕。
6. P1 共 6 条（均 IO 直连）；其余为 P2 组结论，无 P0。

## 未覆盖
- 本视角为 A5-C1 架构合规，未评估实现正确性（空安全/竞态/字段解析）——属 C2。
- 未评估上层（L6 session / L7 surface）是否实际调用 CollectLogic.toggle 与 DownloadManager.enqueue——属 A1/A3/A6 报告范围。
- 未打开 bridges/bridge_core.dart、bridge_kernel.dart 内部验证门面签名与 try/catch+Log 实现——属 A6（六桥）范围；本视角仅从 logic 侧 import 事实判断通道合规。
- 未跑任何分析器/测试/门禁（工具纪律禁止）。

## 76 合规小结
- **符合**：第 1 条（跨层经桥，27 文件均经 bridge_core/kernel，零直连非桥 core）、第 2 条（每方法 try/catch+Log 留痕）、第 3 条（无影子桥）、第 5 条（全部 <1500 行）、§0-8/§4（播放状态机在 L5，编排在 L6）、依赖方向（零反向 import）。
- **违反**：§0「L5 无 IO 直连」及第 1/4 条 —— 6 个文件 dart:io 直连：download_manager.dart(HttpClient+File+IOSink)、download_commit.dart(File.readAsBytes+delete)、download_paths.dart(File.delete+Directory.systemTemp)、lyrics_logic.dart(File.read/write/delete/createDir)、playback_service.dart(File.existsSync)、url_health.dart(HttpClient 探测)。均为 P1，建议下沉 L4 core 并经桥暴露。
- 无 P0；无网络域名白名单问题（logic 未直连酷狗端点，均经 core 端点封装）。
