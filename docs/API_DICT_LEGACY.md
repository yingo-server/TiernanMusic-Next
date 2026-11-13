# 旧版（v5.5.0 归档 TiernanMusic）API 调用字典 — 新版网络层对照基线

> 只提取规格，不含源码。所有结论可由标注文件定位；未确认处显式标注。
> 归档路径前缀 `lib/core/direct/`、`lib/core/`，下文简写文件名。

## 1. 端点总表

签名类型说明：android = md5(androidSalt + 排序"k=v" + body + androidSalt)（kg_crypto.dart）；web = webSalt 同构；paramsKey(signKey) = md5(appid + salt + clientver + data)，data 形如 `clienttime(+mid+body)`（kg_crypto.dart KgSignature.paramsKey）。默认参数 dfid/mid/uuid='-'/appid/clientver/clienttime(+token/userid 登录态) 由 kg_client.dart request 注入并参与 android 签名。

| 域 | 方法 | URL/域名 | x-router / 特殊头 | 关键参数 | 签名 | 响应顶层键 | 成功判定 |
|---|---|---|---|---|---|---|---|
| 搜索-歌曲 | GET | `https://complexsearch.kugou.com/v3/search/song` | - | keyword/page/pagesize/platform=AndroidFilter/iscorrection/privilegefilter/area_code/dopicfull | android（默认参数参与） | status, data | status==1（response_policy） |
| 搜索-专辑 | GET | complexsearch `/v1/search/album` | - | 同上+category/sorttype/searchsong | android | status, data | status==1 |
| 搜索-其他 | GET | complexsearch `/v1/search/{special,author,mv,lyric}` | - | albumhide/nocollect/iscorrection/keyword/page/pagesize/platform | android | status, data | status==1 |
| 歌词候选 | GET | `https://lyrics.kugou.com/search` | 无签名 | appid/clientver/keyword/lrctxt/man/duration(ms)/hash/album_audio_id；clearDefaultParams+notSignature | 无 | status(200), errcode, candidates | status==200 且 errcode==200 |
| 歌词正文 | GET | lyrics.kugou.com `/download` | - | ver=1/client=android/id/accesskey/fmt/charset；id/accesskey 缺失前置拒绝（ApiException） | android | status, content/contenttype | status==1 |
| 歌单删除 | POST | gateway `/v2/delete_list` | x-router: cloudlist.service.kugou.com | clienttime/key(paramsKey)/last_area=p/clientver/appid/p(RSA-PKCS1)；body=AES base64 | android | AES 二进制→status | 解密得 status |
| 歌单收藏/新建 | POST | gateway `/cloudlist.service/v5/add_list` | - | query: last_time/last_area/userid/token；body: userid/token/name/type/list_create_* | android | status | status==1 |
| 歌单加歌 | POST | gateway `/cloudlist.service/v6/add_song` | - | query: last_time/last_area/userid/token；body: listid/data(对象数组，5 必带字段) | android | status | status==1 |
| 歌单删歌 | POST | gateway `/v4/delete_songs` | x-router: cloudlist.service.kugou.com | body: listid/userid/data[{fileid}]/type/token/list_ver | android | status | status==1 |
| 我的歌单 | POST | gateway `/v7/get_all_list` | x-router: cloudlist.service.kugou.com | query: plat/userid/token；body: userid/token/total_ver/type/page/pagesize | android | status | status==1 |
| 用户歌单歌曲 | POST | gateway `/v4/get_list_all_file_v3` | x-router: cloudlist.service.kugou.com | body: listid/userid/type/page/pagesize/area_code/allplatform/show_cover/token | android | status | status==1 |
| 歌单详情 | POST | `https://pubsongs.kugou.com/v3/get_list_info` | - | body: data[{global_collection_id}] (1..10)/userid/token | android | status | status==1 |
| 歌单曲目 | GET | pubsongs `/v2/get_other_list_file_nofilt` | - | global_collection_id 或 specialid（按前缀选择）/begin_idx/pagesize/extend_fields/plat/type/mode | android | status | status==1 |
| 播放地址 | GET | `https://trackercdn.kugou.com/v5/url` | - | hash(小写)/album_id/album_audio_id/quality/IsFreePart/cdnBackup/key=signKey(hash+salt+appid+mid+userid)+默认参数(含 signature) | android | status,url,backupUrl,bitRate,hash_offset,fail_process,extName,filesize | evaluateResponse；直接失败回退 kapi（20028 风控兜底） |
| 权益 | POST | gateway `/v2/get_res_privilege/lite` | x-router: media.store.kugou.com | body: resource[{type:audio,page_id:0,hash,album_id}]/qualities(恒整表 9 档)/need_hash_offset/relate/support_verify | android | status,data[].relate_goods | status==1；空 hash 前置拦截返回合成 502 |
| MV 地址 | GET | `https://trackermv.kugou.com/v2/interface/index` | - | cmd=123/ext=mp4/hash/pid=1/type=1/key=signKey | android | status,data[hash].downurl | status==1 |
| 音频 MV | POST | `https://openapi.kugou.com/kmr/v1/audio/mv` | KG-TID:38 | body: data[{album_audio_id}]/fields（非 mixsongid） | android | status,data | status==1 |
| 评论列表 | POST | gateway `/v1/cmtlist` | x-router: m.comment.service.kugou.com | ver=6/mixsongid/p/pagesize/show_classify/code=fc4be… | android | status,err_code | err_code==0（mcomment 口径） |
| 评论计数 | GET | gateway `/index.php` | x-router: sum.comment.service.kugou.com | r=comments/getcommentsnum/code/hash 或 childrenid（真值判定） | web | errcode | status==200 类 |
| 发评论 | POST | gateway `/index.php` | x-router: m.comment.service.kugou.com；clearDefaultParams+notSignature | r=commentsv3/add/code/childrenid/kugouid/clienttoken/mid/clienttime/key=paramsKey(clienttime+mid+data)/uuid='-'/dfid | 无通用签名（自带 key） | err_code | err_code==0 |
| 楼中楼回复 | POST | gateway `/index.php` | 同上 | r=commentsv2/reply/key=paramsKey(clienttime+mid)（不含 body）/tid/is_t/pid | 无通用签名 | err_code | err_code==0 |
| 删评论 | GET | gateway `/index.php` | 同上 | r=commentsv2/delcomment/cid/tid/key=paramsKey(clienttime+mid) | 无通用签名 | err_code | err_code==0 |
| 首页推荐 | GET | gateway `/v1/yueku/recommend_v2` | x-router: service.mobile.kugou.com | operator=7/plat=0/type=11/area_code/req_multi | android | status | status==1 |
| 榜单列表 | GET | `https://ocean.kugou.com/v6/rank/list` | - | plat=2/withsong/parentid=0 | android | status | status==1 |
| 榜单歌曲 | POST | gateway `/openapi/kmr/v2/rank/audio` | kg-tid:369 | body: rank_id(缺省丢弃)/page/pagesize/area_code；defaultParams+body 共同签名 | android | status,data{total,songlist} | status==1 |
| 新歌速递 | POST | `https://musicadservice.kugou.com/container/v1/newsong_publish` | - | body: rank_id/userid(数值 0)/page/pagesize/tags:[] | android | status | status==1 |
| 每日推荐 | POST | gateway `/everyday_song_recommend` | x-router: everydayrec.service.kugou.com | platform 必须在 query（body 无效） | android | status | status==1 |
| 热门歌单 | POST | gateway `/v2/special_recommend` | x-router: specialrec.service.kugou.com | body: appid/mid/clienttime(秒)/userid/module_id/key=paramsKey(dateTime)+special_recommend 内层 8 字段 | android | status,special_list | status==1 |
| 热搜 | GET | `https://msearch.kugou.com/api/v3/search/hot_tab` | - | navid/plat=2 | android | status,data.list | status==1 |
| banner | POST | gateway `/ads.gateway/v3/listen_banner` | - | body: plat/channel/operator/userid/vip_type(登录真实值)/m_type/tags/apiver | android | status | status==1；匿名恒 error_code=31136 → 回退 kapi → 置空 |
| 视频详情 | POST | gateway `/v1/video` | x-router: kmr.service.kugou.com；clearDefaultParams | body: appid/clientver/mid/uuid=md5(dfid+mid)/dfid/token/key=paramsKey/data[{video_id}] | android | status,data[] | status==1 |
| 歌手详情 | POST | `https://openapi.kugou.com/kmr/v3/author` | x-router+kg-tid:36 | body: author_id | android | status,data | status==1 |
| 歌手单曲 | POST | openapi `/kmr/v1/audio_group/author` | kg-tid:220（必须 v1 非 v2） | body: appid/clientver/mid/clienttime(秒)/key=paramsKey(clienttime)/author_id/area_code=all/sort/page/pagesize(≤100)；query 保留默认参数 | android | status,data(List),total | status==1 |
| 歌手专辑 | POST | gateway `/kmr/v1/author/albums` | kg-tid:36 | body: author_id/pagesize/page/sort/category/area_code | android | status | status==1 |
| 专辑详情 | POST | gateway `/kmr/v2/albums` | kg-tid:255 | body: data[{album_id}]/is_buy/fields | android | status | status==1 |
| 专辑歌曲 | POST | gateway `/v1/album_audio/lite` | kg-tid:255 | body: album_id/is_buy(0→'' 否则少歌)/page/pagesize | android | status | status==1 |
| 短信验证码 | POST | gateway `/v7/send_mobile_code` | x-router: login.user.kugou.com | body: businessid=5/mobile/plat=3 | android | status | status==1 |
| 验证码登录 | POST | `https://loginserviceretry.kugou.com/v7/login_by_verifycode` | UA: Android16-…-LOGIN-wifi | body: mobile(掩码)/params(AES)/pk(RSA)/t1/t2/lite 加 dfid/dev；成功解 secu_params 回写 token/userid/vip_type/vip_token/t1 | android | status,data.secu_params | status==1 |
| 密码登录 | POST | gateway `/v9/login_by_pwd` | x-router: login.user.kugou.com | body: username/params(AES)/pk/t1,t2,t3 固定常量 | android | status,data | status==1 |
| token 刷新 | POST | gateway `/v5/login_by_token` | x-router: login.user.kugou.com | body: dfid/p3(AES token)/t1/t2/userid/clienttime_ms | android | status,data | status==1 |
| QR key/检查 | GET | `https://login-user.kugou.com/v2/qrcode` `/v2/get_userinfo_qrcode` | - | appid/type/plat=4/srcappid=2919/qrcode/_t | web | status,data.status(4=已确认) | data.status==4 取 token/userid |
| 用户信息 | POST | gateway `/v3/get_my_info` | x-router: usercenter.kugou.com | body: p(RSA{token,clienttime})/usertype=1/userid；query plat=1 | android | status,data(响应无 userid，客户端回填) | status==1 |
| 人机验证 | POST | `https://verifyservice.kugou.com/verifyservice/v3/get_verify_info` `/v4/verify_user_info` | - | eventid=ssaCode/userid/platid/v_type(23/32)/wasm=1/sid/edt | android | status | status==1 |
| 设备注册 | POST | `https://userservice.kugou.com/risk/v3/r_register_dev` | form 表单；UA 同通用头 | query: part=1/platid=2(必须，1 仅 50% 成功)/p(小写 hex RSA)/dfid/mid/uuid='-'；body=AES base64；signature 含 body；响应二进制 AES 解密；uid 字符串 '0'；失败重试 3 次退避 | android(含 body) | 解密后 {status,data.dfid} | data.dfid 非空 |

## 2. 多版 API 差异（kapi vs 直连、/v1…/v7）

- 架构：`kg_direct_api_client.dart` 继承 kapi 客户端覆写 get/post；已移植路径走直连，未移植回退父类。`fallbackToKapi` 常量永久 false（PLY-13：kapi 只作参考不实际调用），故「回退」机制存在但运行期不生效；失败统一抛 DioException(error: ApiException)。
- 写操作（评论/收藏/加歌/删歌/歌单删除）禁止回退与自动重试（_directOrFallback write 分支、requestWithVerify 注释第 21 条）：请求可能已被服务端执行。
- 版本取舍实例：
  - 搜索歌曲 `/v2→/v3`（complexsearch 原生域）：kapi /search 是 v3 结构，gateway /v2 缺 HQ/SQ/Res.Hash 且多 40+ 字段，实测 /v3 与 kapi 0 差异（kg_endpoints_search.dart）。
  - 歌手单曲 `/v2→/v1`：v2 data 是 Map、hash 藏 audio_info，status=1 判成功但解析得空列表且不触发回退；v1 data 是 List 带 total（kg_endpoints_artist_album.dart）。
  - 歌单收藏 `/v5/add_list`、加歌 `/v6/add_song`、我的歌单 `/v7/get_all_list`、删歌 `/v4/delete_songs`、歌单详情 `/v3/get_list_info`、榜单 `/v6/rank/list`：各版本混用，以 Node module 对应实现为准（kg_endpoints_playlist.dart / kg_endpoints_home.dart）。
  - 登录 `/v9/login_by_pwd`、`/v7/login_by_verifycode`、`/v5/login_by_token`、`/v7/send_mobile_code`（kg_endpoints_auth.dart）。
  - 播放 `/v5/url`、权益 `/v2/get_res_privilege/lite`（kg_play_api.dart）。
- 域名选择规律：两标签域名（*.kugou.com 通配证书覆盖）直连原生域；三标签域（media.store/sum.comment/service.mobile/everydayrec/specialrec/kmr.service/login.user）TLS 不匹配必须 gateway+x-router；gateway 路由带前缀时（pubsongs/、ocean/、msearch/、musicadservice/）原生域需去掉前缀否则 404。评论走「裸路径+x-router」，`/mcomment/…`+x-router 会 403 Access Deny。

## 3. 三态行为（匿名 / 非VIP / VIP）

判定字段：`kg.token`、`kg.userid`（匿名 '0'）、`kg.vipType`/`kg.vipToken`（登录响应 data.vip_type/vip_token，_afterLogin 写入，kg_client.dart/kg_endpoints_auth.dart）。
- 播放：匿名/非 VIP 免费/试听曲可播；VIP 判定走 privilege 每档 relate_goods（privilege==0 && status!=0 && exists 即免费，needsPurchase = payType!=0||privilege!=0，kg_play_api.dart PrivilegeItem）。试听 IsFreePart=1。
- 搜索：三态同接口，无态分支（未在旧版代码中确认有搜索态差异）。
- 收藏/歌单/评论：均需登录（token/userid），匿名传 '0' 无效；未在旧版代码中确认匿名可收藏。
- 登录：匿名/非 VIP 与 VIP 的区分在 banner（`vip_type` 硬编码 0 曾致 VIP 拿不到会员 banner，改取真实 vip_type，kg_endpoints_home.dart yuekuBanner）。
- 新歌/歌单推荐：userid 匿名落数值 0，空串会触发参数校验失败（F4-13）。

## 4. URL 解析（play_url）

顶层字段：url(数组或串)/backupUrl/bitRate/quality/extName/error/fail_process/filesize/hash_offset{clip_hash,start_byte,end_byte,start_ms,end_ms,offset_hash,file_type}/ssaCode（kg_play_api.dart PlayUrlResult.fromResponse）。
- 试听判定：区间时长 (end_ms-start_ms)≤65000 或 URL 含 `/p_0_`（只看 end_ms 会误判短歌整曲）。
- VIP 档降级：fail_process 非空 = 服务端明确拒绝（需购买/无版权），降级无意义；试听由 freePart→IsFreePart=1 获取 hash_offset 片段（clip_hash 与整曲 hash 不同）。
- CDN：http://fsandroid.kugou.com 直链约 5 分钟过期；MV downurl 为 http，代理转换在 Repository 层（kg_endpoints_media.dart）。
- 20028 风控带 ssa-code（头/体），requestWithVerify 提交 sid/edt 后重试一次（kg_client.dart）。

## 5. 缓存与预读

- ResourceCache（lib/core/resource/resource_cache.dart）：JSON Hive 箱 `resource_json`；in-flight 按 fullKey（含 scope 前缀 + TTL 毫秒）合并并发；fetch 失败有旧值返回 `__stale:true` 副本并落日志；损坏条目删除防反复。
- 三级（resource_gateway.dart）：L1 内存 90s 默认 TTL（同源 L2 口径）；L2 磁盘 JSON TTL=cacheTtl：json 168h / list 90s / file 永久；L3 永久文件身份=(URL,声明字节数) FNV-1a 命名，declaredBytes≤0 拒绝入库，下载后校验实际长度==声明；试听 URL（/p_0_、hash_offset、IsFreePart=1）缓存层直接拒绝入库。
- 键维度：cache_keys.cacheKey = ns+scope+path+排序 query+userid(u=)+extra；切号 onUserChanged 清 L1+JSON/列表，带用户世代号防竞态。
- 播放 URL 短缓存：`playurl:{userid}:{hash}:{quality}:{freePart}` TTL 4 分钟（kg_play_api.dart）。
- PrefetchEngine（lib/core/prefetch/prefetch_engine.dart）：启动预热 enqueueSongs 单次上限 60 首、spacing 100ms 节拍逐个消费；updateUpcoming 未来 window=15 首插队头；去重有界 LRU 512；只预取 URL/歌词候选/封面 JSON，不下载文件；完整播放完成后 onPlaybackCompleted 落永久文件缓存（需 declaredBytes>0）。
- 图片：AppImageCache 单例串行化 getSingleFile/getFileStream 防 SQLITE_BUSY，stalePeriod 30 天、600 条上限（lib/core/image/app_image_cache.dart）。

## 6. 响应策略（lib/core/domain/response_policy.dart evaluateResponse）

判定顺序：1) err_code 存在（mcomment）：不可解析=失败，非 0=失败；2) error_code/errcode 不可解析=失败；3) ec==20028（kVerificationRequired）恒失败带 ssaCode；4) status==1：ec==0 成功，警告码 {0,151,152,200,201} 且 _hasData（data 非空或存在非错误类键）成功，否则失败；5) status==200（歌词类）：警告码成功；6) 有明确 status 且 0/2=失败；7) 无 status 且空体=风控拦截失败；8) 无 status 带数据=裸 Map 成功。网络异常折成 502 假响应必须带 error_code=-1 与 ssaCode（kg_client.dart DioException 分支）。

## 7. 已知坑

1. 设备注册 platid 必须 2、uid 必须字符串 '0'、p 用小写 hex、signature 必须含 body、响应为二进制 AES（kg_client.dart registerDevice）。
2. uuid 恒传 '-'，改 guid 无收益（kg_client.dart defaultParams）。
3. 评论三个签名形态：gateway+/mcomment/…+x-router 会 403，须裸路径+x-router（kg_endpoints_comment.dart F4-04）。
4. 歌单删除解密失败不得静默吞，须返回「结果未知勿直接重试」（kg_endpoints_playlist.dart）。
5. 加歌 data 必须是对象数组（5 必带字段 number/size/sort/timelen/bitrate），字符串形态失败（kg_endpoints_playlist.dart P0-5/PLY-05）。
6. 歌单详情只认 global_collection_id（collection_xxx 形式）不认数字 specialid，1..10 个上限（kg_endpoints_playlist.dart）。
7. 专辑歌曲 is_buy=0 要落空串，否则付费专辑少歌（kg_endpoints_artist_album.dart F4-24）。
8. 权益 qualities 恒下发完整 9 档整表，只传单档会缺 ogg/vip 条目（kg_play_api.dart F4-07）；128 取 relate_goods level[1,2] 不是 first（F4-08）。
9. lyric /v1/search 恒空响应体（x-kg-errcode:20010），真路径是 /search（kg_endpoints_search.dart）。
10. 每日推荐 platform 必须在 query；热门歌单 dateTime 用秒级，YYYYMMDDHH 会 ec=200101（kg_endpoints_home.dart）。
11. banner 匿名恒 error_code=31136，属上游行为（kg_endpoints_home.dart）。
12. 歌手单曲若误用 v2 版端点，status=1 但解析空列表且不触发回退（kg_endpoints_artist_album.dart）。
13. 写操作禁止 requestWithVerify/回退重试，可能重复提交（kg_client.dart 第 21 条）。
14. 播放 URL 试听判定只看 end_ms 会误判短歌整曲（kg_play_api.dart F4-09）。
15. `@override` 声明的三个标签域名 certificate 失败清单见各文件注释；未在旧版代码中确认所有三标签域的完整枚举。
