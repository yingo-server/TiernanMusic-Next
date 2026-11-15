# 批1-F2 · 三态字段捕获报告

时间：2026-11-15 · 依据：docs/six_b1_c1.md、six_b1_c2.md、six_b1_c3.md、docs/research_field_capture_3state.md、docs/batch5_live.md（不重新调研）。

> **F1 留样说明**：docs/api_samples_v2/ **不存在**（F1 未产出样本），本报告所有「实测三态值」均标 **实跑未覆盖**，不杜撰三态数据。判定基于 C1 代码核对 + 研究文档实测章节。

判定口径：**已修** = 当前代码已捕获且落点明确；**仍缺** = 代码未捕获、待后续批次；**未覆盖** = 无实测证据支撑判定。

## 1. play_url v5（play_endpoints.dart）

| 顶层键 | 三态是否可取 | 顶层键存在性 | 当前代码捕获 | 缺什么 | 判定 |
|---|---|---|---|---|---|
| url[] | 是（研究§1.1 实测三态响应；匿名 20028/31833 失败态无） | ✅ 22 键实测 | ✅ PlayResult.urls（play_endpoints.dart:96–105，兼容 List/String） | — | 已修 |
| backupUrl[] | 是 | ✅ | ✅ PlayResult.backupUrls（:106–117，与 urls 分开保留去重） | — | 已修 |
| bitRate | 是 | ✅ | ✅ PlayResult.bitrate（:134）→ PlaySource.bitrate；登录态选档按最大档优先 | 注意 flac 档实测 bitRate=0，代码无防御（A3-1 ⚠️） | 已修 |
| extName | 是 | ✅ | ✅ PlayResult.extName（:135）→ PlaySource.extName | — | 已修 |
| timeLength | 是 | ✅ | ✅ PlayResult.timeLengthSec（:136）→ PlaySource.timeLengthSec | 与 fileSize/end_ms=60000 试听交叉校验未接线（F3） | 已修 |
| hash_offset | 是（失败态/试听态含 clip_hash/offset_hash/end_ms=60000） | ✅ | ✅ `_PlayExtras.hashOffset` Expando 侧挂（:25–63、:171–186） | **无下游消费**：PlayResultExtras 仅 play_endpoints 自身 Log.d 打印，playback_service/play_models/播放器零引用；试听分片、断点续传未接线 | 已修（捕获）；消费归 F3 |
| end_byte | 是 | ✅ | ✅ `_PlayExtras.endByte` 同上侧挂 | 同上，无下游消费（end_byte>0 → isFreePart 标记未做） | 已修（捕获）；消费归 F3 |
| fail_process | 是 | ✅ | ✅ `_PlayExtras.failProcess` 同上侧挂 | 同上，无下游消费（风控处置未接线） | 已修（捕获）；消费归 F3 |
| q（服务端实际档位） | 是（22 键实测含 q） | ✅ | ❌ 无读取 | playback_service.dart:261 `quality: hits.first.quality` 仍按请求档回填，服务端降档不可感知（多档候选时 hits.first.quality 是降档重试的请求档） | **仍缺**（唯一已实测存在且语义关键却丢弃的键） |
| fileSize / fileName / fileHead / std_hash / std_hash_time / hash_token / hash_token_query | 是 | ✅ | ❌ | 全未捕获，仅 A3-1 留样；fileSize↔timeLength 交叉校验无输入 | 仍缺 |
| volume / volume_gain / volume_peak（响度均衡） | 是 | ✅ | ❌ | 播放器未做 gain 补偿 | 仍缺 |
| classmap / trans_param.qualitymap / auth_through[]（可用档位图） | 是 | ✅ | ❌ | 「最大权益 URL」决策关键输入被丢弃 | 仍缺 |
| tracker_through.musicpack_advance | 是 | ✅ | ✅ → isVipTrack | — | 已修 |
| status / priv_status / errcode | 是 | ✅ | ✅ privKnown 判缺；error_code=35104 兜底；privKnown 防匿名 priv_status 折叠 | — | 已修 |
| is_hash_backup / backupUrl 与 priv 关联 | 是 | ✅ | ❌ | 备链是否低权益未记录 | 仍缺 |

三态实跑值（q、hash_offset、end_byte、fail_process 按 vip/nonvip/anon 分别留样）：**实跑未覆盖**（api_samples_v2/ 不存在），F3 三态跑 play_url 时按态记录四键再固化解析。

**C1 结论登记**（必含）：
1. urls/backupUrls/bitRate/extName/timeLength 已落点 ✅。
2. hash_offset/end_byte/fail_process 已 Expando 侧挂但**无下游消费**（F3 处理）。
3. 响应 q / fileSize / volume / classmap **仍未捕获**。
4. PlaySource.quality 按请求档回填（hits.first.quality），非响应 q。

## 2. 搜索 /v3/search/song（SongBrief.fromSearchList，item 57 键）

| 字段 | 三态是否可取 | 当前代码捕获 | 缺什么 | 判定 |
|---|---|---|---|---|
| FileName/SingerName/FileHash/FileSize/ExtName/Duration/Bitrate/AlbumID/AlbumName/MixSongID/Audioid/Image/AlbumImage/Singers/HQ/SQ/Res/trans_param.musicpack_advance/isVip | 是 | ✅ 已捕获 | — | 已修 |
| mvdata[].hash（歌曲侧 MV 入口） | 是 | ❌ | MV 页需另查接口浪费一次请求 | **仍缺（待批2）** |
| HQ/SQ/Res 档位 hash（音质预判） | 是 | ❌ | 本可免一次 privilege 查询 | **仍缺（待批2）** |
| OriSongName/OtherName/PublishDate/PayType/HeatLevel/ogg_* 直链 hash 等 | 是 | ❌ | 其余 ~13 键丢弃 | 仍缺（待批2） |

三态差异表：**实跑未覆盖**。

## 3. 评论（comment_endpoints.dart）

| 字段 | 三态是否可取 | 当前代码捕获 | 缺什么 | 判定 |
|---|---|---|---|---|
| like.count | 是 | ✅（:62–65） | — | 已修 |
| reply_num（楼中楼数） | 是 | ❌ | 未解析 | **仍缺（待批3）** |
| addtime（格式化字符串） | 是 | ❌ 不解析 → CommentItem.timeMs 恒 0 | 需字符串→时间戳解析 | **仍缺（待批3）** |
| haslike / likenum / user_id / hot_word_list[].count | 是 | ❌ | 未解析 | 仍缺（待批3） |
| CommentItem.floor 的 floo/floor 键 | 无实测章节 | ❌ 恒 0 | 无实测证据，不臆造 | 未覆盖 |

三态样本仅 vip 态留样（comment_music/comment_count）；anon/nonvip 差异：**实跑未覆盖**。

## 4. 收藏（collect_endpoints.dart / playlist_write_endpoints.dart）

| 字段 | 三态是否可取 | 当前代码捕获 | 缺什么 | 判定 |
|---|---|---|---|---|
| 加歌回执 fileid | 是（写端点禁调匿名态，匿名=20010） | ✅（:140–150，audio_id 兜底） | — | 已修 |
| 加歌回执 name/cover/hash 回显 | 是 | ❌ 只取 fileid | 本地镜像校验缺 | **仍缺（待批4）** |
| mget_collect per-song 收藏态（mixsongid 级 count） | 是 | ❌ 仅求和 | 无法判断「是否已收藏」 | **仍缺（待批4）** |
| list_ver 乐观并发 | 是 | ⚠️ 写端点默认传 0 | 未用实测递增值 | 仍缺（待批4） |

三态差异：**实跑未覆盖**（写端点仓库侧禁写，仅键名级证据）。

## 5. MV 域（mv_endpoints.dart）

| 字段 | 三态是否可取 | 当前代码捕获 | 缺什么 | 判定 |
|---|---|---|---|---|
| getMvBySong 基础项（video_id/mv_name/singername/duration/hdpic/thumb） | 是 | ✅（:40–63） | — | 已修 |
| getMvBySong hit/play_times/is_recommend/publish_time/desc 等 20+ 键 | 是 | ❌ | 未解析 | **仍缺（待批2）** |
| videoDetail 各档 bitrate/width/height、audio_hash | 是 | ❌ MvQuality.fromFlat 仅取 hash/filesize | 档位清晰度/音轨缺失 | 仍缺（待批2） |
| videoUrl privileges{hash:0/1}（MV 无权限信号） | 是 | ❌ | 权限判断缺 | 仍缺（待批2） |
| 档位契约错位：getVideoQualities body={hash} vs 实测 data:[{video_id}]+show_resolution=1（§4.4） | 是（实测文档） | ❌ 主路径恒空 | 需按实测契约改请求体，并与 getMvBySong/歌曲侧 mvdata[].hash 打通 | **仍缺（契约错位，待批2）** |

三态样本仅 vip 态（mv_by_song）：**实跑未覆盖**。

## 6. 其余端点（C1 范围外，登记不展开）

歌词 candidates id safeInt 溢出风险、playlist_write `_ok()` s==0 判成功：是否已被后续批次修复未核对代码 → **未覆盖**。歌单 tracks/rank_audio/userDetail 等字段维持研究文档原状，未逐一核代码 → 未覆盖。

## 7. 汇总

- **已修**：play_url 8 键落点（urls/backupUrls/bitRate/extName/timeLength + extras 三键侧挂）+ status/priv_status/errcode/isVipTrack。
- **仍缺（明确登记，不冒充完成）**：搜索 mvdata/HQ-SQ-Res hash（待批2）；评论 reply_num/addtime 等（待批3）；收藏回显/per-song 态/list_ver（待批4）；MV 档位契约错位（待批2）；play_url 响应 q/fileSize/volume/classmap。
- **实跑未覆盖**：F1 未产出 docs/api_samples_v2/，全部三态差异值留空待 F3 补测（q、hash_offset、end_byte、fail_process 四键按 vip/nonvip/anon 分别记录）。
