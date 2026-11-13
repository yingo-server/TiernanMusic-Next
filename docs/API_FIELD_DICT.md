# API_FIELD_DICT — 字段字典（按域分节，批01-C 骨架，2026-11-14）

> 锚点格式：`§x` = `docs/API_FIELDS_TRUTH.md` 章节；「待实测」= 矩阵复测后回填。
> 类型注记：str/int/bool/arr/obj；「str(int)」= 实测为字符串但语义是整数。

## 通用信封
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| status | 顶层 | int | 否 | 搜索/榜单/歌单系业务码（1=成功）；歌词系复用 HTTP 码（200） | §A1/§A3-3 |
| error_code | 顶层 | int | 否 | 0=成功；20006/20010/20018/20028/35104/152 见矩阵 verdict | §A6 |
| error_msg / errmsg | 顶层 | str | 是 | 失败时 | 待实测 |
| data | 顶层 | obj/arr | 否 | 形态逐端点不同（平铺/数组/嵌套），见各域 | §A1~§A6 |

---

## 播放域（play_url / privilege_lite）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| ⚠️ **顶层即数据，非 data[]** | — | obj | 否 | play_url 成功响应 22 键全在顶层 | §A3-1 |
| url / backupUrl | url[] | arr[str] | 是 | status==1 && priv_status==1（VIP/合法态） | §A3-1 |
| status | 顶层 | int | 否 | 1=出 URL；2=需验证(20028)；0=无权限 | §A3-1 |
| priv_status | 顶层 | int | 是 | 仅登录态返回；1=有权限；匿名无此键 | §A3-1 |
| bitRate | 顶层 | int | 否 | bps；flac 档恒 0，不可用 bitrate 判档 | §A3-1 |
| timeLength | 顶层 | int | 否 | 秒（试听判定以此+hash_offset 为准） | §A3-1 |
| hash_offset | 顶层 | obj | 是 | 非VIP 试听（clip_hash/end_ms=60000） | §A3-1 |
| errcode | 顶层 | int | 是 | 20028 匿名需验证 | §A3-1 |
| tracker_through.musicpack_advance | tracker_through | int | 否 | 1=VIP 曲 | §A3-1 |
| trans_param.qualitymap / ogg_* | trans_param | obj | 是 | 档位/ogg 哈希 | §A3-1 |
| privilege | data[0].privilege | int | 否 | privilege_lite：恒 10，**不作权限判定** | §A3-2 |
| resource[].{type,page_id,hash,album_id} | 请求 body | obj[] | 否 | resource 必须对象数组（裸 str 数组→20010） | §A3-2 |
| qualities | 请求 body | arr[str] | 否 | 128/320/flac/high/viper_* /super/multitrack | §A3-2 |
| data[hash].downurl / backupdownurl | data | obj | 否 | videoUrl；单串+数组 | §A5-3 |

## 搜索域（v3/song, v1/special, album, author, mv, lyric, suggest）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| ⚠️ **列表恒在 data.lists[]**（不是 data[]） | data.lists | arr | 否 | 搜索系全部 | §A1-1 |
| total | data.total | int | 否 | v3/song | §A1-1 |
| FileHash | data.lists[].FileHash | str | 否 | 大写 | §A1-1 |
| Audioid / Scid | data.lists[].Audioid | int | 否 | ⚠️ 无 AlbumAudioId 键 | §A1-1 |
| MixSongID / AlbumID | data.lists[].MixSongID | str(int) | 否 | 实测字符串 | §A1-1 |
| Duration | data.lists[].Duration | int | 否 | 秒 | §A1-1 |
| trans_param.musicpack_advance | data.lists[].trans_param | int | 否 | 1=VIP 曲 | §A1-1 |
| Suffix / ExtName / Bitrate / PublishAge | data.lists[].* | int/str | 是 | — | §A1-1 |
| HQ / SQ / Res / mvdata | data.lists[].* | obj/arr | 是 | 高档位/MV 关联 | §A1-1 |
| specialid / specialname / img / song_count / play_count | data.lists[].* | — | 是 | 歌单搜索；⚠️ img 非 imgurl/pic、song_count 非 count | §A1-2 |
| albumid / albumname / img / songcount / publish_time | data.lists[].* | — | 是 | 专辑搜索 | §A1-3 |
| AuthorId / AuthorName / Avatar / FansNum | data.lists[].* | — | 是 | 歌手搜索（大写驼峰族） | §A1-4 |
| MvID / MvName / MvHash / Pic / ThumbMp4 | data.lists[].* | — | 是 | MV 搜索 | §A1-5 |
| LyricID / FullLyric / 320Hash / SQHash | data.lists[].* | — | 是 | 歌词搜索 | §A1-6 |
| data（数组）+ LableName + RecordDatas[] | data[] | arr | 否 | searchSuggest：⚠️ data 是数组非 records 包裹 | §R1-A-8 |
| /v6/search/complex | — | — | — | 实测不可达（502×3），字段不固化 | §A1-7 |

## 评论域
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| FileHash | 请求/响应键 | str | 否 | 评论以 FileHash 定位歌曲 | 待实测（⚠️ 已知坑） |
| like.count | like | obj | 否 | 点赞数嵌套在 like.count，非平铺 likeCount | 待实测（⚠️ 已知坑） |
| tid | item | str/obj | 否 | 评论 thread id | 待实测（⚠️ 已知坑） |

## 收藏域（= 写「我喜欢」歌单）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| ⚠️ **listid=2「我喜欢」**（listid=1 默认收藏已弃用，不用） | data.info[].listid | int | 否 | user_playlist 返回中按 name=='我喜欢' 定位 | §收藏 |
| data.info[0].fileid | data.info[] | int | 否 | add_song 回执（=album_audio_id 口径，**非 hash**） | §A6-3/§收藏 |
| data.listid / pre_list_ver | data | int | 否 | add_song 成功态 | §A6-3 |
| data.count / data.list_ver | data | int | 否 | delete_songs 成功态（count=删除数） | §A6-4 |
| mixsongids → collect 映射 | data | obj | 否 | favorite_count 只读收藏数 | 待实测 |
| /collect、/cancel_collect | — | — | — | 上游无独立端点，不臆造 URL | ENDPOINT_TRUTH §5 |

## 歌词域
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| ⚠️ **status==200 才算成功**（非 1；HTTP 码复用，404 未命中仍返结构） | 顶层 | int | 否 | lyricSearch/download 全部 | §A3-3/§A3-4 |
| candidates | 顶层（无 data 包层） | arr | 是 | 顶层即数据 | §A3-3 |
| id / download_id / uid | candidates[].* | str(int) | 否 | 实测字符串 | §A3-3 |
| accesskey | candidates[].accesskey | str | 否 | 大写 hex，download 必带 | §A3-3 |
| contenttype | 顶层/candidates[] | int | 否 | 0=krc（加密）1=lrc（明文 b64） | §A3-4 |
| content | 顶层 | str | 否 | base64；krc 需解密（"krc1"魔数+16B XOR+zlib） | §A3-4/§A3-5 |
| duration | candidates[].duration | int | 否 | 毫秒 | §A3-3 |
| product_from / hitlayer / transuid | candidates[].* | — | 是 | 官方轨判定/译文轨作者 | §A3-3 |
| 独立翻译端点 | — | — | — | 不存在；译文随 krc 内嵌 | §A3-5 |

## 用户域
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| ⚠️ **data 平铺，头像键是 pic**（非 avatar/user_pic） | data.pic | str | 否 | userDetail 成功态 | §R1-A-1 |
| nickname / vip_type / gender / birthday | data.* | — | 是 | 平铺 | §R1-A-1 |
| ⚠️ 无 userid / 无 level 键 | — | — | — | userid 客户端自持；level 如实 0 | §R1-A-1 |
| p | 请求 body/query | str | 否 | 裸 RSA 右补零大写；键序 {token,clienttime}(userDetail)/{clienttime,token}(listen) | §R1-A-1 |
| 匿名 error_code=20018 | 顶层 | int | — | userDetail 匿名态 | §R1-A-1 |
| data.lists[] / total_week / total_history | data | arr/int | 否 | listenReport（收听列表，非上报；上报走 personal_fm action） | §R1-A-3 |
| qrcode / qrcode_img | data | str | 否 | qr_key：qrcode_img=PNG base64 官方图 | §QR 实测 |
| data.status | data | int | 否 | qr_check 登录状态在 **data 内**（1待扫/2待确认/4成功），顶层 status=1 恒业务成功 | §QR 实测 |
| token / userid | data | str | 否 | qr_check data.status==4 时下发 | §QR 实测 |

## FM 域（personal_fm / fm_songs / fm_class / fm_recommend / yueku_fm）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| body.data.songs[] | body.data | arr | 是 | personal_fm 歌曲池 | 待实测 |
| action / songid / playtime | 请求 body | — | 否 | 播放上报经 personal_fm action 承载，**无独立 fm_play 端点** | ENDPOINT_TRUTH §3 |
| fmid / fmtype / offset / size | body.data[] | — | 否 | fm_songs 请求 | 待实测 |
| 其余字段 | — | — | — | 全部待三态实测回填 | 待实测 |

## 榜单域（rank list/info / rankAudio）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| rankid / rankname / imgurl / update_frequency / issue | data.info[] | — | 是 | rank/list；⚠️ 无 updatetime 键 | §A2-4 |
| ⚠️ **songinfo[] 仅 3 字段**：album_audio_id / album_cover / songname | data.songinfo[] | arr | 否 | rank/info；无 hash/mixsongid，如实 0/空 | §A2-4 |
| total / data.songlist[] | data | int/arr | 否 | rankAudio（tid 369，匿名可用） | §R1-A-6 |
| business.sort / audio_info.hash_128 | data.songlist[] | int/str | 否 | 名次/音源 | §R1-A-6 |

## 歌单域（recommend / detail / tracks / similar / 写操作）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| special_list[] / global_collection_id / imgurl | data.special_list[] | arr/str | 否 | recommend；tags 是**字符串数组** | §A2-1 |
| ⚠️ detail data 是**数组**：name(非 specialname) / pic(非 imgurl) / count | data[0].* | — | 否 | get_list_info；tags 是**逗号分隔字符串**；无 playcount | §A2-2 |
| songs[] / count；song.timelen=毫秒、song.size、singerinfo[] | data.* | — | 否 | nofilt 曲目；⚠️ 非 timelen(秒)/filesize/singername 平铺 | §A2-3 |
| data[] → collection_list[]（双层） | data[].collection_list[] | arr | 否 | similar 双形态（另见 §A4-4 collection_info 形态）；cover 完整 URL，song_count int | §A3-3 |
| ⚠️ **listid 路径 = data.info.listid**（data.listid/data.id 不存在） | data.info.listid | int | 否 | create 成功态 | §A6-2 |
| info[] 逐曲回执 fileid/number/hash | data.info[] | arr | 否 | add_song 成功态 | §A6-3 |
| list_ver 递增 | data.list_ver | int | 否 | 写操作成功态 | §A6-4 |
| data[] 直排 + tag_name + son[] | data[] | arr | 否 | tags 分类（⚠️ 非 data.tags[]/tagname） | §A6-5 |
| data.info[] 40 键：listid/pic/count/tags(空串) | data.info[] | arr | 否 | user_playlist；⚠️ listid 非 specialid | §A6-1 |
| delete_list 响应 | 顶层（二进制） | bytes | 否 | AES 密文回包，按字节解密（非 base64 文本） | §R1-A-5 |

## MV 域（bySong / videoDetail / videoUrl）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| ⚠️ **data 是嵌套数组 data[0][]** | data[0][] | arr | 否 | bySong（旧口径 /kmr/audio/mv 502 不存在） | §A5-1 |
| video_id / mv_name / hdpic / duration(ms) | data[0][].* | — | 否 | ⚠️ MV 项无 hash 键（hash 从歌曲侧 mvdata[].hash 取） | §A5-1 |
| {ld,sd,hd,fhd,qhd}_{hash,hash_265,filesize,bitrate,width,height} | data[0] 平铺 | int/str | 是 | videoDetail 档位前缀展开（无数组） | §A5-2 |
| timelength | data[0] | int | 否 | 毫秒 | §A5-2 |
| mkv_sd_* / mkv_qhd_* / audio_* | data[0] | — | 是 | mkv/音轨档 | §A5-2 |
| status / privileges{hash:0/1} / data | 顶层 | — | 否 | videoUrl；仅 cmd=123/pid=1 合法（12/4/25→40003） | §A5-3 |

## 推荐域（recommend_endpoints）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| 全部字段 | — | — | — | 待三态实测回填（special_recommend 已归歌单域 §A2-1） | 待实测 |

## 专辑域（album_audio/lite / kmr/v2/albums）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| base.{audio_name,author_name,album_id,audio_id,album_audio_id} | data.songs[].base | obj | 否 | lite 十键结构族（⚠️ 与 nofilt 不同族，用 fromAlbumLite） | §A4-2 |
| audio_info.{hash,hash_320,hash_flac,duration(毫秒),bitrate,extname} | data.songs[].audio_info | obj | 否 | — | §A4-2 |
| album_info.{album_name,cover} / authors[] / copyright.privilege* | data.songs[].* | obj/arr | 否 | — | §A4-2 |
| deprecated.{video_hash,video_id,pay_type,cid} | data.songs[].deprecated | obj | 是 | MV 关联 | §A4-2 |
| mvdata[].{typ,trk,hash,id} | data.songs[].mvdata | arr | 是 | id="596344" 字符串 | §A4-2 |
| album_name / sizable_cover / publish_date / publish_company / grade / heat / language / type | data[0].* | str | 否 | kmr/v2/albums；data 是数组 | §A4-3 |
| ⚠️ cover 是裸文件名（非 URL，不可展示）；无曲目数键 | data[0].cover | str | 否 | 封面取 sizable_cover | §A4-3 |

## 歌手域（kmr/v3/author / audio_group/author / author/albums）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| author_id / author_name / sizable_avatar / long_intro / album_count / song_count / mv_count / fansnums / area_id / birthday | data 平铺 | — | 是（intro 可空串） | 14 键；⚠️ fansnums 复数形式；匿名与 VIP 同构 | §A4-1 |
| data 平铺数组：audio_name / hash_128..super / timelength(毫秒) / trans_param.musicpack_advance / video_id | data[] | — | 否 | audio_group/author；⚠️ 无 singerinfo/mixsongid/singername 键 | §A4-2' |
| /v1|/kmr/v1/author/albums | — | — | — | 实测不可达（502/403），不猜，降级路径已接线 | §A4-5 |

## 登录域（send_verifycode / login_cellphone / login_token / qr / register_dev）
| 字段 | 路径 | 类型 | 可空 | 出现条件 | 锚点 |
|---|---|---|---|---|---|
| businessid / mobile / plat | 请求 body | — | 否 | send_verifycode（http 明文域） | ENDPOINT_TRUTH §2 |
| secu_params | data.secu_params | str | 否 | status==1 时 AES 解出 token/userid/vip_type/vip_token | ENDPOINT_TRUTH §2 |
| pk / params / t1 / t2 / t3 / clienttime_ms | 请求 body | str | 是 | RSA/AES 密文族；lite 才有 t1/t2/dev | ENDPOINT_TRUTH §2 |
| mobile（打码）/ code | 请求 body | str | 否 | login_cellphone | ENDPOINT_TRUTH §2 |
| p = rsaEncrypt2({aes,uid,token}) | 请求 query | str | 否 | PKCS1 v1.5，大写 | §A6-7 |
| dfid | data.dfid | str | 否 | register_dev 解密后（需 playlistAesDecrypt） | ENDPOINT_TRUTH §2 |
| qrcode_txt / appid=1001 / plat=4 | 请求 query | — | 否 | qr_key；web 签名 | §QR 实测 |

## 已知坑汇总（必查）
1. **play_url 顶层非 data[]**：22 键全平铺；匿名 20028，非VIP priv_status=0/35104。
2. **搜索 data.lists[]**：所有搜索系列表路径，勿取 data[]。
3. **评论**：FileHash 定位、like.count 嵌套、tid 三处口径待实测固化。
4. **收藏 listid=2**：listid=1 是已弃用默认收藏；fileid 非 hash；add_song 用 x-router 形态（URL 前缀式 404）。
5. **歌词 status=200**：非业务 1；顶层即数据；id/download_id 是字符串；直连 lyrics.kugou.com 恒空体，必须 gateway+x-router。
6. **用户 data 平铺 pic**：头像主键 pic；无 userid/level 键；p 用裸 RSA 右补零。
7. 歌单详情 tags 是逗号字符串，recommend tags 是字符串数组，user_playlist tags 是空串——三形态并存。
8. 时长单位三态并存：秒（搜索 Duration / play_url timeLength）vs 毫秒（nofilt timelen / lite duration / author timelength / MV duration）。
