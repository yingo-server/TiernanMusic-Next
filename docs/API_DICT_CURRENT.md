# API_DICT_CURRENT — 新版 API 调用字典（含三态真实返回）

> 范围：`lib/core/net/endpoints/` + `lib/core/net/kugou_client.dart` EndpointRegistry（54 端点）。
> 证据等级：✅ 已实测（有三态留样/探针落盘）；⚠️ 部分实测（仅部分态或部分字段）；❔ 待实测（仅有上游模块推断或未探针）。
> 证据来源缩写：FIND＝`.test_creds/FINDINGS.md`；N1A＝`N1A_FINDINGS.md`；N3A＝`N3A_FINDINGS.md`；FT＝`docs/API_FIELDS_TRUTH.md`（批 N1/N2-A/N2-B/N2-C/N3-B/N3-C/R1-A 分节）；ET＝`docs/ENDPOINT_TRUTH.md`（上游模块提取，非直连实测）。
> 通用事实：签名=android（按名 ASCII 排序 k=v 拼 md5(salt+s+salt)）；默认参 dfid/mid/uuid/appid/clientver/clienttime 恒显式入签；**mid 缺失/空 → 20006**（N1A §0）；srcappid 入签 → cloudlist 系 20006（FT A6）。
> 旧版对照：`docs/API_DICT_LEGACY.md` 尚未生成，§4 仅按旧代码注释推断，全部标「待对照」。

## 1. 端点总表

| 函数/端点 | 域 | 方法 | 路径（gateway 除非注明） | x-router | 关键参数 | 签名 | 成功判定 | 证据 |
|---|---|---|---|---|---|---|---|---|
| searchSong | 搜索 | GET | /v3/search/song | complexsearch | keyword,page,pagesize,iscorrection=1 | android | status=1 且 data.lists[] 非空 | ✅ N1A §1/FT A1-1 |
| searchComplex | 搜索 | GET | complexsearch 直连 /v6/search/complex | — | keyword | android | **不可达**（502/152） | ✅ N1A §5/FT A1-7 |
| searchSuggest | 搜索 | GET | /v2/getSearchTip | searchtip | keyword,+TipCount 组 | android | status=1；data[] 数组分组 | ✅ N1A §2/FT R1-A-8 |
| searchHot | 搜索 | GET | /api/v3/search/hot_tab | msearch | navid=1,plat=2 | android | status=1；data.list[].keywords[] | ✅ N1A §3 |
| playUrlV5 | 播放 | GET | /v5/url | trackercdn | hash(小写),quality,album_audio_id,album_id,cmd=26… + key=playKey + token/userid/Cookie t1 | android+key | status==1 && priv_status==1 && url 非空 | ✅ FIND/FT A3-1/A2-C |
| playUrlV6 | 播放 | POST | tracker.kugou.com /v6/priv_url | — | 多档批量 | android | 未探针 | ❔ FIND §待测 |
| privilegeLite | 播放 | POST | /v2/get_res_privilege/lite | media.store | resource:[{type,page_id,hash,album_id}],qualities[] | android | status=1,error_code=0 | ✅ FT A3-2/N2-A |
| lyricSearch | 歌词 | GET | /v1/search | lyrics | hash,keyword,duration,album_audio_id,lrctxt=1,man=no | android | **status=200**（非1）；candidates[] | ✅ FT A3-3 |
| lyricDownload | 歌词 | GET | /download | lyrics | ver=1,client=android,id,accesskey,fmt,charset | android | status=200,content(base64) | ✅ FT A3-4 |
| playlistRecommend | 歌单 | POST | /v2/special_recommend | specialrec.service | categoryid,withtag…,page,pagesize,key=signParamsKey | android | status=1；data.special_list[] | ✅ FT A2-1 |
| playlistDetail | 歌单 | POST | /v3/get_list_info | pubsongs | data:[{global_collection_id}],userid,token | android | status=1；data[] 数组首项 | ✅ FT A2-2 |
| playlistTracks | 歌单 | GET | /pubsongs/v2/get_other_list_file_nofilt | — | specialid（gc_id 报 20010）,begin_idx,pagesize,extend_fields | android | status=1；data.songs[]+count | ✅ FT A2-3 |
| playlistSimilar | 歌单 | POST | /pubsongs/v1/kmr_get_similar_lists | — | data:[{gc_id}],appid/clientver/clienttime/key/userid/ugc/show_list/need_songs | android | status=1；data[].collection_list[] | ✅ FT A3-3/A4-4 |
| playlistTags | 歌单 | POST | /pubsongs/v1/get_tags_by_type | — | tag_type:'collection',tag_id:0,source:3 | android | status=1；data[]+son[] | ✅ FT A6-5 |
| userPlaylists | 歌单 | POST | /v7/get_all_list | cloudlist.service | plat=1,userid,token；body total_ver:979,type:2 | android+omitSrcappid | status=1；data.info[]；匿名 20010 | ✅ FT A6-1 |
| playlistCreate | 歌单写 | POST | /cloudlist.service/v5/add_list（前缀式） | — | last_time,last_area=gztx,userid,token；body name,type:0 | android+omitSrcappid | status=1；**data.info.listid** | ✅ FT A6-2/R1-A-4 |
| playlistDelete | 歌单写 | POST | /v2/delete_list | cloudlist.service | p=rsaEncrypt2({aes,uid,token}),key,AES密文 rawBody | android+omitSrcappid | 解密后 status=1 | ✅ FT A6-6/A6-7/R1-A-5 |
| playlistAddSongs | 歌单写 | POST | /v6/add_song | cloudlist.service | last_time,last_area,userid,token；body data:[{number,name,hash小写,size,timelen,bitrate,album_id,mixsongid}] | android+omitSrcappid | status=1；data.info[] 回执 fileid | ✅ FT A6-3 |
| playlistDelSongs | 歌单写 | POST | /v4/delete_songs | cloudlist.service | body data:[{fileid}]（=album_audio_id 非 hash） | android+omitSrcappid | status=1；data.list_ver 递增 | ✅ FT A6-4 |
| rankList | 榜单 | GET | /ocean/v6/rank/list | — | — | android | status=1；data.info[] | ✅ FT A2-4 |
| rankInfo | 榜单 | GET | /ocean/v6/rank/info | — | rankid,rank_cid=0,with_album_img=1 | android | status=1；songinfo 仅 3 字段 | ✅ FT A2-4 |
| rankAudio | 榜单 | POST | /openapi/kmr/v2/rank/audio | —（kg-tid 369） | rankid,page,pagesize | android | status=1（匿名可用）；data.songlist[] | ✅ FT R1-A-6 |
| artistDetail | 歌手 | POST | /kmr/v3/author | openapi（kg-tid 36） | body {author_id} | android | status=1；data 平铺 14 键；匿名=VIP 同构 | ✅ FT A4-1 |
| artistAudios | 歌手 | POST | /kmr/v1/audio_group/author | openapi（kg-tid 220） | body {author_id,page,pagesize} | android | status=1；data 平铺数组 103 键 | ✅ FT A4-2'/N3-C |
| artistAlbums | 歌手 | GET | /v1/author/albums | openapi | author_id | android | **不可达**（502 三态复测） | ✅ FT A4-5/A4-3' |
| artistList | 歌手 | GET | /ocean/v6/singer/list | — | — | android | 未探针 | ❔ |
| albumDetail | 专辑 | POST | /kmr/v2/albums | openapi（kg-tid 255） | body {data:[{album_id}]} | android | status=1；data[] data[0] 21 键 | ✅ FT A4-3 |
| albumSongs | 专辑 | POST | /v1/album_audio/lite | openapi（kg-tid 255） | body {album_id,page,pagesize,is_buy:0} | android | status=1；data.songs[] 10 键结构 | ✅ FT A4-2 |
| recommendSongs | 推荐 | POST | /everyday_song_recommend | everydayrec.service | — | android | 未探针 | ❔ |
| personalFm | FM | POST | /v2/personal_recommend | persnfm.service | action,key(ms 毫秒),fakem=固定串,m_type:1,area_code:1 | android | status=1；**data.song_list[]**；匿名可用 | ✅ N3A §6 |
| fmSongs | FM | POST | /v1/app_song_list_offset（注册表仍 /v1/fm/songs 待改） | fm.service | data:[{fmid,fmtype,offset,size}],key(ms) | android | status=1；data[].songs[] | ⚠️ N3A §6 实测真实路径，注册表路径未接线 |
| fmClass/class_fm_song | FM | POST | /v1/class_fm_song | fm.service | kguid,clienttime(ms),mid,key | android | status=1；data.class_list[] | ✅ N3A §6 |
| fmRecommend | FM | POST | /v1/rcmd_list | fm.service | rcmdsongcount:1,level:0,uid:0,key(ms) | android | status=1；data[].rcmdlist[] | ✅ N3A §6 |
| yuekuFm/time_fm_info | FM | GET | /v1/time_fm_info | fm.service | operator=7,plat=0,type=11,req_multi=1 | android | status=1；data[].fm_list | ✅ N3A §6 |
| mvDetail | MV | POST | /kmr/v1/audio/mv | openapi（kg-tid 38） | body {data:[{album_audio_id}],fields:''} | android | status=1；data[0][] 嵌套数组 | ✅ FT A5-1 |
| videoDetail | MV | POST | /v1/video | kmr.service | clearDefaultParams 全参 body+key=signParamsKey,show_resolution:1 | android | status=1；data[0] 88 键平铺档位 | ✅ FT A5-2 |
| videoDetailKmrV2 | MV | POST | /kmr/v2/videos | kmr.service | video_id | android | **不可达**（三态 404） | ✅ FT R1-A-7 |
| videoUrl | MV | GET | /v2/interface/index | trackermv | backupdomain=1,cmd=123,ext=mp4,pid=1,type=1,hash + key=playKey | android+key | status=1；data[hash].downurl | ✅ FT A5-3 |
| loginQrKey | 登录 | GET | login-user /v2/qrcode | — | appid=1001,type=1,plat=4,qrcode_txt | web | status=1；data.qrcode/qrcode_img | ✅ FT QR 登录节 |
| loginQrCheck | 登录 | GET | login-user /v2/get_userinfo_qrcode | — | plat=4,qrcode=key | web | 顶层 status=1；**登录态看 data.status**(2/4) | ✅ FT QR 登录节 |
| loginToken | 登录 | POST | login.user /v5/login_by_token | — | p3=AES,pk=RSA,params=AES | android | secu_params 解密流程 | ❔ ET §2 推断 |
| smsLogin | 登录 | POST | loginserviceretry /v7/login_by_verifycode | — | params=AES,pk=RSA,support-calm 头 | none | 未探针（只构造不外发） | ❔ |
| sendSmsCode | 登录 | POST | login.user /v7/send_mobile_code | — | businessid:5,mobile,plat:3 | none | 未探针 | ❔ ET §2 |
| commentMusic | 评论 | POST | /mcomment/v1/cmtlist | mcomment | **query**:mixsongid,p,pagesize,code=fc4be…；歌单 childrenid=collection_3_.._366_0+code=ca53b9… | android | 顶层 status='1'；count/list/hot_word_list/classify_list 顶层 | ✅ N3A §1 |
| commentFloor | 评论 | POST | /mcomment/v1/hot_replylist（歌单走 m.comment.service 前缀） | mcomment | **tid**(非 commentid),childrenid,mixsongid/song code | android | status=1；comments_num/list | ✅ N3A §2 |
| commentCount | 评论 | POST | /index.php | sum.comment.service | r=comments/getcommentsnum,code,**hash**（mixsongid 恒 0） | **web** | 响应 {hash:count} | ✅ N3A §3 |
| favoriteCount | 收藏 | GET | /count/v1/audio/mget_collect | 注册表标 sum.comment（实测无 x-router 直连通） | mixsongids 逗号分隔 | android | status=1；**data.list[]**（非映射） | ✅ N3A §5 |
| collectSong/cancelCollect | 收藏 | POST | （无真实端点） | — | — | — | 上游无歌曲 collect 端点；收藏=写「我喜欢」歌单 listid=2 | ✅ N3A §5/FT 收藏节 |
| userDetail | 用户 | POST | /v3/get_my_info | usercenter | **p=cryptoRSAEncrypt({token,clienttime}) 裸 RSA 右补零**,usertype:1 | android | 匿名 20018；登录态 status=1；data 平铺（pic 平铺头像） | ✅ FT R1-A-1 |
| playHistoryUpload | 用户 | POST | /playhistory/v1/upload_songs | — | plat=3；body songs:[{mxid,op:1,ot,pc}] | android | 匿名 20010；登录态 status=1,data.songs[].code=1 | ✅ FT R1-A-2 |
| listenReport | 用户 | POST | listenservice 直连 /v2/get_list | — | p=cryptoRSAEncrypt({clienttime,token})；body t_userid/userid 字符串 | android | 匿名 20010；登录态 status=1；lists[] 35 键 | ✅ FT R1-A-3 |
| songClimax | 用户 | GET | expendablekmrcdn /v1/audio_climax/audio | — | data=[{hash},…] | android | 未探针 | ❔ ET §1 |
| userCloud | 用户 | POST | mcloudservice /v1/get_list（注册表仍 /v1/user_cloud 待改） | — | p=rsaEncrypt2,AES body,notSignature | none | 未探针 | ❔ ET §1 |

## 2. 三态真实返回（匿名 / 非VIP / VIP）

### play_url（/v5/url）— FIND §表 + FT A3-1（两次独立实测，VIP 曲=晴天 hash b3a52a7a…）
- 匿名：`status=2, errcode=20028「本次请求需要验证」`，顶层仅 errcode/error/fail_process:[pkg]/status，**无 priv_status、无 url**。
- 非VIP（VIP 曲）：FIND 记 `status=2, priv_status=0` 无 url；FT N2-A（带 key 后）记 `status=0, error_code=35104 "Hash not found"`——两种失败形态并存，判定一律不信 error_code，只信 status/priv_status/url。
- 非VIP（免费曲，musicpack_advance=0）：status=1 出 URL（FIND §9 贝瓦儿歌）。
- VIP：`status=1, priv_status=1, url[]+backupUrl[]`（约 5 分钟有效）；128/320 mp3 bitRate=档位×1000；**flac 档 bitRate=0 不可用 bitrate 判档**。
- 关键：key=md5(hash+`57ae12eb6890223e355ccfcb74edf70d`+appid+mid+userid||0)；错盐恒 `status=0 illegal key`(31833)（FT A3-1 负对照）。

### privilege_lite — FIND §10/11 + FT A3-2
- 匿名：status=1 正常返回（不校验登录，可作元数据源）。非VIP/VIP：status=1，**privilege=10 三态同值（int 标量），不用于权限判定**。
- resource 必须是对象数组（裸 hash 串数组 → 20010）。

### /v3/search/song — N1A §1
- 三态均可读（不校验登录态，假 token 也 status=1）；失败形态=签名错 20006（data 仍回空 lists）。

### /v7/get_all_list（用户歌单）— FT A6-1
- VIP：status=1（17 歌单）；非VIP：status=1（3 歌单）；匿名：**status=0 error_code=20010**。

### 建歌单 v5/add_list — FT R1-A-4
- 匿名 20010；非VIP data.info.listid=5；VIP listid=42。明文 body 即通（无加密）。

### 删歌单 v2/delete_list — FT R1-A-5
- 明文兜底：两账号均 `status=0 error_code=20010 "need param p"`；加密契约（p=rsaEncrypt2 PKCS1-v1_5 + AES-128-CBC rawBody，响应为二进制密文需按字节解密）打通：非VIP/VIP 均 status=1 删除成功。

### 加/删歌 v6/add_song、v4/delete_songs — FT A6-3/4 + 收藏节
- VIP/非VIP status=1（逐曲回执 data.info[]）；VIP 完整加/删往返通过并清理测试数据；匿名未逐测（缺登录态属 20010 族，实证价值有限）。

### 歌词 search/download — FT A3-3/4
- 三态均返回 candidates（歌词不校验登录态）；VIP 曲命中官方轨 hitlayer=1，匿名命中 UGC 轨。status=200 语义。

### 评论域 — N3A §1-4
- cmtlist/hot_replylist/count/hotword/classify **匿名全部可读**；登录态额外返回 captcha/haslike 点赞态。

### favorite_count — N3A §5
- 匿名可用；data.list[]{mixsongid,count,count_text("4787w")}。

### FM 域 — N3A §6
- personal_recommend/rcmd_list/class_fm_song/app_song_list_offset/time_fm_info **匿名全部 status=1 可读**；登录态 kguid 应与 userid 一致。

### userDetail / listenReport / playHistoryUpload — FT R1-A-1/2/3
- 匿名分别 20018 / 20010 / 20010；非VIP/VIP 均 status=1 error_code=0。userDetail 响应**无 userid/level 字段**，头像主键=pic。

### rankAudio — FT R1-A-6
- 三态全部 status=1（匿名可用）；total=100，data.songlist[]。

### MV videoUrl/videoDetail — FT A5-2/3
- 三态留样以 VIP 号为主（qhd 档实测出 downurl）；匿名/非VIP 对 VIP MV 档位行为**未实测**。

## 3. 字段层级与坑（全部实测）

- **play_url：响应顶层即数据**（22 键 url/backupUrl/bitRate/extName/timeLength(秒)/status/priv_status/tracker_through…），**无 data 包层**（FIND §1/FT A3-1）。
- **搜索系：列表路径 `data.lists[]`**（song/album/author/mv/lyric/special 全部），info[] 不存在；越界页返回 total=0+空 lists（「没有更多」应看 lists.isEmpty）（N1A §1/§4）。
- 搜索 song item：**无 `AlbumAudioId` 键**（用 `Audioid`，=Scid）；`MixSongID/AlbumID` 是**字符串**；`musicpack_advance` 在 `trans_param` 内**不在顶层**（N1A §1）。
- 歌单搜索 item：封面键=`img`（非 imgurl/pic）、`play_count`/`song_count` 下划线（FT A1-2）。
- 歌单详情：键=`name`/`pic`/`list_create_username`，tags=**逗号分隔字符串**，count=曲目数，**无 playcount 键**（FT A2-2）。
- 歌单曲目：`timelen` 是**毫秒**、`size`（非 filesize）、singerinfo[] 数组无平铺 singername、albuminfo.name（FT A2-3）。
- 评论：响应**顶层即数据**；点赞是对象取 **`like.count`**；楼中楼参数键是 **`tid`**（commentid 无效）；评论数端点**必须传 hash**（mixsongid 恒 0）；歌单评论 childrenid 必须 `collection_3_<specialid>_366_0` 形态（N3A §1-3）。
- 收藏：favorite_count 返回 `data.list[]`（非映射）；**歌曲收藏=写 listid=2「我喜欢」歌单**（listid=1 默认收藏已弃用），加歌用 /v6/add_song+x-router 形态（URL 前缀式 404）、删用 /v4/delete_songs，**fileid=album_audio_id 非 hash**（N3A §5/FT 收藏节）。
- 歌词：search/download 成功判定 **status=200**（非 1）；直连 lyrics.kugou.com 恒空体，必须 gateway+x-router；candidates 的 id/download_id 是字符串；krc 解密链 b64→去"krc1"魔数→XOR 16 字节表→zlib（FT A3-3/4/5）。
- 用户：userDetail 的 data **平铺**（pic 平铺头像，无 userid/level 键）（FT R1-A-1）。
- FM：列表键是 **`data.song_list[]`**（personal_recommend）/ `data[].songs[]`（app_song_list_offset），别名 songs/list 不命中；FM 域 clienttime/key 用**毫秒**，其余域用秒（N3A §6）。
- 专辑详情：cover 是裸文件名不可展示（用 sizable_cover）；publish_date（无 publish_time）；**无曲目数键**（取 albumSongs 的 data.total）（FT A4-3）。
- 榜单：rank/info 的 songinfo 仅 3 字段（album_audio_id/album_cover/songname），无 hash——完整曲目走 rankAudio（FT A2-4/R1-A-6）。
- cloudlist 系：**omitSrcappid 必须**；建歌单 listid 在 `data.info.listid`（A6-2/R1-A-4）。

## 4. 新旧版差异（API_DICT_LEGACY.md 未生成 → 全部「待对照」，仅按旧代码注释推断）

- 旧版 play_url 直连 kapi.344977.xyz 返回 404 → 新版统一 gateway.kugou.com（FIND §6）。〔待对照〕
- 旧版歌词「不签名」记载（KUGOU_API.md §3.1）被实测推翻：必须 android 签名+默认参（FT A3-3）。〔待对照〕
- 旧版 privilege_lite「body 只需 appid/clientver」不完整：resource 必须对象数组（FT A3-2）。〔待对照〕
- 旧版歌单删除用明文 body → 新版加密契约 p+AES rawBody（FT R1-A-5）。〔待对照〕
- 旧版删歌 body resource:[{hash,number}] → 新版 data:[{fileid}]（FT A6-4）。〔待对照〕
- 旧版综合搜索 v6 complex → 上游失效 152，新版三段并列降级（FT 降级节）。〔待对照〕
- v6/priv_url、songClimax、userCloud、登录三端点：新版注册表已有声明但契约未实测，与旧版差异不明。〔待对照〕

## 5. 改造建议（按网络层分离原则；每条 ≤2 行）

1. **换实现（端点不可达/路径错）**：searchComplex→弃用走三段并列（已降级✅）；artistAlbums→走 search/album 降级（已接线✅）；videoDetailKmrV2 仅留 fallback；fmSongs 注册表路径 /v1/fm/songs → /v1/app_song_list_offset+x-router fm.service（实测真实路径未接线）。
2. **补字段/解析**：collectSong/cancelCollect 声明改为「写/删 listid=2 歌单」契约化；fmSongs 解析键 data[].songs；userCloud 注册表路径 /v1/user_cloud → mcloudservice /v1/get_list（ET §1）。
3. **新增（上游有而注册表缺）**：rcmd_list/class_fm_song/time_fm_info/personal_recommend 已在 fm_endpoints 层实现，建议注册表补声明以便统一审计；user_video_collect（MV 收藏列表）可新增声明。
4. **待实测后收口**：playUrlV6 批量档、songClimax、userCloud、smsLogin/sendSmsCode/loginToken 契约——探针留样后只改 Endpoint 声明，不动 KugouClient.request。
5. **勿依赖**：privilege_lite 权限判定（三态同值）；scene_collection_list（502）；v6 complex。
