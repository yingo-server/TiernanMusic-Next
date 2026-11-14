# 重构后 L4 core / 桥 / 门禁 / 文档 全面审查报告（只读审计 · 2026-11-15）

审查范围：lib/core/{cache,audio,algorithms,l10n}、lib/bridges/ 六桥、tool/ 七件门禁工具、docs/SEVEN_SIX_RULE.md、docs/SIX_FIVE_RULE.md、README.md、docs/ARCHITECTURE.md、docs/FUNCTION_TREE.md、.github/workflows/ci.yml、test/qr_painter_test.dart、tool/gen_i18n.py。

---

## 1. 命名一致性（76 原则 vs 旧「六层五桥/六五」残留）

权威文档 `docs/SEVEN_SIX_RULE.md` 已是七层六桥正确口径（LAYERS 1-7、六桥、L6 session / L7 surface）。两门禁代码逻辑也已全部是 7 层 + 6 桥（bridge_session 被两门禁同时认定，见 §2）。残留的是**注释/文档字符串**：

| 文件:行 | 内容 |
|---|---|
| tool/layer_audit.py:2 | docstring「76 原则强约束审计（strict six-five）」 |
| tool/layer_audit.py:5,7,11,30,206 | 「五桥」字样（BRIDGE_NAMES 实为 6 个） |
| tool/layer_audit.py:13,246,250 | 输出字符串 `PASS/FAIL strict six-five` |
| tool/smoke_check.dart:9,147,154,195,218,249,313 | 「五桥/强约束六五」注释与错误消息 |
| docs/SIX_FIVE_RULE.md | 全文仍标榜「唯一权威定义」，标题仅写「V1 已废弃」在括号内，易误导；建议顶部加显著 DEPRECATED 横幅 |
| docs/ARCHITECTURE.md:1,14,37 | 标题「76 原则（V1 已废弃）」+「五桥定义表」（只有 5 桥、6 层图，未含 session/bridge_session）——整篇是 V1 口径，与 SEVEN_SIX_RULE.md 冲突 |
| README.md:3,7,58 | 「76 原则（V1 已废弃）」+ 架构速览仍是六层五桥图 + 「五桥门面」 |
| docs/FUNCTION_TREE.md | 未含 session 层目录条目（清单仍按旧六层组织） |
| tool/api_matrix_probe.dart:3 | 「六五规则」 |
| lib/bridges/bridge_boot.dart:1, bridge_kernel.dart:1, bridge_logic.dart:1 | 头注释「五桥 ·」（bridge_session/bridge_surface 已是「六桥 ·」） |
| lib/core/algorithms/qr_codec.dart:31, color_extract.dart:11, core/l10n/strings.dart:7 | `_tag = 'surface.qr' / 'surface.color' / 'surface.l10n'`——文件已下沉 core，日志 tag 仍是 surface.*（低危，属留痕口径残留） |

**门禁输出 "PASS strict six-five" 判定**：仅字符串未改。语义已是 7 层（LAYERS 含 session:6/surface:7、BRIDGE_NAMES/LAYER_ALLOWED_BRIDGES 均含 bridge_session、L7_EXTRA/L6_EXTRA 分列）。字符串与语义不一致会误导 CI 日志读者，应改为 `strict seven-six`。

**结论**：代码层已彻底转换；文档+注释层残留约 **22 处**（上表逐条），其中 docs/ARCHITECTURE.md 与 README.md 架构速览是**现行权威文档写旧口径**，属必修。

## 2. 层表正确性（两门禁对齐）

| 项 | layer_audit.py | smoke_check.dart | 一致？ |
|---|---|---|---|
| LAYERS/_layers | init1/boot2/kernel3/core4/logic5/**session6/surface7** | 同 | ✅ |
| BRIDGE_NAMES/_bridgeNames | 6 个含 bridge_session | 同 | ✅ |
| LAYER_ALLOWED_BRIDGES/_layerAllowedBridges | L6:{boot,kernel,core,logic,session}、L7:{surface,session,logic,core} | 同 | ✅ |
| L4_EXTRA | isar + just_audio + audio_service | 同（l4Extra 内联于 _checkForbiddenImports） | ✅ |
| L7_EXTRA | flutter/riverpod/just_audio/video_player/audio_service/path_provider/flutter_localizations | _l7Extra 少 `flutter_riverpod`、`flutter_localizations`，但 `startsWith('package:flutter')` 前缀匹配已覆盖 flutter_riverpod；flutter_localizations 两边白名单同有/无差异：**py 有、dart 无** → L7 import flutter_localizations 会过 py 过不了 dart（当前无使用方，未爆发） | ⚠️ |
| L6_EXTRA | riverpod + flutter/foundation + flutter/widgets | 同 | ✅ |
| L1_EXTRA | material/services/path_provider | 同 | ✅ |
| 装配例外 | init/main→bootloader/register | 同（_isLayerException） | ✅ |
| 影子桥/桥 try-catch/桥不 import 桥 | 有 | 影子桥有；桥 try-catch 与桥互斥 import 仅 py 有（dart 无，容忍度可接受） | ⚠️ |

**bridge_session 双门禁认定**：✅（两处白名单均含，且 L7 可用）。

## 3. 纯算法下沉

- `core/algorithms/qr_codec.dart`：仅 dart:convert/typed_data + bridge_kernel.Log，**零 package:flutter** ✅。
- `core/algorithms/color_extract.dart`：实际 import 仅 dart:math ✅（头注释第 8-11 行仍写「本 surface 文件 import package:flutter/material.dart」——已过时，注释残留）。
- `core/l10n/strings.dart`：零 flutter ✅（另 import bridge_core 的 KeyValueSettings/StoragePaths——属 L4 经桥合法）。
- `test/qr_painter_test.dart:7`：`import 'package:tiernan_music_next/core/algorithms/qr_codec.dart'` ✅ 已改 core 路径。
- `tool/gen_i18n.py:123`：输出 `lib/core/l10n/strings.dart` ✅。
- 旧 `lib/surface/l10n/`：**已删** ✅；`lib/surface/widgets/`：目录仍在但为**空目录**（qr_painter.dart 已删）——空目录无害，建议顺手删掉。

## 4. 门禁覆盖

local_gate.sh 十一道（脚本自称十道，实际数了 11 个步骤）：layer_audit / syntax / smoke / analyze_gate / md5 / field_truth / reachability / boot / play / **session_contract** / resolve / download。

**CI（ci.yml analyze-test job）比对**：有 smoke、md5、reachability、syntax、field_truth、layer_audit、analyze_gate、boot、play、resolve、download。
**缺失：session_contract_test 在 CI 无对应 step、verdict 无对应 grep** ——「本地过但 CI 抓不到」的真实缺口（本次重构核心正是 L6 session，恰是唯一漏掉的一道）。

**feature_reachability_test.dart 旧断言**：⑤ 检查 `lib/surface/pages/home_page.dart` / `player_page.dart` 存在——lib/surface/ 下确有 pages/ 目录，当前通过；但按 SEVEN_SIX_RULE §7 要求应「删除 surface/pages 存在断言、改为 session 装配图存在」，属口径滞后（若独立 UI 模型重建页面目录结构会误报）。②③④⑥⑦ 已是 V2 口径（endpoint_registry、session bootstrap、arb 10语×20键、miuix 移除）。⚠️ 注意 ① 的 `endpoints.difference(registered).isEmpty` 是恒真式（registered=endpoints），属无效断言。

**verdict 对齐**：其余各道均有正向+反向双 grep，判据健全。

## 5. 成熟库与缓存

- `core/audio/audio_gateway.dart`：**真用 just_audio**（AudioPlayer + 三流订阅 + NullAudioEngine 兜底，纯 IO 适配）✅。
- `core/audio/notification_gateway.dart`：**真用 audio_service**（BaseAudioHandler/MediaItem/MediaControl + AudioService.init，失败返回 null 降级）✅。
- 两文件 L4_EXTRA 均放行（py/dart 同列 just_audio/audio_service）✅。
- `core/cache/cache_service.dart`：**无自研 ResourceCache 引用**——它是 KugouClient 之上的薄门面（get/prefetch/invalidateSession/stats），缓存实为 client 内 L1 内存 + L2 磁盘 + 单飞。L2 磁盘仍是 `core/storage/resource_cache.dart`（dart:io 自研，纯标准库、无 flutter 依赖）。
  **判断**：SEVEN_SIX_RULE §0 铁律 9 明示「缓存网络允许 dio+缓存拦截器」，即项目自己已把缓存列为可换成熟库项。当前 ResourceCache 是唯一活跃 I/O 自研件且已有单飞/互斥；**不必立即替换**（替换需动 KugouClient 全链路，收益有限），但建议列入后续批次的候选改造项，非本次必修。

## 确认已彻底转换

1. LAYERS/_layers、六桥白名单、L4/L6/L7/L1 extra、装配例外——两门禁完全同口径，均为 7 层 6 桥。
2. qr_codec / color_extract / strings 三件纯算法/常量已下沉 core/l10n、零 flutter 依赖，测试与 gen_i18n 路径同步改妥。
3. surface/l10n、qr_painter 真删；audio/notification 网关真用 just_audio/audio_service；CacheService「缓存⊃预读」融合正确（resolve_contract 锚点齐）。

## 残留清单（全部为文档/注释/字符串，无代码语义残留）

- layer_audit.py：2,5,7,11,13,30,206,246,250（含 `PASS/FAIL strict six-five` 输出串）
- smoke_check.dart：9,147,154,195,218,249,313
- docs/ARCHITECTURE.md：1,14,37（整篇 V1 口径，需重写为七层六桥）
- README.md：3,7,58（架构速览图 + 五桥门面）
- docs/SIX_FIVE_RULE.md：全文（建议顶部加 DEPRECATED 横幅并注明被 SEVEN_SIX_RULE.md 取代）
- docs/FUNCTION_TREE.md：缺 session 层条目
- tool/api_matrix_probe.dart:3
- bridge_boot/kernel/logic 头注释「五桥」
- qr_codec/color_extract/strings 的 `_tag='surface.*'`
- color_extract.dart:8-11 过时分层注释

## 必修 TOP5

1. **CI 补 session_contract_test step + verdict grep**（唯一本地有、CI 无的门禁；本次重构核心层恰好失守）。
2. **重写 docs/ARCHITECTURE.md 与 README.md 架构速览**为七层六桥（现行权威文档写旧口径，派代理/新人易被误导）。
3. **layer_audit.py 输出串改 `strict seven-six`** + 两工具内「五桥/六五」注释清理（避免 CI 日志语义误导）。
4. **docs/SIX_FIVE_RULE.md 顶部加显著 DEPRECATED 声明**（其正文仍自称「唯一权威定义」，与 SEVEN_SIX_RULE.md 冲突）。
5. **feature_reachability_test.dart ⑤ 改为 session 装配图断言**（按 SEVEN_SIX_RULE §7），并顺手删恒真断言 ①、清理 surface.* 日志 tag 与空 widgets 目录。

（低优先：smoke_check._l7Extra 补 flutter_localizations 与 py 对齐；bridge try-catch 检查 dart 侧缺失。）
