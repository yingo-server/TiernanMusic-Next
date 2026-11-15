# 旧 URL / 登录方式 / 免登录播放 调研报告（只读调研，2026-11-15）

> 证据源：旧归档 KuGouMusicApi/module/*、旧项目 v5.5.0 字典 docs/API_DICT_LEGACY.md、docs/KUGOU_API.md（含 2026-11-10 实测修正）、docs/API_DICT_CURRENT.md、docs/API_TEST_REPORT.md（三态实测）、当前代码 lib/core/net/endpoints/*、lib/logic/*。
> 三态口径（docs/API_TEST_REPORT.md:16-94，2026-11-13 tool/api_probe.dart 实测）：匿名 play_url v5 → `status=0 errcode=20028`（人机验证）；非VIP 对 VIP 曲 → `status=2 priv_status=0`；VIP → `status=1 priv_status=1 urls=2 backupUrls=1`。

---

## 1. 登录方式全集（旧归档 + 当前接线）

| # | 方式 | 端点 / 路径 / x-router | 关键参数 | 当前代码是否接线 | 证据 |
|---|---|---|---|---|---|
| L1 | **二维码登录（已接）** | GET `https://login-user.kugou.com/v2/qrcode`（key）+ `/v2/get_userinfo_qrcode`（轮询）；web 签名 | `appid=1001`、`type=1`、`plat=4`、`srcappid=2919`、`qrcode_txt=h5 扫码页 URL+key`；轮询 status: 0 过期/1 待扫/2 待确认/**4 成功**（data.token+data.userid 下发） | ✅ AuthLogic.requestQrLogin / pollQrLogin 已接且实测（2026-11-13 data.qrcode_img 返回 PNG base64） | KuGouMusicApi/module/login_qr_key.js、login_qr_check.js；lib/logic/auth/auth_logic.dart:60-131；lib/core/net/endpoint_registry.dart:229-236 |
| L2 | **短信验证码登录** | POST `https://loginserviceretry.kugou.com/v7/login_by_verifycode`（直连官方子域，UA `Android16-1070-11440-130-0-LOGIN-wifi`） | body `params`=AES(固定key `90b8382a…`/iv `f063102053fd75b8`) 加密 {mobile, code} hex；`pk`=RSA({clienttime_ms, key}) **大写** hex；成功解 data.secu_params 回写 token/userid/vip_type/vip_token/t1 | ⚠️ 半接线：auth_endpoints.dart 已实现（kAuthEndpointsProbed=true）但**未三态实测**，smsLogin 注释仍标 needs probe | module/login_cellphone.js；docs/KUGOU_API.md §3.8；lib/core/net/endpoints/auth_endpoints.dart:14-19,105-133；endpoint_registry.dart:247-250 |
| L3 | **发送短信验证码** | POST `http://login.user.kugou.com/v7/send_mobile_code`（x-router login.user.kugou.com） | body `businessid=5, mobile, plat=3`；android 签名 | ✅ sendSmsCode 已按契约外发 | module/captcha_sent.js；auth_endpoints.dart:67-93；endpoint_registry.dart:255-257 |
| L4 | **密码登录** | POST gateway `/v9/login_by_pwd`（x-router: login.user.kugou.com） | body `username/params(AES)/pk/t1,t2,t3 固定常量` | ❌ 未接线（注册表无对应 Endpoint） | docs/API_DICT_LEGACY.md §1 端点总表 |
| L5 | **token 续期（refreshToken）** | POST `http://login.user.kugou.com/v5/login_by_token`（x-router login.user.kugou.com） | body `dfid/p3=AES固定key({clienttime,token})/t1/t2/userid/clienttime_ms` | ⚠️ EndpointRegistry.loginToken 已声明（registry.dart:237-240），AuthLogic **无调用方**——token 过期不会自动续期 | module/login_token.js（AES key/iv 对 §2.1）；registry.dart:237 |
| L6 | **微信开放平台登录** | 微信侧：`open.weixin.qq.com/connect/sdk/qrconnect`（建码）、`long.open.weixin.qq.com/connect/l/qrconnect?uuid=`（轮询）、`api.weixin.qq.com/sns/oauth2/access_token`（换 token）；酷狗侧 POST gateway **`/v6/login_by_openplat`** | `partnerid=36, force_login=1, openid, params=AES({access_token}), pk=RSA, dev, t1/t2(lite), t3='MCwwLDAsMCww…'`；wx_appid/wx_secret（lite 有独立对） | ❌ 未接线 | module/login_openplat.js、login_wx_create.js、login_wx_check.js |
| L7 | **设备信息/登出** | POST `https://userinfoservice.kugou.com/v2/get_dev`（AES{token}+RSA pk）；GET gateway `/loginservice/v1/dev_logout`（signParamsKey + t_mid/t/t_appid=3116/t_clientver=10597） | — | ❌ 未接线 | module/login_device.js、login_device_kick.js |
| L8 | **设备注册（免登录前置）** | POST `https://userservice.kugou.com/risk/v3/r_register_dev`，register 签名（md5("1014"+排序值+"1014")） | query `part=1/platid=2(必须,1 仅 50% 成功)/p(小写hex RSA)/dfid/mid/uuid='-'`；body=AES base64；响应二进制 AES 解密；uid 字符串 `'0'`；失败退避重试 3 次 | ❓ 当前 KugouClient 有无 registerDevice 待核（字典 legacy §1 有规格）；platid=2/uid='0'/signature 含 body 三坑必守 | docs/API_DICT_LEGACY.md §1 + §7.1 |
| L9 | **用户信息 / VIP 详情** | POST gateway `/v3/get_my_info`（x-router usercenter.kugou.com，p=RSA{token,clienttime}.toUpperCase()）；GET `https://kugouvip.kugou.com/v1/get_union_vip?busi_type=concept` | — | ⚠️ user_endpoints.dart 存在（getMyInfo 形态待核）；VIP 详情未接 | module/user_detail.js、user_vip_detail.js；legacy §1 |
| L10 | **人机验证（20028 兜底，非登录但同链路）** | POST `https://verifyservice.kugou.com/verifyservice/v3/get_verify_info` + `/v4/verify_user_info` | `eventid=ssaCode/userid/platid/v_type(23/32)/wasm=1/sid/edt` | ⚠️ verification_logic.dart 存在；匿名 20028 播放依赖此链路 | legacy §1；docs/API_TEST_REPORT.md:78 |

**结论：「登录方式不止扫码」属实**——旧归档至少 6 条链路（扫码/短信/密码/token 续期/微信开放平台/设备注册）。当前 Next 只接了扫码（可用）+ 短信（半接线未实测）；密码、微信、token 自动续期、设备登出全部缺失。

---

## 2. 免登录 URL（不需要 token/userid 拿可播 URL 的候选）

三态实测（docs/API_TEST_REPORT.md:18,78）已否定「play_url v5 匿名可播」：正确盐下匿名恒 `errcode=20028`（人机验证拦截）。旧归档内的替代路径候选：

| 候选 | 路径/模板 | 所需参数 | 可用性证据等级 | 备注 |
|---|---|---|---|---|
| C1 play_url v5 + 设备注册 | gateway `/v5/url`（x-router trackercdn） | 匿名也必须 token+userid+'0'+Cookie(t1)+随机 24 位 dfid+key | **文档+实测**（KUGOU_API.md §3.2 实测修正 2；API_TEST_REPORT 匿名 20028） | 严格说非免登录：需先 r_register_dev 拿 dfid + 人机验证过 20028。这是旧版唯一匿名播放通道 |
| C2 试听片段 IsFreePart=1 | 同 C1，`IsFreePart=1` | + hash | **文档**（song_url.js:35） | 实测修正 6：IsFreePart=1 仍返回全长 URL，试听以 timeLength 为准；VIP 曲非 VIP 号仍 priv_status=0，试听不成立 |
| C3 hash_offset 试听 | 响应内 `hash_offset{clip_hash,start_ms,end_ms…}` | 需登录态请求 | **文档**（legacy §4） | clip_hash 与整曲 hash 不同；缓存层对试听 URL 拒绝入库（legacy §5） |
| C4 play_url v6 多档批量 | POST `http://tracker.kugou.com/v6/priv_url` | body 带 token/userid/vip/vip_token/viptoken，tracker_param.key=md5(hash+lite盐+appid+mid+userid) | **代码推断**（song_url_new.js 全文；docs/API_DICT_CURRENT.md:18 标「未探针」） | 同样要求 token/userid，非免登录；但一次拿 9 档音质，是权益最大化的正路 |
| C5 MV downurl | GET `trackermv.kugou.com/v2/interface/index`（cmd=123/pid=1/type=1/ext=mp4 + key=signKey(hash+appid+mid+userid||0)） | **userid 缺省可传 0**，key 匿名可算 | **文档**（legacy §1、KUGOU_API.md §3.9；matrix 标 OK A5-3） | 匿名可取 MV 直链 http downurl+backupdownurl；MV 链路本身就是"免登录播放"最可行路径 |
| C6 歌词/搜索/H5 | lyrics.kugou.com/search+download、msearch hot_tab、complexsearch v3/v6 | 无 token（search 匿名三态同接口） | **文档+实测**（legacy §3「搜索三态同接口」；KUGOU_API.md 域名矩阵） | 非播放，但免登录可用的元数据链路 |
| C7 CDN 直链 | `http://fsandroid.kugou.com` 响应 url[]/backupUrl[] | 由 C1/C4 派生 | **实测**（API_TEST_REPORT:84 host=fsandroid…269s） | 约 5 分钟过期，非独立取链手段 |

**结论：旧归档中不存在绕过 token/验证的纯免登录播放 URL**（kapi.344977.xyz 第三方代理已 404 弃用，KUGOU_API.md 域名矩阵）。匿名播放的现实路径 = 设备注册 + 匿名 '0' 凭据 + 20028 人机验证（verification_logic 已有骨架）；MV 是唯一真正匿名可播的内容线。所有候选均为「文档/代码推断」，无新实测。

---

## 3. 权益最大 URL（按 VIP/登录态选最高音质）

- **旧版逻辑**：play_url v5 单次单档（quality 参数，魔法音质 piano/acappella/subwoofer/ancient/dj/surnay 走 magic_ 前缀）；**play_url v6 /v6/priv_url 一次请求 9 档** `qualities:["128","320","flac","high","multitrack","viper_atmos","viper_tape","viper_clear","super"]`，响应 data[] 每档独立 hash/url/backup_url，无权限档 status≠0 或 url 空；tracker_param 带需 viptoken/vip_type/priv_vip_type=6/need_xcdn=1（song_url_new.js）。权益判定唯一可信源：v5 的 `status==1 && priv_status==1`；privilege_lite 的 privilege 是 int 标量**不可**用于判权（KUGOU_API.md 实测修正 5）。VIP 曲标记 `tracker_through.musicpack_advance=1`。
- **当前能力**：play_endpoints.dart 只封装 v5 单档（:38-136），已正确捕获 url[]/backupUrl[]/bitRate/extName/timeLength/status/priv_status/privKnown（flac 档 bitRate=0 不可用 bitrate 判档，API_DICT_CURRENT.md:73）。playback_service.dart resolvePlaySource 只请求单一 preferQuality（默认 128），**失败不降档、不批量探测 9 档、不消费 v6**（:101-143）——**捕获不了最大权益**。vip_token/vip_type 旧版在登录响应 _afterLogin 落 kg.vipToken/kg.vipType（legacy §3），当前 AuthLogic 未回写 vip_token，v6 即便接了也缺参。
- **修法方向**：接 playUrlV6（registry 已留 playUrlV6 声明位）；playback_service 按登录态 VIP 与否选档阶梯（VIP: super→viper→flac→320；非 VIP: 128/320 试降），consume backupUrl 串作为 fallback 主链。

## 4. MV 现状

- 旧归档：kmr_audio_mv.js（POST openapi `/kmr/v1/audio/mv` kg-tid:38，按 album_audio_id 查 MV hash）；video_detail/video_url/video_privilege（清晰度 ld/sd/hd/fhd/qhd 各带 hash/filesize/bitrate + *_265 + mkv_*）；播放走 trackermv `/v2/interface/index` → data[hash].downurl（必带 key，缺则 errcode 40003）。
- 当前：mv_endpoints.dart + mv_logic.dart **已实现并实测**（批N2-B，含 40003 key 教训）；bridge 已转出（bridge_core.dart）。**但 L7 surface 七个页面无任何 MV 引用**（rg 无命中）——纯缺 UI 入口，应挂在 player_page（歌曲详情 MV 角标）与 search_page 结果页（MV 类型项）。

---

## 5. 必修 TOP8（按用户诉求排序）

1. **短信验证码登录闭环**：smsLogin 三态探针实测（loginserviceretry 直连 + AES/RSA 载荷已就绪），回写 token/userid/vip_type/vip_token/t1 → 落 session（auth_endpoints.dart 需探针后翻转注释）。
2. **密码登录 /v9/login_by_pwd**：注册表+端点封装全缺，补 Endpoint + AES 载荷（t1,t2,t3 固定常量见 legacy §1）。
3. **token 自动续期**：loginToken Endpoint 已声明无调用方；启动/401 时调 /v5/login_by_token 续期。
4. **匿名播放链**：核实 KugouClient registerDevice（platid=2、uid='0'、小写 hex p、signature 含 body、二进制 AES 响应）+ verification_logic 过 20028 → 匿名 '0' 凭据播免费曲（现状匿名恒 20028 失败）。
5. **play_url v6 多档批量**：接 /v6/priv_url，一次取 9 档 + viptoken/vip_type 参；「未探针」状态需实测。
6. **playback_service 档位阶梯**：消费 priv_status/fail_process/musicpack_advance，VIP 与否走不同 quality 阶梯 + backupUrl 兜底；不再单档 128 死磕。
7. **微信开放平台登录**（需求存在时）：/v6/login_by_openplat + 微信 qrconnect 三步，依赖 appid/secret 配置。
8. **MV UI 入口**：播放页 MV 角标 + 搜索页 MV 项 → mv_logic.getMvBySong → videoQualities 清晰度选择 → videoUrl 播放（downurl http 需走代理/转 https）。
