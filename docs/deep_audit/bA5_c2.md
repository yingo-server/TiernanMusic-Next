# A5 批 · C2 实现正确性视角（L5 logic 全量 34 文件）

> 审查时间 2026-11-16。视角：C2 实现正确性（空安全/状态机/失败路径/竞态/死代码/契约对齐/功能可达性）。
> 只读审查，依据 `file_read`/`rg`；未跑 dart/analyze/test。已知前置（不重复报底层）：MV 端点 `getMvBySong` 恒 null、`fetchTranslation` 恒空、AES Rcon bug 属 A3/C4 底层，本视角只报 **logic 侧**传导与错位。

## <视角 C2> · lib/logic/catalog/mv_logic.dart:33-50,66-88 · P1 · 契约错位/功能可达性
证据：
```dart
Future<List<mv.MvQuality>> qualities(String mvHash) async {
  final h = mvHash.trim().toLowerCase();
  ...
  final items = await mv.getVideoQualities(_client, h);
}
Future<mv.MvPlayResult> playUrl(String mvHash, {String? requestedId, ...}) {
  ...
  final quals = await qualities(h);
```
`getVideoQualities(_client, String mvHash)` 内部把参数作为 `data:[{'video_id': h}]`（见 `mv_endpoints.dart:301,324`）；端点契约要 **int video_id**（A3 复核 X2：`body.data[0].video_id` 实测为数字 596344）；surface `mv_page.dart:101,129` 传的是歌曲 **hash 串**（A1 X2 已定位上层）。本层 `qualities/playUrl` 入参语义整体围绕 hash 设计，未做 videoId 转换也未按新契约改签名。
问题：logic 侧把 32 位 hash 冒充数字 video_id 送档位端点，档位恒空 → `playUrl` 走 `quals.isEmpty` 早退返回空 MvPlayResult，MV 播放在 logic 层不可达（叠加端点层恒 null，共三重断点）。
建议：把 `qualities/playUrl` 签名与内部缓存键改为 `int videoId`，由上游（MvBrief.videoId / 歌曲侧）传数字 id；`getVideoQualities` 同步改 int 入参；档位 hash 仍从 A5-2 取。
76 合规：不违反（同层逻辑），但属跨层契约未同步（需 L6/L7 联动修）。

## <视角 C2> · lib/logic/player/playback_service.dart:283-330 · P1 · 契约错位/死链（联动 A3 MV P0）
证据：
```dart
Future<PlaySource> resolveMvAudioFallback(SongBrief song) async {
  final aid = song.albumAudioId;
  final mvBrief = await getMvBySong(_client, aid);
  if (mvBrief == null || mvBrief.hash.isEmpty) { ... return notFound; }
  final quals = await getVideoQualities(_client, mvBrief.hash);
```
`getMvBySong` 端点层因 `MvBrief.fromMap` 不读实测 `video_id`、以不存在的 `hash` 为门槛而**恒返回 null**（A3 P0 已复核）。本方法对 `mvBrief == null` 有防御（`no mv` → notFound，无崩溃），将 null 如实映射为 `PlaybackError.notFound` 并可被上层 `playback_session.dart:207` 兜底链消费——null 处理**正确**；但**因为第一段恒 null，本方法恒在第一步早退**，第二段 `getVideoQualities(mvBrief.hash)` 用 hash 冒充 video_id（同 mv_logic 错位）永远不可达。
问题：逻辑侧容错做对了，但整条 MV 音频兜底链在当前端点契约下 100% 不可达（死链）；且即便端点层修好第一段，第二段 hash→video_id 错位会继续让兜底失败。
建议：端点层修 `getMvBySong` 返回 `MvBrief.videoId` 后，本方法改用 `mvBrief.videoId` 调 `getVideoQualities(int)`；删除 `mvBrief.hash.isEmpty` 依赖，改 `mvBrief.videoId > 0` 判定；同步改日志字段。
76 合规：不违反（L5 经桥调 L4，合法）。

## <视角 C2> · lib/logic/auth/verification_logic.dart:27-120 · P0 · 功能不可达/验证死状态机
证据：
```dart
enum VerificationState { idle, required, solving, solved, failed }
Future<bool> getVerifyInfo() async { Log.w(... 'needs probe ...'); return false; }
Future<bool> submitVerification(Map<String,Object?> payload) async {
  if (_state != VerificationState.required) return false;
  ...
  _state = VerificationState.solving;
  return false; // 不发网络请求、不闭环
}
```
全仓 `rg 'VerificationLogic|onVerificationRequired|markSolved'` 仅命中 bridge/session 装配，**零业务消费者**；playback_session 遇到 20028 只把 `needsVerification` 当字符串拼进错误文案（`playback_session.dart:235-242`），未调用 `onVerificationRequired`；状态机 `solved/failed` 永不进入，`markSolved` 零调用。注释自称「唯一可信验证门面」，实际是死代码，20028 用户不可解。
问题：20028 验证链路在 logic 与 session 之间完全断裂——状态机永停 idle/required 且无出口，用户遇到验证必卡死。
建议：在 playback_session 的 20028 分支调用 `verification.onVerificationRequired(20028, ssaCode)` 并经 L6 暴露给 L7 触发验证 UI；端点实测后补 `getVerifyInfo/submitVerification` 的真实请求与 `markSolved` 闭环；否则在 UI 明示「验证暂不可用」避免假承诺。
76 合规：不违反（L5 状态机本身合规），但被 L6 零消费属装配越权缺失（非本视角主报）。

## <视角 C2> · lib/logic/player/playback_service.dart:113-165 · P1 · 权益判定失效/死参数
证据：
```dart
PlaybackService({ required KugouClient client, ..., Object? session })
  : ... _session = session;
bool get _hasRights {
  final s = _session;
  if (s == null) return false;
  if (s is Map) { token = s['vip_token'] ?? s['vipToken']; ... }
  else { final d = s as dynamic; token = d.vip_token; vipType = d.vip_type; }
}
```
装配处 `bootstrap.dart:115-119` 构造 `PlaybackService` **未注入 session**（无 `session:` 实参），`_session` 恒 null → `_hasRights` 恒 false → `_qualityCandidates` 永远按匿名从 `prefer` 档起（`_ladder.indexOf(prefer)`），VIP 权益（`flac` 起）分支永不可达。更严重：`KugouSession`（`kugou_client.dart:17-21`）只有 token/userid/mid/cookies 四个字段，**根本没有 `vip_token`/`vip_type`**——即便注入 session 对象，`d.vip_token` 会抛 NoSuchMethod 被 catch 吞成 false。AuthLogic 把 vip_token/vip_type 存进 settings/cookies（`auth_logic.dart:434-450`），从未回写 session 字段。
问题：VIP 权益判定在当前装配与数据结构下 100% 失效，VIP 用户拿不到高音质候选链，播放权益控制形同虚设。
建议：把 vip_token/vip_type 作为正式字段加进 `KugouSession` 并在登录/恢复/切换时回写；装配处注入 session；或在 `_hasRights` 改从 KugouClient 持有的 settings/cookies 读取（需注入 settings）；补可验证日志。
76 合规：不违反，但暴露 L5 依赖的 L4 数据结构缺字段（跨层契约断裂）。

## <视角 C2> · lib/logic/player/player_state.dart:22,34,72-85 / lib/session/playback_session.dart:82-91,246 · P1 · 状态字段断流（sourceKind 不进 state）
证据：`PlayerState` 有 `sourceKind` 字段与 `copyWith`，但 `playbackReducer`（全文件 204 行）**没有任何 action 写 sourceKind**；`playback_session` 只在私有变量 `_sourceKind` 上赋值（`playback_session.dart:83,212,235,246`），`snapshot`（85-91）只用 `_player/queue/mode/speed/volume`，`PlaybackSnapshot` 不含 sourceKind；surface `player_page.dart:292` 读 `snap.player.sourceKind` 恒为默认 `'kugou'`。
问题：MV 兜底播放标记（`sourceKind='mv-audio'`）永远传不到 UI，「MV 音频播放中」提示分支死代码；local/kugou 标记同样丢失。
建议：给 reducer 增加 `SetSourceKind` action（或在 StartLoad/Playing 带 sourceKind），由 session `_emit` 时注入；并在 `PlaybackSnapshot` 暴露该字段或统一走 player state，避免双份真相源。
76 合规：不违反层界，但 L6 维护了未下沉到 L5 状态的私有真相源，属职责错位边缘。

## <视角 C2> · lib/logic/player/play_resolver.dart:72-196 + play_source_parser.dart + quality_policy.dart + url_health.dart · P1 · 整组死代码/状态丢弃
证据：全仓 `rg 'PlayResolver|parsePlayUrl|downgradeChain|UrlHealthChecker|firstHealthy'` 除自身文件外**零消费者**（仅 `mv_anonymous.dart:203` 有同构镜像注释）。实际播放在走 `PlaybackService.resolvePlaySource`（自建 flac→320→128 循环 + `PlayResult`）与 session `_start`。两套解析/降级实现并存：`play_resolver` 的 `PlayDecision.needVerify/noPrivilege` 终态语义、`url_health` 的 HEAD/Range 探测与断链降档、`quality_policy.decide` 的「20028 立即收口」在真实链路全部不生效。
问题：4 个文件（约 681 行）实现精巧的状态机与健康检查全部死代码；真实播放链路的断链探测/20028 处理只能靠 endpoint 单次返回，缺备用链健康筛选，用户遇到坏 URL 无降档兜底。
建议：明确取舍——要么在 `PlaybackService.resolvePlaySource` 内复用 `parse()`/`decide()`/`checkHealth`（注入 healthChecker），统一三态语义；要么删除死代码避免维护双份契约；不要两套并存。
76 合规：不违反，但死代码违反「功能可达性」精神。

## <视角 C2> · lib/logic/player/queue_state.dart:105-127 · P2 · 随机模式状态机不完备（prev 不可逆）
证据：
```dart
QueueState _shuffleStep(int dir) {
  var base = (index + 1) % n;
  base = (base + dir + n) % n;
  var h = (seed ^ (base * 0x9E3779B9)) & 0x7FFFFFFF;
  ...
  final target = h % n;
```
`next`/`prev` 都用「基于当前 index+seed 的伪随机哈希」选目标，代码注释自承「双向可逆性不保证」。从 A 按 next 到 B 后，再 prev 不保证回到 A（可能跳到第三首或回自身被改成 index+1）。shuffle 播放列表的上一曲语义错乱。
建议：改为固定洗牌序列（维护 `order: List<int>` + `cursor`，seed 一局生成一次），next/prev 走游标 ±1；seed 复用现有字段可复现。
76 合规：不违反。

## <视角 C2> · lib/logic/auth/auth_logic.dart:186-217,414-455 · P1 · 会话恢复异常被吞/凭据落地不完整
证据：
```dart
bool restoreSession() {
  try { ... session..token=token..userid=userid..mid=mid..dfid=dfid;
    _restoreVipExtras();
    _tryRefreshToken();   // fire-and-forget，无 await
    return true;
  } catch (e, st) { Log.e(...); return false; }
}
```
与 A1「异常被吞」分工核实：本层**有 Log.e 留痕、不静默吞**（A1 描述偏重），但两个实质问题：
1) `_tryRefreshToken()` 完全 fire-and-forget：方法返回 true 后 token 刷新结果（成功回写/失败降级）无任何等待点，`restoreSession` 调用方永远看到「恢复成功」，即使 token 已失效；验证码/密码登录都 await 落库，唯独续期不。
2) `restoreSession` 恢复 `vip_token/vip_type` 只通过 `_restoreVipExtras` 写 `session.cookies['t1']`，**不回写 session 的 vip 字段（KugouSession 本就无此字段，见前条）**；续期回执里的 `vipToken/vipType`（259-262）同样只落 settings，运行态权益不可读。
问题：会话恢复是「半成功」——async 续期与权益字段都不在运行态生效，VIP 权益判定（前条）进一步失准。
建议：`restoreSession` 改 `Future<bool>` 并 await 刷新结果；`KugouSession` 增 vipToken/vipType/t1 字段，`_applyCredentials` 与 `_restoreVipExtras` 统一回写运行态；失败返回明确错误态而非一律 true。
76 合规：不违反。

## <视角 C2> · lib/logic/auth/auth_logic.dart:300-313 · P2 · 短信登录失败静默吞
证据：
```dart
Future<SmsLoginResult> signInByVerifyCode(String mobile, String code) async {
  final r = await auth_ep.smsLogin(_client, mobile, code);
  if (r.ok) { await _applyCredentials(...); }
  return r;   // r.ok==false 时不抛、不改状态，直接返回失败结果
}
```
同类门面 `signInByPwd`（296）失败时 `throw KugouApiException`，`renewByToken`（347）也抛，唯独短信登录把失败当普通值返回。若调用方未检查 `r.ok`（UI 层常规做法），表现为「点登录无反应」。
建议：与 signInByPwd 对齐——失败抛带语义的异常或返回显式失败态并在 UI 强制消费；补登录失败提示路径。
76 合规：不违反。

## <视角 C2> · lib/logic/auth/account_logic.dart:75-112 · P1 · 账号切换后 VIP 权益与续期凭据丢失
证据：`switchTo` 全量回写 session/settings 的 token/userid/mid/dfid/cookie（`95-105`），但**不写 vip_token/vip_type/t1 的 session 与 settings 键**；`AccountRecord`（`account_logic.dart:49-56`）也只存 token/mid/dfid/cookieBlob，无 vip 字段。切号后 `auth_logic._tryRefreshToken` 读的 `session.cookies['t1']` 只来自 cookieBlob（若旧账号 cookie 含 t1 还会串到新账号）。
问题：多账号切换后 VIP 权益丢失、t1 可能跨账号污染；与「全量回写、防串号」的代码注释自相矛盾。
建议：AccountRecord 增 vipToken/vipType/t1 字段，saveCurrent 保存、switchTo 回写 session + settings 对应键；cookie 解析后显式覆盖 t1 来源而非依赖 blob 混带。
76 合规：不违反，但逻辑与注释承诺不一致。

## <视角 C2> · lib/logic/auth/account_logic.dart:15-20 · P2 · YKG 凭据导出素材缺失（现状盘点）
证据：文件注释称 AccountRecord 为「本地档案事实源」，字段仅 `token/userid/mid/dfid/cookieBlob`；全仓 `rg -i ykg lib/` 零命中。YKG 设计（`docs/YKG_LINK_CRYPTO_DESIGN.md`）需要「base64(cookie)+md5 加盐密码」导出素材，其中 cookie 序列化已具备（`cookieBlob`），但**密码学加盐/解锁字段、导出格式封装在 logic 层零实现**，仅能作为输入素材复用。
问题：C3 视角的 YKG 设计在 L5 logic 侧没有任何门面或数据准备，B1 阶段需从零补导出/解锁逻辑（本条仅定位，不重复报底层 crypto 原语问题）。
建议：在 AccountLogic 增 `exportCredentialBlob(password)` / `importCredentialBlob(blob,password)` 门面素材（成熟库封装密码学），复用 cookieBlob + userid + mid 序列化；具体密码学设计见 YKG 文档，本视角不定义算法。
76 合规：不违反。

## <视角 C2> · lib/logic/catalog/collect_logic.dart:96-122,158-235 · P1 · 收藏 toggle 实现完备但全链零调用（假按钮根因在 logic 消费侧）


证据：`CollectLogic.toggle` 实现完备（登录守卫/putIfAbsent 防重锁/端点成功才写镜像/按账号分键持久化/fileid 回执/计数校准），但全仓调用点核实：
- `rg '\.toggle\(' lib/` 只命中 `playback_session.dart:267`（播放器暂停/播放）与 `mv_page.dart:189`（MV 播放/暂停），**无一处是 CollectLogic.toggle**；
- surface `player_page.dart:66` 自注「收藏按钮：状态本地维护（收藏域写端点尚未经桥暴露，故不写远端）」，收藏按钮纯 `_fav` 本地 setState；
- 唯一消费者 `library_page.dart:52` 只调 `refreshCount()` 读计数。
问题：与 A1「收藏假按钮」交叉确认——logic 实现正确、零消费，用户收藏行为 100% 不落库/不落远端，换设备全丢。
建议：L6/L7 接线：player_page 收藏按钮改调 `appGraph.collect?.toggle(song.hash, song.mixSongId, song: song)` 并用 `isCollected()` 初始化；注册 `onChanged` 刷新列表。B5 消费侧断点记录。
76 合规：不违反；「服务端成功才改镜像」语义正确。

## <视角 C2> · lib/logic/catalog/playlist_write_logic.dart:56-71,93-105 · P2 · 建歌单成功即删空镜像 + 写后在线缓存不失效
证据：
```dart
final id = await createPlaylist(_client, name);
if (id != null && id.isNotEmpty) { await _invalidate(id); }
Future<void> _invalidate(String listid) async {
  await _dao.delete(listid);   // 新建歌单必然无本地镜像
  _onChanged?.call();
}
```
本地镜像按 `playlistId` 存（`playlist_logic.saveLocalMirror`），新建歌单无镜像可删；bootstrap 构造 `PlaylistWriteLogic` **未注入 onChanged**，写后 `PlaylistLogic` 持有的 LruCache（recommend/detail/tracks）也不失效，UI 可能长期显示旧列表。
问题：写操作成功后缓存失效语义不完整（只删 DAO 空记录）。
建议：注入 onChanged 统一清 LruCache namespace + 刷新 DAO；`create` 去掉无意义 delete。
76 合规：不违反。

## <视角 C2> · lib/logic/catalog/search_logic.dart:52-76 · P2 · 空结果落缓存，失败可能被固化为「无结果」
证据：
```dart
final res = await searchSongs(_client, kw, page, pageSize);
_cache.put(key, res);   // 无 state / isNotEmpty 判定
```
同域策略矛盾：`search_typed_logic.dart:74` 「空结果也落缓存防重复打网」vs `mv_logic.dart:50`/`rank_logic.dart:56` 「空结果不落缓存」（审查修复）。端点若把失败伪装成空 `SearchResult`，LRU 生命周期内反复命中空态。
问题：三态（成功有结果/真空/失败空）不区分，网络失败可能固化为「搜索无结果」。
建议：端点给 SearchResult 加 state（仿 `DailyRecommendResult.state`）；统一 search 与 search_typed 策略。
76 合规：不违反。

## <视角 C2> · lib/logic/catalog/user_logic.dart:43-52 · P2 · 未实测空档案无条件落缓存
证据：
```dart
final p = await user.getUserDetail(_client);
_cache.put(key, p);   // 端点未实测恒空仍写缓存
Log.d(_tag, 'profile got empty=${p.isEmpty}');
```
对比 recommend/fm/rank 的「空不落缓存」修复，本文件明知端点恒空仍固化；探针实测翻转后老空值继续命中。
建议：`if (!p.isEmpty) _cache.put(key, p);`；session 接入已实现的 `invalidatePrefix`。
76 合规：不违反。

## <视角 C2> · lib/logic/catalog/recommend_logic.dart:44-64 / lib/surface/pages/home_page.dart:53 · P1 · 推荐三态在 logic 正确产出但 UI 签名吞掉状态
证据：`recommend_logic.daily` 返回 `Future<List<SongBrief>>`，实际对象为 `DailyRecommendResult`（含 `state`/`loginRequired`），注释明言「UI 可直接从结果取 .state 区分需登录/暂无推荐」；但 `home_page.dart:53` 只 `g.recommend?.daily(1) ?? Future.value(const <SongBrief>[])`，将结果当纯 List 消费，`state=loginRequired` 与 `state=error/empty` 全部渲染成「无推荐」。
问题：logic 侧三态设计到位，消费侧未用；用户未登录/失败都看到「暂无推荐」，误导且无登录引导（对应 A4 X6「i18n/文案没改」同链的诚信问题）。
建议：签名改 `Future<DailyRecommendResult>`（或加 `dailyDetailed()`），home_page 按 state 渲染需登录/重试/空态文案；本条属消费侧断点，logic 侧只需暴露类型。
76 合规：不违反。

## <视角 C2> · lib/logic/download/download_manager.dart:85-113,246-290 / download_commit.dart:44-58 · P1 · 下载任务状态机正确但 enqueue 全链零调用（下载无入口）
证据：`DownloadManager.enqueue`（85）完整（hash 去重/默认音质/emit/_pump 调度），但 `rg '\.enqueue\(' lib/ tool/` **零命中**；下载管理器仅在 `bootstrap`/`graph` 装配，`library_page.dart:_loadDownloads` 只读 `listTasks()`。与 A1「上层零调用」交叉确认——logic 侧实现可用，缺的是 surface 入口。
补充实现正确性瑕疵（非根因，P2）：`download_commit.dart:54` commit 后收到 cancel 时保留已落盘文件但**不入曲库**（`job.abort` 早退跳过 syncSongRecord），`DownloadStore` 索引却已 commit → 已下载歌曲在曲库不可见，与任务表已移除叠加成「幽灵下载」。
问题：下载功能对用户在 UI 完全不可达；且 cancel 边缘路径留下不一致索引记录。
建议：surface 接入 `downloads.enqueue(song, quality)`；commit 后 cancel 应要么完整落库（含曲库同步）要么回滚索引，避免幽灵记录。
76 合规：不违反（logic 侧）。

## <视角 C2> · lib/logic/download/download_manager.dart:246-290,334-384 · P2 · 分块下载失败后残留 .dlpart 与进度脏读风险
证据：
```dart
for (final url in candidates) {
  await _downloadUrl(task, job, url, src.extName);  // 失败时内部 _cleanupPart(part)
  ...
}
```
`_downloadUrl` 异常路径清 part 后 `rethrow`，下个候选重建 part 并重置 `bytesDownloaded=0`（`_downloadUrl:353`），但 `bytesTotal` 若新链未返回 content-length 会留旧值（`res.contentLength>0 ? ... : 0`，实为归零，风险有限）。真正问题是 `task.status` 在备用链尝试期间仍是 `running` 且进度按 URL 重置——UI 出现进度条回跳；最后全失败时 `_mark(failed)` 但 `bytesDownloaded/Total` 保留最后一条链的残值，用户看到「失败 47%」。
建议：备用链切换时显式重置进度并 emit 一次「重试中」事件；失败时清零 bytes 或展示错误态而非残留进度。
76 合规：不违反。

## <视角 C2> · lib/logic/lyrics/translation_logic.dart:53-98 / A3 X5 · P1 · 译文恒空时 translation 模式退化为原文但无显式状态提示（端点恒空联动）
证据：本文件正确防护了端点恒空：`displayFor` 在未传 translatedLines 时从 `LyricResult.content` 抽内嵌翻译轨（`extractEmbeddedTranslatedLines`），无轨则 `local=null`，`hasTrans=false`，`mode=translation` 时用原文填充 main 并 `Log.w`——**无静默伪造译文，处理正确**。但返回 `List<DisplayLine>` 无「是否有译文」标志，UI 无法区分「真的没有译文」与「译文加载中/失败」；A3 X5 已确认独立 `fetchTranslation` 端点恒空死代码。
问题：翻译功能在 UI 表现为「切到译文却还是原文」且无解释，用户痛点「什么功能都用不了」在翻译上落实为无反馈降级。
建议：`DisplayLine` 或返回值增 `hasTranslation` 元信息，UI 在无译文时显示「暂无译文」提示；勿依赖恒空 fetchTranslation 端点。
76 合规：不违反（本层不直连端点，处理正确）。

## <视角 C2> · lib/logic/lyrics/lyrics_parser.dart:61-112,135-176 · P2 · KRC 逐字行的多时间标签 LRC 兼容缺失（解析边界）
证据：
```dart
final _krcHeaderRe = RegExp(r'^\[(\d+),(\d+)\]');  // 只匹配行首 KRC 头
...
final krc = _parseKrcLine(line);   // 命中即 continue，不再走 LRC 多标签解析
```
实测留样（`tool/field_truth_test.dart:455`）KRC 明文 `[0,2250]<0,160,0>晴...` 能被正确解析；但 KRC 文件常见的 `[00:00.00][00:05.00]<...>` 混合形态、或 KRC 行头前有 BOM/空格（本文件 `raw.trim()` 已去首尾空格，BOM `\uFEFF` 未去）会漏识别为 LRC 行且 `_extractTimeTags` 首标签 start!=0 时返回空 → 整行歌词丢失。
建议：`raw.replaceFirst('\uFEFF','')` 后再 trim；KRC 行识别时若行首是 LRC 时间标签也尝试解析尾部 `<t,d,x>` 逐字段；补留样测试。
76 合规：不违反。
## <视角 C2> · lib/logic/download/download_manager.dart:58,113-133（onTask 订阅方）+ download_models.dart:113-129 · P2 · 下载事件流零订阅、状态机对 UI 不可观测
证据：`DownloadManager.onTask` 是唯一进度/状态变更出口（`_emit` 在 enqueue/pause/resume/cancel/retry/进度/完成/失败均回调），但全仓 `rg 'onTask' lib/` 仅命中 manager 自身定义与 bridge export，session/surface 零订阅；`library_page.dart:57` 只用一次性 `dm.listTasks()` 快照，不监听事件。
问题：即便补上 enqueue 入口，UI 也不会收到下载进度/完成/失败通知，用户只能手动重进页面看静态快照；下载状态机在应用层不可观测。
建议：session/graph 装配时订阅 `downloads.onTask` 并转发给 UI（ChangeNotifier/Stream）；或在 `PlaybackSnapshot` 增下载任务快照统一推送。B5 跨层复核。
76 合规：不违反（L5 只暴露回调，消费侧缺失）。

## <视角 C2> · lib/logic/catalog/fm_logic.dart:30-160 + lib/core/net/endpoints/fm_endpoints.dart（needs probe） · P2 · FM 恒空批次但无「不可用」显式态
证据：`FmLogic.start()/next()` 端点 `getFmPlay/getFmSongs` 恒返回空（端点 needs probe），本层 `_load` 正确「空不落缓存」并 Log.w，返回空批次；注释要求「空批次降级不切队列」，但 `List<SongBrief>` 返回类型无法区分「无数据/未实测/网络失败」，调用方（若接）只能当成「FM 没歌」。
问题：与 recommend 同型——空结果与不可用同构，用户无「功能探测中/暂不可用」提示；端点恒空时 FM 入口点了无反应。
建议：返回显式状态对象（仿 DailyRecommendResult），或至少在空批次时由上层 UI 读一个 `lastError/needsProbe` 标志显示提示。
76 合规：不违反。

## <视角 C2> · lib/logic/player/history_recorder.dart:27-63 · P2 · 历史记录在换歌瞬间恒记 playedMs=0（语义失真）
证据：`playback_session._start`（250）与 MV 兜底分支（216）都是 `recordPlay(cur, 0)` 即 **fire-and-forget 固定 0 ms**；注释写「playedMs：本次实际播放毫秒数」，实际从不使用引擎进度。`history_recorder` 把 0 写进 `durationPlayedMs`，`_history.record` 按同 hash 累计该字段。
问题：播放历史累计时长恒 0、「最近播放」无真实收听时长；语义与注释不符，长期数据失真。另 `recordPlay` 内部全 try/catch + Log.e 不抛，session 的 `.catchError` 守卫永远不会触发（日志说「失败必须留痕」尚可）。
建议：在 `onCompleted/pause/切歌` 时以 `DateTime.now()-startTs` 或引擎 positionMs 差值调用 `recordPlay`，或改 `HistoryRecorder` 为 begin/end 两段式（startPlay + finishPlay(playedMs)）。
76 合规：不违反。

## 本视角结论
1. **P0×1**：`VerificationLogic` 20028 验证状态机零消费者、solved/failed 永不可达，验证链路完全断裂（`verification_logic.dart:27-120`）。
2. **P1×8**：MV logic 用 hash 冒充 videoId（档位恒空）且与 playback_service 兜底链共同受端点层恒 null 传导成死链；VIP 权益判定恒 false（session 未注入 + KugouSession 无 vip 字段）；`sourceKind` 不进 PlayerState 致 MV 音频 UI 标记死代码；play_resolver/parser/quality_policy/url_health 整组 681 行死代码；restoreSession 半成功（续期 fire-and-forget、权益不回写）；账号切换丢 VIP/t1 且可跨账号污染；收藏 toggle 实现完备但全链零调用（假按钮根因）；推荐三态 UI 吞掉状态；下载 enqueue 零调用（UI 完全不可达）。
3. **P2×10**：shuffle prev 不可逆、短信登录失败静默吞、YKG 导出门面缺失、歌单写后缓存失效不完整、搜索空结果固化、用户档案空值固化、下载 cancel 幽灵记录/进度回跳、下载事件流零订阅、FM 恒空无显式态、历史播放时长恒 0、翻译无译文态提示、KRC BOM/混合行解析边界。
4. 与前置批次交叉确认：A1「收藏假按钮/下载无入口/restoreSession 异常吞」在 logic 侧复核——异常吞描述偏重（本层有 Log.e 留痕），假按钮与无入口确认是**消费侧零调用**而非 logic 缺失；A3「MV 端点恒 null」经本视角确认传导为 playback_service 兜底链 100% 早退，且 logic 侧自身还有 hash→videoId 第二重错位。
5. 空安全总体良好：34 文件普遍 try/catch + Log，未见可空字段直接解引用导致崩溃的路径；死代码/零消费与错误语义丢失是本批主要问题类型。

## 未覆盖
- 未逐行核对 `download_manager.dart:1-84,290-333,385-494` 之外的所有分支细节（时间预算），但通过完整 `file_read` 覆盖全文，关键状态机路径（enqueue/pause/resume/cancel/retry/_pump/_runOne/_downloadUrl/commit/清理）已审。
- 未跑 dart analyze/test/门禁（按纪律禁跑），所有结论为静态审查。
- 未核对 L6/L7 消费侧修改建议的具体落点（仅定位调用缺失，不越视角展开修复）。
- A5 全 34 文件均已 listing + 逐文件读取；`player/history_recorder` 等短文件已覆盖。

## 76 合规小结
- 层职责：34 文件均为 L5 logic（auth/player/download/catalog/lyrics），无 flutter/surface import；仅经 bridge_kernel/bridge_core 访问下层，无反向依赖；无影子桥。
- `url_health.dart` 直连 `dart:io HttpClient` 做 HEAD/Range 探测，与文件头「L5 仅后端逻辑、无 IO 直连」自注释冲突（76 §0 L5 定义），且该实现还是死代码——架构裁定交 C1，本视角记录为职责越界疑点。
- `download_manager.dart` 同属 L5 但直连 `dart:io HttpClient` 分块下载（路径/分片清理），与「L5 仅后端逻辑」边界不符（网络/IO 应归 L4）；同样交 C1 裁定。
- 状态机跨层问题：`sourceKind` 在 L6 私有变量与 L5 PlayerState 双份真相源、`PlaybackAction` 无写 sourceKind 的 action；20028 验证状态机停在 L5 无 L6 驱动——属职责不越界但装配缺失。
- 除上述 IO 直连疑点外，本视角发现均为「正确性/可达性」问题，非 76 架构硬违规。
