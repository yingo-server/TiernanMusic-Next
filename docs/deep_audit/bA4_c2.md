# A4 批 · C2 实现正确性视角审查报告

> 审查时间：2026-11-16 23:30 (Asia/Shanghai)
> 视角：C2 实现正确性（空安全/状态机/失败空结果路径/缓存失效/异步竞态/字段契约/死链死代码/异常吞没/密码学）
> 范围：L4 core 非网络 15 文件（database×3 / storage×4 / cache×1 / audio×2 / algorithms×2 / l10n×1 / memory×2）
> 已读：`DEEP_AUDIT_14_BATCH_PLAN.md` 全文 + `A2_P0_VERIFICATION.md`（确认 AES Rcon P0 为真、RSA mul P0 为误报；本视角不重复）。
> 纪律：只读静态分析，未跑 dart/analyzer/test/门禁，未改任何源码。交叉调用链仅作只读 rg 取证。

---

## <视角 C2> · core/l10n/strings.dart:280-295 · P1 · 死代码/功能不可达（与用户痛点"文案没改"直接相关）
证据：
```dart
static String normalize([String? language, String? script, String? country]) {
  final lang = (language ?? '').toLowerCase();
  ...
  for (final c in supportedCodes) {
    if (c.toLowerCase() == lang) return c;   // 用单个 loc.language 匹配 'zh_Hant'
  }
  return defaultCode;                          // 不匹配就回 zh
}
```
全仓 `rg 'TnStrings|forCode\(|\.tr\('` 仅命中 `bridge_core.dart:49 export` 与定义处，**无任何业务调用点**。
问题：① 整个 `TnStrings` 取词器 + 10 语 `_kCatalog` 是死代码，UI 不消费 → 用户痛点"相关文案也没改"在 core 侧落实为零；② `normalize()` 的三形参语义与调用矛盾：它设计接收 `(language, script, country)`（见注释"zh+Hant/TW/HK/MO -> zh_Hant"），但唯一会传单一字符串的地方是 `forCode(s)`/`loadLocale()` → `normalize(code)`，此时 `language='zh_Hant'`。白名单循环里 `c.toLowerCase()=='zh_hant'` 恰好能命中，尚可工作；但 `appLocaleCode()` 返回 `'zh_Hant'` 这种非法 Dart `Locale` 语言码（下划线），L7 若直接包 `Locale('zh_Hant')` 会有兼容风险。
建议：接上 TnStrings 到 surface 文案层（阶段 B7）；`normalize` 拆成「解析复合 code」与「解析三元组」两函数，返回标准 BCP47（`zh-Hant`）。
76 合规：不违反层级（core/l10n 常量归 L4 正确）；但属 L4 能力未被上层桥接消费的"断链"，违反"能力可达"精神。

## <视角 C2> · core/cache/cache_service.dart:139-158 · P2 · 失效语义不全/空结果落缓存
证据：
```dart
Future<Map<String,dynamic>> get(...) async {
  try { _reads++; return await _client.request(ep, params, body: body); }
  catch { _errors++; return <String,dynamic>{}; }   // 失败降级空 Map
}
void invalidateSession() { _client.clearInflight(); } // 只清单飞表
```
`kugou_client.dart:96-113`：`cacheable` 命中即返回；`res` 不论是否为空/`{error}` 都 `putJson(cacheKey,res)`。
问题：① get 失败吞异常返回空 Map，调用方无法区分"真无数据"与"网络失败"，与空结果三态需求冲突；② 失效只有 `invalidateSession()`，无按 key/按 namespace/按 TTL 的失效 API，磁盘缓存一旦写入错数据无法从门面清除；③ 空 Map/错误响应被 `KugouClient` 无条件落 L2，污染后续读（属 net 层根因，门面无防护）。
建议：门面暴露 `invalidate(key|namespace)`；get 失败改为可识别的错误态；net 层只对成功且非空响应 `putJson`（线A范围，登记交叉）。
76 合规：符合分层（策略层门面，不另起缓存表），无越级。

## <视角 C2> · core/algorithms/qr_codec.dart:281-297 · P1 · 数据放置列对起点 off-by-one（QR 大概率不可被标准扫码器识别）
证据（数据放置列对，代码与其自身注释矛盾）：
```dart
// 注释（本文件 281 行）：标准列对（右列，左列）：28/27, 26/25 … 8/7, 5/4, 3/2, 1/0
for (var right = size - 2; right >= 8; right -= 2) {   // 起点 size-2（奇）
  pairs.add(<int>[right, right - 1]);
}
pairs.addAll([<int>[5,4], <int>[3,2], <int>[1,0]]);
```
问题（逐版本推导）：size=17+4v 恒为奇数（21/25/29/33）；Nayuki 标准算法从 `right=size-1`（偶）起，配对 (size-1,size-2),(size-3,size-4)…(8,7)，跳过 timing 列 6 后接 (5,4),(3,2),(1,0)。本实现从 `size-2`（奇）起，V1 生成 (19,18),(17,16)…(9,8),(5,4),(3,2),(1,0)：**完全漏掉最右列 20 与列 7**，二者的数据区模块（如 V1 列 20 的 y=9..20 约 12 个数据模块）永不写入 → `bitIdx` 到不了 `totalBits`，末尾码字丢失，QR 结构损坏。代码与紧邻注释（结尾 8/7）自相矛盾，证实为 off-by-one。全版本 V1–V4 均受影响。
建议：起点改为 `right = size - 1`，与 Nayuki 对齐；用已知 QR 向量（Nayuki V1-L/M）离线核对数据放置、格式信息、掩码；接线 YKG 时优先采用成熟 `qr` 包（76 §0 第9条）。另注意 mask 固定 0、无最优掩码，非标准最佳实践。
76 合规：归 L4 纯算法正确；无越级 import。另外全仓 `rg 'encodeQr|QrMatrix'` 仅命中定义与 `bridge_core.dart:46 export`，无业务调用点（当前为死代码，YKG 扫码尚未接线）。

## <视角 C2> · core/storage/resource_cache.dart:158-200 · P2 · FNV-1a 负哈希产生非契约文件名（含 '-'、长度不定）
证据：
```dart
int h = 0xcbf29ce484222325;
for (final int c in utf8.encode(key)) {
  h ^= c;
  h = (h * 0x100000001b3) & 0xffffffffffffffff;
}
final String hex = h.toRadixString(16).padLeft(16,'0');
```
问题：Dart VM int 是 64 位有符号（web 目标为 53 位浮点），`(h * 0x100000001b3)` 在中间步骤会溢出为负数。`& 0xffffffffffffffff` 在 Dart 中字面量 `0xffffffffffffffff` 会被解析为负值（-1）或对 64 位按位与恰好保留低 64 位——在 native 64 位 int 上结果位模式正确；但在 dart2js/web 目标上 int 为 double，`&` 不支持大数，会出错。虽本项目为 Android native，风险有限，但 `h.toRadixString(16)` 当 h 为负数时会输出形如 `-xxxx`，导致 `padLeft(16,'0')` 后文件名含负号、长度不定，与"16 hex 字符"契约不符——例如 h<0 时字符串为 `'-1a2b...'`（17 字符），文件名 `safeName(key)` 不再是固定 16 hex，降低唯一性保证且可能触碰平台文件名限制。
建议：`final u = h & 0x7fffffffffffffff;` 取无符号语义再 `toRadixString(16).padLeft(16,'0')`，或用 `(h >>> 0)` 分段输出；补单测覆盖负哈希键。
76 合规：不违反分层。

## <视角 C2> · core/storage/resource_cache.dart:339-372 · P1 · putString 写失败仍返回成功/索引与文件不一致
证据：
```dart
await _enqueue<void>(() async {
  ...
  final bool ok = await _renameAtomic(tmp, target);
  if (!ok) { await _discardTmp(tmp); bk.logW(...); return; }  // 仅 return，无异常
  _index[key] = {...};
  await _saveIndex();   // 其返回值被忽略
});
```
问题：① `_renameAtomic` 失败（返回 false）时，`putString` 静默 `return`，调用方（`KugouClient.request`：`await _cache!.putJson(...)`）认为写成功，但数据未落盘、索引未更新——失败被吞；② `_saveIndex()` 返回 bool 表示索引持久化是否成功，此处被完全忽略：若数据文件已 rename 成功但 `_saveIndex` 失败（磁盘满/权限），则内存 `_index` 有新条目、磁盘 index.json 无该条目，进程重启后数据文件成孤儿（缓存泄漏），且本次 get 能命中内存索引但重启后丢失；③ 无"写后校验"机制。
建议：putString 返回 `bool` 或在 `_saveIndex` 失败时回滚内存索引并抛；`_renameAtomic` 失败要向调用方传错误信号而非静默 return。
76 合规：不违反分层。

## <视角 C2> · core/storage/resource_cache.dart:223-260 · P2 · 索引加载失败竞态/并发 put 可能被空索引覆盖
证据：
```dart
Future<void> _ensureLoaded() {
  final pending = _loadFuture; if (pending != null) return pending;
  final done = _recoverLoad(_enqueue<void>(_loadIndex));
  _loadFuture = done; return done;
}
Future<void> _recoverLoad(Future<void> raw) async {
  try { await raw; } catch(e,st) { _loadFuture = null; ... }
}
```
问题：`_loadIndex` 内部已吞掉所有异常（损坏则清空重建），故 `_recoverLoad` 的 catch 几乎不触发；但 `_loadFuture=null` 的重试路径若被触发，第二次 `_ensureLoaded()` 会再次 `_enqueue(_loadIndex)`，而 `_loadIndex` 会向已有 `_index`（可能已被并发 put 写入新条目）**追加**旧文件内容，导致脏读。虽有串行链保护 RMW 不交错，但"重试加载"与"已写入内存的新条目"语义冲突。属低概率竞态。
建议：`_loadIndex` 加载前先 `_index.clear()`（在其串行段内），确保重建语义干净；或加载失败后禁止重试直到显式 invalidate。
76 合规：不违反分层。

## <视角 C2> · core/storage/download_store.dart:105-134 · P1 · saveIndex 非真正原子（先删目标再 rename）
证据：
```dart
bool saveIndex() {
  final tmp = File('${_indexFile.path}.part');
  tmp.writeAsStringSync(jsonEncode(arr), flush: true);
  if (_indexFile.existsSync()) _indexFile.deleteSync();   // ① 先删旧
  tmp.renameSync(_indexFile.path);                        // ② 再 rename
  ...
}
```
问题：① 与同目录 `resource_cache.dart` 已修复的"先删目标再 rename 空窗"是同一类 bug：`deleteSync` 与 `renameSync` 之间若进程崩溃/断电，`index.json` 丢失，全部下载记录不可见（文件还在但索引没了）；POSIX `rename` 可直接原子覆盖存在目标，无需先删。② 固定临时名 `index.json.part`：若两个 `DownloadStore` 实例并发 `saveIndex`（bootloader 只 new 一个，但 `upsert`/`remove` 各自 `loadIndex(forceReload)+saveIndex` 非原子，同一实例多线程/隔离区调用会互踩 .part），会造成写放大/错乱。③ 全同步 IO（`*Sync`）在小李件量级可接受，但 `commitDownload` 把整个文件 `data` 一次性读入内存 `List<int>` 再 `writeAsBytesSync`，大文件（几百 MB）会 OOM。
建议：去掉 `deleteSync`，直接 `tmp.renameSync(_indexFile.path)`（原子覆盖）；.part 用唯一名；大文件下载改流式 `IOSink`。
76 合规：不违反分层（storage IO 归 L4 正确）。

## <视角 C2> · core/storage/settings_store.dart:56-66 · P2 · 双实例共享表只登记首次构造者，后续 new 仍互盲
证据：
```dart
KeyValueSettings(this._paths) : _file = _paths.fileIn('db','settings.json') {
  _sharedByPath[_file.path] ??= this;   // 仅当无登记时才放
}
static KeyValueSettings shared(StoragePaths paths) {
  final hit = _sharedByPath[key];
  if (hit != null) return hit;
  final created = KeyValueSettings(paths);
  _sharedByPath[key] = created; return created;
}
```
问题：构造器用 `??=` 只登记第一个实例。bootloader `bootloader.dart:132` 用 `new KeyValueSettings(paths)` 创建 L2 那一份并登记；`TnStrings.saveLocale/loadLocale`、`theme_controller` 用 `shared()` 命中它，OK。但若某处先 `new` 了第二个实例（如历史遗留 `player_controller._fallbackSettings`，注释中已承认存在），该实例**不会**覆盖共享表，也不走 `shared()`，其内存缓存与 L2 实例互盲 → 重现历史 bug（写读互盲）。注释把收口寄托于"F1 完成后主会话改调用点"，属未完成依赖。全仓 rg 当前未见活跃的第二 new，但设计缺陷仍在。
建议：构造器改为无条件登记 `_sharedByPath[_file.path] = this`（后写覆盖），或构造器私有化、强制走 `shared()`。
76 合规：不违反分层；属实现健壮性问题。

## <视角 C2> · core/storage/settings_store.dart:71-82 · P2 · 配置损坏静默重置为空表（数据丢失）
证据：
```dart
} catch (e, st) {
  Log.e('kvsettings','load failed',e,st);
  _loaded = true;          // 损坏文件不阻塞启动，按空表继续
}
```
问题：`settings.json` 损坏（截断/写一半崩溃）时，`_ensureLoaded` 记 `_loaded=true` 且沿用空 `_cache`。此后任意 `setXxx` → `_flush()` 用空/半空 `_cache` 原子覆盖损坏文件，永久丢失全部用户设置（登录 token、主题、语言偏好等）。有 Log 但无备份/恢复机制。对照 `resource_cache.dart:_loadIndex` 损坏时至少删除文件重建（同样丢数据但语义明确），settings 的静默继续更危险。
建议：损坏时把原文件改名为 `settings.json.corrupt-<ts>` 备份后再按空表继续；或提供默认值合并而非全空。
76 合规：不违反分层。

## <视角 C2> · core/database/dao.dart:88-110,199-240,262-290 · P2 · 读-改-写非事务，并发更新丢失
证据：
```dart
// SongDao.markPlayed
final song = await getByHash(hash);   // txn 外读
if (song == null) return;
song.playCount += 1;                  // 内存改
await put(song);                      // 另一个 txn 写
// PlaylistDao.addSong / removeSong / reorder 同为 getByPlaylistId → 改 → put
```
问题：`markPlayed` 的计数自增、`addSong/removeSong/reorder` 的歌曲列表修改均为「读在 txn 外、写在独立 txn」的非原子 RMW。两个并发播放完成事件都读到 `playCount=N`，各自写 `N+1` → 丢失一次计数；并发歌单编辑后写覆盖先写。Isar 单写事务本身串行，但跨 txn 的读-改-写无隔离。对照 `AccountDao.setActive`（dao.dart:399）把清_all+置目标放进**同一个** writeTxn，是正确范式。
建议：把读+改+写整体移入一个 `writeTxn` 内；或用 `where().filter()...` 的原子更新 API。
76 合规：不违反分层。

## <视角 C2> · core/database/dao.dart:300-345 · P2 · HistoryDao.record 按 hash 去重仅保留一条，语义与注释/命名不符
证据：
```dart
final sameHash = await _isar.playHistoryEntrys.where().hashEqualTo(hash).findAll();
for (final e in sameHash) { if (existing==null || e.playedAt>existing.playedAt) existing=e; }
if (existing != null) { /* 更新这一条 */ } else { /* 新建 */ }
```
问题：类注释称"一条 = 一次播放事件"（entities.dart:79），但 `record` 对同 hash 只保留 1 条并累加 `durationPlayedMs`。结果是"最近播放"列表里每首歌最多出现一次，无法回溯历史播放事件；`durationPlayedMs` 跨多次播放累加但 `playedAt` 只记最后一次，语义混乱。若产品期望"历史流"，此为设计缺陷；若期望"每歌聚合"，则实体注释错误。属契约不一致。
建议：明确产品语义——保留逐条事件则去掉去重；保留聚合则修正注释与字段命名。
76 合规：不违反分层。

## <视角 C2> · core/audio/notification_gateway.dart:107-118 · P2 · MediaItem.id 用 title.hashCode，跨曲碰撞/不稳定
证据：
```dart
mediaItem.add(MediaItem(
  id: meta.title.hashCode.toString(),   // 仅标题哈希
  title: meta.title, artist: meta.artist, ...
));
```
问题：媒体会话用 `id` 区分条目。不同歌曲同名（翻唱/同名曲）会生成相同 id → 通知栏/媒体中心可能合并或复用状态；`String.hashCode` 在 Dart 中跨进程不稳定（本版本启用了 hash randomization），重启后同一首歌 id 变化。历史 bug"updateMetadata 零调用"已修复（playback_session.dart:220/253 确有调用），但 id 生成仍不可靠。
建议：id 用稳定的业务键（song.hash / mixSongId）经 NotificationMeta 传入；`NotificationMeta` 增 `id` 字段。
76 合规：音频网关归 L4 正确；无越级。

## <视角 C2> · core/audio/notification_gateway.dart:70-85 · P2 · processingState 映射使用 `!` 强制解构，新增枚举值会崩
证据：
```dart
processingState: const {
  ProcessingState.idle: AudioProcessingState.idle,
  ProcessingState.loading: AudioProcessingState.loading,
  ProcessingState.buffering: AudioProcessingState.buffering,
  ProcessingState.ready: AudioProcessingState.ready,
  ProcessingState.completed: AudioProcessingState.completed,
}[event.processingState]!,   // 强制解包
```
问题：just_audio 若在后续版本新增 `ProcessingState` 枚举值，或返回未列入的值，`[...]!` 会抛空指针异常；该异常发生在 `playbackEventStream.listen` 回调内且无 try/catch 包裹（仅 onError 捕获流错误，不捕获同步 throw），会导致订阅中断、通知栏状态停止更新。
建议：改为 `[...]? ?? AudioProcessingState.idle`，并在回调体包 try/catch。
76 合规：不违反分层。

## <视角 C2> · core/audio/audio_gateway.dart:173-185 · P2（待分析器确认）· clamp 返回 num 传入 double 参数
证据：
```dart
Future<void> setVolume(double v) async {
  await _player.setVolume(v.clamp(0.0, 1.0));   // num → double?
}
Future<void> setSpeed(double v) async {
  await _player.setSpeed(v.clamp(0.5, 2.0));
}
```
问题：Dart `num.clamp()` 静态返回类型为 `num`（即使接收者与参数均为 double）。若 just_audio 的 `setVolume/setSpeed` 形参为 `double`，则 `num` 不能直接赋给 `double`，分析器会报 `The argument type 'num' can't be assigned to the parameter type 'double'`。本视角禁跑分析器，无法确认该 SDK 版本签名，标为**待确认**；若成立则编译失败（P0）。
建议：显式 `.toDouble()`：`v.clamp(0.0,1.0).toDouble()`。
76 合规：不违反分层。

## <视角 C2> · core/memory/cache_keys.dart:48-52 · P2 · _canonical 对 Set/Iterable 未排序，键不稳定
证据：
```dart
// 注释（类顶部）：Set 转字符串排序
if (value is Iterable) {
  return value.map(_canonical).toList(growable: false);   // 未 sort
}
```
问题：注释承诺"Set 排序"，实现却保持迭代顺序。`LinkedHashSet` 按插入顺序迭代，两个元素相同但插入顺序不同的 Set 会生成不同的 canonical 列表 → 不同的缓存键 → 同一逻辑请求缓存未命中/重复条目。若业务参数含 Set 会出现键抖动。
建议：对 Iterable 结果按渲染后字符串排序（若确需区分 List 保序，则分开处理 Set 与 List）。
76 合规：不违反分层。

## <视角 C2> · core/memory/lru_cache.dart:全文件 · 已确认正确 · 淘汰算法与边界
证据：`put` 中 `_order.remove/add` 移动 MRU，`while(_entries.length>_capacity)` 从 `_order.first`（LRU）淘汰；`capacity`/`resize` 对 ≤0 取 1。
结论：LRU 顺序维护正确，onEvict 回调用 try/catch 隔离，`invalidateWhere/Prefix` 基于 `_order.toList()` 快照安全删除。容量 0/负数被规约为 1（不崩）。**并发安全**：纯同步 Map/LinkedHashSet，单 isolate 内无 await 交错，正确；跨 isolate 无共享（每个 LruCache 实例独立）。无缺陷，仅记录为已核。
76 合规：不违反分层。

## <视角 C2> · core/database/db.dart:26-36 / bootloader:108-148 / main.dart:90-95 · 已确认正确 · DB open 竞态已修复
证据：`DatabaseService` 静态单例 + `open()` 幂等 await；bootloader 把 `dbOpenFuture` 放进 deps，main 在 `installServices` 前 `await dbFuture`；DAO 无状态、构造不访问 Isar；`restoreSession()`（auth_logic.dart:180）只读 KeyValueSettings 不碰 Isar。
结论：DAO 先于 DB 用的历史竞态已消除；`db.dart`（DatabaseService 实例）与 `net/database_opener.dart`（openDatabase 包装）关系清晰，后者经 bridge_core 暴露给 L2，前者不 import net。无多实例问题（静态单例）。无缺陷，记录为已核。
76 合规：不违反分层；`database_opener.dart` 位于 core/net 但属 core 门面，命名已去"bridge"字样（A2 记录），无影子桥。

---

## 本视角结论

1. **共 17 条**：P1×5（TnStrings 死代码+normalize 歧义、QR 列对 off-by-one、ResourceCache 写失败吞没、download_store 索引非原子、FNV 已降 P2 不计）、P2×11、已确认正确×2。
2. **最严重 3 条**：
   - **qr_codec.dart:283 数据放置列对 off-by-one**：从 `size-2`（奇）起，最右列与列 7 永不写数据，末尾码字丢失；代码与自身注释直接矛盾，V1–V4 全受影响，QR 大概率无法被标准扫码器识别（当前死代码，YKG 接线前必须修）。
   - **download_store.dart:116-117 索引先删后 rename**：`deleteSync` 与 `renameSync` 之间有空窗，崩溃即丢全部下载记录；同类 bug 在 resource_cache 已修，此处遗漏。
   - **resource_cache.dart:352/360 写失败静默**：`_renameAtomic` 失败仅 `return`、`_saveIndex()` 返回 bool 被忽略，调用方以为写成功，数据/索引不一致且无信号。
3. **历史 bug 复核**：DB 单例/await 竞态**已修**（main await dbOpenFuture）；settings 双实例互盲**部分修**（shared() 存在，但构造器 `??=` 只登记首个，第二个 new 仍互盲，依赖未完成的 F1 收口）；notification `updateMetadata` 零调用**已修**（playback_session 两处真实调用）；ResourceCache 同步 IO/写放大/并发丢条目/原子性批评**已系统性修复**（全异步 + _writeChain 串行 + rename 原子 + tmp 唯一名）。
4. **CacheService**：三级职责（门面→KugouClient L2 磁盘 + InFlight 单飞）正确，stats 恒 0 诚实标注不伪造（好实践）；缺按 key/namespace 失效、空结果落缓存由 net 层无条件 put 造成（跨层问题，已在 A2 登记）。
5. **LRU / DB open**：实现正确，无缺陷（详见"已确认正确"两条）。

## 未覆盖

- **未跑 dart/analyzer/test**（工具纪律禁止）：`audio_gateway.dart:175,184` 的 `v.clamp()` 返回 `num` 若 just_audio 形参为 `double` 会是编译错误，标为"待分析器确认"，未终验。
- **未做 QR 向量数值仿真**（禁止跑代码）：列对 off-by-one 为静态逐版本推导 + 代码注释自证，置信度高但未用真实扫码器/FIPS 式向量实测；RS 纠错码字表、格式信息 BCH 位序仅静态审阅未数值验证。
- **未验证 ResourceCache FNV 在具体 Dart 版本下 `h.toRadixString(16)` 负号表现**（静态推断，native 64 位 int 下 `& 0xffff...` 结果为负 int）。
- **未扩展审 A2 密码学**（AES Rcon/RSA 已由主会话仿真裁定，本视角不重复）。
- **未审 lib/l10n/*.arb 与 surface 文案一致性**（属 A7 C3 范围）。
- 未审 `entities.g.dart`（代码生成物，仓库内是否存在未核）。

## 76 合规小结

- **层级归属**：15 文件全部位于 L4 core 非网络层（database/storage/cache/audio/algorithms/l10n/memory），归属正确；纯算法、存储 IO、音频引擎适配、缓存策略均属 L4 职责，无 L5/L6/L7 反向依赖。
- **跨层桥**：各文件仅 import `bridge_kernel`（Log）或经 `bridge_core` 导出，符合"六桥唯一通道"；未发现影子桥目录或跨层直 import 非桥文件。
- **异常纪律**：绝大多数公开方法 try/catch + Log 留痕，无静默吞（ResourceCache putString 吞写失败、Settings 损坏静默重置是"有 Log 但无传播"的降级，属实现问题非铁律违反）。
- **成熟库优先（§0 第9条）**：just_audio / audio_service / Isar 均用成熟库，符合；**QR 为自研且疑似有 bug**（qr_codec.dart），YKG 接线时应改用成熟 `qr` 包；color_extract 自研纯算法可接受但当前死代码。
- **功能可达性**：TnStrings（10 语）、color_extract、encodeQr 三者均为"已导出但无业务调用"的死代码，是 L4 能力未被上层消费的断链，与用户痛点"功能用不了/文案没改"方向一致（具体接线属 A7/B 批）。
- **未发现**：容量 >1500 行文件（最大 qr_codec 350 行）、反向依赖、surface 塞状态机等 76 违规。
