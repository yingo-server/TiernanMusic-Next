# A4 批 · C3 用户痛点专项视角 · 审查报告

> 审查对象：L4 core 非网络层 15 文件（database/storage/cache/audio/algorithms/l10n/memory）
> 视角：C3 用户痛点（动态取色链 / 通知栏 / 存储恢复 / 缓存 / 文案 / QR）
> 方法：只读（file_read / rg / ls / wc），不跑 dart/analyze/test，不改源码
> 时间基准：2026-11-16；每得结论即 append

---

## [C3] · lib/core/algorithms/color_extract.dart:4-8,59-121 · P1 · 动态取色链/断链
证据：文件头注释自承「extractDominant / fromSeed 当前版本未被任何 UI 消费方调用（原封面取色桥 cover_color_bridge.dart 已删除）」。rg 全仓：extractDominant/fromSeed 的调用仅出现在 bridge_core.dart:48 的 `show` 导出，**无任何实际调用者**。真正生效的主题是 surface/design/tokens.dart:70-95 的 `ColorScheme.fromSeed(seedColor: green...)`，seed 为硬编码 `#1DB954`（Spotify 绿），tn_theme.dart:10 同样 `Color(0xFF1DB954)`。
问题：动态取色算法完整可用但**全链路断开**——封面主色提取结果从未进入 ColorScheme，用户看到的主题永远是固定绿，与 M3_BASELINE「取色链断、无 UI 消费者」结论一致。用户痛点「UI 不舒服/动态取色」在 L4 段无解，缺的是 L6 theme_controller 接线 + L7 消费。
建议：在主会话阶段 B6 接回链路——封面字节→extractDominant→fromSeed→ColorScheme.fromSeed(derived seed)；或删除死代码避免误导（当前注释已诚实标注，非运行期故障）。L4 算法本身可用，无需重写。
76 合规：涉及。L4 仅导出算法、无越级调用（注释称经 bridge_kernel 取 Log 合法）；断链属 L6/L7 职责缺口，非 L4 违规。

## [C3] · lib/core/algorithms/color_extract.dart:143-186 · P2 · 动态取色/调色板正确性
证据：fromSeed 用自实现 HSL 推导 primary/onPrimary/primaryContainer/surface 四色；`s = clamp(0.36,0.92)`、`primaryL = dark?0.62:0.46`；失败返回 `_fallbackPalette`（品牌紫）。仅为 4 角色，**非完整 M3 tonal palette**（缺 secondary/tertiary/on-* 成对角色、五级 surface container）。与 M3_BASELINE §2 第1/2条「无 ColorScheme 语义角色、无 tonal 阶梯」呼应。
问题：即便接回，此调色板也不满足 MD3 十类审计的 Color tokens/Theming 要求（skill Anti-Patterns：tonal pairing、完整色阶）。onPrimary 用 `s*0.18 + L` 反推对比度不可靠，高饱和 seed 下可能对比度不足 4.5:1。
建议：接回时改用 Flutter 原生 `ColorScheme.fromSeed(seedColor)` 生成全套 tonal 角色，本文件仅保留 extractDominant 提供 seed，fromSeed 可退居备选/删除。
76 合规：不涉及（纯算法，层级正确）。

## [C3] · lib/core/algorithms/color_extract.dart:59-121 · P2 · 动态取色/降级健壮性（正面）
证据：extractDominant 对空输入、畸形长度(`length < total*4`)、无彩色样本(sampled==0)、空直方图、异常全部分支返回 `ColorSeed.fallback=#7C4DFF` 且 Log.w/Log.e 留痕；采样步长 `step=max(1,total~/4096)` 上限约 4096 样本；过滤近黑/近白/低饱和/近透明。HSL 转换、_hue 取模、_byte clamp 均可防越界。
问题：无实质 bug——失败降级完备且有日志，符合「不静默吞」。唯一小瑕疵：fallback 为紫色，而实际 UI 主题 seed 是绿色(#1DB954)，降级色与现行品牌色**不一致**，接回后取色失败会突兀变紫。
建议：接回时把 ColorSeed.fallback 与品牌/主题 seed 统一（改绿或让主题统一取该紫）。
76 合规：不涉及。

---

## [C3] · lib/core/audio/notification_gateway.dart:102-117 + lib/session/playback_session.dart:220-224,253-257 · P1 · 通知栏/历史 bug 已修
证据：本层**确实实现** updateMetadata，向 mediaItem.add(MediaItem(id,title,artist,artUri,duration))；rg 全仓确认 playback_session.dart 有 2 处真实调用（起播主链 :253、MV 音频兜底 :220），artUri 来自 cur.cover。历史 bug「audio_service.updateMetadata 零调用」在 L6 session 侧**已修复**，非本层遗留。
问题：历史零调用缺陷不在本层，通知栏元数据写入能力齐备。但存在两个真实缺陷（见下条）。
建议：无需补 updateMetadata 本身。
76 合规：涉及。通知经 bridge_core 导出、session 经桥调用，方向正确。

## [C3] · lib/core/audio/notification_gateway.dart:149-167 + lib/session/playback_session.dart:109-119 · P1 · 通知栏/初始化竞态
证据：initNotification 为 async，session 端用 `.then((h)=>_notification=h)` 异步赋值；起播路径 `_notification?.updateMetadata(...)`（:220,:253）用空安全调用。用户「起播瞬间」_notification 可能仍为 null → 首曲的歌名/封面/时长**静默不推**，要等下次切歌才更新（因无重试）。
问题：初始化竞态导致首播通知栏元数据丢失，用户感知「通知栏歌名不对/不显示」。两处 updateMetadata 调用未 await（fire-and-forget）且无 catchError，异常虽在函数内 try/catch 吞掉但 session 侧无兜底重试。
建议：把首曲元数据缓存，待 initNotification 完成后补推一次；或将 start 等待 handler ready 后再更新。
76 合规：不涉及（本层无越级）；竞态属 L6 编排，仅记录。

## [C3] · lib/core/audio/notification_gateway.dart:29,32,71-96 · P2 · 通知栏/拖动进度失效
证据：NotificationControls 定义 onSeek: Function(int ms)?，但 rg 全仓 onSeek 仅在 notification_gateway.dart 自身出现 2 次（定义处），session bind 时只传 `NotificationControls(onNext: next, onPrev: prev)`（playback_session.dart:112），**未传 onSeek**；虽然 handler 声明 `systemActions: {MediaAction.seek}` 且 override 了 seek()，但 seek() 直接 `_player.seek()` 不走 _controls。
问题：通知栏系统级 seek（拖动进度条）能改 just_audio 播放位置，但**不回写 session 的播放状态**（position reducer），可能出现引擎位置与 UI/session 状态不同步。onSeek 回调形同虚设（死字段）。
建议：session bind 时补 onSeek 回调 `NotificationControls(onNext, onPrev, onSeek: seekTo)` 并在 handler.seek 优先转发 _controls.onSeek，再回退 _player.seek。
76 合规：不涉及。

## [C3] · lib/core/audio/notification_gateway.dart:35,149-167 · P2 · 通知栏/控制回调不全
证据：bind() 写入 controls 仅 skipToPrevious/play/pause/skipToNext；play()/pause()/stop() 直接调 `_player.*`，不经过 session，故用户点通知栏播放/暂停后 session 状态（playing/paused reducer）是否同步**取决于** audio_gateway 的 playerStateStream→onEvent 回传（audio_gateway.dart:71-88 确有该流）。stop() 无对应 session 事件语义。
问题：播放/暂停靠引擎状态流间接同步（可行但绕），无 skipToNext/prev 的位置重置明确契约；整体可用但状态一致性依赖多跳。
建议：可考虑 play/pause 也走 _controls 显式回调以缩短状态同步链，非阻塞。
76 合规：不涉及。

---

## [C3] · lib/core/storage/settings_store.dart:41-71,76-86 · P1 · 设置/崩溃恢复
证据：`_flush()` 顺序为 `tmp.writeAsStringSync(jsonEncode(_cache), flush:true)` → `if(file.existsSync()) file.deleteSync()` → `tmp.renameSync(file.path)`。**先删目标再改名**，存在真实崩溃窗口：进程在 delete 之后、rename 之前被杀 → settings.json 消失、只剩 .part；下次 `_ensureLoaded()` 因 `file.existsSync()==false` 按空表继续，用户所有设置（含 ui.locale 语言偏好、倍速等）**静默全丢**。注释自称「原子落盘」名不副实（同文件 :40）。
问题：崩溃/强杀后设置可能整体丢失且无法从 .part 恢复，用户痛点「设置用不了/每次重设」的底层成因之一。
建议：改用 rename 直接覆盖（Dart `renameSync` 在目标存在时多数平台为原子替换），去掉显式 delete；或启动检测 `.part` 存在且正式文件缺失时自动回滚 .part。
76 合规：不涉及（层内 IO，方向正确）。

## [C3] · lib/core/storage/download_store.dart:91-106,196-225 · P1 · 下载/崩溃恢复 + 任务状态持久化
证据：`saveIndex()` 同为「写 .part → delete index.json → renameSync」，同样崩溃窗口（:100-102）；更关键：`commitDownload()` 仅在**下载完整落盘后**才 `upsert` 一条 `complete:true` 的记录（:205-216），全仓 download_store **没有任何 in-progress/paused/failed 任务状态字段或写入**（DownloadRecord 仅 complete 布尔，无进度/状态枚举）。中途被杀 → 只有孤立 `.part` 数据文件，索引无记录、无残留清理/续传入口。
问题：下载任务状态未持久化，崩溃后续传/失败提示无从谈起；用户「下载用不了」在 L4 表现为：进度/失败态完全不落库，只剩成功记录。索引本身还有丢记录窗口。
建议：saveIndex 去 delete 直接 rename；DownloadRecord 增 status/progress 并在任务生命周期各节点 upsert；启动时扫描孤立 .part 清理或标记可续传（属 L5 download_logic 编排，L4 提供原语）。
76 合规：不涉及。

## [C3] · lib/core/storage/resource_cache.dart:60-65,296-320 · P1 · 缓存/7 天 TTL 陈旧内容
证据：全局默认 `ttl = const Duration(days: 7)`（:62）；`getString()` 仅按 `createdAt + ttlMs` 判过期（:303-310）；per-entry ttl 虽有预埋（:308、:360 `if(ttl != null) 'ttlMs'`），但文件头注释明写「接线点在 KugouClient/Endpoint（线A范围）」——本层调用方**未传 ttl**，故所有条目一律 7 天。且 createdAt 写死在 put 时刻，无按内容版本/Etag 失效机制。
问题：酷狗榜单/歌单等内容 7 天内变更，用户「改了内容还是旧的」在缓存层成立——到期前一律命中旧数据，即便服务端已更新。无主动 invalidate 单键 API（只有整条目过期后 `_dropAndPersist`）。
建议：把 ttl 接线到 Endpoint 分级（榜单/推荐短 TTL，静态资源长 TTL）；给 CacheService 增按 key 主动失效接口供换号/编辑后清缓存；或在 KugouClient 用服务端时间戳/Etag 做条件失效。
76 合规：不涉及。

## [C3] · lib/core/cache/cache_service.dart:110-126 · P2 · 缓存/失败降级空 Map（历史「空结果固化」需上层确认）
证据：`get()` 失败 `return <String,dynamic>{}`，仅门面自身计数，不写缓存；本层**不固化空结果**。缓存实际在 KugouClient.request（A2 范围）。rg 确认本文件不持久化任何数据。
问题：历史 bug「空结果固化」不在本层（属 A2 KugouClient 磁盘缓存写入路径）。本层返回空 Map 的降级语义会让上层把「失败」误当「空数据」渲染空态，但不能确认它被缓存。
建议：主会话在 A2/B2 复核 KugouClient 是否把空结果 put 进 ResourceCache；本层建议区分「失败」与「空结果」（如返回 sealed result）以免 UI 三态错乱。stats 恒 0 已诚实标注 source，非缺陷。
76 合规：不涉及（单一真源、不造第二缓存表，符合规范）。

---

## [C3] · lib/core/algorithms/qr_codec.dart:1-350 · P2 · QR/YKG 扫码导入能力盘点
证据：文件为**纯 QR 编码器**（encodeQr:63，版本1-4/Byte模式/EC L·M/mask0），rg 全仓调用者仅 bridge_core.dart:46 的 `show QrMatrix,QrException,encodeQr` 导出，**无任何实际消费方**。文件末 :348-350 仅有一行悬空注释「黑白模块绘制：quiet zone 4 模块，可选圆角模块」却**没有任何 Painter 实现**（无 QrPainter 类/函数）→ 只有矩阵数据，L7 无法直接绘制成图。无 QR **解码/扫描**能力（无 camera/扫码依赖）。
问题：主会话设计稿 §9「YKG 扫码导入链接」待定项——若指「扫描二维码导入」则需 decoder，本层**不具备**；若指「导出二维码供对方扫」，编码器能力现成但缺 Painter 且未接线。容量上限 V4-L 78B / V4-M 62B；酷狗扫码 URL ≈45B 可容纳，但若 YKG 载荷含 base64(cookie)+md5 盐值，通常 >78B，**会抛 QrException**（:72-74），能力不足。
建议：主会话先定 §9 场景方向：导入侧另引入成熟扫码库（mobile_scanner 等，遵循 76§9 成熟库优先）；导出侧补 QrPainter 实现并评估载荷长度，必要时提高版本/纠错或改短链。当前编码器可复用为「导出」原语，非死代码但零接线。
76 合规：涉及（能力盘点）。仅经 bridge_core 导出，无越级；但「QR 编码器归 L4 纯算法」合理。

## [C3] · lib/core/memory/cache_keys.dart:1-245 · P2 · 缓存键/换号串号风险（正面为主）
证据：buildKey 键格式 `json:<ns>:u=<userid>:<path>:<sortedQuery>:v<schemaVer>`，userid 作为独立段（:82）；prefixOf(ns,userid) 与 namespacePrefixOf(ns) 提供按用户/按命名空间失效；_canonical 对 Map 按键 ASCII 排序、组件编码避免 ':' '/' 撞段。parseKey 用 split(':') 稳定性依赖 query 已编码（注释成立）。
问题：无用户痛点级缺陷。`sortedQuery` 对 null 值渲染为空串（:67），可能使「参数缺失」与「参数为空串」产生同键，属 C2 边缘项。对用户体验的正面价值：换号时按 u= 前缀失效可防串号数据。
建议：保持。主会话换号链路应调用 invalidatePrefix(prefixOf(ns,uid)) 而非全清，避免误清他人缓存。
76 合规：不涉及。

## [C3] · lib/core/memory/lru_cache.dart:1-424 · P2 · 内存缓存/线程安全（正面）
证据：LruCache 用 Map+LinkedHashSet 维护 LRU 序，get/put 移尾部、超容量从头部淘汰并触发 onEvict；invalidatePrefix 配合 cache_keys 做前缀失效；所有公开方法 try/catch+Log。纯内存、无 IO。
问题：无用户痛点级缺陷。全仓 rg lru_cache 消费方未在本次范围（属 L5/L6），本层实现健壮。Dart 单线程事件循环下无并发问题。
建议：保持。
76 合规：不涉及。

---

## [C3] · lib/core/database/db.dart:75-108 · P2 · 数据库/清库保留设置（正面，历史 bug 已修）
证据：deleteAll() 显式跳过 `settings.json`（:98 `if(name=='settings.json') continue`）并只删 `.isar`/`.isar.lock`，注释记录旧实现 `delete(recursive:true)` 会连 settings.json 一起删（清库/登出丢全部用户设置）已修。open/close 幂等、失败 rethrow 不静默。
问题：无痛点缺陷；历史「清库丢设置」已在此层修复。
建议：保持。
76 合规：不涉及。

## [C3] · lib/core/database/entities.dart:97-146 · P2 · YKG 登录/凭据落盘（设计输入）
证据：AccountRecord 含 `token / mid / dfid / cookieBlob / vipType / isActive`（:110-131），均为**明文 String 存 Isar**，无加密字段；cookieBlob 由 L5 account_logic.dart:58 序列化 session.cookies 写入。全仓 crypto 原语见 bridge_core.dart:141 `Md5/md5Hex`（core/net/signing.dart）。
问题：对照 YKG「base64(cookie)+md5 加盐密码、导出、输密码解锁」需求——L4 已具备 ① cookie 持久化字段 ② md5Hex 原语，能力可复用；但凭据明文落盘，且**无 base64 编解码 / 加盐派生 / 密码解锁的原语**（signing 的 md5 用于签名非 KDF）。导出解锁功能在 L4 无现成支撑。
建议：主会话设计 YKG 时：密码学设计输入——用 `PasswordHmac/PBKDF2`（非裸 md5）从用户密码派生密钥，base64(cookie+token) 后 HMAC 校验，导出物含 salt+密文+校验和；L4 增 crypto 纯算法模块，密钥不落盘。此项属设计输入不实现。
76 合规：不涉及（实体字段归属 L4 正确）。

## [C3] · lib/core/database/dao.dart:288-320 · P2 · 播放历史/语义（轻微）
证据：HistoryDao.record 按 hash 去重，同 hash 只保留一条（更新 playedAt + 累加 durationPlayedMs）；recent(limit) 从全表取出内存排序后 take。:288-291 方法注释自相矛盾/语句断裂（「记录一次播放：同 hash 去重——更新既有条目的 playedAt 并累加 durationPlayedMs 与 PlayHistoryEntry 无计数字段…」）。
问题：用户「最近播放」列表每首歌只出现一条（去重符合设计），但无法看某首歌的多次播放时间线；属产品语义非 bug。注释质量差（C3 文案角度的源码注释瑕疵）。
建议：如产品需要「历史时间线」则改为不去重；否则仅修正注释。
76 合规：不涉及。

---

## 动态取色链结论
- **L4 算法可用**：extractDominant（RGBA8888→32级色桶直方图→主色，过滤近黑/近白/低饱和/近透明）与 fromSeed（自实现 HSL 四色调色板）实现完整，失败降级返回品牌紫 #7C4DFF 且全分支 Log 留痕，健壮性合格（P2 唯瑕疵：fallback 紫与现行主题 seed 绿不一致）。
- **全链路断开**：rg 确认 extractDominant/fromSeed 唯一「调用」是 bridge_core.dart:48 的 `show` 导出，无任何实际消费者（原 cover_color_bridge.dart 已删）。真实主题是 tokens.dart:70 的 `ColorScheme.fromSeed(seedColor: #1DB954)` + tn_theme.dart:10 硬编码绿。与 M3_BASELINE「取色链断、无 UI 消费者」**结论一致**。
- **结论**：用户在设置里换封面/主题不会有任何动态取色效果，痛点「UI 不舒服/动态取色」在 L4 无解；缺的是 L6 theme_controller 接线 + L7 消费 ColorScheme。即便接回，本文件 fromSeed 仅 4 角色非完整 tonal palette，建议改用 Flutter 原生 ColorScheme.fromSeed 生成全套角色。

## 通知栏结论
- **历史 bug「updateMetadata 零调用」不在本层、且已在 L6 修复**：notification_gateway.dart:102 完整实现 updateMetadata→mediaItem.add(MediaItem(title/artist/artUri/duration))；playback_session.dart:220、253 有 2 处真实调用。通知栏能更新歌名/歌手/封面/时长。
- **仍有 3 个真实缺口**：① 初始化竞态——initNotification 异步赋值 `_notification`，首曲起播若 handler 未 ready 则元数据静默丢失，无补推；② onSeek 是死字段——session bind 只传 onNext/onPrev，未传 onSeek，通知栏拖动进度不回写 session 状态；③ play/pause/seek 直接调 _player，状态同步依赖 audio_gateway 的 playerStateStream 多跳回传（可行但绕）。
- **歌名占位**：`title: cur.name.isEmpty ? cur.hash : cur.name`——歌名为空时把技术 hash 推到通知栏给用户看，属文案占位漏出（见 i18n 核对）。

## i18n 常量表核对
证据：strings.dart `_kCatalog` 10 语（zh/zh_Hant/en/ja/ko/es/fr/de/pt/ru）× 20 键；10 个 app_*.arb 各 20 个真实可译键（app_zh.arb 多出的第 21 项 `description` 实为 `@appTitle.description` 元数据属性，非可译 key，en/zh_Hant 缺该元数据**不构成文案缺口**）。
- **键一致性：0 缺口**——strings.dart 20 键与所有 ARB 20 键逐一对齐；10 语间键完全同集；tr() 有 zh 兜底 + keyName 兜底，无占位/空值/旧文案。normalize() 对 zh-Hant/TW/HK/MO 归一正确。
- **缺口在「表之外」（L4 未覆盖的面向用户串），共 3 类**：
  1. **YKG 登录文案缺失**：20 键无任何登录方式/扫码导入/导出/输密码解锁相关 key（设计稿新增登录方式无文案支撑）。
  2. **错误/空态文案缺失**：无错误/空态/加载/失败类 key；playback_session.dart:234 把硬编码中文 `'播放源不可播或需登录'` 直接塞进 ErrorAction 面向用户显示，未走 i18n。
  3. **通知栏歌名占位**：cur.name 为空时用 hash 当用户可见歌名（:221/:255），非本地化占位策略。
- 结论：L4 常量表本身干净且一致；「相关文案也没改」的痛点缺口在 L5/L6/L7 硬编码中文与表容量不足（需补 YKG/错误/空态键），A7 批 + B7 批跟进。audio_gateway/notification_gateway 内中文仅注释与 Log 标签，**无面向用户的硬编码中文串**（已 rg 核实）。

---

## 本视角结论
1. 动态取色链：L4 算法完整健壮但**零消费者、全链断**，与 M3_BASELINE 一致；痛点在 L6/L7 接线缺失，非 L4。
2. 通知栏：updateMetadata 已实现且 L6 已调用，历史「零调用」bug 已修；残留初始化竞态（首曲元数据丢失）、onSeek 死字段、状态多跳同步 3 个 P1/P2 缺口。
3. 下载/设置存储：settings.json 与 index.json 均「先删后 rename」有崩溃丢数据窗口；下载任务无 in-progress/failed 持久化、崩溃后无续传/清理，是「下载用不了」的底层成因之一。
4. 资源缓存：默认 7 天 TTL 且 per-entry TTL 未接线，内容变更后 7 天内仍返回旧数据，对应「改了内容还是旧的」。cache_service 空结果固化不在本层（属 A2 KugouClient）。
5. i18n：strings.dart 与 10 个 ARB 键完全一致（0 缺口）；缺口在表容量——YKG/错误/空态文案缺失 + L6 硬编码中文 + 通知歌名 hash 占位。
6. QR：纯编码器（v1-4/Byte/EC L·M），能力现成但**零接线、无 Painter、无解码**；服务 YKG「扫码导入」需另配 decoder，导出场景需补 Painter 并评估 78B 容量（base64 cookie 载荷可能超限）。
7. 正面项：settings 清库保留、db deleteAll 保 settings.json、StoragePaths fail-fast、cache_keys 换号前缀失效、LruCache/ResourceCache 原子写 + 串行链，均为已修/健壮实现。

## 未覆盖
- L5/L6/L7 的上游消费链（theme_controller、download_logic、KugouClient 缓存写入、surface 文案显示）不属 A4 范围，仅据 rg 证据点名，未逐文件审。
- lib/l10n/README.md 与 gen-l10n CI 脚本未读（文案键校验机制仅依据 strings.dart 头注释与 ARB 实测）。
- qr_codec.dart:276-346 之后无 Painter 实现（文件在 :350 注释处结束），已确认但未见其它文件补 painter（全仓 rg 已核）。
- 未运行任何 dart/analyze/test（按纪律禁止），所有结论为静态研读 + rg 取证，QR 编码正确性/HSL 数值未做运行时验证。

## 76 合规小结
- 本批 15 文件层级归属正确：均只依赖 dart:* / isar / audio_service / just_audio / bridge_kernel / 同域文件，无 import logic/surface/net/bridge 以外跨层文件，无影子桥、无反向依赖。
- color_extract / notification_gateway / qr_codec / strings 均经 bridge_core.dart 统一 `show` 导出供上层消费，符合「跨层经桥」铁律。
- 动态取色断链、通知竞态、L6 硬编码中文均为 **L6/L7 职责缺口**，不构成本批（L4）76 违规；已单列供主会话跨层追踪。
- 唯一需注意：strings.dart（L4）经 bridge_core 导出 KeyValueSettings/StoragePaths 并直接读写设置（saveLocale/loadLocale）——属 L4 内同层协作，合法。
- 单文件行数：全部 ≤500 行（最大 resource_cache 471、dao 431），符合 ≤1500 行约束。
- MD3/76 交叉：color_extract 调色板非完整 tonal palette 属 MD3 Color tokens/Theming 偏差（已在动态取色结论记录），但算法层非 UI 层，不按 surface 十类打分。
