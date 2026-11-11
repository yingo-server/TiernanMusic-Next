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

# 批N2-B · A4+A5 歌手/专辑/MV 域实证（2026-11-12）

> 探针：`.test_creds/n2b_probe.py`（A4）+ `n2b_mv_probe.py`（A5），复刻 n1c_probe
> android 签名直连 gateway.kugou.com；留样 `n2b_raw.json` / `n2b_video_detail_ok.json`
> / `n2b_videourl_qhd.json`。样例对象：周杰伦（author_id 3520，夜曲专辑 958909，
> 夜曲 album_audio_id 32029511，MV video_id 596344）。

## A4 · 歌手/专辑域

### A4-1 · /kmr/v3/author（歌手详情，POST，openapi，kg-tid 36，body {author_id}）
- 实测：匿名与 VIP 响应**同构**，`data` 平铺 **14 键**：
  `author_id`(=3520)、`author_name`="周杰伦"、`sizable_avatar`({size} 模板)、
  `intro`（短简介，可为空串）、`long_intro`（长文）、`album_count`、`song_count`、
  `mv_count`、`fansnums`（⚠️ 复数形式键，非 fans/fans_num）、`area_id`、`birthday`、
  `is_publish`、`pinyin_initial`、`user_status`。
- 代码：`ArtistDetail` 扩 albumCount/songCount/mvCount/fans（fansnums）；intro 空
  时落 long_intro；ArtistBrief 补 AuthorId/AuthorName/Avatar/FansNum 搜索域驼峰兜底。

### A4-2 · /v1/album_audio/lite（专辑歌曲，POST，openapi，kg-tid 255，body {album_id,page,pagesize,is_buy:0}）
- 实测（匿名=VIP 同构）：`data.songs[]`，item **10 键**：
  `base`{audio_name,author_name,album_id,audio_id,album_audio_id,is_publish}、
  `audio_info`{hash,hash_128,hash_320,hash_flac,hash_high,hash_super,filesize,
  filesize_128/320/flac,bitrate,duration(**毫秒**,226873),duration_128/320/flac,
  extname}、`album_info`{album_name,cover}、`authors`[{author_name,author_id,
  sizable_avatar,is_publish}]、`copyright`{privilege,privilege_128/320/flac,…}、
  `deprecated`{video_hash,hash_multitrack,pay_type,pay_block_tpl,cid,…}、
  `extend`{has_obbligato,cd_name,disc,sort}、`extra`{remark}、
  `mvdata`[{typ:0,trk:"3",hash,id:"596344"}]、`trans_param`{musicpack_advance:1,
  ogg_*_hash/filesize,union_cover,hash_offset{offset_hash,start_ms,end_ms},…}。
- ⚠️ 与 pubsongs nofilt 口径（fromTrackInfo）**不同族**：无 singerinfo/albuminfo/
  timelen/size 键 → 新增 `SongBrief.fromAlbumLite` 专用工厂（hash=audio_info.hash、
  名=base.audio_name、歌手=base.author_name→authors[]聚合、albumAudioId=
  base.album_audio_id、duration ms→s、isVip=trans_param.musicpack_advance）。
  `album_endpoints.getAlbumSongs` 已切换到 fromAlbumLite。

### A4-3 · /kmr/v2/albums（专辑详情，POST，openapi，kg-tid 255，body {data:[{album_id}]}）
- 实测：`data` 为**数组**，data[0] **21 键**：`album_id`("958909" 字符串)、
  `album_name`="十一月的萧邦"、`author_name`、`sizable_cover`(完整 {size} URL)、
  `cover`（⚠️ 裸文件名 "20250125121901851911.jpg"，**非 URL，不可直接展示**）、
  `intro`(长文案)、`publish_date`="2005-11-01"（⚠️ 无 publish_time 键）、
  `publish_company`="杰威尔音乐有限公司"、`grade`="8.7"、`grade_count`="5504"、
  `heat`="2329975"、`language`="国语"、`language_id`、`category`、`classification`、
  `exclusive`、`is_publish`、`quality`、`special_tag`、`type`="录音室专辑"、`trans_param`。
- ⚠️ **无曲目数键**（count/song_count/songnum 均不存在）→ AlbumBrief.songCount
  在此口径如实 0（曲目数取 A4-2 的 data.total）。
- 代码：getAlbumDetail cover 改 sizable_cover/imgurl（去掉裸 cover 兜底防死链）。

### A4-4 · /pubsongs/v1/kmr_get_similar_lists（相似歌单）
- 实测（body {data:[{global_collection_id}]}，key/signature 可不带，status=1）：
  `data` 为**数组**，data[i] 两键 `collection_info`（21 键）+ `tag_info`
  [{tag_id,tag_name}]。collection_info 键：global_collection_id/collection_id/
  cloudlist_id/collection_name/cover(150px 完整)/flexible_cover({size})/intro/
  heat/user_id/user_name/publish_date/percount/type/is_publish/is_recommend/
  sync/special_tag/ugc_talent_info/user_is_verified/trans_param。
- ⚠️ 与批N2-C 实测的 `data[].collection_list[]` 双层形态并存（服务端按灰度/参数
  返回两种形态）→ getSimilarPlaylists 已双形态容错。collection_info 口径
  **无 song_count**（trackCount 如实 0）。

### A4-5 · 歌手域两端点实测不可达（不猜字段）
- `/v1/author/albums`（tid 36/38/无）与 `/kmr/v1/author/audios`（tid 36/38/255/无、
  匿名/VIP、body 合并/清默认参数、gateway+openapi 直连）——**全部 502/403**。
  字段树未固化；artist_endpoints 注释已如实标注，_pickList 容错维持原样。

## A5 · MV 域（全部实测打通）

### A5-1 · /kmr/v1/audio/mv（按歌查 MV，POST，openapi，kg-tid 38）
- ⚠️ 旧口径 `/kmr/audio/mv`（body {album_audio_id}）实测 **502 不存在**。
- 实测口径：body `{data:[{album_audio_id:"32029511"}], fields:''}`；
  响应 `data` 为**嵌套数组** `data[0][]`，项键（27 个）：
  `video_id`、`mv_name`（⚠️ 非 mvname/filename）、`singer`、`duration`(**毫秒**
  231732)、`hdpic`({size} 高清封面)、`thumb`(缩略图)、`hit`/`hot`/`play_times`/
  `download_total`/`collection_total`、`audio_id`/`album_audio_id`/`songid`、
  `music_trac`、`have_mp4`、`is_recommend`/`is_ugc`/`is_short`/`is_publish`/
  `is_other`、`publish_time`、`desc`/`other_desc`/`remark`/`topic`、`type`、
  `user_id`/`user_name`/`user_avatar`、`__status`。
- ⚠️ MV 项本身**无 hash 键**——播放 hash 来自歌曲侧 `mvdata[].hash` 或
  `deprecated.video_hash`（A4-2），或由 video_id 走 A5-2 取档位 hash。
- 代码：mvDetail 路径改 `/kmr/v1/audio/mv`；getMvBySong 双层取数+容错；
  MvBrief.fromMap 键修 mv_name/hdpic。

### A5-2 · /v1/video（MV 详情/清晰度，POST，kmr.service）
- ⚠️ `/v1/video/detail` 实测 **404**；`/kmr/v2/videos` 404。
- 实测口径（**clearDefaultParams 全参 body**）：`{appid:'1005',clientver:'20489',
  clienttime:秒, mid, uuid, dfid, token:'', key:md5(appid+SALT+clientver+秒),
  show_resolution:1, data:[{video_id:596344}]}`，android 签名对 body 全参。
  网关默认参数形态（不带这些键）404/502。
- 响应 `data[0]` 平铺 88 键，**清晰度档位以前缀展开**（无数组）：
  `ld_*`(480×270)/`sd_*`(768×432)/`hd_*`(1280×720)/`fhd_*`(1920×1080)/
  `qhd_*`(960×540)，每档 `{tier}_hash/{tier}_hash_265/{tier}_filesize/
  {tier}_bitrate/{tier}_width/{tier}_height`（+ld/sd/hd/fhd/qhd 各实测留样，
  如 qhd_hash=32952294B 对应 qhd_filesize）；另有 `mkv_sd_*`/`mkv_qhd_*` 三键、
  `audio_hash/audio_filesize/audio_bitrate/audio_timelength`、
  `video_name`="夜曲"、`hdpic`/`thumb_gif`/`thumb_mp4`/`thumb_hd_mp4`/
  `thumb_hd_h265_mp4`、`timelength`(231732 ms)、`video_id`/`album_audio_id`/
  `audio_id`、`authors[]`、`classification[]`、`publish_date`、`track`、
  `have_mp4`、`heat`/`history_heat`/`play_times`/`download_total`/
  `collection_total` 等。
- 代码：videoDetail 路径改 `/v1/video` + clearDefaultParams:true；
  MvQuality.fromFlat 平铺抽取（主档+265 档+mkv 档）。

### A5-3 · /v2/interface/index（MV 播放地址，GET，trackermv）
- 实测参数表（缺 key 即 40003）：
  `backupdomain=1, cmd=123, ext=mp4, ismp3=0, hash, pid=1, type=1, key,
  userid(0), appid('1005')`；key=md5(hash+**57ae12eb6890223e355ccfcb74edf70d**
  (signKeySalt)+appid+mid+userid||0)（与 play_url 同盐；signing.playKey）。
  ⚠️ cmd=12/4/25 及缺参数组合实测 40003 "Bad cmd"/"Empty key"。
- 响应：`{status:1, privileges:{hash:0/1}, data:{hash:{downurl:"http://…mp4"
  (单串), backupdownurl:["http://…mp4"](数组), filesize}}}`。
- 代码：videoUrl 声明 encryptKey:true（KugouClient 自动注 key）；getVideoUrl
  参数表更新，解析 data[hash].downurl+backupdownurl 并去重。

## 模型映射修正清单（批N2-B 落地）
| 位置 | 修正 |
|---|---|
| kugou_client.dart EndpointRegistry | mvDetail→/kmr/v1/audio/mv；videoDetail→/v1/video+clearDefaultParams；videoUrl+encryptKey |
| mv_endpoints.dart getMvBySong | body {data:[{album_audio_id}]}；data[0][] 嵌套取数 |
| mv_endpoints.dart MvBrief.fromMap | mv_name / hdpic / duration(ms) 实测键 |
| mv_endpoints.dart MvQuality | 新增 fromFlat（ld/sd/hd/fhd/qhd 平铺+265+mkv） |
| mv_endpoints.dart getVideoUrl | 实测参数表 cmd=123/pid=1 + data[hash].downurl/backupdownurl |
| artist_endpoints.dart ArtistDetail | 扩 albumCount/songCount/mvCount/fans(fansnums)；long_intro 兜底 |
| artist_endpoints.dart ArtistBrief | 补搜索域驼峰 AuthorId/AuthorName/Avatar/FansNum |
| artist_endpoints.dart AlbumBrief | sizable_cover 优先；songcount 兜底；实测注释 |
| models.dart SongBrief.fromAlbumLite | 新增（album_audio/lite 十键结构专用） |
| album_endpoints.dart getAlbumSongs | fromTrackInfo→fromAlbumLite |
| album_endpoints.dart getAlbumDetail | cover 不落裸文件名；publish_date 实测注释 |
| album_endpoints.dart getSimilarPlaylists | collection_info / collection_list 双形态容错 |
| tool/field_truth_test.dart | 追加 A4/A5 六组锚点（fromAlbumLite/MvQuality.fromFlat/MvBrief/AlbumBrief/ArtistDetail/MvPlayResult） |

---

## 批N3-C · 歌手域接线收口（2026-11-12，探针产物 n3c_artist_raw.json）

### A4-2' · /kmr/v1/audio_group/author（歌手热门歌曲，POST，openapi，kg-tid 220）
- ⚠️ 旧口径 `/kmr/v1/author/audios`（N2-B 探针 502）确认**不存在**；
  真实路径 `/kmr/v1/audio_group/author`（kg-tid 220，body
  `{author_id,page,pagesize}`，defaultParams+body 合并签名）实测 **status=1**。
- 响应顶层：`{status, errcode, errmsg, error_code, extra, total}`，
  `data` 为**平铺数组**（非 songs[] 包裹）。
- item 键（103 个，发如雪实测留样）：`audio_name`、`author_name`、
  `album_name`、`album_id`(958909)、`album_audio_id`(32029513)、
  `audio_id`(339589)、`hash`/`hash_128`/`hash_320`/`hash_flac`/`hash_high`/
  `hash_super`、`filesize(_128/320/flac/high/super)`、
  `timelength`(**毫秒** 299284)、`timelength_128/…`、`bitrate(_128…)`、
  `extname(_super)`、`playcount`(0)、`publish_date`("2005-11-01")、
  `privilege(_128/320/flac/high/super)`、`pay_type(_*)`、`price(_*)`、
  `status(_*)`、`fail_process(_*)`、`old_hide(_*)`、`old_cpy(_*)`、
  `rp_id/rp_publish/rp_type(_*)`、`pkg_price(_*)`、`topic_remark/topic_url(_*)`、
  `video_hash`/`video_id`(2761)/`video_file_head`/`video_filesize`/
  `video_timelength`/`video_track`、`trans_param`{cpy_grade,classmap,language,
  cpy_attr0,musicpack_advance,display,flags,ogg_*_hash/filesize,union_cover,
  qualitymap,is_original,…}、`has_obbligato`、`is_original`、`identity`、
  `level`、`mixsong_type`、`cid`、`version`、`remarks`、`audio_file_head`、
  `cd_url`、`tmp_privilege`。
- ⚠️ **无 singerinfo[]/albuminfo{}/mixsongid/singername 键**（与 pubsongs
  nofilt 口径不同族）→ 映射仍用 `SongBrief.fromTrackInfo`：
  singer=author_name 兜底、albumName=album_name 兜底、durationSec=
  timelength(ms) 兜底链已覆盖；mixSongId 如实 0（songid 键不映射，不猜）。
- 代码：EndpointRegistry.artistAudios 路径/tid 已改（audio_group/author,
  tid 220）；kArtistAudiosPath 同步；getArtistAudios 注释按实测键集更新；
  field_truth_test.dart 追加 11 条锚点（N3-C artist audios field truth）。

### A4-3' · 歌手专辑端点复测（不猜维持）
- `/v1/author/albums`（tid 36）与 `/kmr/v1/author/albums`（tid 36，
  author_id=3520 匿名）批N3-C 复测**仍 502**——端点不可达，声明维持任务
  口径原样，数据源走已实证 albumDetail（/kmr/v2/albums）由调用方降级。

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

## A6 · 用户域歌单写（批N3-B · 2026-11-12 三态实测，探针 `.test_creds/n3b_probe.py`）

> 样例落盘：`n3b_vip.json` / `n3b_nonvip.json` / `n3b_anon.json` /
> `n3b_addlist_item.json` / `n3b_addsong_item.json` / `n3b_delsongs_item.json` / `n3b_tags_item.json`。
> 测试账号：VIP uid 1666835066 / 非VIP uid 2461028533（cj_vip.txt / cj_nonvip.txt）。
> **签名关键发现**：`srcappid` 参与签名 → cloudlist 系端点（本节全部端点）恒
> `status=0 error_code=20006`；不带 srcappid 则 status=1。已落地
> `Endpoint.omitSrcappid` 开关（kugou_client.dart），cloudlist 系五端点全部置 true。

### A6-1 · 用户歌单列表（POST /v7/get_all_list，x-router cloudlist.service.kugou.com）
- query：`plat=1` + 默认参数（mid/dfid/uuid/appid/clientver/clienttime，**不含 srcappid**）
  + userid/token（query 与 body 双带，登录态从 Cookie 亦带 t1）。
- body：`{userid(int), token, total_ver:979, type:2, page, pagesize}`。
- 三态：VIP status=1（14→17 个歌单随写操作增长）；非VIP status=1（3 个）；
  匿名 **status=0 error_code=20010**（需登录）。
- 成功 `data.info[]` item 键（**40 个，全键留样**）：`listid`(int)、
  `global_collection_id`("collection_3_1666835066_1_0")、`name`、`pic`、`intro`、
  `count`(int 曲目数)、`m_count`/`per_count`/`per_num`、`pub_new`/`pub_time`/`pub_type`、
  `type`/`source`/`sort`、`status`、`is_def`/`is_del`/`is_drop`/`is_edit`/`is_mine`/
  `is_per`/`is_pri`/`is_publish`/`is_featured`/`is_custom_pic`、`incr_sync`、`list_ver`、
  `list_create_userid`/`list_create_listid`/`list_create_gid`/`list_create_username`、
  `create_user_pic`、`create_time`/`update_time`、`tags`（**空串**，非数组）、
  `musiclib_tags`（数组）、`trans_param`、`sound_quality`、`radio_id`、`kq_talent`。
- ⚠️ 字段名口径：`listid`（非 specialid/id）、`pic`（非 imgurl）、`count`（非 song_count）。

### A6-2 · 建歌单（POST /cloudlist.service/v5/add_list，URL 前缀式无 x-router）
- query：`last_time`(秒) / `last_area=gztx` / `userid` / `token` + 默认参数（无 srcappid）。
- body：`{userid, token, total_ver:0, name, type:0, source:0, is_pri:0,
  list_create_userid:0, list_create_listid:0, list_create_gid:0, from_shupinmv:0}`。
- 三态：VIP/非VIP status=1；匿名 error_code=20010。
- 成功 `data` 键（8 个）：`info` / `last_area` / `last_time` / `list_count` /
  `need_to_upfile` / `pre_total_ver` / `total_ver` / `userid`。
- **`data.info`**（新歌单全量对象）：`listid`(int 新歌单ID) / `list_create_listid` /
  `global_collection_id` / `list_create_gid` / `name` / `status:1` / `code:1` /
  `source:1` / `is_pri` / `is_edit:1` / `count:0` / `list_ver:0` / `type:0` /
  `pub_type`/`pub_new`/`per_num`/`is_per`/`is_featured`/`is_copy` / `pic:""` /
  `intro:""` / `tags:""` / `create_time`/`update_time` / `list_create_userid` /
  `list_create_username`。
- ⚠️ **listid 路径 = `data.info.listid`，`data.listid`/`data.id` 不存在**（旧封装假设证伪并已修正）。

### A6-3 · 歌单加歌（POST /cloudlist.service/v6/add_song，URL 前缀式无 x-router）
- query：`last_time` / `last_area=gztx` / `userid` / `token` + 默认参数（无 srcappid）。
- body：`{userid, token, listid(int), list_ver:0, type:0, slow_upload:1,
  scene:"false;null", data:[{number, name("歌手 - 曲名.mp3"), hash(小写), size,
  sort:0, timelen(秒), bitrate, album_id, mixsongid}]}`。
  （实测用 /v3/search/song `data.lists[]` 的 FileHash/FileSize/Duration/Bitrate/
  AlbumID/MixSongID/FileName 映射；hash 大写需转小写。）
- 三态：VIP/非VIP status=1（逐曲回执）；匿名 20010（未测到本端点，body 缺登录态）。
- 成功 `data` 键：`cursor`("202611|131071")、`status:1`、`pre_update_time`/`update_time`/
  `last_time`、`listid`、`is_copy`/`is_pri`/`is_drop`/`is_edit`/`is_featured`/`pub_new`/
  `pub_type`、`create_time`、`pre_list_ver`、`del_fileids:null`、**`info[]`（逐曲回执）**。
- `data.info[]` item 键：`fileid`(歌单内序号 1 起)、`number`、`hash`(大写回显)、
  `name`、`audio_id`、`cover`、`singerinfo[{name,id,type,publish,avatar}]`、
  `tagmap{genre0}`、`language`、`task`、`fsort`、`sort`、`csong`、`bpm_type`、`ipmap{attr0,bits}`。

### A6-4 · 歌单删歌（POST /v4/delete_songs，x-router cloudlist.service.kugou.com）
- body：`{listid(int), userid, data:[{fileid}], type:0, token, list_ver:0}`。
  **fileid = A6-3 回执的 fileid / audio_id 口径（album_audio_id），非 hash。**
- 三态：VIP/非VIP status=1，`data.list_ver` 递增、`data.count` 为删除数；
  匿名未测（写端点依赖登录态）。
- 成功 `data` 键：`pre_list_ver`/`list_ver`、`count`、`cursor`、`listid`、`userid`、
  `last_area`、`last_time`、`status:1`、`is_pri`/`is_copy`/`is_drop`/`is_featured`/
  `pub_type`/`pub_new`、`create_time`/`update_time`、`type`。
- ⚠️ 旧封装 body 用 `resource:[{hash,number}]`（/v2/add_songs_by_hash 口径）——
  实测正确形态是 `data:[{fileid}]`；已修正 Endpoint 路径 + 注释，调用方接线随批N3 收口。

### A6-5 · 歌单分类 tags（POST /pubsongs/v1/get_tags_by_type，gateway 无 x-router）
- body：`{tag_type:"collection", tag_id:0, source:3}`；三态均 status=1（不校验登录）。
- `data[]`（**数组**）item：`tag_id`("5" 字符串)、`tag_name`("场景")、`parent_id`("0")、
  `sort`("1")、**`son[]`（子标签数组，{tag_id, tag_name, parent_id, sort}）**。
- ⚠️ 旧封装容错路径 `data.tags[]`/别名 tagname——实测是 `data[]` 直排 +
  `tag_name`；`getPlaylistTags` 已按 `data[]`+`tag_name`+`son[]` 修正。

### A6-6 · 删歌单（POST /v2/delete_list，x-router cloudlist.service.kugou.com）
- 真实契约：query `p = rsaEncrypt2({aes key, uid, token})` 大写 + `key=signParamsKey`
  + AES 加密 body（明文 `{listid, total_ver:0, type:1}`）。
- **明文兜底实测（VIP + 非VIP 双账号均复现）：status=0 error_code=20010
  "need param p"** → 加密契约无 rsaEncrypt2/playlistAesDecrypt 实现，诚实失败不猜。
- Dart 侧维持明文兜底 + Log.w 留痕；`playlistDelete` Registry 已改真实路径 +
  x-router + omitSrcappid（后续接加密组件时只需补 p/key 生成）。

### 批N3-B 代码修正清单（本批落地）
| 位置 | 修正 |
|---|---|
| kugou_client.dart Endpoint | 新增 `omitSrcappid` 字段（srcappid 入签 → cloudlist 系 20006） |
| EndpointRegistry.playlistCreate | /v2/add_playlist → /cloudlist.service/v5/add_list（omitSrcappid） |
| EndpointRegistry.playlistDelete | /v2/del_playlist → /v2/delete_list + router cloudlist.service + omitSrcappid |
| EndpointRegistry.playlistDelSongs | /v2/del_songs_by_hash → /v4/delete_songs + router + omitSrcappid |
| EndpointRegistry.playlistAddSongs | /v2/add_songs_by_hash → /cloudlist.service/v6/add_song（omitSrcappid） |
| EndpointRegistry.userPlaylists | 补 omitSrcappid |
| playlist_write_endpoints.dart createPlaylist | listid 路径 data.listid → **data.info.listid** |
| playlist_write_endpoints.dart 新增 addSongsToPlaylist | A6-3 实测契约封装（data:[{…mixsongid}]，回执 data.info[]） |
| playlist_write_endpoints.dart removeSongsFromPlaylist | 注释修正：body data:[{fileid}]（fileid=album_audio_id 非 hash） |
| playlist_write_endpoints.dart deletePlaylist | 实测结论落注释：明文兜底 → 20010，不猜加密 |
| playlist_write_endpoints.dart getPlaylistTags | data.tags[] → data[]（tag_name + son[] 子标签） |
| test/n3b_field_truth_test.dart · tool/field_truth_test.dart | 新增 A6 回归锚点 13 例（listid 路径/add_song 回执/delete_songs/20010 失败形态/user_playlist 41 键子集） |

### 批N3-B 未竟（如实标注，不猜）
- delete_list 加密契约（p=rsaEncrypt2 + AES body）：仓库无对应密钥组件，明文兜底
  实测 20010 失败——接入官方 App 抓包样本或补 rsaEncrypt2 实现后才能打通。
- 匿名态对写端点（add_list/add_song/delete_songs）未逐个跑：body 依赖
  userid/token，匿名请求缺登录态本就是 20010/20006 族，实证价值有限。
- `pl_cache.json` 收藏他人歌单（add_list type≠0）形态未测：本批仅测 type=0 自建。
