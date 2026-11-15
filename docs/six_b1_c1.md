# 批1-C1「现有端点字段捕获缺口收口」核对（只读，实时落盘）

时间：2026-11-15 · 依据：docs/research_field_capture_3state.md、docs/batch5_live.md、lib/core/net/endpoints/play_endpoints.dart（另以 rg 核对 playback_service.dart / play_models.dart 消费情况）

## ① play_url 22 顶层键 → urls/backupUrls/bitRate/extName/timeLength/hash_offset/end_byte/fail_process 落点

| 键 | 落点 | 状态 |
|---|---|---|
| url[] | PlayResult.urls（play_endpoints.dart:96–105，兼容 List/String） | ✅ 已修（此前已捕获） |
| backupUrl[] | PlayResult.backupUrls（:106–117，与 urls 分开保留） | ✅ 已修 |
| bitRate | PlayResult.bitrate（:134）→ PlaySource.bitrate | ✅ 已修 |
| extName | PlayResult.extName（:135）→ PlaySource.extName | ✅ 已修 |
| timeLength | PlayResult.timeLengthSec（:136）→ PlaySource.timeLengthSec | ✅ 已修 |
| hash_offset | `_PlayExtras.hashOffset` + Expando 侧挂（:25–63、attach :171–186） | ✅ 已捕获（仅 L4 捕获，下游未消费） |
| end_byte | `_PlayExtras.endByte` 同上 | ✅ 已捕获（仅 L4 捕获，下游未消费） |
| fail_process | `_PlayExtras.failProcess` 同上 | ✅ 已捕获（仅 L4 捕获，下游未消费） |

三键消费现状：`PlayResultExtras`（hashOffset/endByte/failProcess）目前**仅被 play_endpoints.dart 自身的 Log.d 打印**（:189–194），playback_service.dart / play_models.dart / 播放器均无引用——试听分片（timeLength/end_ms=60000 交叉校验）、断点续传、风控处置均未接线。属「已捕获、未消费」。

另：研究文档 §1.1 所列其余丢弃键（q、fileSize/fileName/fileHead/std_hash*/hash_token*、volume*、classmap/trans_param.qualitymap/auth_through[]）本次核对 play_endpoints.dart 当前代码仍无读取，**仍未捕获**。特别是 `q`（服务端实际档位）：playback_service.dart:261 `quality: hits.first.quality` 仍是请求档回填，服务端降档不可感知（若有多档候选时 hits.first.quality 是降档重试的请求档，非响应 q，两者口径可能不一致）。

## ② 搜索 / 评论 / 收藏 / MV 仍被丢弃的实测字段

- **搜索**（SongBrief.fromSearchList，item 57 键）：仍丢 mvdata[].hash（歌曲侧 MV 入口）、HQ/SQ/Res 档位 hash（可免一次 privilege 查询做音质预判）、OriSongName/OtherName/PublishDate/PayType/HeatLevel/ogg_* 直链 hash 等。
- **评论**：仍丢 haslike、likenum、reply_num（楼中楼数）、addtime（不解析→timeMs 恒 0）、user_id、hot_word_list[].count；CommentItem.floor 的 floo/floor 键无实测章节恒 0。
- **收藏**：加歌回执只取 fileid，name/cover/hash 回显仍丢（本地镜像校验缺）；per-song 收藏态（mget_collect 的 mixsongid 级 count）仍丢；list_ver 乐观并发仍未用实测递增值。
- **MV**：getMvBySong 仍丢 hit/play_times/is_recommend/publish_time/desc 等 20+ 键；videoDetail 仍丢各档 bitrate/width/height、audio_hash；videoUrl 仍丢 privileges（MV 无权限信号）与 filesize。§4.4 契约错位（getVideoQualities body={hash} vs 实测 data:[{video_id}]）按文档仍是主路径恒空。

## ③ 已修 / 仍缺 清单

**已修**（batch5_live.md + 代码核对一致）：
- urls/backupUrls 分开解析去重、bitRate/extName/timeLength 落 PlayResult+PlaySource ✅
- hash_offset/end_byte/fail_process 三键侧挂捕获 ✅（PlayResultExtras 扩展）
- errcode 兼容顶层 error_code=35104；privKnown 防匿名 priv_status 折叠 ✅
- 登录态选档降级链 _qualityCandidates（最多降 2 档）、bitRate 最大档优先、backupUrls 顺序归并兜底 ✅
- 全档无出链不冒充成功；20028/31833/priv 0/35104 相关错误映射分类（35104 单列与否以 _mapError 现状为准，batch5_live 称已分类收口）✅

**仍缺**（未修，按研究文档 §1.1/§4）：
- 响应 `q` 未捕获，PlaySource.quality 仍为请求档回填 → 服务端降档不可感知
- extras 三键无下游消费（无试听分片/断点/风控接线）
- fileSize/fileName/fileHead/std_hash/hash_token/volume 响应均衡/classmap/trans_param.qualitymap/auth_through 全未捕获
- 搜索 mvdata/HQ/SQ/Res hash、评论 reply_num/haslike/addtime、收藏回显字段、MV 档位打通——均维持文档原状
- 歌词 id safeInt 溢出风险、playlist_write `_ok()` s==0 判成功（若已另行修复不在本次三份文件证据内，按「未覆盖」标注）

## F1 / F3 可直接执行的 3 条结论

1. **F1（字段捕获）**：play_endpoints.dart 解析处补 `q`（res['q']）捕获并回填 PlaySource.quality（hits.first.quality 改为「响应 q ?? 请求档」），这是 22 键中唯一「已实测存在且语义关键」却仍丢弃的键；顺带把 fileSize/timeLength 交叉校验留给 F3。
2. **F1（消费接线）**：hash_offset/end_byte/fail_process 已侧挂在 PlayResultExtras，F1 无需新增捕获，只需在 playback_service 或 L5 读取 `result.hashOffset`/`endByte`：end_byte>0 或 hashOffset>0 → 标记 isFreePart 试听段（覆盖 IsFreePart 请求标志的误判，A3-1）。
3. **F3（三态实测前置）**：extras 三键与 `q` 的实际值均未留样（batch5_live「未覆盖」自认），F3 三态跑 play_url 时按 vip/nonvip/anon 分别记录 q、hash_offset、end_byte、fail_process 四键到 api_samples，再固化解析——不臆造默认值。

## 未覆盖

- 歌词/歌单 tracks/rank_audio/userDetail 等其余端点字段（任务范围仅 play_url + 搜索/评论/收藏/MV 文档核对）；`_ok()` s==0 与歌词 id 溢出是否已被后续批次修复未核对代码（未覆盖）；三态运行时验证未跑（任务禁止）。
