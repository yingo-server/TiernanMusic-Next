# A2 批 · C3 用户痛点专项 · 网络底座用户影响面 + 密码学/文案盘点

> 子代理：A2-C3｜视角：C3 用户痛点（网络底座 → 用户功能坏掉 / 密码学支撑 YKG / 文案从底层漏出 / 功能可达性补充）
> 仓库根：`/var/minis/workspace/NextWorkspace/TiernanMusic-Next`
> 审查方式：只读（file_read / ls / rg / wc），未跑任何 dart/flutter/analyze/test/门禁，未联网，未改源码。
> 落盘纪律：每得一条结论即 append，带时间戳。

---

## [2026-11-16 22:23:40] 批次开局 · 范围确认

读取范围（一口气读完）：
- 底座：`kugou_client.dart`(297行) / `network_phase.dart`(115行) / `inflight.dart`(112行) / `endpoint_registry.dart`(503行) / `signing.dart`(266行) / `crypto_aes.dart`(786行) / `crypto_rsa.dart`(179行) / `crypto_rsa_raw.dart` / `crypto_bigint.dart` / `crypto_extra.dart` / `cover_color.dart`(56行) / `database_opener.dart`
- 参考：`docs/API_TEST_REPORT.md` / `docs/YKG_LINK_CRYPTO_DESIGN.md` / `docs/deep_audit/bA1_c3.md`（YKG 节，复用不重做）
- 对照 skill：`material-3/SKILL.md` 的 MD3 Compliance Audit 十类、motion 表、反模式（用于判定网络层是否混入 UI/动效关注点）

MD3 判定（前置结论）：本批 `core/net/` 全部文件均为**纯 Dart，无 flutter import**，无 `Color(0x…)`、无 rounded/shadow/magic-Dp、无动画时长/曲线、无 build/Widget。**网络底座未混入任何 UI/动效关注点，MD3 十类在此层全部 N/A（不评分）**。唯一沾 UI 语义的是 `network_phase.dart:2` 注释「>500ms 的网络阶段必须可见」，但仅为规格描述，无 UI 代码，且该 tracker 实际零接线（见 C3-06）。

---

## [2026-11-16 22:24:05] C3-01 · kugou_client.dart:243-260 · P1 · 超时→用户转圈/报错

证据：
```dart
// kugou_client.dart:67-69
HttpClient get _h => _http ??= HttpClient()
  ..userAgent = KugouSign.defaultUa
  ..connectionTimeout = const Duration(seconds: 10);
// kugou_client.dart:237-260
const responseTimeout = Duration(seconds: 15);
final res = await req.close().timeout(responseTimeout,
  onTimeout: () { throw KugouApiException(-2, 'response header timeout (${ep.id})'); });
final text = await res.transform(utf8.decoder).join().timeout(responseTimeout,
  onTimeout: () { throw KugouApiException(-2, 'response body timeout (${ep.id})'); });
```
问题：连接 10s + 响应头 15s + body 15s，最坏一条请求 ~40s 才落地为 `KugouApiException(-2)`；期间 UI 若只挂一个 loading，用户感知为「点了转圈十几秒」且**无进度/无取消/无重试**。两段超时虽已归一为 -2（比旧版裸 TimeoutException 好），但**全仓无 -2 的重试/退避消费点**。
建议：① 上层对 -2 做一次幂等重试 + 退避（仅 GET/可缓存端点）；② 缩短响应头超时至 8s、total 预算封顶；③ 给 loading 加「取消」与超时后的明确错误态（走 i18n，见文案清单）。
76 合规：不涉及（超时语义属 L4 网络职责，重试编排应落 L5/L6，不在本层塞状态机）。

## [2026-11-16 22:24:20] C3-02 · kugou_client.dart:92-115 + resource_cache.dart:69 · P1 · 缓存固化（7 天扁平 TTL）

证据：
```dart
// kugou_client.dart:110-112
if (cacheable) { await _cache!.putJson(cacheKey, res); }  // 未传 ttl
// resource_cache.dart:69
final Duration ttl;
this.ttl = const Duration(days: 7),   // 全局默认 7 天
// resource_cache.dart:301-304 注释：per-entry ttl「为按端点 TTL 分级预埋」——但 KugouClient 不传 ttl
```
问题：端点表注释多处写「播放地址短时效，禁止缓存」（`endpoint_registry.dart:74,331` 已置 `cacheable:false`），但**其余端点默认 `cacheable:true`（:17）+ 命中全局 7 天 TTL 且未接线 per-entry ttl**。`searchHot/searchSuggest/rankList/userDetail/favoriteCount/commentCount/vipType` 等动态结果被固化 7 天：用户看到过期榜单/评论数/VIP 态，且**业务错误 Map（如 errcode=200103 未登录推荐、20028 风控）也被当成功结果缓存 7 天**（直到 token/uid 变化才换键）。这就是「点了没反应/内容不刷新」的典型根因之一。
建议：① 在 `Endpoint` 增 `ttl` 字段并在 `request()` 把 `ep.ttl` 传给 `putJson`（预埋能力接线）；② 业务层出现 `errcode/status!=成功` 的 Map **不写缓存**；③ 动态类端点（评论数/收藏数/VIP/用户信息）默认短 TTL 或禁缓存。
76 合规：不涉及（TTL 分级是 L4 缓存职责，接线点在 L4，符合分层）。

## [2026-11-16 22:24:33] C3-03 · inflight.dart:56-96 + kugou_client.dart:105-107 · P1 · 单飞 clear 竞态 + 计数不可见

证据：
```dart
// inflight.dart:88-96 _execute finally
} finally { _pending.remove(key); }
// inflight.dart:56-64 clear()：_pending.clear() 但不取消底层任务
// inflight.dart 头注 15-20 行自认：
//  「clear() 会让后续同 key 请求成为新任务，而旧任务完成时 finally 的
//    _pending.remove(key) 只删同字符串键——这是既有语义，本版不改」
//  「KugouClient 未转出这些 getter → CacheService 仍无法取到底层真实计数」
```
问题：登出/换号调 `clearInflight()` 后，若旧任务仍飞行，同 key 新请求会新建 task2，旧 task1 的 finally 再 `_pending.remove(key)` 会**误删 task2 的登记**，导致同一 key 并发双发（浪费+签名重放风险，非死锁）。另 `KugouClient.request` 调 `_inflight.run(cacheKey, run)` **未传 timeout**，等待侧超时计数（timedOut）恒为 0，且 started/coalesced/failed 全部 getter 未转出 → 上层（CacheService/UI）拿不到真实网络统计，无法据此展示「正在请求/已合并」，用户侧只能靠猜。
建议：① `_pending.remove(key)` 改为「仅当 _pending[key] === 当前 future 才移除」（身份比对，防误删）；② KugouClient 转出 inflight 只读统计 getter 给 CacheService；③ request 侧给 run 传一个等待侧总预算 timeout。
76 合规：不涉及（修复限 L4 内部）。

## [2026-11-16 22:24:52] C3-04 · kugou_client.dart:171-172,183-185 + API_TEST_REPORT.md §四/§五 · P1 · 签名错误 20006/20028/200103 的用户面

证据：
```dart
// kugou_client.dart:171-172（已知坑，已修）
// srcappid 参与签名会让搜索/cloudlist 返回 20006；默认不注入，仅 includeSrcappid 开启
// endpoint_registry.dart:162 注释：缺 kg-tid → error_code 20006 "err KG-TID"
// endpoint_registry.dart:210-211：clearDefaultParams=true 会返回 20006
// API_TEST_REPORT.md §四.3：匿名正确盐 errcode=20028（人机验证）；31833=错盐负对照
// API_TEST_REPORT.md §四.2：未登录每日推荐 errcode=200103、data 为字符串
// API_TEST_REPORT.md §五.6：srcappid 默认注入致全线 20006（已修网络层真 bug）
```
问题：`KugouClient` 只处理**传输层错**（HTTP 非 200 / json 解析错 → -3 / shape 错），**业务错误码 20006/20028/200103/31833 等以 HTTP 200 的 Map 原样透传**，全由各端点/上层自行判定。已核对这些是 API_TEST_REPORT 明示的「已知坑」：
- 20006 = 签名/参数坑（srcappid、缺 kg-tid、clearDefaultParams 误用）→ 用户看到空搜索/空榜单，无从得知是签名问题；
- 20028 = 匿名风控验证态，`play_models.dart:116` 判为「需验证」，但 `verification_logic.dart:2` 自注「验证链路未接线」→ 用户点播匿名曲转圈后无引导；
- 200103/31833 各有专门判定，但**均无统一错误码→文案映射**。
结果：用户「点了没反应 / 报错不明确」，因为错误码从不翻译成可见提示。
建议：在 L4 建 `KugouApiErrorMapper`（纯函数，code→语义枚举，不产文案），L5/L7 再把枚举走 `strings.dart` i18n 成中文/繁/英提示；特别为 20028 接上 verification 流程引导。
76 合规：不涉及（错误码分类是 L4 纯逻辑，文案落 L7 经 i18n，禁在 L4 硬编码中文）。

## [2026-11-16 22:24:58] C3-05 · kugou_client.dart:271-286 · P2 · 非 JSON 成功响应 shape 判错

证据：
```dart
if (decoded is Map<String, dynamic>) return decoded;
if (rawBody != null) return <String, dynamic>{'_raw_text': text};
throw KugouApiException(res.statusCode, 'unexpected response shape'); // :286
```
问题：非 `rawBody` 端点若上游返回合法 JSON 但是 **List 顶层**（部分上游响应），被判为 `KugouApiException(200,'unexpected response shape')`，上层按异常走「加载失败」而非解析数据 → 用户功能假失败。API_TEST_REPORT §四.2 记录 `daily_recommend` 未登录时 `data` 为字符串（键为 `errcode`），顶层仍是 Map 故能过，但**顶层非 Map 的契约无兜底**。
建议：对已知返回 List 的端点在注册表加 `responseShape` 声明，或 KugouClient 统一包 `{'_list': decoded}` 由端点层解；保持 rawBody 端点的原文回退语义。
76 合规：不涉及。

## [2026-11-16 22:25:10] C3-06 · network_phase.dart:1-115（全文件）· P1 · 网络阶段 tracker 零接线（死代码）

证据：
```
rg -n 'NetworkPhaseTracker|NetworkPhase\.' lib --glob '*.dart'
→ 仅 network_phase.dart 自身；bridge_core.dart / lib/session / lib/surface 均无 export/import/调用
```
问题：`NetworkPhaseTracker`（begin/end/reset/events）是一个设计完整的「网络阶段播报器」，注释称「>500ms 阶段必须可见」，但**全仓无任何 begin/end 调用、无 bridge 转出、无 UI 订阅**。因此：
- 用户等待网络时**没有统一阶段指示**（resolving/buffering 从不上报）；
- `detail` 字段注释「UI 不得直接展示」也无从消费；
- 与用户「转圈/没反馈」痛点直接相关——机制写了却没接。
建议：① 在 `bridge_core.dart` 经桥转出 `NetworkPhaseTracker.instance` 的 `events/current`；② 在 KugouClient.request 的缓存 miss/真实请求前后成对 `begin/end(resolving)`（try/finally）；③ L7 建模态指示器订阅 events 并节流（>500ms 才显示），符合 MD3 progress indicator 规范；④ 登出接 `reset()`。
76 合规：本文件自身守层（纯 Dart、无 flutter、try/catch+Log）；**问题在「跨桥未转出导致 L7 无法消费」——属 76 六桥通道未接通，非越级**。

---

## [2026-11-16 22:25:30] C3-07 · 全仓 lib/ · P1 · 文案从底层漏出：硬编码英文错误串经异常上抛到 UI（i18n 缺口）

证据（底层抛出的 message 均为英文硬编码，无 i18n key）：
- `kugou_client.dart:249,258` `'response header timeout (${ep.id})'` / `'response body timeout …'`
- `kugou_client.dart:261,269,286` `'http ${code}: $text'` / `'invalid json from ${ep.id}: …'` / `'unexpected response shape'`
- 上层把异常直接拼进可见 UI：`mv_page.dart:177 _fail(_Phase.error, 'MV 加载失败：$e')`、`player_page.dart:222 Text('FM 启动失败：$e')`、`login_sheet.dart:357 _toast('验证码登录失败：$e')`
- `strings.dart` 209 个 key 中**无任何 error/retry/timeout/network/failed 条目**（`rg -ni "'error|retry|timeout|failed'" → 0`）
问题：`KugouApiException.message`/`CryptoException.message` 是英文技术串（含 ep.id、截断 json、http code），一旦被 UI 用 `$e` 拼进 SnackBar/错误态，**用户看到「response body timeout (searchSong)」「invalid json from …」这类英文乱码**，正是用户「相关文案没改」痛点。底层无 key、上层无对应国际化条目。
建议：① 底层异常只带 `code`/结构化字段，message 仅供日志；② UI 错误态按 `code → strings.dart key` 映射（key 落 `lib/core/l10n/strings.dart` + 三语 arb），禁止 `$e` 直显；③ 补 `error.network/error.timeout/error.parse/error.server` 等 key。详见末尾《文案泄漏清单》。
76 合规：底层产英文技术串本身不违规；但**UI 直接显示底层 `$e`（mv_page/player_page/login_sheet）是 L7 违反「文案走 i18n」**——文案应经 L4 strings.dart key，不得硬编码拼接。

---
## [2026-11-16 22:25:50] C3-08 · crypto_aes.dart:564-585 · P0 · AES 密钥扩展 Rcon 恒定 0x01（密码学实现 bug，直接影响 YKG 兼容层可信度）

证据：
```dart
// crypto_aes.dart:570-575 _expandKey()
if (i % 16 == 0) {
  // RotWord + SubWord + Rcon
  final tmp = t0;
  t0 = _sbox[t1] ^ 0x01;   // ← Rcon 恒 0x01，未随轮次递增
  t1 = _sbox[t2];
  t2 = _sbox[t3];
  t3 = _sbox[tmp];
}
```
问题：AES-128 密钥扩展需 10 个 Rcon 值 `[0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]`（对应 `i/16 = 1..10`）。此处**每轮都异或 0x01**，仅第 1 轮正确，第 2–10 轮全部轮密钥错误。文件头 `:6-9` 声称的 FIPS-197 C.1 向量（key=`000102..0f` → `69c4e0d86a7b0430d8cdb78070b4c55a`）**无法通过**，且全仓无自测代码（`rg '69c4e0d8|self.?test' lib` 零命中）。该缺陷经 `AesCbc.encrypt/decrypt` 波及真实链路：`crypto_rsa.dart:119,138` 的 playlist AES、`auth_endpoints.dart:193,291,375,455-467` 的密码登录/sms/改密 AES。结论：**现有 AES 不能作为「成熟库之外的正确兼容层」**——它连标准向量都过不了，产出错误密文、解不开上游响应，用户侧歌单删除/密码登录等直接失败。（本条与 C2 子代理独立取证一致，构成交叉共识。）
建议：① 维护 `const _rcon=[…]`，`t0 = _sbox[t1] ^ _rcon[(i~/16)-1]`；② 必须补 FIPS-197 C.1 + NIST SP800-38A CBC 向量自测（离线回归）；③ 更优：按用户「成熟库」原则，AES/RSA 整体迁 `cryptography` 包，自研仅留 legacy 协议兼容。
76 合规：不涉及（实现层正确性问题，限 L4）。

## [2026-11-16 22:26:05] C3-09 · signing.dart:70-266 · P1 · md5Hex 正确性复核（可支撑 YKG 兼容字段 m）

证据（逐段核对 RFC 1321）：
- `_s` 64 个移位量、`_k` 64 个常量：与 RFC 1321 逐字一致（`:72-168`）；
- 填充 `hexBytes`：`data.add(0x80)` 后补零到 `%64==56`，末 8 字节 `bl = ml*8` 按小端写（`:171-180`）——**长度用原始字节数 ml，正确**；
- 四轮 F 函数：`i<16` `(b&c)|(~b&d)`；`i<32` `(d&b)|(~d&c)`；`i<48` `b^c^d`；else `c^(b|~d)`，与 RFC 一致（`:195-210`）；
- 轮转 `(f << s)|(f >>> (32-s))`：Dart `>>>` 无符号右移，正确（`:214`）；
- 输出 `le()` 按 4 字节小端 hex，正确（`:220-230`）。
问题：**未发现算法级 bug，md5Hex 可正确支撑 YKG 兼容字段 `m`**（`m = md5Hex(salt_b64+":"+password)`，见设计稿 §4）。但两点风险：① `bl = ml*8` 用 `int`（Dart VM 64 位无溢出，安全）；② 全仓无 MD5 已知向量自测（`"abc"→900150983cd24fb0d6963f7d28e17f72`），正确性仅靠人工核读，建议补离线断言。
建议：补 3 条 MD5 标准向量自测；MD5 仅用于酷狗签名与 YKG 兼容字段 `m`，**绝不做口令 KDF/放行判据**（设计稿 §4 已定此口径，正确）。
76 合规：不涉及。

## [2026-11-16 22:26:20] C3-10 · crypto_aes.dart:739-750 · P2 · AesCbc unpad 语义复核（除 Rcon 外本身正确）

证据：
```dart
// _pkcs7Pad(:739)：pad = 16-(len%16)，满块补 16，正确 PKCS7
// _pkcs7Unpad(:744-750)：
final pad = data[data.length - 1];
if (pad < 1 || pad > 16) throw CryptoException('bad pkcs7 pad: $pad');
for (var i = data.length - pad; i < data.length; i++)
  if (data[i] != pad) throw CryptoException('bad pkcs7 pad bytes');
return Uint8List.sublistView(data, 0, data.length - pad);
```
问题：unpad 逻辑本身正确（校验 pad 范围 + 逐字节一致，非恒定时间但本地解密无侧信道顾虑）。**注意**：`decrypt` 先校验 `ciphertext.length % 16 == 0`（:713），空/非对齐抛异常，正确。**唯一阻断性缺陷仍是 C3-08 的 Rcon**——轮密钥错会导致解密出的明文末字节随机，`_pkcs7Unpad` 抛 `bad pkcs7 pad`，表现为「解不开/功能失败」而非静默错数据（fail-closed，可接受）。
建议：修 Rcon 后补 unpad 边界测试（pad=1/pad=16/坏 pad）；不新增逻辑。
76 合规：不涉及。

## [2026-11-16 22:26:40] C3-11 · YKG 设计稿 vs 原生能力 · P1 · 「成熟库方案」遗漏项核对（复用 bA1_c3，不重做盘点）

证据（复用 `docs/deep_audit/bA1_c3.md:148-165` YKG 节 + 本批复核）：
- 设计稿 §8 方案 1 `cryptography:^2.x` / 方案 2 `crypto^3 + encrypt^5`——**pubspec.yaml 当前零密码学依赖**（`rg 'crypto|cryptography|encrypt|argon2|pointycastle' pubspec.yaml` 零命中），SDK `>=3.5.0 <4.0.0`（`pubspec.yaml:7`）；
- bA1_c3 已盘：原生 MD5✅/AES-CBC✅(但有 C3-08 bug)/RSA-encrypt✅/CSPRNG✅；HMAC❌/SHA-256❌/PBKDF2❌/URL-safe Base64❌；
- 设计稿 §8 明确「不自己写 GCM，用成熟库」——**方向正确**，但遗漏/需注意：
  1. **`cryptography`/`encrypt` 在 Dart 3.5 aarch64 的可用性需实测**：`cryptography` 依赖原生 `Crypto` 插件或纯 Dart 回退，本仓为 Flutter（`sdk:flutter`），可用；但 `encrypt:^5` 的 AES-GCM 在部分平台走 pointycastle 纯 Dart，性能/兼容需 CI 验证——设计稿未列「依赖可用性门禁」为待定项。
  2. **未提 `crypto` 包 `base64Url` 其实来自 `dart:convert`（SDK 内置）**：bA1_c3 已指出可直接用 `base64UrlEncode/Decode` 无填充，设计稿 §2 全程写 BASE64URL 但未点明零依赖即可实现，建议明确以减依赖。
  3. **§4 `m` 字段复用「现有自研 Md5」与设计稿 §8「YKG 兼容字段 m 也调这个成熟实现」措辞矛盾**：自研 Md5 不是「成熟实现」，建议措辞改为「复用既有自研 Md5（已由 C3-09 验证正确）作为 legacy 兼容，仅此一处保留自研」。
  4. **设计稿未覆盖 C3-08 的 AES bug 对 YKG 的影响**：YKG 用 AES-256-GCM（成熟库），不受自研 AES-CBC 的 Rcon bug 影响——**需在定稿中显式声明「YKG 不复用 AesCbc」**（设计稿 §3.2 已说不用，但与 §4「复用自研 md5」的口风格不一致，易被误接）。
问题：设计稿的「成熟库方案」总体正确且更大方向（GCM+PBKDF2+不复用 CBC）无误，但**遗漏依赖可用性门禁、base64Url 零依赖说明、以及措辞上把自研 MD5 误称「成熟实现」**；且需与 C3-08 结论对齐（自研 AES 不可信，YKG 必须走成熟库 GCM）。
建议：定稿补 ① 依赖在 Dart3.5/Flutter/aarch64 的 CI 可用性验证项；② 明确 base64Url 走 dart:convert；③ 修正 §4/§8 对自研 Md5 的措辞；④ 声明 YKG 严禁复用 `AesCbc`（Rcon bug）；⑤ 待定项 `it/exp/密码复用/多链接/二维码` 按设计稿 §9 决策。
76 合规：建议落位（L4 crypto 封装 + L5 编排 + L7 文案）符合 76；新增依赖须同步 `pubspec.yaml` + `tool/layer_audit.py` + `tool/smoke_check.dart` 白名单（设计稿 §7/§8 已列，正确）。

## [2026-11-16 22:27:00] C3-12 · YKG 密码学支撑结论（总判定）

1. **复用盘点**（继承 bA1_c3，不重做）：可用 MD5 / AES-CBC(有 bug) / RSA-encrypt / CSPRNG / 凭据素材(cookieBlob+token+mid+dfid)；缺 HMAC / SHA-256 / PBKDF2 / URL-safe Base64 / GCM。
2. **md5Hex 正确性**（C3-09）：RFC1321 逐段核对无误，可作为 YKG 兼容字段 `m` 与酷狗签名的 legacy 层；建议补标准向量自测。
3. **AesCbc 正确性**（C3-08）：**Rcon 恒定 0x01 是 P0 bug**，第 2–10 轮密钥全错、FIPS 向量不可过，**不可作为成熟库之外的正确兼容层**；必须修 Rcon + 自测，或整体迁成熟库。
4. **能否支撑 YKG**：**现状不能直接落地**——YKG 需 GCM+PBKDF2+HMAC+SHA256+URL-safe Base64，仓内均无；设计稿 §8 的「引 cryptography/encrypt 成熟库」路线**方向正确**，补齐 C3-11 的 4 项遗漏后即可作为落地输入。
5. 用户「成熟库封装」诉求：**当前实现是自研为主（MD5/AES/RSA 全手写）且 AES 有 bug，尚未满足**；按设计稿引入成熟库是唯一达标路径。

---
## [2026-11-16 22:27:20] C3-13 · cover_color.dart:13-56 + color_extract.dart:1-9 · P1 · 动态取色/封面加载全链无消费者（空白封面/主题不生效）

证据：
```dart
// cover_color.dart:13 fetchCoverBytes：取字节，失败返回 null（有 8s 超时/800KB 上限/try-catch+Log，降级本身健全）
// bridge_core.dart:44 export '../core/net/cover_color.dart' show fetchCoverBytes;  ← 仅 export
// color_extract.dart:4-9 注释自认：
//  「extractDominant / fromSeed 当前版本未被任何 UI 消费方调用
//    （原封面取色桥 cover_color_bridge.dart 已删除）」
// rg 'fetchCoverBytes' lib → 仅 bridge_core export + 自身定义，无调用点
```
问题：动态取色三层（取字节 `fetchCoverBytes` → 提主色 `color_extract` → 主题）**只完成前两层的实现，没有第三层消费者**：`fetchCoverBytes` 经桥导出但零调用，`extractDominant/fromSeed` 直接自认未被 UI 消费，取色桥已删除。结果：用户看不到任何动态主题效果（GAP #19 功能等于没做）。降级方面：`fetchCoverBytes` 本身失败返回 null 且 full try/catch + 8s timeout + 体积上限（`:46-51`），**有健全降级、不会崩**；但「没有消费者」意味着即使取到色也没用——空白/静态主题是必然，不是偶发降级失败。
建议：① 恢复经桥的取色链路或在 L7 主题控制器订阅封面变化调用 `fetchCoverBytes → extractDominant → fromSeed`；② 保持 L4 只出字节/纯算法（当前分层正确），UI 解码落 L7；③ 失败 null 时回退品牌紫 `#7C4DFF`（color_extract 已有 fallback），确保不空白。
76 合规：`cover_color.dart` 守层（dart:io，无 flutter，try/catch+Log），`color_extract.dart` 守层（纯 dart:math，经桥取 Log），**均合规**；问题是「桥已导出但上层未接」——76 六桥通道下游断点，非越级。

## [2026-11-16 22:27:35] C3-14 · endpoint_registry.dart:17,33,74,331 · P2 · 缓存开关默认值与端点实际语义错位（配合 C3-02）

证据：
```dart
// endpoint_registry.dart:17  this.cacheable = true,   ← 默认开缓存
// :32-33 「是否允许进入 L2 磁盘缓存（短时效 URL 类端点须显式 false）」
// :74 playUrlV5 cacheable:false；:331 anonymousSongUrl cacheable:false（已显式关）
```
问题：设计上「白名单式关缓存」依赖每个短时效端点都记得写 `cacheable:false`。目前仅 2 处显式关闭；`privilegeLite`、`songClimax`、`userCloud`、`fmPlay` 等时效/账号态敏感端点仍默认 7 天缓存（见 C3-02）。虽非崩溃，但用户数据陈旧且无刷新入口。
建议：默认值改为 `cacheable:false`，对真正静态端点（searchHot 等）显式开启白名单；或至少给所有账号态/时效端点补 `cacheable:false`。
76 合规：不涉及。

---

## 文案泄漏清单

> 判定口径：底层（L4 core/net）抛出的、会被上层拼进可见 UI 的硬编码串。**纯注释/docs 中的中文不计**（非用户可见）。

**A. 底层硬编码错误串（L4，assistant 英文技术串，会被 `$e` 带进 UI）**
| 文件:行 | 串 | 去向 |
|---|---|---|
| `kugou_client.dart:249` | `'response header timeout (${ep.id})'` | KugouApiException.message → UI `$e` |
| `kugou_client.dart:258` | `'response body timeout (${ep.id})'` | 同上 |
| `kugou_client.dart:261` | `'http ${code}: $text'` | 同上 |
| `kugou_client.dart:269` | `'invalid json from ${ep.id}: …'` | 同上 |
| `kugou_client.dart:286` | `'unexpected response shape'` | 同上 |
| `crypto_aes.dart:19` 等 | `CryptoException('bad pkcs7 pad…')` / `'aes key must be 16 bytes'` 等 | 端点解密失败 → UI |
| `network_phase.dart:81` | `'reset'`（detail，仅诊断，注释禁展示） | 低风险，非直接 UI |

**B. 上层把底层异常直显（L7 硬编码中文拼接，违反 i18n）**
| 文件:行 | 串 |
|---|---|
| `mv_page.dart:177` | `'MV 加载失败：$e'` |
| `player_page.dart:215` | `'FM 暂无可用曲目（端点待实测）'` |
| `player_page.dart:222` | `'FM 启动失败：$e'` |
| `login_sheet.dart:357` | `'验证码登录失败：$e'` |
| `login_sheet.dart:78,88` | `'已切换账号 $accountId'/'切换失败'/'已移除账号'/'移除失败'` |
| `login_sheet.dart:422,431` | `'请输入账号与密码'/'密码登录待后端就绪'` |
| `login_sheet.dart:185-215` | `'二维码获取失败，请重试'` 等多处 hint 硬编码 |
| `settings_page.dart:147` | `Text(msg)`（msg 由调用方硬编码传入） |

**C. i18n 缺口**：`strings.dart` 209 key 中 `error/retry/timeout/network/failed` 类 key **为 0**（`rg` 零命中）；YKG 相关文案（链接导入提示/密码输入/风险提示/有效期，见设计稿 §3.3/§5）**全仓零 key**。
**统计**：底层可漏出硬编码错误串 **7 处**（A 类），上层直显拼接硬编码 **≥12 处**（B 类，非本批主范围，仅记录供 A7/B7 交叉），i18n 缺口 **2 类**（错误态 key + YKG 文案 key 全缺）。
**建议**：本层只输出结构化错误码（不产文案）；L7 错误态统一走 `strings.dart` + 三语 arb 的 key，禁止 `$e` 直显；新增 `error.network/error.timeout/error.parse/error.server` 与 YKG 全套 key。
**76 合规**：底层产技术串不违规；L7 用 `$e` + 硬编码中文显示属**违反 76「文案走 i18n / 边界职责」**与 material-3 无障碍/文案规范。

---

## YKG 密码学支撑结论

- **成熟度判定：现状不满足「成熟库封装」。** 全仓 MD5/AES/RSA 均自研且**自研 AES 存在 P0 级 Rcon bug（C3-08）**，pubspec 零密码学依赖。
- **可复用**：`md5Hex`（C3-09 验证 RFC1321 正确）可作 YKG 兼容字段 `m`；CSPRNG `Random.secure()`；凭据素材现成（cookieBlob/token/mid/dfid）。
- **不可复用**：`AesCbc`（Rcon bug + CBC 无认证）；private Base64（拒绝 URL-safe）。
- **缺失需引入**：AES-256-GCM / PBKDF2-HMAC-SHA256 / SHA-256 / HMAC / URL-safe Base64（后者走 dart:convert 零依赖）。
- **设计稿判定**：`YKG_LINK_CRYPTO_DESIGN.md` §8「引 cryptography/encrypt 成熟库、不写 GCM、不复用 AesCbc」**方向正确**；但需补 4 项（依赖在 Dart3.5/aarch64 可用性门禁、base64Url 零依赖说明、修正「自研 MD5=成熟实现」措辞、声明 YKG 严禁复用 AesCbc），详见 C3-11。
- **落地建议**：定稿后按 L4 crypto 封装 / L5 编排 / L7 文案落位，同步 76 白名单；实现后补离线向量回归（往返/错密码/篡改/错 salt/过期必失败）。

---

## 本视角结论

1. **用户影响面问题 8 条**（C3-01~06 + C3-13~14，其中 P1×6）：超时最坏 ~40s 才报错且无重试/取消；缓存默认 7 天固化动态数据（业务错误 Map 也缓存）；单飞 `clear()` 竞态会误删新任务+统计 getter 未转出；业务错误码 20006/20028/200103 无统一错误码→文案映射（均为 API_TEST_REPORT 已知坑）；顶层非 Map 响应判 shape 错；`NetworkPhaseTracker` 全量死代码（机制写了没接）；动态取色三层只有前两层、无 UI 消费者；缓存开关默认值与时效语义错位。
2. **密码学 P0 1 条（C3-08）+ P1/P2 各 1 条**：`crypto_aes.dart:574` AES Rcon 恒 `0x01`，第 2–10 轮密钥全错、FIPS 向量不可过，波及 playlist/密码登录等真实链路；`md5Hex`（C3-09）逐段核对 RFC1321 无误可支撑 YKG `m`；`AesCbc unpad`（C3-10）本身正确、唯一阻断仍是 Rcon。
3. **YKG 密码学支撑结论**：现状不满足成熟库封装（全自研 + AES 有 bug）；设计稿成熟库路线方向正确但有 4 项遗漏需补（C3-11/12）。
4. **文案泄漏**：底层硬编码错误串 **7 处**、上层 `$e` 直显/硬编码 **≥12 处**（A7/B7 主范围，本批记录）、i18n 缺口 2 类（错误态 key + YKG 文案 key 全缺）。
5. **MD3**：本批 `core/net/` 全为纯 Dart，无 Color/shape/motion/Widget，**未混入 UI/动效关注点，MD3 十类均 N/A**；与用户 UI 痛点无直接交集（归 A7/B6）。
6. **交叉共识**：AES Rcon bug 与 C2 子代理独立同判，构成确认项，主会话修复优先级建议 P0。

## 未覆盖

1. `lib/core/net/endpoints/*.dart` 全部端点实现（A3 批范围）——仅通过 `endpoint_registry.dart` 声明与 API_TEST_REPORT 间接核对错误码，未逐个读端点封装的字段解析/错误分支。
2. `database_opener.dart`、`crypto_bigint.dart`、`crypto_rsa_raw.dart` 细节——仅扫中文串与关联引用，未逐行审算法（C2 覆盖正确性）。
3. A7 surface 全部 18 文件 + `lib/l10n/*.arb`——文案泄漏仅从底层与少量上层消费者侧取证，完整页面硬编码清单由 A7 子代理出；arb 与 strings.dart 键集逐一对齐未做。
4. `tool/layer_audit.py` / `tool/smoke_check.dart` 白名单——未读（禁跑门禁/只读源码），YKG 新增依赖的门禁登记仅按设计稿文字采信，未核验脚本现状。
5. MD5/AES 标准向量**未实际运行验证**（纪律禁跑 dart）——正确性结论为人工逐段核读，标注为「需离线自测确认」。
6. YKG 设计稿 §9 五个待定项（it/exp/密码复用/多链接/二维码）属产品决策，本视角未拍板。

## 76 合规小结

- **层归属正确**：`core/net/` 全部文件守 L4，纯 Dart、无 flutter import、无 UI/动效代码；`network_phase.dart`/`cover_color.dart`/`color_extract.dart` 均守「不 import flutter、try/catch+Log」铁律。
- **无越级/反向 import**：本批内未见 surface/session 反向依赖或影子桥；crypto_* 同层引用合法。
- **桥通道问题（非越级，是断点）**：① `NetworkPhaseTracker` 未从 `bridge_core.dart` 转出 → L7 无法订阅（C3-06）；② `fetchCoverBytes` 已转出但零消费者、取色桥已删除 → L7 取色链断（C3-13）。两处均为「桥下游未接通」，不违反依赖方向，但导致功能不可用。
- **文案越界**：L7 层 `mv_page/player_page/login_sheet` 用 `$e` + 硬编码中文显示错误，违反「文案走 i18n（`strings.dart`/arb）」边界（B 类清单）；本层建议只产结构化错误码。
- **成熟库边界（§0 第 9 条）**：全自研 MD5/AES/RSA 且 AES 有 bug，未「能用成熟库就用成熟库」——YKG 落地应按设计稿引入 `cryptography`/`encrypt`（C3-11/12）。
- **端点分文件（第 6 条）**：`core/net/endpoints/` 每端点一 dart 模块，符合；`endpoint_registry.dart` 为声明表（从 kugou_client 拆出控长），符合。
- **1500 行限制（第 5 条）**：本批最大 `crypto_aes.dart` 786 行、`endpoint_registry.dart` 503 行，均未超 1500。

---
*本报告由 A2-C3 子代理于 2026-11-16 只读审查生成，全部结论已实时 append 落盘；未改任何源码、未跑任何验证、未联网。*
