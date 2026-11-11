# API_FIELDS_TRUTH — 网络层字段实证（批N1 · A1+A2，2026-11-12；批N2-C 补 A3，2026-11-12）

> 探针：`.test_creds/n1c_probe.py` / `n1c_probe2.py`（复刻 lib/core/net/signing.dart android 签名，
> 直连 gateway.kugou.com）；批N2-C 补测 `.test_creds/n2c_probe.py` / `n2c_playurl_final.json`。全部字段为**实测响应逐键留样**，非文档推断。
> 每键值样例见 `.test_creds/n1c_probe_out.json` / `n1c_probe_out2.json`。
> 回归锚点：`tool/field_truth_test.dart`（纯 Dart，全过输出 FIELD-TRUTH-OK）。
> 探针脚本自带 A1 五类+recommend 复跑（`import n1c_probe` 即触发），无关输出可忽略。

## 通用响应形态
- 搜索/榜单系：`{ status:1, error_code:0, error_msg:'', data:{...} }`
- 歌单 recommend/detail/tracks：同上；`data` 内分页键 page/pagesize/total（搜索）或 count（tracks）。
- complex v6（complexsearch.kugou.com）：**实测不可达**（HTTP 502 三连，2026-11-12），
  字段不固化、不猜——维持 search_typed_endpoints.dart 的三路容错。

## A1 · 搜索系（x-router complexsearch.kugou.com）

### A1-1 · /v3/search/song（已实测，锚点定稿）
- 列表：`data.lists[]`；total：`data.total`；另有 page/pagesize/size/correctiontype 等。
- item 键（57 个，样例值）：
  `FileName`="周杰伦 - 发如雪"、`SingerName`="周杰伦"、`OriSongName`、`OtherName`、`Suffix`、`Auxiliary`、
  `FileHash`="1F7E7659B9FFF4FB6F71562A61BBC25F"（大写）、`FileSize`=4789176、`ExtName`="mp3"、
  `Duration`=299（**秒**）、`Bitrate`=128、`PublishAge`=255、`AlbumID`="958909"（**字符串**）、
  `AlbumName`、`MixSongID`="32029513"（**字符串**）、`Audioid`=339589、`Scid`=339589、
  `AlbumPrivilege`、`PayType`、`FailProcess`、`IsOriginal`、`PublishDate`、`TagContent`、`RankId`、
  `Accompany`、`HeatLevel`、`Image`（{size} 模板 URL）、`AlbumImage`、`Singers`=[{name,id,ip_id}]、
  `HQ`/`SQ`/`Res`={Hash,FileSize,Privilege,...}、`mvdata`=[{typ,hash,id,trk}]、
  `trans_param`={musicpack_advance(=1→VIP),language,union_cover,ogg_*_hash/ filesize,cid,hash_offset,...}、
  `bitflag`、`version`、`Grp`。
- ⚠️ **无 `AlbumAudioId` 键**——音频 id 在 `Audioid`（=Scid）。`SongBrief.fromSearchList` 已修：
  AlbumAudioId→album_audio_id→Audioid 三级兜底。
- ⚠️ `MixSongID`/`AlbumID` 实测为字符串，safeInt/safeStr 已兼容。

### A1-2 · /v1/search/special（歌单搜索）
- 列表：`data.lists[]`（另有 theme/correction* 键）。
- item 键（32 个）：`specialid`、`specialname`、`img`（⚠️ 非 imgurl/pic）、`intro`、`play_count`（⚠️ 下划线）、
  `song_count`（⚠️ 非 count）、`collect_count`、`nickname`、`suid`、`publish_time`、`grade`/`grade_float`/`grade_int`、
  `isvip`、`isugc`、`ispublish`、`high_quality`、`quality`/`quality_new`、`tag_str`、`abtags`、
  `contain`、`gid`、`nper`、`srid`、`total_play_count`、`trans_param`、`version` 等。
- `PlaylistBrief.fromMap` 已修：cover 加 `img` 兜底；trackCount 加 `song_count`；playCount 加 `play_count`。

### A1-3 · /v1/search/album（专辑搜索）
- 列表：`data.lists[]`。
- item 键（41 个）：`albumid`、`albumname`、`title`、`singer`、`singerid`、`singerids`、`singers`、
  `img`、`publish_time`、`songcount`、`play_count`/`play_times`、`collect_count`、`company`、`intro`/`short_intro`、
  `grade`/`grade_float`/`grade_int`、`privilege`、`language`、`category`、`isfirst`、`isouter`、`newquality`、
  `rec_tag`、`special_tag`、`tag_str`、`trans_param` 等。
- ⚠️ 无 AlbumBrief 强类型模型（批N2 补，键集以此为准）。

### A1-4 · /v1/search/author（歌手搜索）
- 列表：`data.lists[]`。
- item 键（19 个，**大写驼峰**）：`AuthorId`、`AuthorName`、`Avatar`、`AlbumCount`、`AudioCount`、
  `FansNum`、`Heat`、`Identity`、`IsReal`、`IsSettledAuthor`、`UserId`、`VideoCount`、`ComposerCount`、
  `LyricistCount`、`ComplexSongName`、`FirstFrameImage`、`AuthorStatus`、`Auxiliary`、`AlgPath`。
- ⚠️ 无 AuthorBrief 模型（批N2 补）。

### A1-5 · /v1/search/mv（MV 搜索）
- 列表：`data.lists[]`（另有 aggregation/kuwalists/kuwatotal/istag 键）。
- item 键（44 个）：`MvID`、`MvName`、`MvHash`、`MvHot`、`MvType`、`MvTrac`、`MvHashMark`、
  `FileName`、`FileHash`、`FileSize`、`Bitrate`、`Duration`、`ExtName`、`Pic`、`ThumbGif`、`ThumbMp4`、
  `SingerName`、`SingerID`、`Singers`、`MixSongID`、`Scid`、`AlbumID`、`AudioID`、`AudioCdn`、
  `IsOfficial`、`IsNew`、`IsUgc`、`Isshort`、`PublishDate`、`PublishAge`、`Remark`、`Description`、
  `Privilege`、`Userid`、`Username`、`goods_info` 等。
- ⚠️ 无 MvBrief 模型（批N2 补）。

### A1-6 · /v1/search/lyric（歌词搜索）
- 列表：`data.lists[]`。
- item 键（50 个）：`LyricID`、`Lyric`、`FullLyric`、`SongName`、`SingerName`、`SingerID`、`Singers`、
  `FileHash`、`FileName`、`FileSize`、`BitRate`、`TimeLength`、`AlbumID`、`MixSongID`、`Scid`、
  `320Hash`/`320Size`/`320Privilege`、`SQHash`/`SQSize`/`SQPrivilege`、`HQ`、`Res`、`MvHash`、`HasMv`、
  `Image`、`PayType`、`Privilege`、`Quality`、`Weight`、`vvid` 等。

### A1-7 · /v6/search/complex（综合搜索）
- **实测不可达**（gateway 与 complexsearch 直连均 502/非 JSON，2026-11-12 三连失败）。
- 不固化字段；代码维持 lists[]/info[]/顶层三路容错（search_typed_endpoints.dart）。
- 待批N2 网络低峰复测。

## A2 · 歌单/榜单系

### A2-1 · /v2/special_recommend（推荐歌单，POST，x-router specialrec.service.kugou.com）
- 列表：`data.special_list[]`；另有 has_next/refresh_time/session/show_time/alg_id/bi_biz。
- item 键（29 个）：`global_collection_id`="collection_1_486950678_2255477_0"、`specialid`=2255477、
  `specialname`、`imgurl`（{size} 模板）、`pic`、`flexible_cover`、`intro`、`play_count`、`percount`、
  `nickname`、`singername`（创建者艺名，通常空）、`suid`、`slid`、`tags`（**字符串数组**）、
  `collectcount`、`collectType`、`publishtime`、`sync`、`type`、`show`、`from`/`from_hash`/`from_tag`、
  `bz_status`、`ugc_talent_review`、`trans_param`、`report_info`、`list_info_trans_param`、`alg_path`、`abtags`。
- 请求体（实测通过）：appid/mid/clientver + special_recommend{categoryid,withtag,withsong,sort,ugc,
  is_selected,withrecommend,area_code} + page/pagesize/module_id=1/platform=android/clienttime(秒串)/
  userid/key=signParamsKey/req_multi=1/retrun_min=5/return_special_falg=1。

### A2-2 · /v3/get_list_info（歌单详情，POST，x-router pubsongs.kugou.com）
- 请求体：`{ data:[{global_collection_id}], userid, token }`。
- 响应：`data[]`（**数组**）首项，键（47 个）：
  `global_collection_id`、`specialid`、`name`（⚠️ 非 specialname）、`pic`（⚠️ 非 imgurl）、
  `intro`、`count`=23（曲目数）、`tags`="英语,兴奋,运动"（⚠️ **逗号分隔字符串**）、
  `musiclib_tags`=[{tag_id,parent_id,tag_name}]、`list_create_username`（⚠️ 非 username）、
  `list_create_userid`、`list_create_listid`、`list_create_gid`、`listid`、`status`、`list_ver`、
  `publish_date`、`create_time`、`update_time`、`collect_total`、`heat`、`is_pri`/`is_publish`/`is_featured`/
  `is_drop`/`is_def`/`is_edit`/`is_mine`/`is_per`/`is_custom_pic`、`create_user_pic`、`create_user_gender`、
  `pub_type`、`source`、`sort`、`type`、`number`、`per_count`/`per_num`、`parent_global_collection_id`、
  `trans_param`、`plist`(空)、`kq_talent`、`sound_quality`、`radio_id`、`musiclib_id`、`code`。
- ⚠️ **无 playcount 键**——`PlaylistDetail.playCount` 保持 0（真实字段不存在，不映射）。
- playlist_endpoints.playlistDetail 已修：name/pic/list_create_username + tags 三形态兼容。

### A2-3 · /pubsongs/v2/get_other_list_file_nofilt（歌单曲目，GET）
- 请求参数：specialid（⚠️ 必须 specialid，global_collection_id 报 20010）/begin_idx/pagesize/area_code=1/
  plat=1/type=1/mode=1/personal_switch=1/extend_fields=abtags,hot_cmt,popularization。
- 响应：`data.songs[]` + `data.count`（+begin_idx/pagesize/list_info/userid/popularization）。
- song 键（41 个）：`hash`（大写）、`name`、`singerinfo`=[{name,id,avatar,publish,type}]（⚠️ 无 singername 平铺）、
  `album_id`（字符串）、`albuminfo`={name,id,publish}（⚠️ 键是 **name**，非 album_name）、
  `mixsongid`、`audio_id`、`timelen`=213133（⚠️ **毫秒**，非秒）、`bitrate`、`size`（⚠️ 非 filesize）、
  `extname`、`fileid`、`cover`、`privilege`=10、`mvdata`/`mvhash`/`mvtrack`/`mvtype`、
  `language`、`bpm`/`bpm_type`、`feetype`、`level`、`heat`、`sort`、`collecttime`、`publish_date`、
  `add_mixsongid`、`audio_group_id`、`brief`、`csong`、`download`、`has_obbligato`、`media_old_cpy`、
  `medistype`、`rcflag`、`relate_goods`、`remark`、`singerinfo`、`tagmap`、`trans_param`、`user_id`。
- SongBrief.fromTrackInfo 已修：timelen(ms>100000→÷1000)/size/singerinfo[]全量「、」聚合/albuminfo.name/
  songname 兜底/audio_id→albumAudioId。

### A2-4 · /ocean/v6/rank/list + /ocean/v6/rank/info（排行榜）
- rank/list：`data.info[]` + total/show_line/theme/timestamp。
  item 键（41 个）：`rankid`、`rankname`、`imgurl`、`img_9`、`img_cover`、`intro`、`rank_cid`、
  `ranktype`、`classify`、`update_frequency`（"每天更新"）、`update_frequency_type`、
  ⚠️ **无 updatetime 键**（旧映射 updatetime 恒空，已加 rank_id_publish_date/update_frequency 兜底）、
  `issue`（期号）、`haschildren`/`children`、`bannerurl`/`banner_9`/`banner7url`、`play_times`、
  `songinfo`、`jump_url`/`jump_title`、`is_city_rank`/`is_timing`/`isvol`、`new_cycle`、`zone`、
  `share_bg`/`share_logo`、`table_plaque`、`custom_type`、`extra`、`count_down` 等。
- rank/info（参数 rankid/rank_cid=0/with_album_img=1/zone=''）：`data` 平铺榜单元信息 +
  `data.songinfo[]` ⚠️ **仅 3 字段**：`album_audio_id`、`album_cover`、`songname`（如
  `{"album_audio_id":968734427,"album_cover":"http://…jpg","songname":"村口吴老二 - 慌啥子嘛"}`）。
  无 hash/mixsongid/duration——fromTrackInfo 已加 songname 兜底，hash 等如实为 0/空。

## 模型映射修正清单（本批落地）
| 位置 | 修正 |
|---|---|
| models.dart SongBrief.fromSearchList | albumAudioId 加 Audioid 兜底（v3/song 无 AlbumAudioId 键） |
| models.dart SongBrief.fromTrackInfo | timelen 毫秒→秒（>100000 判定）；size 键；singerinfo[] 全量聚合；albuminfo.name；songname 兜底；audio_id→albumAudioId |
| models.dart PlaylistBrief.fromMap | cover 加 pic/img；trackCount 加 song_count；playCount 加 play_count；creator 加 list_create_username |
| models.dart RankBrief.fromMap | updateTime 加 update_frequency 兜底（info[] 无 updatetime） |
| playlist_endpoints.dart playlistDetail | name/pic/list_create_username 实测键 + tags 逗号字符串/List 双形态 + playCount play_count 兜底 |
| playlist_endpoints.dart recommendPlaylists | 注释按 A2-1 实测键集更新 |

## 遗留（不猜，待批N2）
- /v6/search/complex 实测不可达（502）——三路容错维持原样。
- Album/Author/Mv 搜索项无强类型模型：AlbumBrief/AuthorBrief/MvBrief 键集已在 §A1-3/4/5 固化。
- fromTrackInfo 未映射 albuminfo.id（albumId 已有顶层 album_id，两处一致实测=981208）。

---

# 批N2-C · A3 三端点收口实测（2026-11-12，探针 n2c_probe.py / n2c_playurl_final.json）

## A3-1 · play_url v5（/v5/url，x-router trackercdn.kugou.com）

### ★ 关键实测修正：key 盐是 `57ae12eb6890223e355ccfcb74edf70d`
- key = md5(hash + `57ae12eb6890223e355ccfcb74edf70d` + appid + mid + userid||0)。
- 负对照：错盐 `57ae12ebac930836ebac6f064f95b046`（docs 旧口径）→ `status=0, error="illegal key"`
  （errcode 31833），恒拒绝。**与 lib/core/net/signing.dart `signKeySalt` 一致，Dart 实现正确。**
- key 拼接顺序：hash、盐、appid（'1005'）、mid、userid（匿名/无登录态为 '0'）。三变体
  （clientver=11430/20489、dfid=随机24位/'-'）均 status=1 出 URL；502 为网关风控抖动，幂等 GET 重试可过。

### 三态矩阵（非 VIP 曲 hash=d613ca5d…（羽泉·深呼吸，实为 musicpack_advance=1 曲目）与 VIP 曲 b3a52a7a…（晴天））
| 态 | 结果 |
|---|---|
| 匿名（无 cookie/token） | status=2, errcode=20028「本次请求需要验证」，顶层仅 errcode/error/fail_process:[pkg]/status，无 priv_status |
| 非VIP（musicpack_advance=1 曲目） | status=2, **priv_status=0**，无 url；顶层有 tracker_through.musicpack_advance=1、hash_offset（试听 clip_hash/offset_hash/end_ms=60000）、fail_process |
| VIP | status=1, priv_status=1, url[]（2 条，host fsandroid.kugou.com）+ backupUrl[]；128→bitRate=128000/extName=mp3；320→320000/mp3；flac→**bitRate=0/extName=flac**（flac 档 bitRate 恒 0，不可用 bitrate 判档） |
| VIP 曲 VIP 号 | 同 VIP 出 URL（timeLength=269 秒） |

- 成功响应**顶层即数据**（22 键）：`url[]`/`backupUrl[]`/`bitRate`/`extName`/`timeLength`(秒)/
  `status`/`priv_status`/`hash`/`std_hash`/`std_hash_time`/`fileHead`/`fileName`/`fileSize`/
  `hash_token`/`hash_token_query`/`q`(档位)/`volume`/`volume_gain`/`volume_peak`/`classmap`/
  `tracker_through{musicpack_advance}`/`trans_param{qualitymap,ogg_*,union_cover,...}`/`auth_through[]`。
- ⚠️ `IsFreePart=1` 实测 VIP 曲 VIP 号仍回全长（timeLength=269 与不传一致）——试听判定仍以
  实际返回 timeLength/hash_offset 为准（与 FINDINGS.md §10 一致）。
- ⚠️ 匿名请求连非 VIP 曲也 20028：play_url 必须登录态（token+userid+cookie t1），
  与 2026-11-10 FINDINGS.md 矩阵一致。权限判定唯一可信源 status/priv_status。

## A3-2 · 歌词 search + download（lyrics.kugou.com，网关 + x-router: lyrics.kugou.com）

- **直连 lyrics.kugou.com 恒返回空体（HTTP 200 + 0 字节）**——必须走
  `gateway.kugou.com` + 头 `x-router: lyrics.kugou.com`（GET /v1/search 与 /download 同）。
- 请求：android 签名 + 默认参数（dfid/mid/uuid/appid/clientver/clienttime）；
  /v1/search 参数 hash/keyword/duration/album_audio_id/lrctxt=1/man=no；
  /download 参数 ver=1/client=android/id/accesskey/fmt/charset=utf8。
- **search 响应顶层即数据**（非 {status:1,data:...} 包层）：`status`(HTTP 状态码复用，
  200=OK；404=未命中，仍返回结构)、`candidates[]`、`info`、`keyword`（服务端纠正后的关键词，
  实测回「周杰伦 - 晴天」）、`proposal`、`has_complete_right`、`companys`、`ugc/ugccount`、
  `ugccandidates[]`、`artists[]`、`ai_candidates[]`、`errcode/errmsg`。
- candidates[] item 键（25 个）：`id`（**字符串**，如 "167469123"）、`download_id`（字符串，同 id）、
  `accesskey`（大写 hex）、`product_from`（"ugc"/"官方推荐歌词"）、`singer`、`song`、`duration`（毫秒）、
  `uid`/`nickname`/`origiuid`/`transuid`/`transname`/`sounduid`/`soundname`、`language`、
  `krctype`、`contenttype`（0=krc）、`content_format`、`can_score`、`score`、`adjust`、
  `hitlayer`/`hitcasemask`、`parinfo`/`parinfoExt`。
- 匿名/非VIP/VIP 三态均返回 candidates（歌词不校验登录态）；VIP 曲命中官方轨
  （hitlayer=1，product_from=官方推荐歌词），匿名命中 UGC 轨。
- **download 响应顶层**：`status=200`、`info="OK"`、`error_code=0`、`fmt="krc"`、
  `contenttype=0`、`content`(base64 krc 密文)、`_source="bss"`、`charset`、`id`。
- krc 解密链复测通过：base64 → 去 4 字节魔数 → XOR 16 字节密钥表 → zlib inflate → utf8
  （VIP 轨 8405B/68 行，UGC 轨 6629B/59 行；样例落盘 n2c_krc_sample.txt）。
- ⚠️ **Dart 侧修正**：`kugou_client.dart` lyricSearch/lyricDownload 声明改走 gateway + x-router
  （原 base=lyrics.kugou.com 直连恒空）。候选 id 是字符串，safeInt 已兼容。
- 翻译轨：krc 内嵌（transuid/transname 字段在候选中标识译文轨作者），无独立翻译端点
  （与 ENDPOINT_TRUTH §6 一致，维持本地内嵌轨抽取）。

## A3-3 · 相似歌单（POST /pubsongs/v1/kmr_get_similar_lists，gateway 无 x-router）

- 请求 body（实测通过，全参不缺参）：`appid/clientver/clienttime(秒)/key=signParamsKey(秒)/
  userid/ugc=1/show_list=1/need_songs=1/data:[{global_collection_id}]`。
  ⚠️ key 盐是 `Or2onSUDL9kpyMys0NsMqDcYC0NVvEIf`（signParams 专用盐），公式
  md5(排序 'k=v' 拼接 of {appid,clientver,clienttime,mid})，**不是** Dart `signParamsKey()`
  的 md5(appid+OIlwieks28dk2k092lksi2UIkp+clientver+clienttime)——两种公式实测均 status=1
  （body 同入 android 签名，key 仅 body 内容校验），维持 Dart 现公式即可。
- 响应：`data` **直接是数组**（40 项），无包层。item 键（2 个）：
  `collection_list[]`（相似歌单数组）+ `tag_info[]`。
- `tag_info[]`：`[{tag_id:"20", tag_name:"英语"},...]`（**数组**，与歌单详情的逗号字符串不同形态）。
- `collection_list[]` item 键（22 个）：`collection_id`("9443893")、`cloudlist_id`("15")、
  `global_collection_id`("collection_3_1210326444_15_0")、`collection_name`、`cover`（完整 URL）、
  `flexible_cover`（{size} 模板）、`intro`、`heat`("286" 字符串)、`song_count`(52 int)、
  `percount`、`publish_date`、`type`("0")、`is_publish`("1")、`is_recommend`、`special_tag`、
  `sync`、`user_id`/`user_name`/`user_avatar`/`user_is_verified`、`ugc_talent_info`、`trans_param`、
  `songs[]`（need_songs=1 时内嵌，实测 8 首）。
- `songs[]` item 键（8 个）：`hash`(大写)、`name`（含 .mp3 后缀）、`mixsongid`(int)、
  `cover`、`privilege`(10)、`level`(1)、`sort`(0)、`trans_param{musicpack_advance,...}`。
  ⚠️ 无 duration/album_audio_id——SimilarSong 如需时长需二次查询，不映射不猜。
- ⚠️ **Dart 侧修正**：album_endpoints.getSimilarPlaylists 原取
  `data.lists/list/info/similar/data`——实测列表路径是 `data[].collection_list[]`（双层），
  已改为平铺 collection_list 并映射 PlaylistBrief（songs 内嵌曲目丢弃，不猜字段）。

## 批N2-C 代码修正清单（本批落地）
| 位置 | 修正 |
|---|---|
| kugou_client.dart lyricSearch/lyricDownload | base 改 gateway + x-router lyrics.kugou.com（直连恒空体） |
| album_endpoints.dart getSimilarPlaylists | body 补 appid/clientver/clienttime/key/userid/ugc/show_list/need_songs；解析 data[].collection_list[] 双层平铺 |
| models.dart SongBrief.fromSearchList | （A3 无涉，维持 N1 修正） |
| play_endpoints.dart | key 由 KugouClient.encryptKey 生成，盐 signKeySalt 已实测正确，无需改 |

## 批N2-C 未竟（如实标注，不猜）
- artist_audios/artist_albums（A4，N2-B 502 未测成）——批N2-B 补测后确认真实路径
  /kmr/v1/audio_group/author（kg-tid 220，body 带 key）与 /kmr/v1/author/albums（kg-tid 36）
  均实测 status=1（字段树见 .test_creds/n2b_raw.json 补测），端点封装在批N3 收口时统一接线。
- /v6/search/complex 维持「实测不可达」结论（上游模块本身 152，见 N1-A FINDINGS §5）。

## A3 · 播放/歌词域（批N2-A · 2026-11-12 实测，gateway.kugou.com + lyrics.kugou.com 三态）

> 探针：`.test_creds/n2a_probe.py`（play_url/privilege_lite 签名直连）+ 内嵌 lyrics.kugou.com
> 签名版请求。留样：`n2a_search_full.json` / `n2a_download_krc.json` / `n2a_download_lrc.json` /
> `n2a_krc_plain.txt` / `n2a_lrc_plain.txt` / `n2a_playurl_{vip,nonvip,anon}.json` /
> `n2a_privilege_lite.json`。样曲：晴天 hash `b3a52a7a958bf0aed0ebfba2e9a818b7`（VIP 曲，
> album_audio_id 339589，cid 2456863）。

### A3-1 · /v5/url（play_url，x-router trackercdn.kugou.com，GET + encryptKey）
- 必带参数（缺一即失败）：`hash`(小写) + `key` = md5(hash + `57ae12eb6890223e355ccfcb74edf70d`
  + appid + mid + userid||0)（signKey 公式复核 KuGouMusicApi util/helper.js，实测验证）+
  token/userid 参数 + Cookie（含 t1）。
  本次实测参数集：hash/album_audio_id/album_id/quality=128/area_code=1/behavior=play/
  ssa_flag=is_fromtrack/version=11430/clientver=11430/page_id/ppage_id/pid=2/cmd=26/
  pidversion=3001/cdnBackup=1。
- **成功响应顶层即数据**（无 data 包层，与 FINDINGS.md §1 一致，本次逐键固化）：
  `hash`、`status`(1=出URL)、`priv_status`(1=有权限)、`volume`=-10.8、`is_hash_backup`=1、
  `backupUrl`=[1个]、`url`=[主链]、`tracker_through`={identity_block,cpy_grade=5,
  musicpack_advance=1(VIP曲),all_quality_free,cpy_level}、`trans_param`={pay_block_tpl,
  classmap,language,cpy_attr0,display=32,display_rate,cpy_map,qualitymap{bits,attr0,attr1},
  is_original,flags,ogg_128_hash/filesize,ogg_320_hash/filesize,hash_multitrack,ipmap,union_cover}、
  `fileHead`=0、`auth_through`=[]、`volume_peak`=0.2、`bitRate`=128000（**bps**）、
  `timeLength`=269（**秒**）、`q`=0、`fileName`="晴天"、`extName`="mp3"、`fileSize`=4317292。
- 三态行为（VIP 曲）：
  - VIP：status=1 priv_status=1，url+backupUrl 各 1 条（fsmobile.tx.kugou.com，约5分钟有效期）。
  - 非VIP：**status=0，error_code=35104 "Hash not found"，error="Hash not found"**（⚠️
    与 2026-11-10 记录的 priv_status=0 不同——本次带 key 后错误形态变为 35104；
    顶层还有 quality_degradable/trans_param/tracker_through）。
  - 匿名：status=2，errcode=20028「本次请求需要验证」，顶层键仅
    errcode/error/fail_process=["pkg"]/status。
  - 权限判定以 status==1 && priv_status==1 && url 非空为准。
- 回归锚点样例（VIP 成功态）已存 `n2a_playurl_vip.json`。

### A3-2 · /v2/get_res_privilege/lite（privilege_lite，POST，x-router media.store.kugou.com）
- body（实测通过，来自上游 privilege_lite.js 结构）：`{appid:'1005', area_code:1,
  behavior:'play', clientver:'20489', need_hash_offset:1, relate:1, support_verify:1,
  resource:[{type:'audio', page_id:0, hash, album_id:0}],
  qualities:['128','320','flac','high','viper_atmos','viper_tape','viper_clear','super','multitrack']}`。
  ⚠️ resource 必须是 **{type,page_id,hash,album_id} 对象数组**（裸 hash 字符串数组 → 20010
  "param error, len resource:0"；旧记录「body 只需带 appid/clientver」不完整）。
- 响应：`{appid_group, data[], error_code, message, should_cache, status}`；status=1 error_code=0。
- data[0] 键（49 个）：`type`="audio"、`id`=20505418、`album_id`="0"、`recommend_album_id`、
  `album_audio_id`=32100650（⚠️ 与搜索侧 339589 不同源，勿互混）、`hash`(大写)、`name`、
  `singername`、`albumname`、`level`=2、`quality`="128"、`expire`=0、`publish`/`is_publish`=1、
  `old_hide`=1、**`privilege`=10（int 标量，与 FINDINGS.md §10 一致：三态同值，不用于权限判定）**、
  `status`=0、`fail_process`=12、`pay_type`=3、`price`=200、`pkg_price`=1、`topic_url`/`topic_remark`、
  `start_time`/`end_time`="0000-00-00"、`cd_url`、`cid`=2456863、`old_cpy`、`rebuy_pay_type`、
  `is_search_top`、`pay_block_text`、`is_separate`、`buy_count*`(4键)、`_msg`/`_errno`、
  `info`={bitrate,duration,extname,filesize,flag,image,imgsize,intro}、
  `popup`={btn_name,btn_url_android,btn_url_ios,content,redirect_url_h5,title}、
  `trans_param`={...musicpack_advance,ogg_*,hash_offset,cpy_*...}、`relate_goods`[]。
- 502 风控抖动：/v2/privilege_lite 路径不存在（502），正确路径为
  /v2/get_res_privilege/lite（与 kugou_client.dart EndpointRegistry.privilegeLite 一致）。

### A3-3 · lyrics.kugou.com/v1/search（歌词搜索，GET）
- ⚠️ **重大实测修正（推翻 KUGOU_API.md §3.1「不签名」记载）**：直接裸 GET 一律返回
  HTTP 200 + **空 body**（0 字节，无状态码线索，UA/头组合均试过无效）。
  必须按 **android 签名 + 显式 dfid 请求头** 发送：params {album_audio_id, appid:'1005',
  clientver:'20489', duration, hash(小写), keyword, lrctxt:1, man:'no'} 签名 android（无 body），
  headers dfid=随机24位/mid/uuid='-'/clienttime/kg-*。
- 成功语义：`status`=200（**不是 1**）、`errcode`=200、`info`="OK"（PARITY_NOTES 语义正确）。
- 顶层键：status/info/errcode/errmsg/keyword/proposal/has_complete_right/companys/
  ugc/ugccount/expire=7200/candidates[]/ai_candidates[]/ugccandidates[]。
- candidates[0] 键（27 个）：`id`="274944371"（**字符串**）、`product_from`="官方推荐歌词"、
  `accesskey`（大写MD5）、`can_score`=false、`singer`、`song`、`duration`=269792（**毫秒**）、
  `uid`、`nickname`、`origiuid`/`transuid`/`sounduid`、`originame`/`transname`/`soundname`、
  `parinfo`=[]、`parinfoExt`=[]、`language`="国语"、`krctype`=1、`hitlayer`=1、`hitcasemask`=111、
  `adjust`=30、`score`=60、`contenttype`=0（0=krc）、`content_format`=1、`download_id`。
- ⚠️ `id`/`uid`/`download_id` 实测为字符串——safeInt 可容错但建议 safeStr 透传。

### A3-4 · lyrics.kugou.com/download（歌词下载，GET，同样需 android 签名 + dfid 头）
- params：{ver:1, client:'android', id, accesskey, fmt:'krc'|'lrc', charset:'utf8'}，android 签名。
- 响应键：`status`=200、`info`="OK"、`error_code`=0、`fmt`、`contenttype`、`_source`="bss"、
  `charset`（krc 时空串；lrc 时 "utf8"）、`id`、`content`（base64）。
- contenttype：**0=krc（加密）**，1=lrc（明文 base64）。fmt=lrc 请求同一 id/ak 成功返回 lrc。

### A3-5 · krc 解密（本地，misc_endpoints.krcDecode 复核）
- 魔数实测：b64 解码后前 4 字节 = `6b726331` = "krc1"（跳过），随后异或
  `[64,71,97,119,94,50,116,71,81,54,49,45,206,210,110,105]` 16 字节循环，zlib inflate → utf8。
  本次实测 4192 字节密文 → 8405 字符明文，krcDecode 算法逐字节验证正确。
- krc 明文结构：`[ti:][ar:][al:][by:][offset:]` 头 + 行 `[start_ms,dur_ms]<s,e,0>字<s,e,0>字…`
  （逐字卡拉 OK 时间轴，毫秒）。**晴天样例无 translation 独立轨**（译文内嵌未见，
  GAP_ANALYSIS #17 的译文错行防御仍按条数不等不落缓存处理）。
- lrc（contenttype=1）b64 直接 utf8 解码，标准 [mm:ss.xx] 行。

### 模型映射修正清单（批N2-A 落地）
| 位置 | 修正 |
|---|---|
| kugou_client.dart lyricSearch/lyricDownload Endpoint | SignType.none→android；clearDefaultParams 移除（需 dfid/mid/uuid/clienttime 默认参参与签名）；新增实测注释（空 body 风险） |
| misc_endpoints.dart lyricSearch | candidates id 用 safeStr；注释按 A3-3 实测键集更新 |
| misc_endpoints.dart lyricDownload | 增加 status==200 判定语义注释；_source/charset 如实不映射 |
