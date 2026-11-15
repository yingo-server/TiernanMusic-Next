# 批5「按登录态选权益最大 URL」收口复核（实时）

时间：2026-11-15 · 复核对象仅 2 文件：play_endpoints.dart / playback_service.dart

## 1. play_url 解析字段核对 — 已落盘 ✅
- urls / backupUrls：分别解析（res['url'] / res['backupUrl']，兼容 List/String），不混写 ✅
- bitRate / extName / timeLength → PlayResult.bitrate / extName / timeLengthSec ✅
- hash_offset / end_byte / fail_process：经 `_PlayExtras` + Expando + `PlayResultExtras` 扩展侧挂，不破坏 models.dart 既有构造（可选字段默认 null）✅
- errcode 兼容顶层 error_code=35104（批N2-A）✅；privKnown 防匿名 priv_status 缺失被折叠为 0 ✅
- 结论：**已落盘，无需修改**

## 2. resolvePlaySource 登录态选档 — 已落盘 ✅
- 可选 session 注入（vip_token/vip_type，Map 或对象，容错探测异常落 Log.e）✅
- `_qualityCandidates`：有权益从 flac 起，无权益从请求档向下，`sublist(start).take(3)` = 降级最多 2 次 ✅
- 公开签名 `resolvePlaySource(SongBrief, String)` 未变，可选参不破坏现构造 ✅
- 结论：**已落盘，无需修改**

## 3. 优先 bitRate 最大者 + backupUrls 顺序兜底 — 已落盘 ✅
- hits 按 `b.pr.bitrate.compareTo(a.pr.bitrate)` 降序；主链 = 最高 bitRate 档 urls，其余档 urls 续接；backupUrls 按 hits 顺序归并；addAll 去重且不混写 ✅
- 结论：**已落盘，无需修改**

## 4. priv_status=0 且无 url 不冒充成功 — 已落盘 ✅
- 全档无出链（hits.isEmpty）→ `_mapError` 返回语义错误，返回 `PlaySource(error: …)`（ok=false）✅
- `_mapError`：20028→needsVerification；31833→network（不落 notFound）；status=2 且 privKnown 且 priv=0→noPrivilege；VIP 曲无 URL→noPrivilege；status=2 且 !privKnown 无 url→needsVerification；兜底 notFound ✅
- 终态提前收口：20028 / noPrivilege 直接 break，不空降档 ✅
- 结论：**已落盘，无需修改**

## 5. PlaySource/PlayResult 构造兼容 — 已落盘 ✅
- PlaySource 仅加可选 backupUrls/isFallback，默认值不破坏现构造；PlayResult/privKnown 由 play_models.dart 默认值保证（未改该文件，仅核对）✅
- 结论：**已落盘，无需修改**

## 语法自检
- `dart format --output=none` 首轮报 2 changed → 就地 format 一次 → 复查 `--set-exit-if-changed` exit=0 ✅（仅包解析 warning：flutter_lints 未装，属环境，非语法错误）

## 未覆盖（不补齐，按任务要求）
- 「待三态实测」：匿名/VIP/非VIP 三态真实响应、hash_offset/end_byte/fail_process 实际值、未实测端点均维持注释标注，未臆造。
- 三态运行时验证、CI/全门禁：未跑（任务禁止）。
