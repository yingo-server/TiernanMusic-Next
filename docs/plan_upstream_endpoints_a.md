# 上游原生端点全表（A 组：播放/歌曲URL/音质/登录/设备注册/MV/视频/歌词）

> 源：`KuGouMusicApi/module/`（只读源码提取，行号为证据行）。未实测、未运行任何入口。
> 签名类型：`android` = 通用 android 签名（useAxios encryptType），`web` = web 签名，`signParamsKey` = md5 时间参数 key，`notSign` = 不参与签名。

## 1. 歌曲 URL / 音质

### song_url.js — /v5/url（GET）
- 域名/路由：`x-router: trackercdn.kugou.com`（L49）
- 签名：`encryptType: 'android'`, `encryptKey: true`, `notSign: true`（L48-50）
- 关键参数（L15-38）：`hash`(小写)、`album_audio_id`、`quality`(默认128，支持 magic_piano/acappella/subwoofer/ancient/dj/surnay)、`album_id`、`area_code:1`、`ssa_flag:'is_fromtrack'`、`version:11430`、`clientver:11430`、`page_id`(lite=967177915/普通=151369488)、`ppage_id`、`behavior:'play'`、`pid`(lite=411/普通2)、`cmd:26`、`pidversion:3001`、`IsFreePart`(试听)、`cdnBackup:1`；cookie 注入随机 `dfid`（L51）
- 登录态：非强制（可用匿名+随机 dfid；带 token/userid/vip_token 可解锁更高音质）
- 响应字段（键名证据，源自 useAxios 通用处理与本仓库文档惯例）：`status`、`data` → 每档含 `url`/`backupUrl`、`hash`、`ext_name`、`file_head`、`time`、`bitrate`、`size`、`trans_param`(含 `music_id`/`privilege`/`pay_type`/`crawlUrl` 等)。
- 证据行：L12-13（quality）、L17-20（page_id）、L28（quality||128）、L49（/v5/url）
- 版本变体：源码 v5 → 猜测可试 v5、v4、v3（待实测）；不建议升 v6。

### song_url_new.js — /v6/priv_url（POST，9 档音质）
- 域名：`baseURL: http://tracker.kugou.com`（L42）
- 签名：`encryptType: 'android'`（L43）
- 关键参数（L6-40）：
  - `qualities`：`['128','320','flac','high','multitrack','viper_atmos','viper_tape','viper_clear','super']`（L14）—— 共 9 档
  - `resource`：`album_audio_id`、`hash`、`type:'audio'`、`page_id`、`collect_list_id`、`collect_time`、`id`
  - `tracker_param`（L21-34）：`all_m:1`、`need_climax:1`、`need_xcdn:1`、`is_free_part`、`pid:'411'`、`pidversion:'3001'`、`priv_vip_type:'6'`、`viptoken`(vip_token)、`key = md5(hash + '185672dd44712f60bb1736df5a377e82' + appid + KUGOU_API_MID + userid)`
  - 顶层：`token`、`userid`、`vip`(vip_type)、`area_code:'1'`、`behavior:'play'`
- 登录态：**要求** `token`/`userid`（key 计算依赖 userid）；`vip_token` 影响 VIP 档
- 响应字段：`status`、`data` → 按 qualities 分档，键含 `hash`、`url`/`backupUrl`、`quality`、`priv_status`(0=可完整播放)、`filename`、`ext_name`、`time`、`trans_param`
- 证据行：L14（9 档）、L25（key md5）、L42-44（baseURL/url/method）
- 版本变体：源码 v6 → 猜测可试 v6、v5、v4（v5 与 song_url.js 的 /v5/url 可能同轨，待实测）。

### user_cloud_url.js — 云盘歌曲 /bsstrackercdngz/v2/query_musicclound_url（GET）
- 默认域名（无 x-router，走默认网关），签名 android + `key=signCloudKey(hash,20026)`（L21）
- 参数：`hash`(小写)、`album_audio_id`、`audio_id`、`ssa_flag:'is_fromtrack'`、`version:'20102'`、`pid:20026`、`ssl:0`、`kv_id:2`、`bucket:'musicclound'`、`name`、`with_res_tag:0`
- 响应字段：`status`、`url`/`backup_url`、`hash`
- 证据行：L9-25。版本变体：v2 → 试 v2、v1（待实测）。

### song_climax.js — /v1/audio_climax/audio（GET，audio 高潮段）
- `baseURL: https://expendablekmrcdn.kugou.com`，`params.data=[{hash}]`（L11-13）

## 2. 权限（privilege）

### privilege_lite.js — /v2/get_res_privilege/lite（POST）
- `x-router: media.store.kugou.com`（L27）
- 参数：`resource=[{type:'audio',page_id:0,hash,album_id}]`、`qualities`（128/320/flac/high/viper_atmos/viper_tape/viper_clear/super/multitrack，L18-20）、`behavior:'play'`、`need_hash_offset:1`、`relate:1`、`support_verify:1`
- 响应字段：`status`、`data[]` 每项 `hash`、`priv_status`、`quality`(档位数组)、`pay_type`、`filename`
- 证据行：L21-27。版本变体：v2 → 试 v2、v1（待实测）。

### video_privilege.js — /v1/get_video_privilege（POST）
- `x-router: media.store.kugou.com`（L30）；参数 `resource=[{hash,id,name}]`、`token`、`userid`、`vip`、`area_code`、`behavior:'play'`（L14-23）。响应 `status`/`data[].priv_status`。

## 3. 登录 / 设备注册

| 文件 | 域名 | 方法+路径 | 签名 | 关键参数 | 返回字段 | 登录态 | 证据行 |
|---|---|---|---|---|---|---|---|
| login.js | login.user.kugou.com (x-router) | POST /v9/login_by_pwd | android；pwd AES + RSA pk | plat:1, support_multi:1, username, params(AES{pwd,code,clienttime_ms}), pk(RSA), t1/t2/t3 | status, data.secu_params→解出 token/userid/vip_type/vip_token, t1 | 否 | L9-21, L24-31, L36-46 |
| login_cellphone.js | loginserviceretry.kugou.com | POST /v7/login_by_verifycode | android + lite t1/t2 AES | mobile(脱敏), params(AES{mobile,code}), key=signParamsKey, pk, plat, lite 加 dfid/dev/gitversion | status, data.secu_params→token/userid/vip_type/vip_token/t1 | 否 | L38-58, L61-72 |
| login_token.js | login.user.kugou.com | POST /v5/login_by_token | android，p3=AES{clienttime,token}(固定key 90b8…/lite c24f…) | dfid, p3, plat, t1/t2/t3, pk, params, userid, clienttime_ms | status, data.secu_params→token/userid/vip_type/vip_token/t1 | 是(旧 token) | L36-53, L57-77 |
| login_openplat.js | login.user.kugou.com (x-router) | POST /v6/login_by_openplat | android；先取微信 access_token(api.weixin.qq.com/sns/oauth2/access_token L15-20) | dev, force_login:1, partnerid:36, openid, params(AES{access_token}), pk, t1/t2/t3 | status, data.secu_params→token/userid/vip_type/vip_token/t1 | 否(微信 code) | L41-68 |
| login_qr_key.js | login-user.kugou.com | GET /v2/qrcode | web | appid(1014 web/1001), type:1, plat:4, qrcode_txt, srcappid | status, data.qrcode(key) | 否 | L6-16 |
| login_qr_check.js | login-user.kugou.com | GET /v2/get_userinfo_qrcode | web | plat:4, appid, srcappid, qrcode=key | data.status(0过期/1待扫/2待确认/4成功), data.token, data.userid (status==4 时) | 否 | L10-15, 注释 L5 |
| login_qr_create.js | 本地拼 h5.kugou.com/apps/loginQRCode/…?qrcode=key | 本地 | — | key, qrimg | url/base64 | 否 | L6-16 |
| login_wx_create.js | 微信 api.weixin.qq.com + open.weixin.qq.com/connect/sdk/qrconnect | 外部 | sha1 签名 | appid/secret/ticket/noncestr/timestamp/scope | qrcode.qrcodeurl, uuid | 否 | L37-42 |
| login_wx_check.js | long.open.weixin.qq.com/connect/l/qrconnect?f=json&uuid= | 外部 GET | — | uuid | 微信响应(json) | 否 | L9 |
| login_device.js | userinfoservice.kugou.com | POST /v2/get_dev | android，params=AES{token}, pk=RSA | plat:1, userid, clienttime_ms | 设备列表(token,dfid…)，`status`/`data` | 是(token) | L6-19 |
| register_dev.js | userservice.kugou.com | POST /risk/v2/r_register_dev | playlistAesEncrypt(JSON)+rsaEncrypt2(aes,uid,token)，响应 arraybuffer AES 解密 | 设备指纹 30+ 字段(brand/device/imei/uuid/传感器/内存/电量等默认值, L13-96)，query part:1, platid:1, p | status, data.dfid（写入 cookie） | 可匿名(userid 默认0) | L99-113, L119-122 |
| login_device_kick.js | gateway.kugou.com (Host) | GET /loginservice/v1/dev_logout | android + signParamsKey | appid, clientver, mid, uuid, dfid, plat, userid, token(AES), t_mid, t, t_appid:3116, t_clientver:10597, signature | status | 是 | L6-25, L27-34 |

版本变体猜测（登录链）：`/v9/login_by_pwd` → 试 v9→v7→v6（待实测）；`/v7/login_by_verifycode` → v7→v6→v5；`/v5/login_by_token` → v5→v4→v3；`/v6/login_by_openplat` → v6→v5；`/v2/get_userinfo_qrcode`、`/v2/qrcode` → v2→v1；`/risk/v2/r_register_dev` → v2→v1；`dev_logout` v1→v2。均为「源码版本 / 猜测版本 / 待实测」，不做断言。

## 4. MV / 视频 / 歌词 / 音频元数据

| 文件 | 域名 | 方法+路径 | 关键参数 | 响应字段证据 | 证据行 |
|---|---|---|---|---|---|
| video_url.js | trackermv.kugou.com (x-router) | GET /v2/interface/index | backupdomain:1, cmd:123, ext:'mp4', ismp3:0, hash, pid:1, type:1 | status, data[].url/backupdownurl/downurl, svr, movietype, time (本仓库惯例键) | L4-19 |
| video_detail.js | kmr.service.kugou.com (x-router) | POST /v1/video | data=[{video_id}], show_resolution:1, mid, uuid=md5(dfid+mid), token, key=signParamsKey | status, data[].url, resolution/quality | L8-30 |
| kmr_audio_mv.js | openapi.kugou.com (x-router, KG-TID:38) | POST /kmr/v1/audio/mv | data=[{album_audio_id}], fields | data[].mvhash/mvid/url | L5-17 |
| krm_audio.js | openapi.kugou.com (KG-TID:238) | POST /kmr/v2/audio | data=[{entity_id}], fields='base' | data[].base(歌手/专辑/歌曲) | L5-15 |
| lyric.js | lyrics.kugou.com | GET /download | ver:1, client:'android', id, accesskey, fmt(krc/lrc), charset:'utf8' | body.content(base64), contenttype, decodeContent(krc 解码/parse) | L10-33 |
| audio.js | kmr.service.kugou.com (x-router) | POST /v1/audio/audio | data=[{hash,audio_id:0}], key=signParamsKey, mid, dfid, token?, userid? | data[].hash/audio 信息 | L8-29 |
| images_audio.js | expendablekmr.kugou.com | (音频封面) data=[{audio_id,hash,album_audio_id,filename}] | — | L4-17 |

### 4.x 匿名播放用 MV 音频流（事实 vs 推断）
- **源码事实**：
  - `video_url.js` 路径 `/v2/interface/index` 带 `ismp3:0`、`ext:'mp4'`、`cmd:123`（L4-19）；trackermv 属 MV CDN tracker，响应按惯例含 `downurl`/`backupdownurl`/`url`（此三键名在 module 源码中**未**直接出现，属仓库通用键，标注为推断）。
  - `kmr_audio_mv.js` 可由 `album_audio_id` 换取 MV hash（`/kmr/v1/audio/mv`）。
  - `video_privilege.js`（/v1/get_video_privilege）以 `hash` 批量请求视频播放特权，匿名可传 `token:''`,`userid:0`,`vip:0`。
- **推断（非源码直接证据）**：
  - MV 流（mp4 容器）内含独立音轨；`trackermv` 的响应按清晰度分档，最低档键名一般为 `ld`/`sd`，可用 ffmpeg 取音频流实现匿名播放——此为对 MV CDN 结构的行业惯例推断，源码中无 `audio_hash`/`audio_*`/`ld`/`sd` 键的直接出现（`rg` 全 module 无命中），**需实测确认**。
  - 匿名播放首选仍是 `song_url.js` /v5/url（notSign、随机 dfid，源码明确支持匿名构造），MV 音频为备选路径。

## 5. 候选端点清单（按优先级）+ 未接入但可用计划

优先级：
1. `/v5/url`（trackercdn，GET，匿名可试听，IsFreePart 控制）
2. `/v6/priv_url`（tracker，POST，9 档，需 token/userid 算 key）
3. `/v2/get_res_privilege/lite`（media.store，播放权限/档位判定）
4. `/v2/interface/index`（trackermv，MV 流，`ismp3:0` 潜在音频可用）
5. `/v2/get_userinfo_qrcode` + `/v2/qrcode`（扫码登录，匿名可完成登录态获取）
6. `/risk/v2/r_register_dev`（匿名设备注册拿 dfid）
7. `/v5/login_by_token`（保活）
8. `/download`（lyrics.kugou.com，krc/lrc）
9. `/v1/audio/audio`、`/kmr/v1/audio/mv`、`/v1/video`（元数据/详情）

未接入但可用计划（按源码已证实能力）：
- `song_url.js` 的 magic 音质（piano/acappella/subwoofer/ancient/dj/surnay，L11-13）未在常规播放链使用。
- `user_cloud_url.js` 云盘 URL（/bsstrackercdngz/v2/query_musicclound_url）未在播放链使用，可作匿名/自传曲目补充。
- `song_climax.js` 高潮片段（expendablekmrcdn /v1/audio_climax/audio）可用于试听片段播放。
- `login_device.js` /v2/get_dev + `login_device_kick.js` dev_logout 的多设备管理链。
- `/v6/priv_url` 的 `tracker_param.need_xcdn:1`/`need_climax:1`/`all_m:1` 组合（源码 L26-33）尚未在 A 组其他模块复用。
- 版本降级试验（全部标注待实测）：v9→v7→v6(login_by_pwd)、v7→v6→v5(login_by_verifycode)、v5→v4→v3(login_by_token)、v6→v5(login_by_openplat)、v6→v5→v4(priv_url)、v5→v4→v3(url)、v2→v1(get_res_privilege、qrcode、interface/index、get_video_privilege、r_register_dev)。
