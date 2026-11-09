# KUGOU API 知识文档（TiernanMusic-Next）

> 来源：逆向项目 `KuGouMusicApi`（Node 网关，仅作知识参考，零代码复用）。
> 本文所有常量与算法均从该项目源码逐字抄录，出处以 `文件路径` 标注。
> 全部端点走网关基址 `https://gateway.kugou.com`（`util/request.js` 默认 baseURL），
> 除非模块显式覆盖 baseURL；带 `x-router` 头的请求由网关把请求转发到对应子域。

---

## 1. 签名算法

出处：`util/helper.js`（三个签名函数 + key 签名）、`util/request.js`（默认参数注入）、`util/config.json`（常量）。

### 1.1 常量（原样抄录，出处 `util/config.json`、`util/helper.js`、`util/request.js`）

| 常量 | 值 | 出处 |
|---|---|---|
| Android 签名 salt（普通版） | `OIlwieks28dk2k092lksi2UIkp` | helper.js signatureAndroidParams |
| Android 签名 salt（lite 版） | `LnT6xpN3khm36zse0QzvmgTZ3waWdRSA` | 同上 |
| Web 签名 salt | `NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt` | helper.js signatureWebParams |
| Register 签名 salt | `1014`（前后各拼一次） | helper.js signatureRegisterParams |
| signKey 盐（普通版） | `57ae12eb6890223e355ccfcb74edf70d` | helper.js signKey |
| signKey 盐（lite 版） | `185672dd44712f60bb1736df5a377e82` | helper.js signKey |
| tracker key 盐（song_url_new 用，同 lite signKey 盐） | `185672dd44712f60bb1736df5a377e82` | module/song_url_new.js |
| signParams 盐 | `R6snCXJgbCaj9WFRJKefTMIFp0ey6Gza` | helper.js signParams |
| 云盘 key 盐 | `ebd1ac3134c880bda6a2194537843caa0162e2e7`（前缀 `musicclound`） | helper.js signCloudKey |
| appid | `1005`（lite: `3116`） | util/config.json |
| clientver | `20489`（lite: `11440`） | util/config.json |
| srcappid | `2919` | util/config.json |
| apiver | `20` | util/config.json |
| 默认 dfid | `'-'`（可被 cookie.dfid 覆盖；song_url 等模块用 randomString(24)，字符集 `1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ`，util/util.js） | util/request.js |
| mid | cookie 中的 `KUGOU_API_MID`（可由 calculateMid 生成：md5(某字符串) 的 hex 按十六进制转十进制大整数，util/util.js） | util/request.js |
| uuid | `'-'` | util/request.js |
| 默认 User-Agent | `Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi` | util/request.js |
| 登录 UA（login_cellphone） | `Android16-1070-11440-130-0-LOGIN-wifi` | module/login_cellphone.js |
| 防爬头 | `dfid`、`clienttime`、`mid`、`kg-rc: 1`、`kg-thash: 5d816a0`、`kg-rec: 1`、`kg-rf: B9EDA08A64250DEFFBCADDEE00F8F25F` | util/request.js |

### 1.2 Android 签名（绝大多数端点用，`encryptType: 'android'`）

```
paramsString = params.keys.sort()                    // 参数名按 ASCII 升序
    .map(k => k + "=" + (isObj(params[k]) ? JSON.stringify(params[k]) : params[k]))
    .join("")                                        // 注意：无分隔符直接拼接
signature = md5(salt + paramsString + requestBodyOrEmpty + salt)
// salt = OIlwieks28dk2k092lksi2UIkp（lite 用 LnT6xpN3khm36zse0QzvmgTZ3waWdRSA）
// requestBodyOrEmpty = GET 为空串；POST 为 JSON 序列化后的 body 原文
// 结果作为 URL 查询参数 signature=<hex> 附加
```

### 1.3 Web 签名（登录二维码等，`encryptType: 'web'`）

```
paramsString = params.entries().map(k=>`${k}=${v}`).join('&').sort().join('')
// 实现细节：先拼成 "k=v" 串再整体排序后拼接（helper.js 原样逻辑）
signature = md5("NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt" + paramsString + "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt")
```

### 1.4 Register 签名（register_dev，`encryptType: 'register'`）

```
signature = md5("1014" + params.values.sort().join("") + "1014")   // 只排序"值"，不含键名
```

### 1.5 key 参数（play_url 专用，`encryptKey: true`）

`util/request.js`：当 `encryptKey` 时自动注入 `params['key'] = signKey(hash, mid, userid, appid)`：

```
key = md5(hash + "57ae12eb6890223e355ccfcb74edf70d" + appid + mid + (userid||0))
// hash = 歌曲 hash（小写）；lite 版盐为 185672dd44712f60bb1736df5a377e82
```

### 1.6 signParamsKey（时间戳签名，top_playlist / fm / playlist_similar / 登录等）

```
key = md5(appid + "OIlwieks28dk2k092lksi2UIkp" + clientver + clienttimeMs)
// 即 appid + Android盐 + clientver + 当前毫秒时间戳（与 body 里的 clienttime 一致）
```

### 1.7 默认参数注入（util/request.js，所有 android 签名请求）

每个请求自动合并以下查询参数（除非 clearDefaultParams）：
`dfid, mid, uuid='-', appid=1005, clientver=20489, clienttime=秒级时间戳`，
有 token 时加 `token`，有 userid 时加 `userid`。headers 同时带 `dfid/clienttime/mid`。

---

## 2. 加密工具（util/crypto.js、util/util.js）

### 2.1 AES-CBC（请求体加密，手机登录/token 续期）
```
cryptoAesEncrypt(data, opt?):
  若不传 key：随机 16 位小写串 tempKey；key = md5(tempKey)（32 hex）；iv = key 后 16 位
  若传 key+iv：直接用（登录模块的固定 key/iv）
  AES-128-CBC / PKCS7，输出 hex
```
固定 key/iv 对（module/login_token.js）：
- 普通：key `90b8382a1bb4ccdcf063102053fd75b8`，iv `f063102053fd75b8`
- lite：key `c24f74ca2820225badc01946dba4fdf7`，iv `adc01946dba4fdf7`
- lite t1：key `5e4ef500e9597fe004bd09a46d8add98`，iv `04bd09a46d8add98`
- lite t2：key `fd14b35e3f81af3817a20ae7adae7020`，iv `17a20ae7adae7020`

### 2.2 RSA（保护 AES key，`pk` 字段）
公钥 PEM 见 `util/crypto.js`（publicRasKey / publicLiteRasKey，1024 位）。两种用法：
- `cryptoRSAEncrypt`：无填充裸 RSA（明文左侧补零到 128 字节，modPow(e,n)），输出 hex，login_cellphone/user_detail 中 `.toUpperCase()`。
- `rsaEncrypt2`：RSAES-PKCS1-V1_5 填充，register_dev 用。
`pk = RSA(JSON({clienttime_ms, key: aesKey}))` —— 服务端用私钥解出 AES key 再解 `params`/`p`/`p3`。

### 2.3 KRC 歌词解密（util/util.js decodeLyrics —— 这是核心常量）
```
enKey = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]
bytes = base64Decode(content)        // lyrics.kugou.com 返回 base64
krc   = bytes[4..]                   // 跳过前 4 字节魔数
for i in 0..len: krc[i] ^= enKey[i % 16]
plain = zlibInflate(krc)             // 标准 zlib inflate → utf8 文本
```
lrc / contenttype != 0 时直接 base64 解码即可，无需异或解压。

### 2.4 其他
- `playlistAesEncrypt`：随机 6 位 key，`encryptKey = md5(key)[0:16]`，`iv = md5(key)[16:32]`，AES-CBC 输出 base64（register_dev）。
- md5 全部输出小写 hex。

---

## 3. 端点清单

> 通用约定：以下 URL 均相对 `https://gateway.kugou.com`（除非写明完整 URL 或模块覆盖 baseURL）；
> 方法 GET/POST 如标注；所有请求都带 §1.7 默认参数 + 对应签名；
> `x-router` 头决定真实后端子域。分页统一为 `page`(从 1) + `pagesize`(默认 30)。

### 3.1 搜索

**关键词搜索**（module/search.js）
- GET `/{v3|v1}/search/{type}`，headers `x-router: complexsearch.kugou.com`
- type ∈ song(v3)/special/lyric/album/author/mv(v1)
- 参数：`keyword`(string)、`page`、`pagesize`、`albumhide=0`、`iscorrection=1`、`nocollect=0`、`platform=AndroidFilter`
- ⚠️ **实测修正（2026-11-10，见 .test_creds/FINDINGS.md）**：响应歌曲列表字段是
  `data.lists[]`（`FileHash`/`FileName`/`SingerName`/`MixSongID`/`AlbumAudioId`/`Duration`/`Bitrate`），
  不是 `data.info[]`/`hash`。`data.total` 正确。

**综合搜索 v6**（module/search_complex.js）—— 更新版，推荐首选
- GET `https://complexsearch.kugou.com/v6/search/complex`
- 参数：`platform=AndroidFilter, keyword, page, pagesize, cursor=0`

**聚合搜索 v3**（module/search_mixed.js）
- GET `/v3/search/mixed`，`x-router: complexsearch.kugou.com`，另带 `kg-clienttimems: <ms>`
- 参数含 `ability=511, apiver=22, clientver=20125, platform=IOSFilter, requestid=md5("bdaa53d04e7475feb9024164a47032f9"+time)+"_0", keyword`

**搜索联想**（module/search_suggest.js）
- GET `/v2/getSearchTip`，`x-router: searchtip.kugou.com`
- 参数：`keyword, AlbumTipCount=10, CorrectTipCount=10, MVTipCount=10, MusicTipCount=10, radiotip=1`

**热搜榜**（module/search_hot.js）
- GET `/api/v3/search/hot_tab`，`x-router: msearch.kugou.com`，参数 `navid=1, plat=2`

**歌词搜索**（module/search_lyric.js）
- GET `https://lyrics.kugou.com/v1/search`（clearDefaultParams，不签名）
- 参数：`hash, keyword, duration, album_audio_id, lrctxt=1, man=no, appid, clientver`
- 响应：`candidates[]`（`id`, `accesskey` —— 供 /download 使用）

### 3.2 播放/下载链接

**play_url v5**（module/song_url.js）—— GET，按 hash 取单音质
- GET `/v5/url`，`x-router: trackercdn.kugou.com`，`encryptKey: true`（自动带 §1.5 key），cookie 用随机 dfid=randomString(24)- 参数（POST 风格 map 以 GET 参数发送）：
  `hash`(小写)、`album_audio_id`、`album_id`、`quality`(默认 128)、`area_code=1`、`behavior=play`、`ssa_flag=is_fromtrack`、`version=11430`、`clientver=11430`、`page_id=151369488`、`ppage_id=463467626,350369493,788954147`、`pid=2`、`cmd=26`、`pidversion=3001`、`IsFreePart`(0/1 试听)、`cdnBackup=1`
- 魔法音质：quality ∈ {piano,acappella,subwoofer,ancient,dj,surnay} → 传 `magic_<q>`
- ⚠️ **实测修正（2026-11-10，三态矩阵见 .test_creds/FINDINGS.md）**：
  成功时响应**顶层即数据**（无 data 包层）：`url`(数组)/`backupUrl`/`extName`/`bitRate`/`timeLength`/
  `status`(1=出URL)/`priv_status`(1=有权限,0=无)/`tracker_through.musicpack_advance`(1=VIP曲)。
  匿名 → status=2 errcode=20028「本次请求需要验证」；非VIP对VIP曲 → priv_status=0 无url。
  play_url 必须带 token+userid 参数及 Cookie（含 t1），dfid=随机24位，否则 20028。

**play_url v6**（module/song_url_new.js）—— POST，一次取多音质（推荐首选）
- POST `http://tracker.kugou.com/v6/priv_url`，encryptType android（body 参与 §1.2 签名）
- body：`qualities: ["128","320","flac","high","multitrack","viper_atmos","viper_tape","viper_clear","super"]`、
  `resource: {album_audio_id, hash, type:"audio", page_id:1, id:0, collect_list_id:"3", collect_time:<ms>}`、
  `tracker_param: {key: md5(hash+"185672dd44712f60bb1736df5a377e82"+appid+mid+userid), pid:"411", pidversion:"3001", priv_vip_type:"6", need_climax:1, need_xcdn:1, all_m:1, is_free_part, viptoken}`、`token, userid, vip, area_code:"1", behavior:"play"`
- vip 判定：响应 `data[]` 每档音质带 `hash` / `url` / `backup_url`；无权限档返回 `status` 非 0 或 `url` 为空；`is_free_part` 控制试听片段。

**歌曲权益判定**（module/privilege_lite.js）
- POST `/v2/get_res_privilege/lite`，`x-router: media.store.kugou.com`
- body：`resource: [{type:"audio", hash, album_id, page_id:0}]`（可批量）、`qualities:[同上9档]`、`area_code=1, behavior=play, need_hash_offset=1, relate=1, support_verify=1`
- 响应：`data[]` 每资源 `privilege[]`（各音质 `id`(档位)/`opcode`/`pay_type`），用于离线判断可播/需 VIP。

### 3.3 歌单

**歌单分类 tags**（module/playlist_tags.js）
- POST `/pubsongs/v1/get_tags_by_type`，body `{tag_type:"collection", tag_id:0, source:3}`

**推荐歌单列表**（module/top_playlist.js）
- POST `/v2/special_recommend`，`x-router: specialrec.service.kugou.com`
- body：`special_recommend:{categoryid, withtag:1, withsong:1, sort:1, ugc:1, is_selected:0, withrecommend:1, area_code:1}`、`page, pagesize, module_id=1, platform:"android", userid`、`key: signParamsKey(clienttimeMs)`（§1.6）
- categoryid 0=推荐，11292=HI-RES

**歌单详情**（module/playlist_detail.js）
- POST `/v3/get_list_info`，`x-router: pubsongs.kugou.com`
- body：`data: [{global_collection_id: <歌单id>}]`（可批量）、`userid, token`
- 响应：`data[]`：`global_collection_id, specialname, imgurl, playcount, count, intro, username, tags`

**歌单全部歌曲（旧版）**（module/playlist_track_all.js）
- GET `/pubsongs/v2/get_other_list_file_nofilt`
- 参数：`global_collection_id, page/pagesize 转 begin_idx=(page-1)*pagesize, pagesize, area_code=1, plat=1, type=1, mode=1, personal_switch=1, extend_fields=abtags,hot_cmt,popularization`
- 响应：`data.info[]`（`hash, album_audio_id, name, singername...`）+ `data.count`

**歌单全部歌曲（新版，含自建歌单）**（module/playlist_track_all_new.js）
- POST `/v4/get_list_all_file`，`x-router: cloudlist.service.kugou.com`
- body：`listid, userid, token, page, pagesize, area_code=1, show_cover=1, allplatform=1, type=0`

**用户歌单**（module/user_playlist.js）
- POST `/v7/get_all_list`，`x-router: cloudlist.service.kugou.com`，query `plat=1&userid&token`
- body：`userid, token, total_ver, type=2, page, pagesize`

**歌单增删歌曲**：POST `/v2/add_songs_by_hash`（playlist_tracks_add，body `resource:[{name,hash,album_id,mixsongid,number:1}]` + `listid,userid,token,list_ver:0`）；删除 module/playlist_tracks_del.js。建/删歌单：playlist_add.js / playlist_del.js。

**相似歌单**（module/playlist_similar.js）：POST `/pubsongs/v1/kmr_get_similar_lists`，body `data:[{global_collection_id}]` + `key: signParamsKey(clienttime)`。

### 3.4 排行榜

- 榜单列表：GET `/ocean/v6/rank/list`（rank_list.js），参数 `plat=2, withsong=1, parentid=0`；响应 `data.info[]`（`rankid, rankname, imgurl...`）
- 榜单详情：GET `/ocean/v6/rank/info`（rank_info.js），参数 `rankid, rank_cid=0, with_album_img=1, zone=''`；响应 `data.songs[]`/`data.list[]`（`hash, name, singername`）
- 其他：rank_top.js（顶部 banner）、rank_vol.js（vol 期刊）、song_ranking.js（歌曲成绩单：GET `/grow/v1/song_ranking/play_page/ranking_info?album_audio_id=`）

### 3.5 歌词

**krc/lrc 下载**（module/lyric.js）
- GET `https://lyrics.kugou.com/download`
- 参数：`id, accesskey`（来自歌词搜索）、`fmt=krc|lrc`、`client=android`、`ver=1`、`charset=utf8`
- 响应：`content`(base64)、`contenttype`(0=krc 加密，需 §2.3 解密；非 0 直接 base64 解)、`fmt`、`duration`

### 3.6 歌手 / 专辑 / 相似推荐

- 歌手列表：GET `/ocean/v6/singer/list`（artist_lists.js / singer_list.js），参数 `hotsize=200, musician=0, sextype=0, showtype=2, type=0`
- 歌手详情：POST `/kmr/v3/author`，`x-router: openapi.kugou.com`，`kg-tid: 36`，body `{author_id}`（artist_detail.js）
- 歌手相关：artist_albums/artist_audios/artist_videos/artist_follow/artist_honour/artist_follow_newsongs 等（module/artist_*.js）
- 专辑详情：POST `/kmr/v2/albums`，`x-router: openapi.kugou.com`，`kg-tid: 255`，body `data:[{album_id}], fields:"album_id,album_name,publish_date,sizable_cover,intro,..."`（album_detail.js）
- 专辑歌曲：POST `/v1/album_audio/lite`，`x-router: openapi.kugou.com`，`kg-tid: 255`，body `{album_id, page, pagesize, is_buy}`（album_songs.js）
- 歌单详情/相似已在 3.3；歌曲相似/场景推荐：module/scene_*.js、theme_music.js、ai_recommend.js

### 3.7 每日推荐 / 私人FM / 每日打卡

- 每日推荐：POST `/everyday_song_recommend`，`x-router: everydayrec.service.kugou.com`，body `{platform:"android", userid}`（recommend_songs.js，需登录 token）
- 私人FM：POST `/v1/fm/play`（personal_fm.js，见模块内 baseURL/路由），body 含 `action:"play", song_pool_id, mode:"normal", m_type:1, key: signParamsKey(clienttimeMs), mid, userid, kguid`，fakem 常量 `ca981cfc583a4c37f28d2d49000013c16a0a`
- 电台歌曲：fm_songs.js（fmid/fmtype/offset/size 批量，key 同 §1.6）

### 3.8 登录 / 账号（cookie/token 体系）

- 二维码 key：GET `https://login-user.kugou.com/v2/qrcode`，encryptType web，参数 `appid=1001(移动)|1014(web), type=1, plat=4, qrcode_txt, srcappid=2919`（login_qr_key.js）
- 二维码轮询：GET `https://login-user.kugou.com/v2/get_userinfo_qrcode`，参数 `plat=4, appid, srcappid, qrcode=<key>`；status：0 过期 / 1 待扫 / 2 待确认 / 4 成功（此时 `data.token`、`data.userid` 下发，login_qr_check.js）
- 短信验证码登录：POST `https://loginserviceretry.kugou.com/v7/login_by_verifycode`（login_cellphone.js）：body `params` = AES(随机key) 加密的 `{mobile, code}` hex，`pk` = RSA({clienttime_ms, key}) 大写 hex，`key = signParamsKey(ms)`，UA `Android16-1070-11440-130-0-LOGIN-wifi`
- token 续期（刷新登录）：POST `http://login.user.kugou.com/v5/login_by_token`（login_token.js）：`p3 = AES固定key({clienttime, token})`（key `90b8382a1bb4ccdcf063102053fd75b8` / iv `f063102053fd75b8`），`pk = RSA({clienttime_ms, key})`，`params = AES随机key({})`，t1/t2（lite）见 §2.1
- 设备信息：POST `https://userinfoservice.kugou.com/v2/get_dev`（login_device.js）；设备注册 register_dev.js（encryptType register）
- 用户详情：POST `/v3/get_my_info`，`x-router: usercenter.kugou.com`，query `plat=1`，body `p = RSA({token, clienttime}).toUpperCase(), visit_time, usertype:1, userid`（user_detail.js）
- VIP 信息：GET `https://kugouvip.kugou.com/v1/get_union_vip?busi_type=concept`（user_vip_detail.js）

### 3.9 其他功能模块（按需重写）

- 听歌历史上报：POST `/playhistory/v1/upload_songs`（query `plat=3`），body `{songs:[{mxid, op:1, ot:秒, pc:1}], token, userid}`（playhistory_upload.js）
- 听歌排行：POST `/playhistory/v1/get_songs`，body `{token, userid, source_classify:"app", to_subdivide_sr:1}`（user_history.js）
- 评论：POST `/mcomment/v1/cmtlist`，`mixsongid, p, pagesize, code: fc4be23b4e972707f36b8a828a93ba8a`（comment_music.js；另有 comment_floor/album/playlist）
- 云盘：user_cloud.js / user_cloud_url.js（signCloudKey §1）
- 视频：video_detail/video_url/video_privilege；长音频 longaudio_*；乐谱 sheet_*（opern）；场景电台 scene_*；青年模式 youth_*；乐库 yueku_*
- 收藏计数 favorite_count.js；歌曲高潮片段 song_climax.js；图片 images.js
