# ENDPOINT_TRUTH — 批8-A 端点真实性补齐

> 直连实测提示：主会话用 gateway.kugou.com 探测 /v3/get_my_info、/v1/user_cloud 等均 404/502，
> 说明这些路径需按 module 真实 URL 修正。本文档全部内容逐条提取自只读参考项目
> `KuGouMusicApi/module/*.js`（含 `util/request.js` 通用请求层）。
>
> 通用请求层事实（util/request.js）：
> - 默认 baseURL = `https://gateway.kugou.com`（仅当模块未显式指定 baseURL 时）。
> - 默认 query 恒注入：`dfid / mid / uuid(="-") / appid / clientver / clienttime`，有登录态时再加 `token / userid`；最终拼 `signature`。
> - 请求头恒带 `dfid, mid, clienttime, kg-rc, kg-thash, kg-rec, kg-rf` + Android UA。
> - 签名类型三选一：android（默认）/ web / register；模块可 `notSignature: true` 关闭签名。
> - x-router 属请求头（headers），非 query；kg-tid 未在上游出现（上游用 dfid/mid 头标识设备）。
> - 响应顶层结构统一为 `{ status, body, cookie, headers? }`；body 内一般含 `status / error_code / data`。

---

## 1. 用户域

### user_detail — 用户详情
- 源：`module/user_detail.js`
- URL：`https://gateway.kugou.com/v3/get_my_info`（默认 baseURL）+ 头 `x-router: usercenter.kugou.com`
- 方法：POST
- query：`plat=1` + 默认参数（dfid/mid/uuid/appid/clientver/clienttime/signature）
- body：`{ visit_time(秒), usertype: 1, p(RSA串, 大写), userid }`
- 签名：android（对 body 参与签名）
- 响应：`body.data`（含昵称/头像等用户资料）；`body.status`

### user_cloud — 云盘歌曲列表
- 源：`module/user_cloud.js`
- URL：`https://mcloudservice.kugou.com/v1/get_list`（**非 gateway**，且真实路径是 `/v1/get_list`，不是 `/v1/user_cloud`）
- 方法：POST；`clearDefaultParams: true` + `notSignature: true`（无 signature）
- query：`clienttime / mid / key=signParamsKey(clienttime, appid) / clientver / appid / p=rsaEncrypt2({aes key, uid, token})大写`
- body：AES(playlistAesEncrypt) 加密的 `{ page, pagesize, getkmr: 1 }` 密文 buffer
- 签名：none（notSignature，靠 p + key）
- 响应：body 为 arraybuffer，需 playlistAesDecrypt 后得到 `data` 列表 / `total` 等
- 注意：dfid/mid 不在 query（clearDefaultParams），mid 显式在 query 参与签名。

### user_cloud_url — 云盘播放链接
- 源：`module/user_cloud_url.js`
- URL：`https://gateway.kugou.com/bsstrackercdngz/v2/query_musicclound_url`
- 方法：GET
- query：`hash(小写) / ssa_flag=is_fromtrack / version=20102 / ssl=0 / album_audio_id / pid=20026 / audio_id / kv_id=2 / key=signCloudKey(hash, 20026) / bucket=musicclound / name / with_res_tag=0` + 默认参数
- body：无
- 签名：android
- 响应：`body.data` 内 url 相关字段（含 ortest/url 等 CDN 字段）

### playhistory_upload — 上报听歌历史
- 源：`module/playhistory_upload.js`
- URL：`https://gateway.kugou.com/playhistory/v1/upload_songs`
- 方法：POST
- query：`plat=3` + 默认参数
- body：`{ songs: [{ mxid, op: 1, ot(秒时间戳), pc }], token, userid }`
- 签名：android
- 响应：`body.status`（1 成功）

### playhistory_get_songs — 听歌排行/历史
- 源：`module/user_history.js`
- URL：`https://gateway.kugou.com/playhistory/v1/get_songs`
- 方法：POST
- query：仅默认参数
- body：`{ token, userid, source_classify: "app", to_subdivide_sr: 1, bp? }`
- 签名：android
- 响应：`body.data.songs` 列表 / `body.status`

### song_climax — 音频高潮段
- 源：`module/song_climax.js`
- URL：`https://expendablekmrcdn.kugou.com/v1/audio_climax/audio`（**非 gateway**）
- 方法：GET
- query：`data=JSON.stringify([{hash},...])` + 默认参数（hash 多个逗号分隔拆成数组）
- body：无
- 签名：android
- 响应：`body.data[*]` 内高潮起点/时长字段

### user_listen_report — 个人推荐电台播放上报
- 源：`module/user_listen.js`（实际是获取收听列表；上报类走 personal_fm 的 action/playtime，见 §3）
- URL：`https://listenservice.kugou.com/v2/get_list`（**非 gateway**）
- 方法：POST
- query：`clienttime / plat=0` + 默认参数
- body：`{ t_userid, userid, list_type, area_code: 1, cover: 2, p(RSA{clienttime, token})大写 }`
- 签名：android
- 响应：`body.data` 收听列表

### lastest_songs_listen（继续播放）
- 源：`module/lastest_songs_listen.js`
- URL：`https://gateway.kugou.com/playque/devque/v1/get_latest_songs`
- 方法：POST
- query：默认参数
- body：`{ area_code: "1", sources: ["pc","mobile","tv","car"], userid, ret_info: 1, token, pagesize }`
- 签名：android；响应 `body.data`

### favorite_count — 批量歌曲收藏数
- 源：`module/favorite_count.js`
- URL：`https://gateway.kugou.com/count/v1/audio/mget_collect`
- 方法：GET
- query：`mixsongids`（逗号分隔）+ 默认参数（dfid/mid/uuid/appid/clientver/token/userid）
- body：无
- 签名：android
- 响应：`body.data` mixsongid→collect 数量映射

---

## 2. 登录

### send_verifycode（发短信验证码）
- 源：`module/captcha_sent.js`
- URL：`http://login.user.kugou.com/v7/send_mobile_code`
- 方法：POST
- query：默认参数（cookie 仅带 mid）
- body：`{ businessid: 5, mobile, plat: 3 }`
- 签名：android
- 响应：`body.status`

### login_cellphone — 短信验证码登录
- 源：`module/login_cellphone.js`
- URL：`https://loginserviceretry.kugou.com/v7/login_by_verifycode`
- 方法：POST
- 头：`support-calm: 1`，UA `Android16-1070-11440-130-0-LOGIN-wifi`
- query：默认参数
- body：`{ plat: 1, support_multi: 1, t1/t2(lite 才有, AES 加密), clienttime_ms, mobile(打码), key=signParamsKey(dateTime), pk(RSA{clienttime_ms, aes key})大写, params(AES{mobile, code} 密文), userid?, dfid/dev/gitversion(lite) 或 t3 }`
- 签名：android
- 响应：`body.status==1` 时 `body.data.secu_params`（AES 解出 token/userid/vip_type/vip_token/t1 等），成功后写 cookie

### login_qr_key — 二维码 key
- 源：`module/login_qr_key.js`
- URL：`https://login-user.kugou.com/v2/qrcode`
- 方法：GET
- query：`appid(web=1014 / 默认1001) / type=1 / plat=4 / qrcode_txt / srcappid` + 默认参数
- 签名：web；响应 `body.data.qrcode / key`

### login_qr_check — 二维码状态轮询
- 源：`module/login_qr_check.js`
- URL：`https://login-user.kugou.com/v2/get_userinfo_qrcode`
- 方法：GET
- query：`plat=4 / appid / srcappid / qrcode(=key)` + 默认参数
- 签名：web
- 响应：`body.data.status`（0 过期 / 1 等待扫码 / 2 待确认 / 4 成功且 `body.data.token / userid`）

### login_token — token 刷新登录
- 源：`module/login_token.js`
- URL：`http://login.user.kugou.com/v5/login_by_token`
- 方法：POST
- query：默认参数
- body：`{ dfid, p3(AES{clienttime, token}), plat: 1, t1/t2(lite), t3, pk(RSA), params(AES{}密文), userid, clienttime_ms, dev(lite) }`
- 签名：android；响应同 login_cellphone 的 secu_params 解密流程

### register_dev — 设备注册（拿 dfid）
- 源：`module/register_dev.js`
- URL：`https://userservice.kugou.com/risk/v2/r_register_dev`（**非 gateway**）
- 方法：POST；响应 arraybuffer 需 playlistAesDecrypt
- query：`part=1 / platid=1 / p=rsaEncrypt2({aes key, uid, token})`
- body：AES 密文，明文含 uuid/imei/brand/device 等设备指纹三十余字段
- 签名：android（但参数显式 part/platid/p；uuid 显式参与）
- 响应：解密后 `body.status==1` → `body.data.dfid`（写入 cookie）

### get_verify_info — 验证码（风控）信息
- 源：`module/get_verify_info.js`
- URL：`https://gateway.kugou.com/verifyservice/v3/get_verify_info`
- 方法：POST
- query：默认参数
- body：`{ eventid, userid, platid=2, rtype=1, wasm=1, i, sid, edt }`
- 签名：android
- 校验回执配套：`module/verify_user_info.js` → `https://verifyservice.kugou.com/v4/verify_user_info`，POST，body 含 `v_type(23/32)/verifycode/pk/params/sid/edt`，query `clientver=11510`，签名 android。

---

## 3. FM

### personal_fm — 私人FM（含播放上报 action）
- 源：`module/personal_fm.js`
- URL：`https://gateway.kugou.com/v2/personal_recommend` + 头 `x-router: persnfm.service.kugou.com`
- 方法：POST
- query：默认参数
- body：`{ appid, clienttime, mid, action(play|skip|overplay等), recommend_source_locked, song_pool_id, callerid, m_type: 1, platform, area_code: 1, remain_songcnt, clientver, is_overplay, mode, fakem, key=signParamsKey(dateTime), userid/kguid, token, vip_type, hash?, songid?, playtime? }`
- 签名：android；响应 `body.data.songs`

### fm_songs — 分类FM歌曲列表
- 源：`module/fm_songs.js`
- URL：`https://gateway.kugou.com/v1/app_song_list_offset` + 头 `x-router: fm.service.kugou.com`，`Content-Type: application/json`
- 方法：POST
- body：`{ appid, area_code: 1, clienttime, clientver, data: [{fmid, fmtype, offset, size, singername}], get_tracker: 1, key, mid, uid }`
- 签名：android；响应 `body.data[*]` 歌曲数组

### fm_class — FM 分类
- 源：`module/fm_class.js`
- URL：`https://gateway.kugou.com/v1/class_fm_song` + 头 `x-router: fm.service.kugou.com`
- 方法：POST；body：`{ kguid, clienttime, mid, platform: "android", clientver, uid, get_tracker: 1, key, appid }`；签名 android

### fm_recommend — FM 推荐列表
- 源：`module/fm_recommend.js`
- URL：`https://gateway.kugou.com/v1/rcmd_list` + 头 `x-router: fm.service.kugou.com`
- 方法：POST；body：`{ appid, clientver, clienttime, mid, key, rcmdsongcount: 1, level: 0, area_code: 1, get_tracker: 1, uid: 0 }`；签名 android

### yueku_fm — 乐库时间FM
- 源：`module/yueku_fm.js`
- URL：`https://gateway.kugou.com/v1/time_fm_info` + 头 `x-router: fm.service.kugou.com`
- 方法：GET；query：`operator=7 / plat=0 / type=11 / area_code=1 / req_multi=1` + 默认参数；签名 android

> 上游另有 `module/fm_image.js`（FM 封面）。**fm_play（播放行为上报独立端点）上游无此模块**：播放上报通过 personal_fm 的 `action/songid/playtime` 字段承载，不应另造 URL。

---

## 4. 歌单写操作

### playlist_add — 创建/收藏歌单
- 源：`module/playlist_add.js`
- URL：`https://gateway.kugou.com/cloudlist.service/v5/add_list`
- 方法：POST
- query：type==0（自建）时 `last_time / last_area=gztx / userid / token`，否则仅默认参数
- body：`{ userid, token, total_ver: 0, name, type(0自建), source, is_pri, list_create_userid, list_create_listid, list_create_gid, from_shupinmv: 0 }`
- 签名：android；响应 `body.status / body.data.id(listid)`

### playlist_del — 删除/取消收藏歌单
- 源：`module/playlist_del.js`
- URL：`https://gateway.kugou.com/v2/delete_list` + 头 `x-router: cloudlist.service.kugou.com`
- 方法：POST；响应 arraybuffer，playlistAesDecrypt
- query：`clienttime / key=signParamsKey(clienttime) / last_area=gztx / clientver / appid / last_time / p=rsaEncrypt2({aes key, uid, token})大写`（clearDefaultParams 隐含不注入 dfid/uuid 到签名外参数——实际未设 clearDefaultParams，默认参数仍在，最终拼 signature）
- body：AES 密文，明文 `{ listid, total_ver: 0, type: 1 }`
- 签名：android（params 内含 p/key）

### playlist_tracks_del — 歌单删歌
- 源：`module/playlist_tracks_del.js`
- URL：`https://gateway.kugou.com/v4/delete_songs` + 头 `x-router: cloudlist.service.kugou.com`
- 方法：POST
- body：`{ listid, userid, data: [{fileid}], type: 0, token, list_ver: 0 }`（fileids 逗号分隔拆分）
- query：默认参数；签名 android；响应 `body.status`

### playlist_tracks_add — 歌单加歌
- 源：`module/playlist_tracks_add.js`
- URL：`https://gateway.kugou.com/cloudlist.service/v6/add_song`
- 方法：POST
- query：`last_time / last_area=gztx / userid / token` + 默认参数
- body：`{ userid, token, listid, list_ver: 0, type: 0, slow_upload: 1, scene: "false;null", data: [{number, name, hash, size, sort, timelen, bitrate, album_id, mixsongid}] }`（入参 "name|hash|album_id|mixsongid" 逗号分隔）
- 签名：android

### playlist_tags — 歌单分类标签
- 源：`module/playlist_tags.js`
- URL：`https://gateway.kugou.com/pubsongs/v1/get_tags_by_type`
- 方法：POST；body：`{ tag_type: "collection", tag_id: 0, source: 3 }`；签名 android

### user_playlist — 用户歌单列表
- 源：`module/user_playlist.js`
- URL：`https://gateway.kugou.com/v7/get_all_list` + 头 `x-router: cloudlist.service.kugou.com`
- 方法：POST
- query：`plat=1 / userid / token` + 默认参数
- body：`{ userid, token, total_ver: 979, type: 2, page, pagesize }`
- 签名：android；响应 `body.data.info` 歌单数组

---

## 5. 收藏

### collect / cancel_collect（歌曲收藏/取消）
- **上游无此模块**。KuGouMusicApi/module/ 内不存在对歌曲本身的 collect / cancel_collect 端点。
  与“collect”相关的仅有：
  - `module/favorite_count.js`（只读收藏数，见 §1）
  - `module/user_video_collect.js` — **MV/视频收藏列表**：`https://gateway.kugou.com/collectservice/v2/collect_list_mixvideo`，POST，query `plat=1`，body `{ userid, token, page, pagesize }`，签名 android。
  - 歌单层面的“收藏/取消收藏”即 §4 的 `cloudlist.service/v5/add_list`（type≠0 为收藏他人歌单）与 `v2/delete_list`（type=1）。
- 结论：歌曲收藏/取消收藏不应臆造 `/collect`、`/cancel_collect` URL；需另行以官方 App 抓包或以 cloudlist/collectservice 系列路径为准。

### mv_collect — 见上 user_video_collect（仅列表查询，无写入端点）

### favorite_count — 见 §1。

---

## 6. 歌词翻译

### 歌词下载（含译文轨判定）
- 源：`module/lyric.js`
- URL：`https://lyrics.kugou.com/download`
- 方法：GET
- query：`ver=1 / client=android / id / accesskey / fmt(krc|lrc) / charset=utf8` + 默认参数；签名 android
- 响应：`body.content`（base64）、`body.contenttype`（0=krc 需 decodeLyrics 解码）；`decodeLyrics` 位于 `util/`（krc 解密），解出的 krc 内含翻译轨字段（translation 行内嵌），即**译文随 krc 一并下发，不是独立接口**。

### 逐行翻译端点
- **上游无独立翻译端点**：module/ 与 util/ 中 grep 无 translation/translate 相关 URL。旧项目的翻译是本地词典/客户端处理（krc 内嵌翻译行 + 本地渲染），**不应臆造任何 translation API**。若需在线逐行翻译，属客户端本地能力，不属于酷狗开放端点。

---

## 附：needsProbe 占位 → 真实端点映射速查

| 占位名 | 猜测路径（错误） | 真实路径 | 真实 host / x-router |
|---|---|---|---|
| user_detail | gateway /v3/get_my_info 直连 | /v3/get_my_info + x-router | usercenter.kugou.com |
| user_cloud | gateway /v1/user_cloud | mcloudservice.kugou.com /v1/get_list | — |
| song_climax | gateway 猜测 | expendablekmrcdn.kugou.com /v1/audio_climax/audio | — |
| fm_play | gateway /v1/fm/play | personal_fm body action 上报 | persnfm.service.kugou.com |
| fm_songs | gateway /v1/fm/songs | gateway /v1/app_song_list_offset | fm.service.kugou.com |
| playlist_create | /v2/add_playlist | gateway /cloudlist.service/v5/add_list | cloudlist.service（URL 前缀式） |
| playlist_delete | 猜测 | gateway /v2/delete_list | cloudlist.service.kugou.com |
| del_songs | 猜测 | gateway /v4/delete_songs | cloudlist.service.kugou.com |
| collect/cancel_collect | 猜测 | 上游无此模块（见 §5） | — |
| favorite_count | 猜测 | gateway /count/v1/audio/mget_collect | count（URL 前缀式） |
| send_verifycode | 猜测 | login.user.kugou.com /v7/send_mobile_code | — |
| translation | 猜测 | 上游无独立翻译端点 | — |
