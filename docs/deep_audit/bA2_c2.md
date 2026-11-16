# A2 批 · C2 实现正确性专项审查

> 视角：C2 实现正确性（空安全、状态机、失败/空结果、缓存失效、异步竞态、字段解析、密码学、异常吞没、死代码、功能可达性）
> 审查对象：A2 批 L4 core·net 底座 + endpoints/models*.dart
> 纪律：只读审查，禁止改源码/跑分析器/联网；证据必须带文件:行。
> 权威契约：docs/DEEP_AUDIT_14_BATCH_PLAN.md（§1 76 原则 / §3 C2 视角 / §8 落盘格式）

---
## [2026-11-16 22:22:15] C2 · crypto_aes.dart:574 · P0 · 密码学实现错误（AES 密钥扩展 Rcon 固定）
证据：
```dart
// _expandKey, line 570-575
if (i % 16 == 0) {
  // RotWord + SubWord + Rcon
  final tmp = t0;
  t0 = _sbox[t1] ^ 0x01;   // ← Rcon 恒为 0x01
  t1 = _sbox[t2];
  t2 = _sbox[t3];
  t3 = _sbox[tmp];
}
```
问题：AES-128 密钥扩展需 10 个 Rcon 常量 [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]，对应 i/16=1..10。此处恒用 0x01，仅第 1 轮正确，第 2~10 轮轮密钥全错。文件头声称的 FIPS-197 C.1 测试向量（key=000102..0f → 69c4e0d8..）根本无法通过（除非自测未真正执行）。该实现被 AesCbc.encrypt/decrypt 用于 playlist AES、delete_list 等真实端点，产生错误密文/解不开上游响应，功能直接失败。
建议：维护 `const _rcon=[0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]`，用 `t0 = _sbox[t1] ^ _rcon[(i~/16)-1]`；并以 FIPS-197 C.1 与 NIST SP800-38A CBC 向量做真实自测。
76 合规：不违反（L4 纯算法）；但注释声称的测试锚点未落实，属实现正确性 P0。

## [2026-11-16 22:22:15] C2 · crypto_bigint.dart:82 · P0 · 密码学实现错误（32-bit limb 乘法溢出）
证据：
```dart
// BigIntL.mul, line 80-84
for (var j = 0; j < o.limbs.length; j++) {
  final t = r[i + j] + limbs[i] * o.limbs[j] + carry;  // ← 溢出
  r[i + j] = t & 0xffffffff;
  carry = t >>> 32;
}
```
问题：limbs[i]、o.limbs[j] 均为 32-bit（最高 0xffffffff）。`0xffffffff * 0xffffffff ≈ 2^64`，再加 r[i+j]+carry 超过 Dart int 有符号 64 位上限（2^63-1），结果 wrap 成负数/错误值。RSA 1024-bit 的 modPow 中 base=base.mul(base) 时两操作数高位 limb 均接近模数（首字节 0xc0…），从第 2 次平方起结果即错，`rsaEncrypt2`/`RsaRaw.encryptHex` 输出错误密文。注释「Dart int 64 位：拆高 32」误解——t 本身已溢出，拆位无意义。
建议：改用 16-bit limb（乘积≤2^32，加进位仍在 int64 内），或用 Dart 内置 `BigInt` 直接实现 modPow（成熟原语优先，符合 76 §0.9）。
76 合规：不违反层归属；纯算法实现正确性 P0。

## [2026-11-16 22:22:15] C2 · inflight.dart:62 · P1 · 异步竞态（clear 与 finally remove 键碰撞）
证据：
```dart
// run()
_pending[key] = future;                 // 新任务登记
// _execute finally:
_pending.remove(key);                    // 无身份校验
// clear():
_pending.clear();
```
问题：注释（inflight.dart 文件头第 14 行）已自认此缺陷但标「本版不改」。场景：A 请求 key=K 进行中 → clear() 清空表（如换号）→ B 请求 key=K 启动并登记 `_pending[K]=fB` → A 完成，其 finally 执行 `_pending.remove(K)`，把 B 仍在飞行的 fB 条目误删。此后 C 请求同 key 不再合并，重复发真实请求；统计 coalesced 失真。属并发丢条目/单飞失效。
建议：finally 中仅当 `_pending[key] === 本次 future` 才 remove（`identical` 判定），或给每次任务带唯一 token；clear 后旧任务不应再操作新表。
76 合规：不违反（L4 纯逻辑，有桥 Log）。
---
## [2026-11-16 22:26:00] C2 · kugou_client.dart:135-143 · P1 · 缓存键降级碰撞（cacheKey 失败回退过粗）
证据：
```dart
// _cacheKeyOf catch 分支, line 141-143
} catch (e, st) {
  Log.e('core.net', 'cacheKey build failed', e, st);
  return '${ep.method} ${ep.path}';
}
```
问题：正常键含 method+base+path+排序 query+body+raw+uid+tk+dfid+mid 全套维度（line 131-139），catch 后降级为仅 method+path。一旦 `_stable()`/`md5Hex()` 因任一异常字段触发（如 jsonEncode 遇到循环引用/特殊 Object），所有同 method+path 但不同参数/不同用户的请求塌缩成同一缓存键 → 跨用户、跨参数脏命中；且该脏条目按 7 天 TTL 固化。降级应失败即禁用缓存，而非退化为高风险宽键。
建议：catch 中返回一个带随机/时间戳唯一后缀的键（等价本次不命中不复用），或直接让 request 侧 `cacheable=false` 跳过缓存；绝不能收敛到公共键。
76 合规：不违反层归属（L4）。

## [2026-11-16 22:26:00] C2 · kugou_client.dart:108-115 · P1 · 缓存失效语义（业务失败被当成功固化 7 天）
证据：
```dart
// request(), line 106-115
final res = _inflight == null ? await run() : await _inflight!.run(cacheKey, run);
if (cacheable) {
  try { await _cache!.putJson(cacheKey, res); } ...
}
```
问题：缓存判定仅 `ep.cacheable && _cache!=null && rawBody==null`（line 94），完全不检查响应 `res` 的业务状态。酷狗大量端点 HTTP 200 + 业务失败（status!=1 / error_code / 空 lists），此类响应同样被 putJson 落盘；`getJson(cacheKey)` 未传 per-entry ttl（line 97），走 ResourceCache 全局默认 7 天（resource_cache.dart:69）。后果：一次偶发限流/风控失败（如临时 20006）被固化 7 天，换号也难自愈（uid 相同场景）。历史「失败固化」bug 语义仍未消除。
建议：仅当响应被判定为成功（端点级 status==1 或含有效 data）才落缓存；失败响应跳过写入，或传短 TTL（分钟级）；为可缓存端点配置合理 per-entry ttl。
76 合规：不违反层归属；实现正确性 P1。

## [2026-11-16 22:26:00] C2 · kugou_client.dart:205-222 · P2 · 请求体 Content-Type 与实际编码不符
证据：
```dart
// _requestRaw, line 205-210
if (bodyStr.isNotEmpty) {
  req.headers.contentType = ContentType.json;   // ← 恒声明 application/json
  req.write(bodyStr);
}
```
问题：rawBody 端点（如 delete_list 的 AES Base64 密文、加密 arraybuffer 载荷）bodyStr 非 JSON，却统一设置 `ContentType.json`。若上游按 content-type 解析将失败；与注释「data 为字符串时直接发送」的契约不自洽。尤其 registerDevice/smsLogin 等加密 body 端点受影响。
建议：rawBody!=null 时用 `ContentType.binary`/`text/plain` 或按端点显式配置 content-type；仅 jsonEncode 的 body 用 application/json。
76 合规：不违反。

## [2026-11-16 22:26:00] C2 · cover_color.dart:35-40 · P2 · 响应体流无整体超时（悬挂隐患）
证据：
```dart
await for (final chunk in resp) {
  bytes.addAll(chunk);
  if (bytes.length > maxBytes) { ... return null; }
}
```
问题：getUrl/close 有 timeout，但 `await for` 读取 body 流无 timeout；服务器建连后涓流式发送（每次 <maxBytes 且永不结束）会让 fetchCoverBytes 永久悬挂，动态取色流程卡死。与 kugou_client 已修的「body join timeout」同类问题此处遗漏。另：`bytes.addAll(chunk)` 逐字节追加到大 List 性能差，且超限判断在追加后（瞬时可能写到 >maxBytes+chunk）。
建议：对 body 流整体包一层 `.timeout(timeout)`；用 `BytesBuilder`/预分配累加并在加入前判断剩余容量。
76 合规：不违反。

## [2026-11-16 22:26:00] C2 · kugou_client.dart:30-44 · P2 · dfid 生成不满足「随机」契约（确定性伪随机）
证据：
```dart
final rnd = DateTime.now().microsecondsSinceEpoch;
_dfid = String.fromCharCodes(List.generate(24,
  (i) => chars.codeUnitAt((rnd >> (i % 31)) % chars.length)));
```
问题：注释明确要求 play_url v5「随机 24 位 dfid」，实测恒 '-' 会 20028。此处用时间戳右移派生，`i%31` 使第 31 位后字符由 0 位移产生规律重复，且仅 63 位熵（微秒时间戳），并非真正随机字符串。同一时刻构造的多个 KugouSession dfid 可能相同，风控场景下有被识别风险。属契约偏离（非阻断，能取到不同值）。
建议：用 Random.secure() 生成 24 位（与 crypto_rsa 一致复用安全随机）。
76 合规：不违反。
---
## [2026-11-16 22:28:00] C2 · network_phase.dart + kugou_client.dart · P2 · 可观测性断点（网络阶段与实际请求脱节）
证据：
```dart
// kugou_client.dart 全文无 NetworkPhaseTracker/begin/end 引用；
// network_phase.dart 仅为独立 tracker，靠调用方手动 begin/end 配对。
```
问题：NetworkPhaseTracker 定义完整（idle/resolving/buffering、深度计数 clamp、broadcast、try/catch+Log、reset），但 L4 网络底座 KugouClient.request/\_requestRaw 完全未接入：真正耗时 15s 的请求期间无 resolving 阶段播报。「>500ms 网络阶段必须可见」的目标在本批范围内无单一事实源落地，依赖上层（L5/L6）自行配对——一旦上层漏配 end 或异常路径无 finally，阶段永久停留。本批内无法验证配对完整性。
建议：由 client 在请求开始/结束（含异常 finally）统一 begin/end resolving；或明确该职责归 L5/L6 并在契约中标注，避免双层都不做。
76 合规：network_phase 自身不违反（L4 纯 Dart，桥日志齐全）；但职责落点在层间悬空。

## [2026-11-16 22:28:00] C2 · cache_service.dart:110-120 · P2 · 异常吞没导致三态坍缩
证据：
```dart
// CacheService.get catch
} catch (e, st) {
  _errors++;
  Log.e(_tag, 'get failed ep=${ep.id}', e, st);
  return <String, dynamic>{};
}
```
问题：网络失败（KugouApiException -2/-3/HTTP）被吞成空 Map，与「业务真返回空数据」在返回值上不可区分。上层 logic 只能拿到空 Map，无法呈现「错误态/重试」而会误判为「空结果态」。虽有 Log 留痕（满足 76 §0 桥铁律），但丢失了错误分类信息（client 刚建立的 -2/-3/HTTP 分类在此被抹平）。
建议：门面改返回 Result/Search 三态封装，或抛特定异常由 L5 捕获；至少把 KugouApiException.code 透传给上层（如塞入特殊键），保留错误分类。
76 合规：不违反层归属/桥日志；属失败路径可观测性 P2。

## [2026-11-16 22:28:00] C2 · models_util.dart:57-65 · P2 · dataOf 对数组形态 data 静默返回空（类型契约坑）
证据：
```dart
// dataOf
final d = root['data'];
if (d is Map<String, dynamic>) return d;
if (d is Map) return d.map(...);
return const <String, dynamic>{};   // ← data 为 List 时静默空
```
问题：searchSuggest 实测 data 为数组分组（search_endpoints.dart:97-100 注释承认），dataOf 对其返回空 map。当前 searchSuggest 靠 `listOf(res['data'])` 绕过，但其它调用 dataOf 的端点若遇数组 data 会静默拿到空结果、无 Log、无异常——属字段解析容错盲区（值与类型混淆：真 Map 空 vs 非 Map 都返回同一空常量）。
建议：dataOf 遇 List 时 Log.w 提示形态异常（或提供 dataListOf 明确返回列表），让调用方感知形态漂移而非静默空。
76 合规：不违反。

## [2026-11-16 22:28:00] C2 · models_util.dart:9-13 · P2 · safe* 工具的 null/缺字段折叠（0 与 null 碰撞通用风险）
证据：
```dart
int safeInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;   // null / 缺字段 / 类型不符 → 0
}
```
问题：safeInt/safeStr/safeDouble/safeBool 统一把缺失/null/类型不符折叠为单一默认值（0/''/0.0/false），丢失「字段缺失」与「值为 0」的区分。play_endpoints 对 priv_status 已用 `privKnown = containsKey && !=null`（line 273）手动补救，证明该碰撞真实存在；但这是逐调用点补丁，非工具层契约。任何新增字段（如 translation id=0、status=0 的合法值）若漏配 containsKey 即误判。
建议：工具层增设「可空/已知」版本（如 safeIntOrNull）或对关键 id/status/priv 字段强制配合 containsKey 判定；在 models_util 注释中把「0≠缺字段」列为使用规约。
76 合规：不违反。

## [2026-11-16 22:28:00] C2 · signing.dart（全局）· 合规确认（非缺陷）
证据：对照 docs/KUGOU_API.md §1.2/1.3/1.4/1.5/1.6：
- android：`md5(salt + 排序k=v无分隔 + body + salt)` ✓（signing.dart:30-42）
- web：`md5(webSalt + 排序k=v片段拼接 + webSalt)` ✓（:47-51）
- register：`md5('1014' + 排序value + '1014')` ✓（:56-59）
- playKey/signParamsKey 盐与拼接顺序 ✓（:64-80）
- MD5（Md5.hexBytes）为标准 RFC1321，F/g/轮移/K/小端输出均正确。
- srcappid：kugou_client 默认不注入、includeSrcappid 开关默认 false（client:172-174；registry 无端点启用）→ 历史 20006 bug 已修复。
结论：签名注入与算法本视角判为**正确**，无 P0/P1 缺陷（故不计入发现数）。
76 合规：不违反。

## 本视角结论
1. **两处 P0 密码学硬缺陷**：AES 密钥扩展 Rcon 恒 0x01（crypto_aes.dart:574）+ BigIntL.mul 32-bit 相乘溢出 int64（crypto_bigint.dart:82），二者独立且连带——即使修 Rcon，RSA 模幂仍因乘法溢出全错。直接影响 playlist 加/删歌、delete_list、register_dev、smsLogin 等全部加密端点，属功能级阻断。
2. **inflight clear 竞态 P1**（inflight.dart:62）：finally 无身份校验 remove，换号/clear 后可误删他人进行中条目，单飞失效（文件注释已自认未改）。
3. **缓存失效语义 P1×2**：业务失败响应被当成功固化 7 天（kugou_client.dart:108-115，未传 per-entry ttl）；cacheKey 构造异常降级为 method+path 粗键导致跨用户脏命中（:135-143）。历史「失败固化」bug 未根除。
4. **可观测性/解析容错 P2 组**：body 流无超时（cover_color）、异常吞没抹平错误分类（cache_service）、dataOf 数组静默空、safe* 0/null 碰撞、请求路径未接 network_phase、rawBody Content-Type 误标、dfid 非真随机。
5. **签名与请求三分类正确**：KugouSign 各算法与上游契约一致，srcappid 默认不注入已修；HTTP/超时(-2)/解析(-3) 三分类清晰、整体+body 双 15s 超时到位——这部分实现质量良好。
6. **models.dart 为纯 export 桶、crypto_extra.dart 为纯 re-export**，无逻辑，无缺陷；端点声明（endpoint_registry）大量「待实测」注释诚实标注，未发现臆造字段。

## 未覆盖
- 允许只读扩展的 `docs/api_samples/*.json`（anonymous/nonvip/vip/summary）未逐字段比对端点解析——属 A3 endpoints 范围，本视角仅核了 models_util/play/search 的解析逻辑。
- 未验证 AES/RSA 算法的实际运行输出（工具纪律禁止跑 dart/test），Rcon 与 mul 溢出为静态推导，需主会话修复后用 FIPS-197/SP800-38A 向量实测确认。
- 未逐条核验 endpoint_registry 全部 60+ 端点路径/参数的真实可用性（大量标注「待三态实测」，属 A3 与阶段 B 范围）。
- translation_models / song_models / play_models 等具体 fromJson 未逐行审（不在 A2 授权范围，仅 models.dart/models_util.dart 在列）。
- 未核验 KugouSession.cookies 生命周期与 dfid 回写缓存的调用链（在 logic/session 层）。

## 76 合规小结
- 层归属：本批全部文件位于 L4 core·net（传输/缓存/纯算法/声明配置），无 surface/logic/session 越级 import；`models.dart`/`crypto_extra.dart` 为同层 export 桶，合法。
- 桥与日志：inflight.clear、network_phase.begin/end/_push、cover_color、database_opener、cache_service 均有 try/catch + Log 留痕，符合 §0 铁律 2。crypto_aes/encrypt/decrypt 的 catch 用裸 `Log.e`（非桥函数内），但 crypto 位于桥下 L4，铁律主要约束桥层，此处可接受。
- 桥唯一目录：本批无影子桥；database_opener.dart 已按审计更名去掉「bridge」字样（文件头注释说明），合规。
- 职责边界：唯一瑕疵是 network_phase 网络阶段播报在 L4 client 中未接线、落点层间悬空（P2，非硬性越级）。
- 端点分文件：endpoint_registry.dart（声明）与 endpoints/*.dart（封装）分离，符合铁律 6；单文件均 <1500 行（最大 endpoint_registry 503 行）。
