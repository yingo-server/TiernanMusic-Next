# A2 批 · C1 架构合规视角 · 深度审查报告

> 审查时间：2026-11-16（Asia/Shanghai）
> 视角：C1 架构合规（76 原则逐条核 / 依赖图 / 端点分文件 / 1500 行 / 桥门面 / 死代码）
> 范围：lib/core/net/ 根文件 12 个 + endpoints/models.dart、models_util.dart
> 只读扩展：lib/bridges/bridge_core.dart（门面导出）、core/net/endpoints/ 全部文件的 import 头（依赖方向）
> 纪律：全程只读（file_read / ls / rg --files / rg / wc），唯一写为本文件 append。

---

## 基线事实（wc -l，只读）

| 文件 | 行数 | 1500 门禁 |
|---|---|---|
| cover_color.dart | 56 | 符合 |
| crypto_aes.dart | 786 | 符合（本批最大，需关注但不超限）|
| crypto_bigint.dart | 146 | 符合 |
| crypto_extra.dart | 7 | 符合 |
| crypto_rsa.dart | 179 | 符合 |
| crypto_rsa_raw.dart | 86 | 符合 |
| database_opener.dart | 24 | 符合 |
| endpoint_registry.dart | 503 | 符合 |
| inflight.dart | 112 | 符合 |
| kugou_client.dart | 297 | 符合 |
| network_phase.dart | 115 | 符合 |
| signing.dart | 266 | 符合 |
| endpoints/models.dart | 9 | 符合 |
| endpoints/models_util.dart | 83 | 符合 |
| （扩展）bridge_core.dart | 178 | 符合 |

结论：无任一文件超过 1500 行，§0 第 5 条行数门禁全部符合。

---

---

## 详细发现

## C1 · bridge_core.dart:15,26,39,53,71,87,104,105,119,121,131,144,146,156,163,165,167,177 · P2 · 桥门面卫生（重复 export）
证据：bridge_core.dart 中同一目标被 export 两次：
- `models.dart`：L15 `show SongBrief,...` 与 L131 `show PlayResult, PrivilegeItem,...`
- `kugou_client.dart`：L39 `show KugouClient,KugouSession,KugouApiException,EndpointRegistry` 与 L53 `show Endpoint, EndpointRegistry`（EndpointRegistry 重复）
- `comment_endpoints.dart`：L71 `show CommentItem,CommentPage` 与 L177 `show getMusicComments,getCommentFloor,getCommentCount`（文件自身在 L177 注释中已承认与 bridge_logic 双桥出口重复符号）
- `mv_endpoints.dart` L26/L163、`album_endpoints.dart` L104/L144、`artist_endpoints.dart` L105/L146、`collect_endpoints.dart` L87/L156、`search_typed_endpoints.dart` L119/L165、`user_endpoints.dart` L121/L167 均成对重复 export。
- 另 L68 存在截断残句注释 `// R3-C #3：PlaylistDetail 已含实测字段 listVer（models.dart re-export 自`（未闭合，紧接 L71 export）。
问题：同一 core 符号经同一桥重复转出，门面不唯一；桥注释自述 comment_endpoints 与 bridge_logic 双桥出口重复符号未收敛，违反「桥为唯一通道」的整洁性，长期易产生 export 冲突与维护歧义。
建议：合并同一目标的 export 为单条 show 列表；清理 L68 截断注释；comment_endpoints 出口统一收敛至单一桥（与 bridge_logic 二选一），并在报告中留痕决策。
76 合规：不违反铁律 1/3（桥仍唯一位于 lib/bridges/），但违背铁律 4「门面唯一」精神，属 P2 卫生问题。

---

## C1 · core/net/network_phase.dart:1-115 · P2 · 死代码 + 层归属存疑
证据：全仓 `rg -n 'NetworkPhaseTracker|NetworkPhaseEvent' lib/ -g '*.dart'` 命中仅在 network_phase.dart 自身；`bridge_core.dart` 无 network_phase/NetworkPhase 的 export（已核：`rg network_phase bridge_core.dart` → 无）；即 NetworkPhase / NetworkPhaseEvent / NetworkPhaseTracker（含单例 instance、begin/end/reset、events 流）零消费方、零门面出口。
问题：整个 network_phase.dart 模块是死代码——定义了网络阶段播报单例与广播流，却无任何上层引用，也无桥导出；其「全局单例 + broadcast stream + 阶段状态机」形态更接近 L5/L6 编排状态，置于 L4 core/net 职责边界模糊。
建议：确认是否为「>500ms 网络阶段可见」预留；若是，应经 bridge_core 显式导出并在 L5/L6 接入消费方；若否，删除该模块。同时复核其是否应上移至 logic/session 编排层而非 core。
76 合规：纯 Dart 无 UI，未违反 L4 禁令；但作为无出口的编排态单例滞留 L4，与铁律 4 层职责划分存在张力（P2 观察项）。

---

## C1 · core/net/cover_color.dart:13 / bridge_core.dart:44 · P2 · 死代码（公开门面符号零调用）
证据：`fetchCoverBytes` 定义于 cover_color.dart:13，经 bridge_core.dart:44 `show fetchCoverBytes` 导出；全仓 `rg fetchCoverBytes` 命中仅定义处 + 桥导出 + 本文件内 Log，`lib/core/algorithms/color_extract.dart:5` 注释明确「未被任何 UI 消费方调用（原封面取色桥 cover_color_bridge.dart 已删除）」。
问题：动态取色链路的取字节函数公开于门面却无任何调用方，属公开但零调用符号；配合 color_extract.dart 同注释，动态取色整条链在 A2/A4 视角可能处于未接线状态（跨层消费待 B6 追踪）。
建议：保留则补齐 L5/L6→bridge_core→fetchCoverBytes 的实际调用；否则连同门面 export 一并移除，避免死门面符号。
76 合规：不违反 76（职责/依赖均合规），纯死代码问题。

---

## C1 · core/net/signing.dart:12,49-52 / endpoint_registry.dart:37 / kugou_client.dart:199-200 · P2 · 死代码（register 签名链）
证据：`SignType.register` 枚举值（endpoint_registry.dart:37）与 kugou_client.dart:199-200 `case SignType.register: p['signature']=KugouSign.register(p)`、`KugouSign.register`（signing.dart:49-52）、`registerSalt='1014'`（signing.dart:12）构成完整 register 签名链；但全仓无任何 Endpoint 声明 `signType: SignType.register`（rg 未命中），也无 `KugouSign.register(` 直接调用（除 client 内 switch）。
问题：register 签名实现完整但无任何端点使用，SignType.register 分支为死路径；属「注册设备」类端点的遗留签名能力（registerDevice 端点实际用 SignType.none）。
建议：确认 registerDevice/未来端点是否需要 register 签名；不需要则删除 SignType.register 枚举值、switch 分支、KugouSign.register 与 registerSalt，减少密码学面。
76 合规：符合 76（纯逻辑，无越层），死代码问题。

---

## C1 · core/net/database_opener.dart:1-24 · P2 · 职责错位（非网络代码置于 core/net/）
证据：database_opener.dart 位于 `lib/core/net/` 目录，但内容为打开 Isar 数据库：`import '../database/db.dart'`（L6）调用 `DatabaseService.instance.open(dir)`，无一行网络相关代码；文件头注释自述「原为 database_bridge.dart，因 bridge 字样……更名为 database_opener.dart」。经 bridge_core.dart:69 `show openDatabase` 转出供 L2 bootloader 使用。
问题：数据库开启函数被放进 net/ 子目录，与 L4 core/net「网络底座」目录语义不符，属职责错位/目录归类错误；其重命名只为规避「桥唯一目录」认知冲突（说明历史命名也曾踩影子桥红线）。依赖方向本身合法（同层 core/database 引用 + bridge_kernel 的 Log）。
建议：将文件移至 `lib/core/database/`（如 `database_opener.dart`），更新 bridge_core.dart:69 的 export 路径；保留单入口 async 幂等语义不变。此为目录整理，非跨层越权。
76 合规：不违反铁律（同层 core 内引用合法、经桥暴露、Log 留痕齐全）；违反目录职责清晰性（P2 归类问题），非反向依赖。

---

## C1 · core/net/* 全部 12 文件 + endpoints/models*.dart · P0(合规维度:符合) · L4 层职责纯净性
证据：对全范围 `rg 'package:flutter|BuildContext|Widget|flutter/material|flutter/widgets|dart:ui'` → NONE FOUND。core/net 根 12 文件仅 import `dart:convert/dart:io/dart:async/dart:math/dart:typed_data`、同级 net 模块、`../../bridges/bridge_kernel.dart show Log`、`../storage/resource_cache.dart`、`../database/db.dart`、`bridge_kernel.dart`；无 logic/session/surface import（rg 命中仅 models_util.dart:3 的「禁 import logic/surface/flutter」注释）。全部加解密（crypto_*）、签名（signing）、传输（kugou_client）、缓存合并（inflight）、DB 开启（database_opener）均为纯逻辑/IO 适配，无 Widget/BuildContext/Flutter import。
问题：无违规。L4 core/net 层职责纯净，加密/签名/网络均为纯 Dart 逻辑；这是本视角最重要的合规确认项，记为「符合」而非问题。
建议：保持现状；后续新增文件维持「禁 Flutter import」约束。
76 合规：完全符合 L4 core 职责定义与铁律 4（同层/向下引用合法）；符合第 10 条（子代理只读）。

---

## C1 · core/net/* + endpoints/全部 import 头 · P1(合规维度:符合) · 依赖方向 / 影子桥
证据：
- 越级/反向 import 检查：`rg 'import.*(logic|session|surface)' lib/core/net/**` → 仅注释命中，零真实越级 import；core/net 只向上引用 bridge_kernel（Log）与同层 storage/database，未 import 上层 logic/session/surface。
- 影子桥检查：`rg --files lib/ | rg -i bridge` → 仅 lib/bridges/ 下 6 座桥（bridge_boot/kernel/core/logic/session/surface），无 lib/bridges/ 之外的影子桥目录/文件。core/net 内仅 database_opener 曾有「database_bridge.dart」历史名（已更名），当前无 bridge 字样文件。
- endpoints/ 依赖方向（只读 import 头）：全部 25 个 endpoints 文件仅 import `bridge_kernel`（Log）、`../kugou_client.dart`、`../signing.dart`、`../crypto_*.dart`、`models.dart`/同级模型、`cover_url.dart`——均为同层 core/net 内 + 桥，无跨层非桥 import。
问题：无违规。依赖方向单向向下（core 不依赖上层），六桥唯一通道成立，无影子桥。
建议：保持。
76 合规：符合铁律 1（跨层经桥）、3（六桥唯一目录）、4（同层合法/无反向依赖）；A2 范围内无越级 import 证据。

---

## C1 · core/net/endpoint_registry.dart:1-503（53 个 Endpoint 常量）· P1(合规维度:符合) · 端点注册表职责 / 一文件一模块
证据：endpoint_registry.dart 全 503 行仅含 1 个 `Endpoint` 数据类（L7-35）、`SignType` 枚举（L37）、`EndpointRegistry` 静态常量类（L39-503，53 个 `static const … = Endpoint(...)` 声明）；`rg` 方法/函数定义 → 无任何函数体、无网络请求实现、无业务解析。文件头注释「声明式配置：每个端点一常量……改 API 只改这里」属实。业务实现分散在 endpoints/ 下 25 个 *endpoints.dart 各一模块（auth/play/search/mv/playlist/collect/…），符合 §0 第 6 条「每端点一 dart 模块」。
问题：无违规——注册表是纯声明注册表而非塞实现；endpoints 一文件一模块成立。（endpoint_registry.dart 503 行是 53 个声明常量+大量实测注释所致，非逻辑膨胀，未超 1500 行。）
建议：保持；若后续常量继续增长，可按域拆 registry 分片，但非必须（未触门禁）。
76 合规：符合 §0 第 6 条（一文件一模块、注册表职责单一）、第 5 条（行数门禁）。

---

## C1 · core/net/endpoints/models.dart:1-9、models_util.dart:1-83 · P2(合规维度:符合) · 模型数据契约纯度
证据：models.dart 仅 5 行 `export`（models_util/song_models/play_models/playlist_models/lyric_models），零逻辑，为纯导出桶。models_util.dart 仅 6 个容错取值函数（safeInt/safeStr/safeDouble/safeBool/dataOf/listOf），每函数 try/catch+Log，无 Flutter import、无网络请求、无业务编排，属纯数据解析契约。
问题：无违规，二者为数据契约。（观察：models.dart 统一导出桶与 bridge_core.dart L15/L131 两次分段 show，属同一符号来源重复转出，已并入桥门面卫生条目。）
建议：保持。
76 合规：符合 L4「纯算法/数据契约」职责与第 6 条。

---

## C1 · endpoint_registry.dart:13,43,368,410 等 53 端点 + endpoints/*.dart 全部域名 · P1(合规维度:符合，2 处 P2 隐患) · 只连酷狗官方域名
证据：提取 registry 全部 base/router 域名（sort -u）：
`gateway.kugou.com / complexsearch.kugou.com / searchtip.kugou.com / msearch.kugou.com / trackercdn.kugou.com / media.store.kugou.com / specialrec.service.kugou.com / pubsongs.kugou.com / cloudlist.service.kugou.com / ocean(经gateway) / lyrics.kugou.com / openapi.kugou.com / everydayrec.service.kugou.com / kmr.service.kugou.com / trackermv.kugou.com / userservice.kugou.com / login-user.kugou.com / login.user.kugou.com / loginservice.kugou.com / loginserviceretry.kugou.com / mcomment.kugou.com / sum.comment.service.kugou.com / usercenter.kugou.com / expendablekmrcdn.kugou.com / listenservice.kugou.com`。
`rg -no 'https?://[host]'` 全范围去除 *.kugou.com/kgimg.com 后 → 空（无第三方域、无测试域、无 localhost/IP）。全部归属酷狗官方 (*.kugou.com 及其 kgimg CDN)。
问题：域名白名单合规，无违规接入第三方。两处隐患（P2）：L368 `loginToken`、L410 `sendSmsCode` 用明文 `http://login.user.kugou.com`（登录/验证码走非 TLS，与同域其他端点的 https 不一致）；虽为官方域，但登录凭据/验证码明文传输存在中间人风险。
建议：两处 `http://` 改为 `https://`（该域已在 L377 loginByPwd 用 https，说明支持 TLS）；其余域名白名单保持。
76 合规：符合 §0 第 6 条「只连酷狗官方域名」；明文 http 属安全观察，非 76 条款违反。

---

## C1 · core/net/crypto_aes.dart:1-786（头注 L5）· P2 · 行数门禁/头注一致性
证据：crypto_aes.dart 实际 786 行（wc -l），文件头 L5 自述「dart:typed_data 自实现，≤500 行」——头注与实际不符（拆分后 S 盒/逆 S 盒两张 256 项常量表各占约 256 行，是行数主体）。`signing.dart L70「MD5 ≤120 行」`实际 Md5 类约 130 行（L75-262），头注亦轻微不符；`inflight.dart L21「≤200 行」`实际 112 行，符合。
问题：无门禁违规（786 < 1500）。crypto_aes.dart 786 行是本批最大文件，需关注：其体积来自两张常量表（纯数据）而非逻辑复杂，暂不需拆分；但「≤500 行」头注失实，易误导后续维护者判断拆分阈值。
建议：修正 crypto_aes.dart L5 头注为实际行数描述（如「常量表占位约 500 行，逻辑 ≤300 行」）；无需按 1500 门禁拆分。
76 合规：符合第 5 条（未超 1500 行，拆分阈值未触发）；头注失实属文档 P2。

---

## C1 · core/net/kugou_client.dart:10-13 / database_opener.dart:6-7 等 · P2(合规维度:说明) · core 对 bridge_kernel(Log) 的依赖方向说明
证据：core/net 各文件普遍 `import '../../bridges/bridge_kernel.dart' show Log`（如 kugou_client.dart:9、crypto_aes.dart:15、cover_color.dart:7、inflight.dart:25、database_opener.dart:7、models_util.dart:4），endpoints 用 `../../../bridges/bridge_kernel.dart`。全仓 core/logic/session 多处均如此（rg bridge_kernel 命中 core/*、logic/*、session/*），属全局日志约定。bridge_kernel 是 L2↔L3 桥，暴露 Log；core(L4) 向上 import 该桥取 Log。
问题：按 76 铁律 4「每层只依赖其下层经桥暴露的门面，反向依赖禁止」，L4 core import bridge_kernel(L2↔L3 桥) 严格看是「向上依赖更底层的桥」——但 Log 属 L3 kernel 能力，经 bridge_kernel 暴露给上层复用是项目一致约定（A1 批已覆盖桥全局图）。此为架构约定下的可接受例外，非跨层直连非桥文件；记录供主会话交叉比对。
建议：主会话在 A1/A6 结论交叉时确认 bridge_kernel.Log 对 core/logic/session 全局可见是否为既定例外；若是，在 76 文档补「日志桥可全局引用」条款以消除歧义。
76 合规：不违反铁律 1（未直连非桥文件，走的正是桥）；对铁律 4「反向依赖」呈灰色（向上引用低层桥），属全局约定例外，标记 P2 观察项而非判定违规。

---

## 本视角结论

1. **L4 层职责纯净（重点核 1，符合）**：core/net 全 12 文件 + models*.dart 零 Flutter import / 零 BuildContext / 零 Widget；加密(signing/crypto_*)、签名、传输(kugou_client)、缓存合并(inflight)、DB 开启均为纯 Dart 逻辑/IO 适配。无一条 UI 依赖泄漏进 L4。
2. **依赖方向干净（重点核 2，符合）**：core/net 无 logic/session/surface 越级 import；endpoints/ 25 文件 import 头只指向 bridge_kernel(Log)+同层 core net 模块；无 lib/bridges/ 之外影子桥（6 座桥唯一位于 lib/bridges/）。database_opener.dart 置于 net/ 下属目录职责错位(P2)，但非跨层越权。
3. **注册表与一文件一模块（重点核 3，符合）**：endpoint_registry.dart 为 53 个纯声明 Endpoint 常量、无实现塞入；models.dart 为纯导出桶、models_util.dart 为纯解析契约；25 个 endpoints 各一模块。符合 §0 第 6 条。
4. **域名白名单（重点核 4，符合+2 隐患）**：全部 base/router 域名及 endpoints 内 host 均为酷狗官方 (*.kugou.com / kgimg CDN)，无第三方/测试域。隐患：loginToken(L368)、sendSmsCode(L410) 走明文 http://（P2 安全）。
5. **桥门面（重点核 5，P2）**：bridge_core.dart 对 core/net 导出存在 10+ 处同目标重复 export（models/kugou_client/comment/mv/album/artist/collect/search_typed/user），并有截断注释；无「导出 private 实现」越权（均 show 公开符号），但门面不唯一，需收敛。
6. **1500 行门禁（重点核 6，符合）**：全部范围文件最大 crypto_aes.dart 786 行，未超限；其体积为 AES S 盒常量表所致，头注「≤500 行」失实(P2)，无需拆分。
7. **死代码/占位（重点核 7，P2）**：发现 3 处公开零调用符号/模块——network_phase.dart 整个单例模块零消费方零门面出口；cover_color.dart fetchCoverBytes 公开但零调用；signing.dart 的 SignType.register + KugouSign.register + registerSalt 完整签名链无端点使用。无 TODO/FIXME/PLACEHOLDER 标记，无占位/未实现方法。
8. **总体**：A2 批 core/net 架构合规主干健康——层归属、依赖方向、端点分文件、域名白名单、行数门禁五项全部符合 76；问题集中在桥门面重复导出、3 处死代码、database_opener 目录错位、2 处明文 http、头注失实，均为 P2，无 P0/P1 实质架构违规。

## 未覆盖

- 按本视角只读授权，`lib/core/net/endpoints/` 下 25 个文件**仅核 import 头（依赖方向）与域名 host**，未逐行审其业务实现（属 A3 批 + C2 实现正确性视角范围）。
- 未验证任何编译/analyze/test/门禁运行结果（工具纪律禁止），所有结论基于静态只读取证。
- bridge_core.dart 仅核 core/net 相关 export 行与重复情况；其与 logic/session 层的门面一致性、bridge_logic 的 comment_endpoints 双桥出口实体，留待 A6 批与交叉汇总复核（本视角只看到 bridge_core 侧注释自述）。
- Log 全局桥引用的「反向依赖例外」定性，留待主会话 A1 全局依赖图交叉比对后最终裁定。

## 76 合规小结

| 铁律/条款 | A2 范围结论 |
|---|---|
| §0-1 跨层经桥、禁跨层直连非桥 | 符合（无越级 import） |
| §0-2 桥 try/catch+Log | 符合（core/net 公开 IO 函数普遍 try/catch+Log） |
| §0-3 桥唯一目录、禁影子桥 | 符合（6 桥仅 lib/bridges/；database_bridge 历史名已更名） |
| §0-4 只依赖下层门面、禁反向 | 主体符合；core→bridge_kernel(Log) 为全局约定灰色项(P2)，待交叉裁定 |
| §0-5 单文件>1500 才拆分 | 符合（最大 786 行，未触阈值） |
| §0-6 每端点一模块/多参不缺参/只连官方域 | 符合（53 声明常量+25 模块；域名全官方）；明文 http 2 处为安全 P2 |
| §0-7 零源仓库代码复用 | 未见违规（本视角未涉及归档复用证据） |
| §0-8 播放控制等禁入 L6 | 非本批范围（A2 为 L4） |
| §0-9 成熟库优先 | 加密/签名自实现为协议契约要求（docs 锚定），符合领域约束；未引入 Flutter UI 库进 core |
| §0-10 子代理只读 | 符合（全程只读，仅 append 本报告） |
| L4 层职责（Widget/BuildContext 禁令） | 符合（零 Flutter import） |

**一句话定调**：A2 批 core/net 架构合规主干通过 76 原则核验，无 P0/P1 实质违规；7 项 P2 均为卫生/死代码/目录归类问题，建议主会话在亲修阶段一并处理。
