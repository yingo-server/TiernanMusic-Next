# 上游原生端点全表 · B 组（搜索/FM/云盘/评论/收藏写/榜单/歌单/专辑/歌手/每日推荐/用户/上报）

> 只读调研 · 2026-11-15 · 源码：/var/minis/workspace/KuGouMusicApi/{module,util}/ · 未运行 Node、未做真实调用。
> 「证据」= module/*.js 与 util/*.js 的行号。所有 baseURL 未显式给出时为 util/request.js:86 的默认网关 `https://gateway.kugou.com`（由 headers['x-router'] 分流到子服务）。

## 0. 公共请求层（util/request.js + helper.js + crypto.js）

- 默认参数（request.js:48–58）：`dfid(默认'-')、mid(=cookie.KUGOU_API_MID)、uuid('-')、appid=1005、clientver=20489、clienttime、token?、userid?`；lite 平台切换 liteAppid=3116/liteClientver=11440（config.json:7–11，request.js:33/52–53）。
- 默认头（request.js:41/87–91）：`dfid、clienttime、mid、kg-rc:1、kg-thash:5d816a0、kg-rec:1、kg-rf:B9EDA08A…`；UA=`Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi`（request.js:87）。
- 三种签名（helper.js）：
  - **android**（helper.js:24–32）：salt `OIlwieks28dk2k092lksi2UIkp`（lite: `LnT6xpN3khm36zse0QzvmgTZ3waWdRSA`），`md5(salt + sort(k=v 串) + POST body 原文 + salt)`；对象值 JSON.stringify。**签名含 body** → body 必须与签名时逐字节一致（含中文未编码、`+` 不转义）。
  - **web**（helper.js:9–16）：salt `NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt`，`md5(salt + sort(k=v&拼接去&) + salt)`，仅 query 参数，不含 body。
  - **register**（helper.js:39–45）：**不拼 k=**，`md5('1014' + sort(values) + '1014')`。
- 其他 key：`signKey`（helper.js:70–74，md5(hash+salt+appid+mid+userid)，salt=`57ae12eb6890223e355ccfcb74edf70d`/lite 另值）；`signParamsKey`（helper.js:95–104，md5(appid+salt+clientver+data)，data 常为毫秒时间戳字符串）；`signCloudKey`（helper.js:82–85，云盘：md5(`musicclound`+hash+pid+`ebd1ac3134c880bda6a2194537843caa0162e2e7`)，固定 pid=20026）。
- **clienttime 秒/毫秒坑**：request.js:39 默认**秒**（Math.floor(Date.now()/1000)）；但 fm_class/fm_recommend/fm_songs/fm_image/personal_fm/top_playlist/album/artist_audios/playlist_similar/search_mixed 各自覆盖为**毫秒** Date.now()（且 fm 类的 key=signParamsKey(毫秒) 与签名参数里的 clienttime 必须同值）；user_cloud/playlist_add/playlist_del/user_listen 用**秒**。混合时签名必然失败。
- RSA/AES（crypto.js:240–308）：云盘/听歌列表用 `rsaEncrypt2`（PKCS1-V1_5，公钥 request.js 顶部 `MIGfMA0G…`，lite 另一公钥 crypto.js:5）；body 用 `playlistAesEncrypt`：随机 6 位小写 key，`AES-CBC-PKCS7`，key=md5(key)[0:16]，iv=md5(key)[16:32]，密文 base64；响应用 `playlistAesDecrypt` 同 key 解密（crypto.js:287–305）。`cryptoRSAEncrypt` 为 raw 无填充 hex（crypto.js:244–262，user_listen 用）。
- 响应判定（request.js:143–155）：`status===0` 或 `error_code!==0` → 502 失败；`ssa-code` 响应头透传进 body.ssaCode。user_cloud 类 responseType=arraybuffer，需 AES 解（user_cloud.js:37/43）。

## 1. 搜索 / 联想 / 热搜

| 模块 | 域名 | 路径 | 签名 | 关键参数 | 顶层响应键 | 登录 | 证据 |
|---|---|---|---|---|---|---|---|
| search.js（分类型） | complexsearch.kugou.com (x-router:22) | song→`/v3/search/song`；special/lyric/album/author/mv→`/v1/search/{type}` (18) | android | keyword,page,pagesize,iscorrection=1,platform=AndroidFilter,albumhide,nocollect | （song 项 57 键，见 capture_3state §1.2） | 否 | search.js:3–24 |
| search_complex.js | complexsearch.kugou.com（直连 baseURL:12） | `/v6/search/complex` (13) | android | keyword,page,pagesize,cursor,platform | 实测不可达（152）→ Next 已降级 v3/song | 否 | search_complex.js:11–18 |
| search_mixed.js | complexsearch.kugou.com (35) | `/v3/search/mixed` (31) | android | ability=511,apiver=22,clientver=20125,platform=IOSFilter,requestid=md5(salt+time)_0,kg-clienttimems=毫秒 | tags/asts songs 混排 | 否 | search_mixed.js:6–37 |
| search_suggest.js | searchtip.kugou.com (15) | `/v2/getSearchTip` (3) | android | keyword,Album/Correct/MV/MusicTipCount,radiotip=1 | data.records[].{hint,keyword,…} | 否 | search_suggest.js:2–16 |
| search_hot.js | msearch.kugou.com (14) | `/api/v3/search/hot_tab` (9) | android | navid=1,plat=2 | data.list[]（热搜标签+词） | 否 | search_hot.js:3–15 |
| search_default.js | （网关默认） | `/searchnofocus/v1/search_no_focus_word` (19) POST | android | body:plat=0,userid,vip_type,m_type,ability=3,bitmap=2,mode=normal；query clientver=12329 | 默认搜索词 | 建议带 token | search_default.js:5–25 |
| search_lyric.js | lyrics.kugou.com（直连:17） | `/v1/search` (18) GET | android + **notSign/clearDefaultParams**（:23–24，只带显式参数） | hash,keyword,duration,album_audio_id,lrctxt=1 | candidates[27 键] | 否 | search_lyric.js:5–25 |

**版本变体猜测**（均待实测，仅按相邻版本规律推）：
- /v3/search/song：源码 v3；猜测 v2/v1 仍在（老客户端）；v4 不确定。
- /v6/search/complex：源码 v6；猜测 v5/v4 存活概率高（Next 已用 v3/song 兜底）。
- /v3/search/mixed：源码 v3；猜测 v2。
- /v2/getSearchTip：源码 v2；猜测 v1 仍存活。
- /api/v3/search/hot_tab：源码 v3；猜测 v2/v1。
- /v1/search/{special,lyric,album,author,mv}：源码 v1，无更早版本；v2 待实测。

## 2. FM

| 模块 | 域名 | 路径 | 签名 | 关键参数 | 登录 | 证据 |
|---|---|---|---|---|---|---|
| fm_class.js | fm.service.kugou.com (23) | `/v1/class_fm_song` (18) POST | android + key=signParamsKey(毫秒)(13) | kguid/uid,platform=android,get_tracker=1 | 否（登录更佳） | fm_class.js:5–24 |
| fm_recommend.js | fm.service.kugou.com (24) | `/v1/rcmd_list` (19) POST | android+key(毫秒) | rcmdsongcount=1,level=0,area_code=1,get_tracker | 否 | fm_recommend.js:5–25 |
| fm_songs.js | fm.service.kugou.com (39) | `/v1/app_song_list_offset` (34) POST JSON | android+key(毫秒) | data[]:{fmid,fmtype,offset=-1,size=20} | 否 | fm_songs.js:6–40 |
| fm_image.js | fm.service.kugou.com (28) | `/v1/fm_info` (23) POST | android+key(毫秒) | data[]:{fmid,fmtype=2,fields=imgUrl100,imgUrl50} | 可选 userid/token(:19–20) | fm_image.js:8–29 |
| personal_fm.js | persnfm.service.kugou.com (44) | `/v2/personal_recommend` (39) POST | android+key(毫秒) | action=play,song_pool_id,remain_songcnt,m_type=1,mode,hash/songid/playtime,fakem | 登录态影响推荐（userid/token 可选） | personal_fm.js:8–45 |
| pc_diantai.js | adservice.kugou.com（直连:10） | `/v3/pc_diantai` (11) POST | android | isvip,userid,vipType | 否 | pc_diantai.js:4–16 |

**FM 真实路径结论（对齐 capture_3state §3）**：personal_fm 的 `/v2/personal_recommend` + x-router persnfm 才是真实可用口径；`/v1/fm/play` 三态 items=0 是死样本。fm_songs 真实契约即 `/v1/app_song_list_offset`（注意 offset 默认 -1）。
**版本变体猜测**：/v2/personal_recommend→v1（待实测，可能已下线）；/v1/rcmd_list、/v1/class_fm_song、/v1/app_song_list_offset、/v1/fm_info 均源码 v1 无降级候选；/v3/pc_diantai→v2/v1。

## 3. 云盘 / 高潮 / 收听

| 模块 | 域名 | 路径 | 签名/加密 | 关键点 | 登录 | 证据 |
|---|---|---|---|---|---|---|
| user_cloud.js | mcloudservice.kugou.com（直连:31） | `/v1/get_list` (32) POST arraybuffer | **无 signature**（notSignature:40, clearDefaultParams:39）；query: clienttime(秒),mid,key=signParamsKey(秒),clientver,appid,p=RSA({aes_key,uid,token}).大写；body=AES( {page,pagesize,getkmr:1} )；响应 AES 解（:43） | AES key 为 6 位随机串回传 RSA | **必须 token** | user_cloud.js:11–43 |
| user_cloud_url.js | 网关默认 | `/bsstrackercdngz/v2/query_musicclound_url` (21) GET | android | key=signCloudKey(hash,20026),pid=20026,ssa_flag,version=20102 | token 建议 | user_cloud_url.js:4–26 |
| song_climax.js | expendablekmrcdn.kugou.com（直连:7） | `/v1/audio_climax/audio` (8) GET | android | data=JSON [{hash},…] | 否 | song_climax.js:4–13 |
| user_listen.js | listenservice.kugou.com（直连:19） | `/v2/get_list` (20) POST | android；p=cryptoRSAEncrypt({clienttime,token}).大写(:8) | t_userid,list_type,cover=2 | **必须 token** | user_listen.js:6–26 |
| lastest_songs_listen.js | 网关默认 | `/playque/devque/v1/get_latest_songs` (15) POST | android | sources=[pc,mobile,tv,car],ret_info=1 | **必须 token** | lastest_songs_listen.js:5–20 |

**版本变体猜测**：/v1/get_list(云盘)→无更早版本，v2 待实测；/v2/query_musicclound_url→v1；/v1/audio_climax/audio→源码 v1（v2 待实测）；/v2/get_list(listen)→v1；/v1/get_latest_songs→v1。响应键：user_cloud 解密后含 `list[]/total`（Next 三态 items=0 系未带 token/AES 未实现所致）；climax 响应键 `data[]:{hash,begin_time,end_time…}`（无留样，待实测）。

## 4. 评论（读）

| 模块 | 域名 | 路径 | code 常量 | 证据 |
|---|---|---|---|---|
| comment_music.js | 网关默认 | `/mcomment/v1/cmtlist` (16) POST | 歌曲码 fc4be23b…(:12) | comment_music.js:4–21 |
| comment_music_classify.js | 同上 | `/mcomment/v1/cmt_classify_list` (16) | 同歌曲码 | :4–21 |
| comment_music_hotword.js | 同上 | `/mcomment/v1/get_hot_word` (15) | 同歌曲码 | :4–20 |
| comment_playlist.js | 网关默认 | `/m.comment.service/v1/cmtlist` (17) | 歌单码 ca53b96f…(:11),content_type=0,tag=5 | comment_playlist.js:4–20 |
| comment_album.js | 网关默认 | `/m.comment.service/v1/cmtlist` (15) | 专辑码 94f1792c…(:11) | comment_album.js:4–20 |
| comment_floor.js | 歌/`mcomment`；歌单专辑/`m.comment.service` (44–46) | `/v1/hot_replylist` | 按 resource_type 选码(:12–20) | comment_floor.js:28–51 |
| comment_count.js | sum.comment.service.kugou.com (21) | `/index.php` (16) **web 签名** | r=comments/getcommentsnum,code=歌曲码;hash 或 childrenid | comment_count.js:4–22 |

均 android 签名 POST（除 count 为 web GET）；公共参数 p/pagesize/need_show_image=1/show_classify/show_hotword_list。**评论写/点赞/回复：本仓 159 文件中不存在任何 cmt_send/reply/praise 端点（rg 全表无命中），纯缺口。**
**版本变体猜测**：/v1/cmtlist、/v1/hot_replylist、/v1/cmt_classify_list、/v1/get_hot_word 源码均 v1；v2 待实测。count 的 /index.php 无版本。

## 5. 收藏 / 歌单写

| 模块 | 路径 | 要点 | 登录 | 证据 |
|---|---|---|---|---|
| favorite_count.js | `/count/v1/audio/mget_collect` GET android | 实测 data.list[]{mixsongid,count,count_text} | 否 | favorite_count.js:3–5 |
| playlist_add.js（建/收歌单） | `/cloudlist.service/v5/add_list` (26) POST android | body:userid,token,total_ver=0,name,type(0=自建,1=收藏),is_pri,list_create_*；type=0 时 query 另带 last_time(秒),last_area=gztx(:28) | **必须** | playlist_add.js:7–32 |
| playlist_del.js（取消收藏） | `/v2/delete_list` (33) x-router cloudlist(38) POST arraybuffer | body=AES({listid,total_ver=0,type:1})；p=RSA；key=signParamsKey(秒)；响应 AES 解(:43) | **必须** | playlist_del.js:12–43 |
| playlist_tracks_add.js | `/cloudlist.service/v6/add_song` (35) POST | data[]:{number,name,hash,size,album_id,mixsongid}；**list_ver:0**(:27)；query last_time/last_area | **必须** | playlist_tracks_add.js:7–36 |
| playlist_tracks_del.js | `/v4/delete_songs` (19) x-router cloudlist(24) | data[]:{fileid}；list_ver:0(:15) | **必须** | playlist_tracks_del.js:7–25 |
| playlist_detail.js | `/v3/get_list_info` (13) x-router pubsongs(18) | data[]:{global_collection_id} | 可选 | playlist_detail.js:4–19 |
| playlist_track_all.js | `/pubsongs/v2/get_other_list_file_nofilt` (19) GET | 歌单曲目（41 键，fileid 在其中，Next 已丢） | 否 | playlist_track_all.js:19 |
| playlist_track_all_new.js | `/v4/get_list_all_file` (19) x-router cloudlist(24) POST | 登录态全量曲目 | 是 | playlist_track_all_new.js:19–24 |
| playlist_similar.js | `/pubsongs/v1/kmr_get_similar_lists` (20) POST | data[]:{global_collection_id},ugc=1,show_list=1,need_songs=1,key=signParamsKey(毫秒)(11) | 可选 | playlist_similar.js:4–25 |
| playlist_effect.js / playlist_tags.js | `/pubsongs/v1/get_sound_effect_list` / `/pubsongs/v1/get_tags_by_type` POST | 否 | playlist_effect.js:10 / playlist_tags.js:11 |
| user_playlist.js | `/v7/get_all_list` (17) x-router cloudlist(23) | 用户全部歌单 | **匿名 20010** | user_playlist.js:17–23 |
| sheet_*（乐库/Opern） | opern/v1/detail/info、home/get_rec_opern、get_rank_opern、detail/song_info、home/get_tags；miniyueku/v1/opern_square/...（web 签名, sheet_collection.js:10） | android | sheet_detail.js:7 等 |
| 歌单收藏真契约结论 | registry `/v2/collect`、`/v2/cancel_collect` 为死声明（上游无此端点，capture_3state §3）；真实收藏=add_song(v6)/delete_list(v2)。 | — |

**list_ver 坑**：add_song/delete_songs 源码恒 0；detail 响应里 `list_ver` 会递增（capture_3state §1.4）——并发编辑应传实测递增 list_ver 做乐观锁，传 0 可能被服务端按最新版本覆盖或拒。
**版本变体猜测**：v5/add_list→v4/v3；v6/add_song→v5/v4；v4/delete_songs→v3/v2；v2/delete_list→v1；v3/get_list_info→v2；v4/get_list_all_file→v3；v7/get_all_list→v6/v5；v2/get_other_list_file_nofilt→v1；v1/kmr_get_similar_lists→v1（v2 待实测）。

## 6. 榜单

| 模块 | 路径 | 关键参数 | 证据 |
|---|---|---|---|
| rank_list.js | `/ocean/v6/rank/list` (11) GET | plat=2,withsong,parentid=0 | rank_list.js:4–16 |
| rank_info.js | `/ocean/v6/rank/info` (11) GET | rankid,rank_cid,with_album_img,zone | rank_info.js:4–16 |
| rank_vol.js | `/ocean/v6/rank/vol` (12) GET | rankid,ranktype=1,type=0,plat=2 | rank_vol.js:4–17 |
| rank_audio.js | `/openapi/kmr/v2/rank/audio` (15) POST，头 kg-tid:369 (20) | rank_id,type=1,page,pagesize,area_code,show_portrait_mv | rank_audio.js:3–21 |
| rank_top.js | `/mobileservice/api/v5/rank/rec_rank_list` (5) GET | 无 | rank_top.js:4–9 |
| song_ranking.js / song_ranking_filter.js | （同族，ocean 域） | — | 未细读，同款 android |
| top_song.js（新歌速递） | `/musicadservice/container/v1/newsong_publish` (14) POST | rank_id(type,默认21608),tags=[],page | top_song.js:5–19 |

**版本变体猜测**：v6/rank/{list,info,vol}→v5/v4（可能仍活）；v2/rank/audio→v1；v5/rec_rank_list→v4/v3；v1/newsong_publish→v1。

## 7. 专辑 / 歌手

| 模块 | 域名 | 路径 | 关键参数 | 证据 |
|---|---|---|---|---|
| album.js | kmr.service.kugou.com（直连:26） | `/v1/album` (27) POST | data[]:{album_id},fields,key=signParamsKey(毫秒)(18) | album.js:11–33 |
| album_detail.js | openapi.kugou.com (14), kg-tid:255 | `/kmr/v2/albums` (9) POST | data:[{album_id}],is_buy,fields 串 | album_detail.js:3–15 |
| album_songs.js | openapi.kugou.com (16), kg-tid:255 | `/v1/album_audio/lite` (11) POST | album_id,page,pagesize,is_buy | album_songs.js:3–17 |
| album_shop.js | 网关默认 | `/zhuanjidata/v3/album_shop_v2/get_classify_data` (4) GET | 无 | album_shop.js:3–8 |
| top_album.js | 网关默认 | `/musicadservice/v1/mobile_newalbum_sp` (14) POST | apiver=20,withpriv=1 | top_album.js:5–19 |
| artist_detail.js | openapi.kugou.com (9), kg-tid:36 | `/kmr/v3/author` (4) POST | author_id | artist_detail.js:3–10 |
| artist_albums.js | openapi.kugou.com (19), kg-tid:36 | `/kmr/v1/author/albums` (14) POST | author_id,sort(hot=3/最新1),category=1,area_code='all' | artist_albums.js:4–20 |
| artist_audios.js | openapi.kugou.com（直连+router:27） | `/kmr/v1/audio_group/author` (22) POST | author_id,sort(hot=1/最新2),key(秒)(12) | artist_audios.js:7–28 |
| singer_list.js | 网关默认 | `/ocean/v6/singer/list` (4) GET | hotsize=200,musician,sextype,showtype=2,type | singer_list.js:3–15 |

**歌手专辑降级结论（capture_3state §3）**：`/kmr/v1/author/albums` 实测 502/403 → Next 走 albumDetail 降级。可尝试变体：v1→无更早版本；但同域 `kmr/v2/author/*`（对齐 albums 的 v2 前缀）是合理猜测候选。其余猜测：v2/albums→v1；v1/album_audio/lite→无；v3/author→v2/v1；v6/singer/list→v5/v4。

## 8. 每日推荐 / 用户 / 上报

| 模块 | 域名 | 路径 | 要点 | 证据 |
|---|---|---|---|---|
| recommend_songs.js / everyday_recommend.js | everydayrec.service.kugou.com (8/15) | `/everyday_song_recommend` POST android | **无版本号路径**；token 可选；每日推荐 30 首 | recommend_songs.js:10–15 |
| everyday_history.js | 同上 (18) | `/everyday/api/v1/get_history` (13) POST | 历史推荐 | everyday_history.js:13–18 |
| everyday_style_recommend.js | 网关默认 | `/everydayrec.service/everyday_style_recommend` (7) | 风格推荐 | :7–9 |
| everyday_friend.js | acsing.service.kugou.com（直连:4） | `/sing7/relation/json/v3/friend_rec_by_using_song_list` (5) | 好友听歌 | everyday_friend.js:4–7 |
| top_ip.js | musicadservice.kugou.com http（直连:11） | `/v1/daily_recommend` (12) POST | IP 推荐；clientver=12349,area_code=1 | top_ip.js:11–19 |
| user_detail.js | usercenter.kugou.com (22) | `/v3/get_my_info` (16) POST | **需 token** | user_detail.js:16–22 |
| user_follow.js | relationuser.kugou.com (26) | `/v4/follow_list` (20) POST | 关注列表 | user_follow.js:20–26 |
| user_follow_message.js | 网关默认 | `/msg.mobile/v3/msgtag/history` (9) GET | 消息历史 | user_follow_message.js:9–11 |
| user_vip_detail.js | kugouvip.kugou.com（直连:3） | `/v1/get_union_vip` (4) GET | 联合 VIP | user_vip_detail.js:3–7 |
| playhistory_upload.js | 网关默认 | `/playhistory/v1/upload_songs` (10) POST android, query plat=3 (14) | body {songs:[{mxid,op:1,ot(秒),pc}],token,userid}；**必须登录** | playhistory_upload.js:6–16 |
| user_history.js | 同上域 | `/playhistory/v1/get_songs` (11) POST | source_classify=app,to_subdivide_sr=1 | user_history.js:6–16 |

**版本变体猜测**：v3/get_my_info→v2/v1；v4/follow_list→v3/v2；v1/get_history、v1/upload_songs、v1/get_songs→v1；v1/daily_recommend→v1；无版本 /everyday_song_recommend 为特例（无降级）。

## 9. 签名/参数坑汇总（对 util 源码）

1. android 签名**包含 POST body 原文**（helper.js:31）→ body 序列化顺序/编码必须与签名一致；含中文/`+` 不做 URL 编码即可，但 query 中含 `+` 的值（如 hash 无）需原样参与签名（request.js 用 axios params 自动编码，签名取原始值 — 复刻实现需自行编码后签名）。
2. clienttime 双轨：网关层秒（request.js:39），FM/专辑/相似歌单/搜索 mixed 覆盖为毫秒且 key 用同一毫秒值——两处不一致必 400/签名错。
3. dfid 默认 '-'、uuid 恒 '-'（request.js:34/36），mid 必须带 cookie.KUGOU_API_MID；dfid/mid 参与部分服务端风控（kg-rf 固定值 request.js:41）。
4. Cookie：token/userid/vip_type 既进 query 默认参数（request.js:57–58）也用于 body；web 签名仅用于 comment_count 与 miniyueku 两处。
5. UA 特殊值：`Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi`；openapicdn 直连时参数拼进 URL 且清空 axios params（request.js:112–119）。
6. rawBody/AES 响应：user_cloud、playlist_del、user_listen 为 arraybuffer，响应需 AES(key 自生成的 6 位)/RSA 回执；`p` 参数 RSA 大写 hex。
7. register 签名（值排序拼接，无 k=、salt 1014）用于注册/设备类（register_dev.js, login_cellphone 等），不要套用到业务端点。
8. 错误语义：上游 `status:0`/`error_code!=0` 即失败（request.js:143）；Next `_ok()` 把 status=0 当成功属高危（capture_3state §4.1）。

## 10. 对 capture_3state 缺口的映射

- FM 真实路径 → §2 personal_fm.js:39 `/v2/personal_recommend` + persnfm（registry /v1/fm/play 死路径）。
- 云盘 AES → §3 user_cloud.js 全流程（RSA p + AES body + AES 响应），Next 未实现。
- 歌曲高潮 → song_climax.js `/v1/audio_climax/audio`（data 数组式，可批量）。
- 评论写/点赞 → **上游仓无源码**，纯缺口，需另行抓包。
- 收藏写真实路径 → playlist_tracks_add.js `/cloudlist.service/v6/add_song`；取消收藏 → playlist_del.js `/v2/delete_list`（AES）；registry /v2/collect 死声明。
- 歌单写 list_ver → 恒 0，应改用 detail 返回的实测 list_ver。
- 上报/历史 → playhistory_upload.js `/playhistory/v1/upload_songs`（Next 已封装未接线）；lastest_songs_listen.js 续播。
- 相似歌单 → playlist_similar.js `/pubsongs/v1/kmr_get_similar_lists`（Next 有封装 UI 未接，GAP #24）。
- 歌手专辑降级 → `/kmr/v1/author/albums` 502/403；降级候选 kmr/v2/author/albums、album_songs 反查。
- 搜索 typed/MV 结果 → search.js type=mv 走 `/v1/search/mv`；MvBrief 模型缺位（capture_3state §3），mvdata[].hash 在 /v3/search/song 已丢弃。

## 11. 候选端点清单（按优先级，只规划不实现）

| P | 端点 | 动作 |
|---|---|---|
| P0 | /v2/personal_recommend（FM） | 探针：匿名/登录各一次，留样响应键，修正 registry 路径 |
| P0 | mcloud /v1/get_list（云盘 AES） | 探针：带 token 复刻 RSA+AES 流程，留样解密后键 |
| P0 | cloudlist /v6/add_song + /v4/delete_songs | 探针：传实测 list_ver（先 /v7/get_all_list 取），验证乐观锁语义 |
| P1 | /v1/audio_climax/audio | 探针：多 hash 批量，确认 data[] 键名 |
| P1 | /playhistory/v1/upload_songs | 探针：登录态上报 1 条后用 /v1/get_songs 回读校验 |
| P1 | /v1/search/mv + complexsearch /v6 | 探针：v6 复测可达性，否则固化 v3/song 兜底 |
| P2 | kmr /v1/author/albums 变体（v2 前缀） | 探针 3 个版本候选各 1 次 |
| P2 | ocean v6 rank 三件套 v5/v4 降级候选 | 探针 |
| P3 | /v2/getSearchTip、/api/v3/search/hot_tab 变体 | 低收益探针 |
| P3 | 评论写/点赞 | 无法离线获得契约，需抓包或 ESCLATE |
