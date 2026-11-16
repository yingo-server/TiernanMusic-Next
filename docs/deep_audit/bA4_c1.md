# A4 批 · C1 架构合规视角 · 深度审查报告

> 审查对象：L4 core 非网络层 15 文件（database / storage / cache / audio / algorithms / l10n / memory）
> 视角：C1 架构合规（76 原则逐条 / 依赖图 / 六桥 / 层职责 / 缓存⊃预读 / DB 归属 / 成熟库边界 / 1500 行 / 死代码占位）
> 工具纪律：全程只读（file_read / ls / rg / wc），唯一写=本文件 append。

---

## 前置事实（只读核）

证据（wc -l，15 文件）：dao 431 / db 113 / entities 146 / download_store 255 / paths 91 / resource_cache 471 / settings_store 196 / cache_service 173 / audio_gateway 202 / notification_gateway 169 / color_extract 240 / qr_codec 350 / strings 327 / cache_keys 245 / lru_cache 424，合计 3833 行。
问题：无。
建议：无。
76 合规：符合第 5 条（单文件均 < 1500 行，**无需拆分**；最大值 resource_cache.dart=471）。

## [2026-11-16 23:20:36] · C1 · lib/core（全局 import 依赖图） · P2 · 依赖方向 / 桥回环
证据：15 文件 import 扫描结果：
- 15/15 全部 import `../../bridges/bridge_kernel.dart`（10 处 `show Log`，resource_cache 用 `as bk`）。
- `strings.dart:7` import `../../bridges/bridge_core.dart` show KeyValueSettings, StoragePaths。
- cache_service.dart:30-31 import `../net/endpoint_registry.dart`、`../net/kugou_client.dart`（同层跨子域，L4 内）。
- 出现 database(dao/db/entities)、storage(download_store/settings_store→paths)、audio(notification→just_audio)、同层内互相引用；无任何 import logic/ / session/ / surface/ / flutter。
问题：全部反向依赖（指向 L5/L6/L7）为零；但存在两处需关注：① core 文件直接 import `bridges/bridge_kernel`（L3↔L4 桥）取 Log——按 76 §1 桥相邻关系 bridge_core(L3↔L4)、bridge_kernel(L2↔L3)，L4 直接依赖 bridge_kernel 属**层级相邻疑似错位**（详见后文 C1 条目）；② strings.dart import bridge_core，而 bridge_core 又 export strings.dart，形成"core 文件 → bridge_core → 自身"的回环引用。
建议：① 统一 Log 获取路径（若项目约定 L4 可取 kernel Log，则在契约中显式豁免并文档化；否则应经 bridge_core 或独立 Log 门面）；② strings.dart 移除对 bridge_core 的 import，KeyValueSettings/StoragePaths 由调用方注入，避免 core↔bridge 循环。
76 合规：待定（第 1/4 条依赖方向本身未违反——未反向到上层；但 bridge_kernel 用于 L4 属桥相邻错位，需主会话裁定）。

---
## [2026-11-16 23:21:22] · C1 · lib/core/storage/{paths,download_store,settings_store,resource_cache}.dart · P1 · 层职责 / 缓存入口分散
证据：storage 四文件均纯 dart:io/convert/async + bridge_kernel Log，零 Flutter/BuildContext/Widget（合规）。但：
- resource_cache.dart 顶层注释「L2 磁盘缓存 ResourceCache」定义完整磁盘缓存（getString/putString/getJson/putJson/cleanup/stats + 内存 _index + LRU/TTL + 单飞写链），落在 `storage/` 而非契约 §3 指定的唯一缓存域 `core/cache/`。
- cache_service.dart:7 注释自称「底层唯一执行者 = KugouClient.request 自带的 ResourceCache(L2 磁盘)」，即磁盘缓存实际由 KugouClient(net/) 持有，CacheService 只是策略门面。
- 于是 L4 内同时存在三处缓存实现：storage/ResourceCache（磁盘）、memory/LruCache（内存）、net/KugouClient._cache（磁盘，未走 ResourceCache 文件？需 A2 交叉）。
问题：76 §3「一个域 core/cache，CacheService 唯一入口」与现状不符——磁盘缓存实现体在 storage/、网络缓存在 net/，cache/ 仅一层无状态门面；缓存职责在 L4 内分散三处。
建议：明确「L2 磁盘缓存实现体归位 core/cache/」，或由主会话裁定契约补充 ResourceCache 属 storage 的持久化组件、CacheService 为跨子域门面；统一对上层只暴露 CacheService。
76 合规：违反第 8 条精神（缓存应集中）/ §3「一个域」；未违反依赖方向。

## [2026-11-16 23:21:22] · C1 · lib/core/storage/paths.dart:19-31, download_store.dart:53, settings_store.dart:19-33 · P2 · 单例装配 / 反向依赖隐患
证据：StoragePaths 用静态 `_instance` + `init()` 注入（paths.dart:19-31），注释写「root 来自 L2 bootloader 装配」「L5 logic 装配时注入」；download_store.dart:53 `DownloadStore(StoragePaths paths)` 构造注入；settings_store.dart:19-33 用静态 `_sharedByPath` 表做进程内共享单例。
问题：注入式设计本身合规（无反向 import），但 core 静态可变单例（StoragePaths._instance / KeyValueSettings._sharedByPath）使 L4 持有全局可变状态，测试隔离/多实例困难；注释提及"L5 装配"意味着上层逻辑直接触摸 core 单例——是否经 bridge_core 门面需 A6/A5 交叉确认。
建议：确认上层仅经 bridge_core 暴露的 StoragePaths/KeyValueSettings 门面访问；静态可变单例改为 bootloader 显式持有并注入。
76 合规：符合第 4 条（无反向 import）；第 1 条门面访问待交叉。

## [2026-11-16 23:21:22] · C1 · lib/core/cache/cache_service.dart:1-173 · P2 · 缓存⊃预读契约落实（正面）
证据：cache_service.dart:3-8 注释明示"缓存⊃预读深度融合"；prefetch()(128-148) 仅构造请求并调用本类 get()（与正常读同路径），无独立队列/定时器；无 PrefetchEngine 类（全仓 rg 仅 docs 历史提及，lib/ 零命中）；session/bootstrap.dart:193-197 由 L6 决定预测键并调用 cacheService.prefetch（执行权在 L4）；bridge_core.dart:51 正确导出 CacheService/CacheOrigin。
问题：无违规。契约契合度高。仅统计 hits/writes/evictions 恒 0（注释明示未接线、非伪造），属可观测性缺口非架构违规。
建议：线A在 KugouClient 暴露只读 stats getter 供门面接线（已在注释中规划）。
76 合规：符合 §3「缓存⊃预读」「禁止 PrefetchEngine 独立调度器」；符合第 8 条（预读触发在 session 决定、执行在 core）。

---
## [2026-11-16 23:22:49] · C1 · lib/core/audio/{audio_gateway,notification_gateway}.dart · P2 · 成熟库边界 / 层职责（正面）
证据：audio_gateway.dart:7 `import package:just_audio`，仅做 IO 适配（play/pause/seek/volume/speed → AudioPlayer），用 onEvent 回调把 AudioEvent 纯数据交 session；notification_gateway.dart:6-7 `import package:audio_service + package:just_audio`，BaseAudioHandler 只做 media control 事件→纯回调（NotificationControls），无队列/无 Widget；两者零 flutter/material、零 BuildContext。
问题：无违规，成熟库边界正确（符合 §0-9）。仅一处文档残留：audio_gateway.dart 注释与 76 §4 用词不一致——契约写「L7 session/playback_session.dart」，实际文件在 lib/session/（L6），属文档层号混淆非代码问题。
建议：统一契约与注释的层号表述（session=L6）。
76 合规：符合第 9 条（just_audio/audio_service）；符合 L4「音频引擎封装」职责；符合 §4「引擎封装属 core/audio 纯 IO 适配」。

## [2026-11-16 23:22:49] · C1 · lib/core/database/db.dart / dao.dart / entities.dart · P1 · DB 归属与 database_opener 错位呼应
证据：db.dart/dao.dart/entities.dart 均在 lib/core/database/，纯 isar + kernel Log，零 net/logic/surface/flutter import，符合 L4。但 `lib/core/net/database_opener.dart:6-18`（A2 范围）才是 bootloader 实际调用的 DB 打开入口（bootloader.dart:109 `.openDatabase(paths.db().path)`，经 bridge_core.dart:69 导出），而 db.dart 内 `DatabaseService.open()` 反成次要路径。
问题：DB 归属分裂——正统 DB 实现在 core/database（本批，合规），但对外"打开数据库"门面函数 openDatabase() 错放在 core/net/（A2 已发现），与本批形成呼应：net/ 目录混入 database 职责，违反 L4 子域边界（net 只应做网络）。
建议：将 database_opener.dart 从 core/net/ 迁至 core/database/（或并入 db.dart），bridge_core 导出路径同步改为 core/database；bootloader 调用不变。
76 合规：本批三文件符合第 4 条与 L4 归属；net/ 里 openDatabase 违反子域职责（属 A2 交叉，本视角仅呼应）。

## [2026-11-16 23:22:49] · C1 · lib/core/algorithms/color_extract.dart:8-10 · P2 · 陈旧注释 / 死代码
证据：color_extract.dart:8 注释写「仅本 surface 文件 import package:flutter/material.dart（取 Color 类型）；Log 经 bridge_logic 取得」，但实际代码（第 11-13 行）只 import dart:math + bridge_kernel，返回纯 int ARGB，无 flutter、无 bridge_logic。文件头另注「extractDominant/fromSeed 当前未被任何 UI 消费方调用（原 cover_color_bridge 已删除）」。全仓 rg 确认：encodeQr/extractDominant/fromSeed 除 bridge_core 导出外零业务调用。
问题：① 注释与实现严重不符（声称 flutter/bridge_logic 依赖，实为纯 Dart + bridge_kernel），误导后续审查；② QR/取色算法为"能力保留"型公开符号，当前零消费者（死代码/占位），但属契约 §5 明确要求下沉的资产，非应删。
建议：① 修正 color_extract.dart 头部注释为真实依赖（纯 dart:math + bridge_kernel）；② 保留算法（§5 资产），在 docs 标注"待 B6/B1 接线"，不误删。
76 合规：注释违反诚实性但不违反具体条款；实际代码符合 L4 纯算法职责与第 9 条（合理自研：QR/取色无成熟库强制要求）。

## [2026-11-16 23:22:49] · C1 · lib/core/algorithms/qr_codec.dart:347-350 · P2 · 残留桩注释
证据：qr_codec.dart 末尾（348-350 行）留 `// ── Painter ──` 与孤立 doc 注释「黑白模块绘制：quiet zone 4 模块，可选圆角模块。」，其后无任何实现——Painter 按 §5 应留 L6/独立 UI 模型，此处只剩悬空注释。
问题：死代码残留（悬空 Painter doc 注释），无实际影响但属未完成占位。
建议：删除该悬空注释块，或注明"Painter 见 L6/独立 UI 模型"并移走。
76 合规：符合 §5「CustomPainter 渲染留 L6」；仅残留注释需清理，不违反条款。

## [2026-11-16 23:22:49] · C1 · lib/core/l10n/strings.dart:7,259-275 · P2 · core↔bridge 循环依赖隐患
证据：strings.dart:7 import `bridge_core.dart` show KeyValueSettings, StoragePaths；而 bridge_core.dart:49 `export core/l10n/strings.dart show TnStrings`。strings.dart:261/271 用 `KeyValueSettings.shared(StoragePaths.I)` 存/读 locale 到 settings.json。形成 strings → bridge_core → strings 的导出回环（Dart 允许导出环，但架构上是 core 反向依赖上层桥门面取同层 storage 能力）。
问题：L4 l10n 组件为读取 KV 设置而 import bridge_core（本应是上层经 bridge_core 访问 core），属依赖方向语义倒置；直接 import 同层 `../storage/settings_store.dart` + `../storage/paths.dart` 更合规，或由上层注入 locale 读写回调。
建议：strings.dart 改直连同层 storage（../storage/settings_store.dart、paths.dart），去掉对 bridge_core 的 import，消除回环。
76 合规：违反第 1/4 条精神（同层能力应同层引用，不应绕道上层桥）；虽未真正反向到 L5/L6，但语义上 core→bridge_core 方向倒置。

---

## 本视角结论
1. 层职责：15 文件中 14 个纯逻辑（零 Flutter/BuildContext/Widget/反向依赖），唯一允许外的 audio_service/just_audio 在 audio/ 属契约许可的成熟库适配。L4 职责整体合规。
2. 依赖方向：零 import logic/session/surface，零影子桥。但存在两处语义倒置——strings.dart→bridge_core（且 bridge_core 又导出 strings，回环）、以及全部 15 文件统一 import bridge_kernel 取 Log（bridge_kernel 按契约是 L2↔L3 桥，L4 取 Log 属桥相邻错位，需主会话裁定是否豁免）。
3. 缓存⊃预读：落实良好。CacheService 为唯一策略门面，prefetch() 与 get() 同路径，无 PrefetchEngine 独立调度器残留（lib 零命中），session 决定预测键、core 执行写入。唯一结构性争议：磁盘缓存实现体 ResourceCache 在 storage/、网络缓存在 net/，cache/ 仅门面，与 §3「一个域」字面不符（P1）。
4. DB 归属：db/dao/entities 三文件正确在 core/database（合规）；但对外打开门面 openDatabase 错放 net/（A2 发现），两批呼应，建议迁回 core/database。
5. 桥门面：bridge_core 已导出本批主要公开符号（StoragePaths/KeyValueSettings/ResourceCache/DownloadStore/各 DAO/entities/LruCache/cache_keys/QR/取色/TnStrings/CacheService/audio 网关），导出完整；无"该导出未导出"的明显缺口。导出多为白名单 show，合规。
6. 成熟库边界：audio 用 just_audio/audio_service、DB 用 isar，符合第 9 条；LRU/QR/取色为合理自研（无强制成熟库），但 QR/取色当前零消费者属"能力保留"型死代码，按 §5 应保留待接线。
7. 1500 行门禁：15 文件全部远低于 1500（最大 resource_cache=471），无超限，无需拆分。
8. 死代码/占位：qr_codec 末尾悬空 Painter 注释需清理；color_extract 头部注释与实现严重不符需修正；无 TODO/FIXME（唯 QR "格式信息占位"为算法正常术语，非 TODO）。

## 未覆盖
- 未验证各公开方法在 C2 视角的正确性（空安全/竞态/异常语义），本视角只审架构合规。
- 未逐文件核对 bridge_core 全部导出符号是否与调用方一一对应（只确认主要符号已导出）；A5/A6 交叉可补。
- 未判定"15 文件统一 import bridge_kernel 取 Log"是否在项目已有豁免清单内（契约 §0 第 2 条要求桥 try/catch+Log，但 L4 直取 kernel Log 的合法性需主会话按全局裁定）。
- 未审查 lib/core/net/ 内部（属 A2/A3 范围），仅就 database_opener 与本批呼应点做定位。
- 未跑任何分析器/测试/门禁（工具纪律禁止），"死代码"结论基于 rg 静态引用计数，非编译器结论。

## 76 合规小结
- 符合：第 5 条（1500 行，全部达标）；第 9 条（成熟库 just_audio/audio_service/isar）；§4（引擎封装在 core/audio 纯 IO 适配）；§5（QR/取色/i18n 常量已下沉 core）；§3 精神（缓存⊃预读、无独立 PrefetchEngine）；L4 层职责（14/15 文件纯逻辑，零 Flutter/Widget/BuildContext）；零反向依赖 logic/session/surface；零影子桥。
- 违反/存疑：第 1/4 条精神（strings.dart→bridge_core 回环，core 绕道上层桥取同层能力）；桥相邻错位（15 文件 import bridge_kernel 取 Log，需裁定豁免）；§3 字面（缓存实现体分散 storage/net，cache/ 仅门面）；DB 打开门面错放 net/（A2 呼应）；子域边界（net/ 混入 database_opener）。
- 总体：本批架构质量较高，无 P0；主要问题为 P1×2（缓存域分散、DB opener 错位）+ 若干 P2（注释失真、bridge 回环、悬空桩、桥相邻 Log）。建议主会话优先处理 P1 两项与 strings.dart 回环。
