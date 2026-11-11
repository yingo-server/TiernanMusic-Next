# API_FIELDS_TRUTH — 网络层字段实证（批N1 · A1+A2，2026-11-12）

> 探针：`.test_creds/n1c_probe.py` / `n1c_probe2.py`（复刻 lib/core/net/signing.dart android 签名，
> 直连 gateway.kugou.com）。全部字段为**实测响应逐键留样**，非文档推断。
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
