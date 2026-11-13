# API_CONTRACT_MATRIX — 契约矩阵骨架（批01-C，2026-11-14）

> 事实来源（只读）：`docs/ENDPOINT_TRUTH.md`（URL/域名/x-router/方法/签名）、
> `docs/API_FIELDS_TRUTH.md`（字段树/三态实测）。端点模块清单取自
> `lib/core/net/endpoints/`（23 个 dart 模块）。本文件是**骨架**：除已被
> API_FIELDS_TRUTH 实证过的行外，全部标注「待实测」。
> 探针工具：`tool/api_matrix_probe.dart`（骨架，不发真实请求；网络层由主会话填）。

## 三态凭据来源（铁律）

| 态 | 来源 | 说明 |
|---|---|---|
| vip | `.test_creds/cj_vip.txt` | uid 1666835066，cookie/token 从本地文件读入 |
| nonvip | `.test_creds/cj_nonvip.txt` | uid 2461028533 |
| anonymous | 无凭据 | 不带 cookie/token/userid |

- **凭据不得进仓库**：`.test_creds/` 永不入 git；探针输出落盘 `.test_creds/`。
- **日志脱敏**：打印响应时必须抹除 token / cookie / t1 / mid / userid / p / key / signature / secu_params 全部值，只留键名与长度。
- dfid/mid/uuid 恒显式携带并参与签名（六五规则铁律 6）。

## verdict 枚举（唯一合法取值）

| 枚举 | 语义 |
|---|---|
| OK | 三态（或该端点合法态）实测 status=1，字段树固化 |
| NO_PRIV | 匿名/非VIP 无权限（如 20010 需登录、priv_status=0、35104） |
| NEED_VERIFY | 匿名命中 errcode=20028「本次请求需要验证」 |
| EMPTY | 200/HTTP 可达但返回空体（如直连 lyrics.kugou.com） |
| RISK | 可达但形态异常/双形态/风控抖动（502 抖动、双层嵌套等） |
| SKIP | 端点不可达或上游无此模块（502/404/152/无 URL），不猜字段 |

## 端点模块清单（23 个 dart 模块，逐行待实测标注）

| endpoint 模块 | 方法 | URL/域名 | state | http | ms | envelope 顶层键 | success 判定式 | 关键字段 | verdict |
|---|---|---|---|---|---|---|---|---|---|
| search_endpoints / search_typed_endpoints | GET | gateway.kugou.com /v3/search/song（x-router complexsearch） | all | 200 | 待实测 | status,error_code,error_msg,data | status==1 | data.lists[], data.total, FileHash, MixSongID(str), Audioid(⚠️无 AlbumAudioId), musicpack_advance | OK（§A1-1） |
| search 系 /v1/search/special | GET | gateway + x-router complexsearch | all | 200 | 待实测 | 同上 | status==1 | data.lists[], specialid, img, song_count, play_count | OK（§A1-2） |
| search 系 /v1/search/album | GET | gateway + x-router complexsearch | all | 200 | 待实测 | 同上 | status==1 | data.lists[], albumid, img, songcount | 待实测（键集 §A1-3） |
| search 系 /v1/search/author | GET | gateway + x-router complexsearch | all | 200 | 待实测 | 同上 | status==1 | data.lists[], AuthorId, AuthorName, Avatar | 待实测（键集 §A1-4） |
| search 系 /v1/search/mv | GET | gateway + x-router complexsearch | all | 200 | 待实测 | 同上 | status==1 | data.lists[], MvID, MvHash, FileHash | 待实测（键集 §A1-5） |
| search 系 /v1/search/lyric | GET | gateway + x-router complexsearch | all | 200 | 待实测 | 同上 | status==1 | data.lists[], LyricID, FullLyric | 待实测（键集 §A1-6） |
| search /v6/search/complex | GET | complexsearch.kugou.com | all | 502×3 | 待实测 | 非 JSON | — | — | SKIP（§A1-7 实测不可达，三路容错维持） |
| searchSuggest /v2/getSearchTip | GET | gateway + x-router searchtip | all | 200 | 待实测 | status,error_code,data[] | status==1 | data[] 分组 RecordDatas[]/LableName（data 是数组！） | 待实测（§R1-A-8） |
| play_endpoints play_url /v5/url | GET | gateway + x-router trackercdn | 3 态 | 200 | 待实测 | **顶层即数据，非 data[]** | status==1 && priv_status==1 && url 非空 | url[], backupUrl[], bitRate(bps), timeLength(s), tracker_through.musicpack_advance | OK（§A3-1 三态矩阵） |
| privilege_lite /v2/get_res_privilege/lite | POST | gateway + x-router media.store | 3 态 | 200 | 待实测 | appid_group,data[],error_code,status | status==1 | data[0].privilege=10(int 不作权限判定), pay_type, trans_param, info | 待实测（键集 §A3-2） |
| quality_endpoints | POST | gateway | 3 态 | 200 | 待实测 | 待实测 | 待实测 | 待实测 | 待实测 |
| lyricSearch /v1/search | GET | gateway + x-router lyrics | all | 200 | 待实测 | **顶层即数据** | status==200（非 1！） | candidates[], id(str), accesskey, contenttype=0(krc) | OK（§A3-3） |
| lyricDownload /download | GET | gateway + x-router lyrics | all | 200 | 待实测 | 顶层平铺 | status==200 && content 非空 | content(base64), contenttype(0=krc,1=lrc), fmt | OK（§A3-4） |
| lyric_models / misc_endpoints krcDecode | 本地 | — | all | — | — | — | 解密成功 | "krc1" 魔数 + 16 字节 XOR + zlib inflate | OK（§A3-5） |
| playlist_endpoints recommend /v2/special_recommend | POST | gateway + x-router specialrec | all | 200 | 待实测 | status,error_code,data | status==1 | data.special_list[], global_collection_id, imgurl, tags(str[]) | OK（§A2-1） |
| playlist_detail /v3/get_list_info | POST | gateway + x-router pubsongs | all | 200 | 待实测 | 同上 | status==1 | data[](数组!)[0]: name,pic,count,tags(逗号str),list_create_username；⚠️无 playcount | OK（§A2-2） |
| playlist_tracks /pubsongs/v2/get_other_list_file_nofilt | GET | gateway | all | 200 | 待实测 | 同上 | status==1 | data.songs[], data.count; song: hash, singerinfo[], timelen(ms), size | OK（§A2-3） |
| rank /ocean/v6/rank/list + /info | GET | gateway | all | 200 | 待实测 | 同上 | status==1 | data.info[]; info: rankid, update_frequency, issue；songinfo[] 仅 3 键 | OK（§A2-4） |
| rankAudio /openapi/kmr/v2/rank/audio (tid 369) | POST | gateway | all（匿名可用） | 200 | 待实测 | status,errcode,data | status==1 | data.songlist[], business.sort, audio_info.hash_128 | OK（§R1-A-6） |
| playlist_endpoints similar /pubsongs/v1/kmr_get_similar_lists | POST | gateway | all | 200 | 待实测 | 同上 | status==1 | **data[] 数组 → collection_list[]** 双形态；cover, song_count, songs[] | OK（§A3-3 双形态容错） |
| album_endpoints songs /v1/album_audio/lite (tid 255) | POST | openapi | all（匿名同构） | 200 | 待实测 | 待实测 | status==1 | data.songs[] 十键: base/audio_info/album_info/authors/copyright/deprecated | OK（§A4-2） |
| album_endpoints detail /kmr/v2/albums (tid 255) | POST | openapi | all | 200 | 待实测 | 待实测 | status==1 | data[0]: album_name, sizable_cover, publish_date；⚠️无曲目数键；cover 是裸文件名 | OK（§A4-3） |
| artist_endpoints detail /kmr/v3/author (tid 36) | POST | openapi | all（匿名同构） | 200 | 待实测 | 待实测 | status==1 | data 平铺 14 键: author_name, sizable_avatar, fansnums, album_count | OK（§A4-1） |
| artist_endpoints audios /kmr/v1/audio_group/author (tid 220) | POST | openapi | all | 200 | 待实测 | status,errcode,data,total | status==1 | data 平铺数组, audio_name, hash_128, timelength(ms), trans_param | OK（§A4-2'） |
| artist albums /v1|/kmr/v1/author/albums | POST | openapi | all | 502/403 | 待实测 | — | — | SKIP（§A4-5 实测不可达，降级路径已接线） |
| mv_endpoints bySong /kmr/v1/audio/mv (tid 38) | POST | openapi | all | 200 | 待实测 | 待实测 | status==1 | **data[0][] 嵌套数组**, video_id, mv_name, duration(ms) | OK（§A5-1） |
| mv videoDetail /v1/video | POST | gateway + x-router kmr.service | all | 200 | 待实测 | 待实测 | status==1 | data[0] 88 键平铺: ld_/sd_/hd_/fhd_/qhd_* 档位前缀展开 | OK（§A5-2；/v1/video/detail 404 → SKIP） |
| mv videoUrl /v2/interface/index | GET | trackermv.kugou.com | all | 200 | 待实测 | status,privileges,data | status==1 | data[hash].downurl, backupdownurl[]；key=md5(hash+signKeySalt+appid+mid+userid\|\|0)；仅 cmd=123/pid=1 合法 | OK（§A5-3） |
| fm_endpoints personal_fm /v2/personal_recommend | POST | gateway + x-router persnfm | 3 态 | 200 | 待实测 | 待实测 | status==1 | body.data.songs[]；action 承载播放上报 | 待实测 |
| fm_songs /v1/app_song_list_offset | POST | gateway + x-router fm.service | 3 态 | 200 | 待实测 | 待实测 | status==1 | body.data[*] 歌曲数组 | 待实测 |
| fm_class /v1/class_fm_song | POST | gateway + x-router fm.service | 3 态 | 200 | 待实测 | 待实测 | status==1 | 待实测 | 待实测 |
| fm_recommend /v1/rcmd_list | POST | gateway + x-router fm.service | 3 态 | 200 | 待实测 | 待实测 | status==1 | 待实测 | 待实测 |
| yueku_fm /v1/time_fm_info | GET | gateway + x-router fm.service | 3 态 | 200 | 待实测 | 待实测 | status==1 | query operator=7/type=11 | 待实测 |
| recommend_endpoints | GET | gateway | 3 态 | 200 | 待实测 | 待实测 | 待实测 | 待实测 | 待实测 |
| user_endpoints userDetail /v3/get_my_info | POST | gateway + x-router usercenter | 3 态 | 200 | 待实测 | status,error_code,data | status==1 | data 平铺: nickname, **pic(非 avatar)**, vip_type；匿名 20018；p=裸RSA{token,clienttime} | OK（§R1-A-1） |
| user_endpoints listenReport /v2/get_list | POST | listenservice.kugou.com（非 gateway） | 3 态 | 200 | 待实测 | status,error_code,data | status==1 | data.lists[] 收听列表；匿名 20010 | OK（§R1-A-3） |
| user_cloud /v1/get_list | POST | mcloudservice.kugou.com | 登录态 | 200 | 待实测 | AES 解密后 | 解密成功 | arraybuffer→playlistAesDecrypt；notSignature | 待实测 |
| user_cloud_url /bsstrackercdngz/v2/query_musicclound_url | GET | gateway | 登录态 | 200 | 待实测 | body.data | status==1 | data 内 ortest/url CDN 字段；key=signCloudKey | 待实测 |
| playhistory upload /playhistory/v1/upload_songs | POST | gateway | 3 态 | 200 | 待实测 | status,error_code,data | status==1\|\|error_code==0 | data.songs[].mxid(str), code=1；匿名 20010 | OK（§R1-A-2） |
| playhistory get_songs /playhistory/v1/get_songs | POST | gateway | 3 态 | 200 | 待实测 | status,error_code,data | status==1 | data.songs[] | 待实测 |
| song_climax /v1/audio_climax/audio | GET | expendablekmrcdn.kugou.com | 3 态 | 200 | 待实测 | 待实测 | status==1 | data[*] 高潮起点/时长 | 待实测 |
| lastest_songs_listen /playque/devque/v1/get_latest_songs | POST | gateway | 登录态 | 200 | 待实测 | 待实测 | status==1 | body.data | 待实测 |
| favorite_count /count/v1/audio/mget_collect | GET | gateway | 3 态 | 200 | 待实测 | body.status | status==1 | data: mixsongid→collect 映射 | 待实测 |
| auth_endpoints send_verifycode /v7/send_mobile_code | POST | login.user.kugou.com | 3 态 | 200 | 待实测 | body.status | status==1 | 待实测 | 待实测 |
| login_cellphone /v7/login_by_verifycode | POST | loginserviceretry.kugou.com | 3 态 | 200 | 待实测 | body.status | status==1 && 解出 data.secu_params（AES: token/userid/vip_type） | 待实测 | 待实测 |
| login_qr_key /v2/qrcode | GET | login-user.kugou.com | all | 200 | 待实测 | body.status,data | status==1 | data.qrcode(key), data.qrcode_img(png base64) | 待实测（QR 实测已复核） |
| login_qr_check /v2/get_userinfo_qrcode | GET | login-user.kugou.com | all | 200 | 待实测 | body.status,data | data.status==4（业务码在 data 内！） | data.status(1待扫/2待确认/4成功), data.token/userid | 待实测 |
| login_token /v5/login_by_token | POST | login.user.kugou.com | 登录态 | 200 | 待实测 | body.status | status==1 | secu_params 同 login_cellphone | 待实测 |
| register_dev /risk/v2/r_register_dev | POST | userservice.kugou.com | all | 200 | 待实测 | 解密后 body.status | status==1 → data.dfid | arraybuffer→playlistAesDecrypt | 待实测 |
| get_verify_info /verifyservice/v3/get_verify_info | POST | gateway | 3 态 | 200 | 待实测 | body.status | status==1 | 待实测 | 待实测 |
| collect_endpoints（收藏=写「我喜欢」歌单） | POST | gateway + x-router cloudlist.service | 登录态 | 200 | 待实测 | status,error_code,data | status==1 | 找 name=='我喜欢' 的 listid（=2，非 listid=1 默认收藏）；fileid 来自 add 回执非 hash | 待实测（契约 §收藏 实测） |
| comment_endpoints | POST | gateway | 3 态 | 200 | 待实测 | 待实测 | 待实测 | FileHash / like.count / tid | 待实测（⚠️ 待固化，见 FIELD_DICT 坑清单） |
| playlist_write create /cloudlist.service/v5/add_list | POST | gateway（URL 前缀式，omitSrcappid） | 3 态 | 200 | 待实测 | status,error_code,data | status==1 | **data.info.listid**（data.listid 不存在）；匿名 20010；明文 body 即通 | OK（§A6-2/§R1-A-4） |
| playlist_write delete /v2/delete_list | POST | gateway + x-router cloudlist | 登录态 | 200 | 待实测 | AES 密文（二进制回包） | 解密后 status==1 | p=rsaEncrypt2({aes,uid,token}) PKCS1；AES key/iv=md5hex ASCII 字节；rawBody 入签 | OK（§R1-A-5） |
| playlist_write add_song /v6/add_song | POST | gateway + x-router cloudlist（非前缀式！前缀式 404） | 登录态 | 200 | 待实测 | status,error_code,data | status==1 | data.info[] 逐曲回执 fileid/number/hash；hash 传小写 | OK（§A6-3/§收藏） |
| playlist_write delete_songs /v4/delete_songs | POST | gateway + x-router cloudlist | 登录态 | 200 | 待实测 | status,error_code,data | status==1 | data:{list_ver 递增,count}；body data:[{fileid}] | OK（§A6-4） |
| playlist_tags /pubsongs/v1/get_tags_by_type | POST | gateway | all | 200 | 待实测 | status | status==1 | data[] 直排 + tag_name + son[] 子标签 | OK（§A6-5） |
| user_playlist /v7/get_all_list | POST | gateway + x-router cloudlist | 3 态 | 200 | 待实测 | status,error_code,data | status==1（匿名 20010） | data.info[] 40 键: listid, pic, count, tags(空串) | OK（§A6-1） |
| translation_endpoints | 本地/无 | 上游无独立翻译端点 | — | — | — | — | — | 译文随 krc 内嵌（transuid/transname） | SKIP（ENDPOINT_TRUTH §6） |
| misc_endpoints 其余 | — | gateway | 3 态 | 200 | 待实测 | 待实测 | 待实测 | 待实测 | 待实测 |

## 实测方法约定

1. 每端点跑三态（anonymous / nonvip / vip），写端点跑「加→查→删」往返不留脏数据。
2. http=HTTP 状态码；ms=响应耗时（P50）；envelope=响应顶层键集（逐键留样）。
3. verdict 判定优先级：20028 → NEED_VERIFY；20010/20018/35104/priv_status=0 → NO_PRIV；空体 → EMPTY；502/404/152/上游无模块 → SKIP；双形态/抖动 → RISK；否则 OK。
4. 复跑命令入口：`dart run tool/api_matrix_probe.dart`（骨架仅打印用法与清单；网络层留主会话填充）。
5. 回归锚点：`tool/field_truth_test.dart`（FIELD-TRUTH-OK）。
