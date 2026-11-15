# 六批批1-F3「play_url 顶层字段补齐」实施记录

状态：**完成**（依据 docs/six_b1_c1.md / six_b1_c3.md 收口，未臆造实测值）

时间：2026-11-15 · 功能范围：六批批1-F3 play_url 顶层字段补齐。

## 允许改动文件（仅 2 个 + 本记录文档）

1. `lib/core/net/endpoints/play_endpoints.dart`（主文件）
2. `lib/core/net/endpoints/play_models.dart` —— **确认过的真实模型文件名 = play_models.dart**
   （先 file_read 确认；`models.dart:7` 有 `export 'play_models.dart';`，PlayResult/PrivilegeItem 在此定义；`PlaySource` 在 `lib/logic/player/playback_service.dart:44`，属禁改的批3范围）
3. `docs/six_b1_f3.md`（本实时记录；规矩要求每步实时写）

未改第三个代码文件；未改 playback_service.dart / 盐常量 / 签名公式 / tool/field_truth_test.dart / CI。

## Step 1 · 现状核对（C1 / C3 直接用）

- urls/backupUrls/bitRate/extName/timeLength 已有落点（保留原解析，未动）。
- hash_offset/end_byte/fail_process 此前 `_PlayExtras`+Expando 侧挂，仅 play_endpoints.dart 自身 Log.d 消费，下游读不到。
- 响应 q / fileSize / volume / classmap 等顶层键仍未捕获；PlaySource.quality 仍按请求档回填（playback_service.dart:261，禁改）。
- C3 风险③：field_truth_test 的 N2-C / mvKey 锚点是纯公式断言，只依赖 signKeySalt / KugouSign.playKey；本批不动盐与公式，锚点理论上不破。

## Step 2 · play_models.dart：PlayResult 新增公开字段（全部构造带默认值，零破坏）

- `hashOffset` / `endByte` / `failProcess`（`int?`，默认 null）→ ① 要求：三键真正落公开字段，L5 可读。
- `responseQuality`（String，默认 ''）+ `String get quality` 便捷读点 → ③ 要求：响应 q 优先、缺省回退请求档的最终值。
- `fileSizeBytes`（int）/ `volume`（double）/ `classMap`（Map<String,String>）→ ② 要求。
- 顺带容错保留 `transParam`（含 qualitymap）/ `authThrough` / `fileName` / `fileHead` / `stdHash` / `hashToken` / `topLevelKeys`（仅键名，脱敏）/ `variantFields`（camelCase 变体标量）。
- `toMap()` 同步补齐新键；`playable` / `needsVerification` 判定语义一字未改（C3 红线）。
- 所有新字段都是 final + 构造默认值，`const PlayResult()` 及现有命名参数调用均不破坏。

## Step 3 · play_endpoints.dart：解析补齐

- 删除 `_PlayExtras` / `Expando` / `PlayResultExtras` 扩展：公开实例字段天然替代扩展 getter，`result.hashOffset`/`endByte`/`failProcess` 读点零改动，且 L5（playback_service，批3）可直接读 → 满足「删掉或保留 Expando 但必须让 L5 可读」（选删除）。
- hash_offset/end_byte/fail_process：存在且非 null 才 `safeInt`，缺失留 null（不臆造默认值）。
- 响应 q：num/String 双形态，`respQ`；`effectiveQuality = respQ.isNotEmpty ? respQ : q` 落 `responseQuality`（= `PlayResult.quality`）。**服务端降档可感知**。L5 只需把 `hits.first.quality` 换成 `hits.first.pr.quality`（批3接线，本批禁改该文件）。
- q/fileSize/fileSize 变体/volume/vol/classmap/trans_param.qualitymap/auth_through/fileName/fileHead/std_hash/hash_token/topLevelKeys/variantFields 全部 safe* 风格 + 每段独立 `try/catch + Log.e(_tag, ...)`，任一形态异常只丢该键不丢整包结果。
- 通用顶层键名兜底只留键名（沿用 C3 脱敏口径：不留 URL/token/凭据值）。
- Log.d 增打 respQ/effectiveQ/fileSize/volume/classmap/transParam/authThrough 计数（数值型，脱敏安全）。

## Step 4 · 语法自检（仅按规矩跑一次 dart format --output=none）

- 命令：`/opt/d3137/dart-sdk/bin/dart format --output=none lib/core/net/endpoints/play_endpoints.dart lib/core/net/endpoints/play_models.dart`
- 结果：`FORMAT_EXIT=0`，两文件语法/格式通过；`--set-exit-if-changed` 复核 0 changed。
- 附带本地静态检查 `dart analyze --no-fatal-warnings` 两文件：无 error；仅 2 条既有 warning（`play_endpoints.dart:28 unnecessary_cast`、`play_models.dart unused_import models_util.dart`，均为改动前已存在，未顺手改以免扩大范围）。
- 未跑全门禁 / 未跑 field_truth_test / 未跑三态网络调用（规矩明确「不跑全门禁」、C1 自认三态未留样）。

## 红线确认

- 未触碰 `signKeySalt` / `KugouSign.playKey` / md5 公式（C3 风险③）。
- 未改 `status/priv_status` 判定语义（`playable` / `needsVerification` / `privKnown` 原样）。
- 未改 field_truth_test 的 play_url 锚点、未改 tool/、未改 CI。
- 未改 playback_service.dart（批3范围）。

## 未覆盖

- **L5 PlaySource.quality 实际接线**：PlaySource 定义在禁改的 `playback_service.dart`，本批只把「响应 q 优先」的最终值落到 `PlayResult.responseQuality` / `PlayResult.quality` 供批3直接读；`playback_service.dart:261 quality: hits.first.quality` 仍是请求档，按范围标「未覆盖」，不强改第三个文件补齐。
- hash_offset/end_byte/fail_process 的**消费逻辑**（试听分片标记 / 断点 / 风控接线）同属批3范围，本批只保证字段可读，标「未覆盖」。
- 三态（vip/nonvip/anon）运行时 q / hash_offset / end_byte / fail_process 实际值未留样（C1 自认；本批不跑网络、不臆造默认值）。
- 全门禁 / field_truth_test / api_samples_v2 留样：按规矩与范围未跑，标「未覆盖」。
