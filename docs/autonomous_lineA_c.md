# 线A 阶段1 检查报告 · 网络与播放链（2026-11-15）

范围：批4/5/12 + 批3 遗留接线。只读检查，未改任何代码。
证据：`docs/research_field_capture_3state.md`（下称 C）、`docs/plan_upstream_endpoints_a.md`（下称 A）、
`docs/plan_upstream_endpoints_b.md`（下称 B，含 util/request.js 公共层）、`lib/core/net/endpoints/play_endpoints.dart`、
`lib/logic/player/playback_service.dart`、`lib/core/net/endpoint_registry.dart`、`tool/api_probe.dart`，
辅以 `play_models.dart` / `mv_anonymous.dart` / `mv_endpoints.dart` / `playlist_write_endpoints.dart` /
`crypto_rsa.dart` / `kugou_client.dart` / `bridge_core.dart` / `tool/field_truth_test.dart` 只读核对。
凭据全程未打印值（仅读 Netscape cookie 的键名）。

## 0. 基线数字（先校正）

- C §3 说「registry 共 50 个端点声明」；**当前 `endpoint_registry.dart` 实际为 53 条** `static const … = Endpoint(`。
  差额来自批3-F1 新增 `anonymousSongUrl` / `registerDevice`（+2）与后续补声明，且 `videoDetailKmrV2`
  已按 C §3「三态 404 死代码」删除（现仅留注释，非声明）。以 53 为本次基线。
- 三方 = ① 本仓 registry 声明 ② 上游 `KuGouMusicApi/module/*.js` + `util/*.js` 源码
  ③ 本仓三态实测留样（`API_FIELDS_TRUTH.md` / `api_samples/*.json` / `tool/field_truth_test.dart`）。
- `field_truth_test.dart`（916 行）断言的是**模型解析与响应留样键**（如 A3-1 play_url 22 键形态、
  A5-2 /v1/video 平铺 7 档、A6 写回执），**并未断言任何 `EndpointRegistry.<name>` 常量本身**；
  但被断言的路径/契约（`playUrlV5`、`videoDetail`、`mvDetail`、`videoUrl`、`searchSong`、
  `commentCount`、`playlistCreate/AddSongs/DelSongs`、`recommendSongs`、`favoriteCount` 等）
  必须保留，删除即断测试语境。阶段2 清理只做「注释与契约说明修正」，不动这些常量。

## 1. ① 53 端点声明 vs 上游源码 vs 实测契约：不一致清单

| # | registry 声明（现状） | 上游源码事实（A/B） | 实测/消费事实（C 与本仓） | 判定 |
|---|---|---|---|---|
| 1 | `personalFm` = POST `/v1/fm/play`（无 router） | B §2：`personal_fm.js` = `/v2/personal_recommend` + x-router `persnfm.service.kugou.com`，action/play/song_pool_id/remain_songcnt/m_type=1，key=signParamsKey(**毫秒**) | C §3 / B §2：/v1/fm/play 三态 items=0 死样本；`fm_endpoints.getFmPlay` 注释也写真实路径是 v2 | **契约错位（最高危）** |
| 2 | `fmSongs` = GET `/v1/fm/songs` | B §2：`fm_songs.js` = POST `/v1/app_song_list_offset`（JSON body `data[]:{fmid,fmtype,offset:-1,size:20}`，毫秒 key） | registry 自注「待实测不猜参数」，但已猜成 GET + 错路径；`getFmSongs` 请求走错声明 | **路径+方法双错** |
| 3 | `userCloud` = POST `/v1/user_cloud`（gateway） | B §3：`user_cloud.js` = `mcloudservice.kugou.com` 直连 `/v1/get_list`，`notSignature`+`clearDefaultParams`，query `p=RSA({aes_key,uid,token})`、clienttime **秒**、body=AES、响应 arraybuffer AES 解密 | C §3：三态 items=0；真实 AES/RSA 未实现 | **路径/域名/加密三重错位** |
| 4 | `artistAlbums` = `/v1/author/albums` + router openapi | A/B §7：`/kmr/v1/author/albums`（kg-tid 36，body author_id/sort/category/area_code） | C §3 与 registry 自注：实测 502/403，已走 albumDetail 降级 | **路径缺 kmr 前缀（死声明保留待实测）** |
| 5 | `commentCount` = `/v1/comment/count` + web 签名 + router `sum.comment.service` | B §4：`comment_count.js` = `/index.php`（**无版本号**），web 签名，`r=comments/getcommentsnum&code=…&hash/childrenid` | 封装已按 hash 键取值 ✅；路径仍非上游 | **路径错位** |
| 6 | `commentFloor` = `/mcomment/v1/hot_replylist` + router mcomment | B §4：`comment_floor.js` = `/v1/hot_replylist`，且歌单/专辑改用 `m.comment.service` 域，按 resource_type 选码 | `getCommentFloor` 已按实测 `tid` 传参，childrenid/mixsongid 口径待实测 | **路径/路由按域分叉未建模** |
| 7 | `favoriteCount` = `/count/v1/audio/mget_collect` + router `sum.comment.service.kugou.com` | B §5：路径 ✅（GET android）；router 无源码证据（registry 自承「类比 comment/count」） | C §3：三态 count=0，字段契约无 A 章节；`data.list[]{mixsongid,count,count_text}` 实测有留样 | **路径对、router 属推断，需标待实测** |
| 8 | `collectSong` = POST `/v2/collect`；`cancelCollect` = POST `/v2/cancel_collect` | B §5：**上游无此模块**；真实收藏 = `/v6/add_song`（+router cloudlist）/ `/v2/delete_list`（AES） | C §3：`collect_endpoints` 已接真契约；两条声明零消费 | **死声明（可清理）** |
| 9 | `playlistCreate` = `/cloudlist.service/v5/add_list`（URL 前缀式） | B §5：`playlist_add.js` = `/cloudlist.service/v5/add_list` ✅ | 同文件 `playlistAddSongs` 注释记录「URL 前缀式 /v6/add_song 实测 404 → 改 /v6/add_song + router」，说明**前缀式在本仓网关不稳**；create 未复测 | **需标待实测** |
| 10 | `playlistAddSongs` 注释自相矛盾 | 上半段写 `/cloudlist.service/v6/add_song`，下半段写实测 404 改 `/v6/add_song`+router（声明本身已是后者） | C §1.4：写端点 `list_ver` 恒 0，未用 detail 实测递增值 | **注释契约错位 + list_ver 缺口** |
| 11 | `listenReport` id=`user_listen_report` 语义「上报」 | B §3：`user_listen.js` `/v2/get_list` = **获取收听列表**（`p=cryptoRSAEncrypt`，t_userid/list_type/cover=2，必须 token）；上报由 personal_fm action/playtime 或 `/playhistory/v1/upload_songs` 承载 | registry 注释已承认语义错位，但 id 仍误导；UI 零消费 | **语义错位** |
| 12 | `loginToken` = POST `http://login.user.kugou.com/v5/login_by_token` | A §3：`login.user.kugou.com`（**https**，android 签名，p3=AES{clienttime,token} 固定 key，dfid/plat/t1/t2/t3/pk/params/userid/clienttime_ms） | C §3 旧结论「无任何封装」已过期：`bridge_core.dart` 已 export `loginByToken`，`auth_endpoints.dart` 有实现；但声明为 http + 默认 android 签名，未实现 p3/pk 专属参数 | **协议/签名契约待实测** |
| 13 | `smsLogin` / `sendSmsCode` = signType `none` + clearDefaultParams | A §3 / B §9：login_cellphone 是 `android + key=signParamsKey + pk(RSA)`；`register` 签名用于注册/设备类；captcha_sent `/v7/send_mobile_code` 契约待实测 | registry 自注「未三态实测，封装只构造不外发」；C §3 指出与 `kAuthEndpointsProbed=true` 矛盾 | **签名类型待实测** |
| 14 | `devLogout` = `base: https://loginservice.kugou.com` + path `/loginservice/v1/dev_logout` | A §3：`gateway.kugou.com` + `Host: gateway.kugou.com` 头、`/loginservice/v1/dev_logout`，**signParamsKey** android 签名，t_appid=3116 | 当前 base 与 path 拼接重复前缀，且 signType none | **域名/签名错位（待实测）** |
| 15 | `anonymousSongUrl` = `/v5/url` + signType `none` + clearDefaultParams + encryptKey | A §1：`song_url.js` L48-51 = `notSign:true` ✅、`encryptKey:true` ✅、随机 dfid cookie ✅；但 L15-38 必带 `area_code/ssa_flag/version:11430/clientver:11430/page_id/ppage_id/behavior/pid/cmd/pidversion/IsFreePart/cdnBackup` | `mv_anonymous.anonymousPlayUrl` 缺 `version/ssa_flag/page_id/ppage_id/clientver`，且 clearDefaultParams 丢 appid/mid/clientver；C §4.7 匿名实测 20028 + fail_process:['pkg'] | **声明方向对、参数半成品，待实测** |
| 16 | `registerDevice` = `https://userservice.kugou.com/risk/v2/r_register_dev`, signType none | A §3：`register_dev.js` = `/risk/v2/r_register_dev` ✅（可匿名，AES body + `p=rsaEncrypt2({aes,uid:'0',token:''})`，响应 arraybuffer AES）；但 `docs/API_DICT_LEGACY.md` / `research_legacy_login_url.md` 记 **v3** + register 签名（`md5('1014'+排序值+'1014')`）+ platid=2 + uid 字符串 '0' + p 小写 hex | 当前 `platid:2` 硬编码（与 A 源码 L100 明示 1 冲突），signType none，响应解密路径不可达（见 §4） | **版本/签名变体冲突，全部标待实测** |
| 17 | `searchComplex` = `/v6/search/complex` | B §1 一致 ✅ | C §3：实测 152 不可达，`searchComplexV6` 已降级 v3/song 薄委托 | **声明保留但不可达（非错位）** |
| 18 | `videoDetailKmrV2`（`/kmr/v2/videos`） | 上游无该 module 路径 | C §3：三态 404，批3-F1 已删声明与 fallback | **已清理（无需再动）** |
| 19 | `playUrlV5` / `privilegeLite` / `mvDetail` / `videoDetail` / `videoUrl` / `rankAudio` / `lyricSearch` / `lyricDownload` 等 | A §1/§2/§4、B §1/§6 与声明一致（含 kg-tid、x-router、encryptKey、clearDefaultParams） | 三态留样齐 | **一致 ✅（不动）** |

其余（searchSong/searchSuggest/searchHot、playlistDetail/Tracks/Tags/userPlaylists、rankList/rankInfo、
albumDetail/albumSongs/artistDetail/artistAudios/artistList/playlistSimilar、recommendSongs、
loginQrKey/loginQrCheck/loginByPwd、commentMusic、userDetail/playHistoryUpload/songClimax）
与 A/B 源码路径一致；`playHistoryUpload` 封装✅实测✅但无 L5 定时上报接线（C §3），属"接线缺"非"声明错"。

## 2. ② 三态字段捕获缺口（play_url v5 顶层键）

### 2.1 「22 键」口径
C §1.1 称成功响应顶层 22 键，其枚举实际列出 23 项：
`url[]、backupUrl[]、bitRate、extName、timeLength(s)、status、priv_status、hash、std_hash、
std_hash_time、fileHead、fileName、fileSize、hash_token、hash_token_query、q、volume、volume_gain、
volume_peak、classmap、tracker_through{musicpack_advance}、trans_param{qualitymap,ogg_*,union_cover,
hash_offset,…}、auth_through[]`；失败态另有 `fail_process:[pkg]`、`hash_offset`(clip_hash/offset_hash/
end_ms=60000)、`error_code`(35104)。任务另点名 `end_byte / is_hash_backup`（api_probe 的
`_sanitizePlayRaw` 已预留 end_byte/traceId 键，说明留样中确有其键）。
**结论：以「22 键标题 + 任务点名键」并集为准，共 ~26 个待捕获键；不臆造未留样键，缺失即标待实测。**

### 2.2 当前 `play_endpoints.dart` 已捕获（13 项）
`status`、`priv_status`(+`privKnown`)、`errcode`(=errcode ?? error_code)、`error`、`url[]`、
`backupUrl[]`、`bitRate`、`extName`、`timeLength`、`tracker_through.musicpack_advance`→isVipTrack、
`hash`(请求侧回填)、`isFreePart`(请求侧回填入参，非响应实测)、`privKnown`。

### 2.3 被丢弃 / 未捕获（逐键）
| 键 | 用途（C/A 证据） | 现状 |
|---|---|---|
| `q` | 服务端实际档位；flac 档 `bitRate=0` 不可判档 | 全丢；`playback_service` 恒用请求 `quality` 回填，服务端降档不可感知 |
| `std_hash` / `std_hash_time` / `fileHead` / `fileName` / `fileSize` | 文件校验/大小/回显 | 全丢 |
| `hash_token` / `hash_token_query` | 备链/重签凭据 | 全丢 |
| `hash_offset`（嵌套 clip_hash/start_ms/end_ms） | 试听片段真实边界 | 全丢；试听判定只靠请求侧 IsFreePart（C §1.1：VIP 号 IsFreePart=1 仍回全长） |
| `end_byte` | 试听片段结束字节 | 全丢（`api_probe._sanitizePlayRaw` 已留样键） |
| `fail_process` | 匿名 20028 的 pkg 校验处置码 | 全丢 |
| `is_hash_backup` | 备链是否低权益/哈希回退标记 | 全丢；与 `backupUrl` 的权益关系未记录 |
| `volume` / `volume_gain` / `volume_peak` | 响度均衡 | 全丢，播放器无 gain 补偿 |
| `classmap` | 可用档位图（最大权益 URL 决策关键输入） | 全丢 |
| `trans_param` 整体（qualitymap / ogg_* / union_cover / hash_offset / musicpack_advance） | 降档链、ogg 直链 hash | 只取了 `tracker_through.musicpack_advance`，`trans_param` 整体未读 |
| `auth_through[]` | 鉴权链路/可用档 | 全丢 |
| `error_code` | 非 VIP 带 key 失败形态 35104 | 仅作为 errcode 兜底，**无独立字段**，35104 语义未单列 |
| `volume`/`q` 等的失败态分支 | — | 失败响应直接返回空 PlayResult 结构 |

### 2.4 `backupUrls` / `priv_status` / `vip_token` 是否被用
- **`backupUrls`**：`play_endpoints` 解析 ✅ → `PlaySource.backupUrls` 透传 ✅ → **消费 ❌**。
  C §2：`playback_service.dart:121 urls: pr.urls` 恒主链第一条，`backupUrls` 无切换/健康检查；
  `PlaySource.toMap` 只是序列化，L6/L7 无按备链重试。
- **`priv_status`**：**被用但仅用于「错误语义」**。`play_models.PlayResult.playable` 要求
  `status==1 && privStatus==1 && urls.isNotEmpty`；`_mapError` 用 `status==2 && privKnown &&
  privStatus==0 → noPrivilege`。**未用于「选最大 URL」**（三态权益决策缺位）；且 `privKnown`
  防误判的设计是做对了的（C §4.7 认可）。
- **`vip_token`**：**完全未被生产链使用**。`.test_creds/cj_vip.txt` 含 `vip_token`（探针 `api_probe._sessionOf`
  只把它塞进 `session.cookies`），而 `KugouClient._requestRaw` 仅注入 `token`/`userid`/`mid`/`dfid`
  到 query，headers 只拼 `session.cookies`；`getPlayUrlV5` 不传 `vip_token`，A §1 的
  `/v6/priv_url`（9 档，`tracker_param.viptoken` + `vip` + key=md5(hash+盐+appid+mid+userid)）
  **本仓无声明、无封装**。结论：VIP 档解锁凭据在链路上断供，VIP 态只能拿到 /v5/url 的登录态默认档。

### 2.5 三态缺口（非 play_url 域，供阶段2 矩阵）
- 完整三态留样：play_url_v5 / search_song / suggest / hot / rank_list / user_detail / favorite_count /
  song_climax / user_cloud / fm_play / daily_recommend（C §2）。
- 仅 VIP 态留样：comment_music / comment_count / mv_by_song / album_detail。
- 三态「失败被吞成空」：daily_recommend(200103)、fm_play(items=0)、user_cloud / song_climax /
  favorite_count（count=0），getUserPlaylists 匿名 20010 返回空列表——「失败」与「真无数据」不可区分。
- `api_probe.dart` 落盘的是**封装函数返回值**（脱敏后的 captured），**不落原始响应顶层键**；
  `_sanitizePlayRaw()` 已写好却从未被调用（`main` 里无引用）→ 阶段2 v2 探针必须直接落顶层键。

## 3. ③ 写操作 `_ok()` status=0 误判现状

`lib/core/net/endpoints/playlist_write_endpoints.dart:18-28`：

```dart
final s = safeInt(data['status'], safeInt(res['status'], safeInt(res['error_code'], -1)));
if (s == 1 || s == 0) return true;
Log.d(... 'ambiguous success flag status=$s');
return s == 0;
```

- 上游 `util/request.js:143-155`：**`status===0` 或 `error_code!==0` 即失败**（502）；B §9.8 明确点名
  「Next `_ok()` 把 status=0 当成功属高危」。
- 现状后果：`createPlaylist`(:58)、`deletePlaylist`(:127)、`removeSongsFromPlaylist`(:141)、
  `getPlaylistTags`(:196)、`getUserPlaylists`(:254) 五处全部走 `_ok()`；匿名 20010 写回执
  顶层 `status=0` → **判 ok=true**，上层会把「需登录」当「写成功」。
- 连带：`error_code` 缺失时 `safeInt(...,-1)` 得 -1 → `return s==0` 为 false（与注释「按成功容错」
  自相矛盾）；`error_code=0`（成功）恰好 s=0 被第一分支收下，属巧合非设计。
- C §5 TOP10 #3 建议改为 `s==1 || (s==-1 && error_code==0)`。
- **本文件不在阶段2 允许修改清单内（硬规范「只改下列文件」）**：本阶段仅记录，阶段2 不改，
  在最终报告列为「范围外遗留风险」，并给出补丁文本供主会话排期。

## 4. ④ 匿名 `/v5/url` 与 `registerDevice` 封装是否已被播放链接入

**结论：均未接入，且 `mv_anonymous.dart` 当前不可编译/不可调用。**

证据链：
1. **零引用**：全 `lib/` 与 `tool/` 无 `import 'mv_anonymous.dart'`；`bridge_core.dart` 未 export 该文件的
   任何符号；`mv_endpoints.dart:416-422` 只有一段 `registerDevice` 的**孤立文档注释**（无函数体），
   文件末尾以注释收尾（半成品拆分痕迹）。
2. **编译级半成品（必修）**：`mv_anonymous.dart:95` 调 `playlistAesEncrypt`、`:112` 调
   `playlistAesDecrypt`，但 import 只有
   `import '../crypto_rsa.dart' show rsaEncrypt2;` → 两个标识符未定义，**静态分析必报错**。
   另有未使用 import：`cover_url.dart show normalizeCoverUrl`、`signing.dart show KugouSign, md5Hex`。
3. **签名/凭据契约半成品**：`registerDevice` 硬编码 `platid: 2`（A §3 源码 L100 明示 1；
   legacy 字典又要求 2，属版本变体冲突，须标待实测）；`signType: SignType.none` 与 legacy
   register 签名冲突；`p` 未做小写 hex 归一（`rsaEncrypt2` 返回值形态未核）。
4. **响应解密路径不可达（关键）**：`KugouClient._requestRaw` 先 `jsonDecode(text)`，解析失败即
   `throw KugouApiException(-3, …)`，**只有解析成功且非 Map 才走到 `if (rawBody != null)
   return {'_raw_text': text}`**。上游 `/risk/v2/r_register_dev` 响应是二进制 AES arraybuffer →
   `jsonDecode` 必抛 → `mv_anonymous.dart:107` 的 `res['_raw_text']` 永远取不到，
   `catch` 直接返回 `''`。`playlist_write_endpoints.deletePlaylist` 同款缺陷（范围外）。
   阶段2 需在 `mv_anonymous.dart` 内自带 raw POST（不改 `kugou_client.dart`、不改桥）。
5. **脱敏缺陷**：`mv_anonymous.dart:124` `Log.d(_tag, 'registerDevice ok dfid=<$dfid>')` —— dfid 属设备指纹/
   凭据类，硬规范要求 token/mobile/URL 掩码，此处须改为 `<redacted>` + 长度。
6. **匿名播放链消费侧**：`playback_service.resolvePlaySource` 只调
   `getPlayUrlV5(_client, hash, quality)`（登录态 android 签名 + key），失败即 `_mapError` 返回
   `PlaySource(error: …)`；**不重试** `isFreePart:true`、不调 `registerDevice`、不调
   `anonymousPlayUrl`、`resolveMvAudioFallback` 虽实现但注释明说「由 L6 session 调用，本方法不判
   失败语义条件」，即主链不会自动兜底。`PlaySource.isFallback` 默认 false。
   `getPlayUrlV5` 的 `isFreePart` 形参存在但**全仓仅 `api_probe`/测试可能传，生产调用点为默认 false**。
7. **错误码语义**：`_mapError` 已把 31833 单列到 `network`（注释写「禁止新扩接口」），35104 未单列
   → C §4.7 指出 nonvip 带 key 的 35104 会落 notFound（应 noPrivilege）。阶段2 需补。
8. **`api_probe.dart` 的 `_sanitizePlayRaw` 从未被调用**：原始顶层键留样缺口，v2 探针需补。

## 5. 阶段1 → 阶段2 可执行项（对齐允许修改的 5+2 文件）

| 文件 | 动作 |
|---|---|
| `play_endpoints.dart` | 补全 §2.3 全键解析（保留 `privKnown`），新增 `PlayResult` 承载（`play_models.dart` 不在允许清单 → 用 `PlayResult` 现有字段 + 同文件内轻量 `PlayRawFields` 结果对象，或扩展 only 允许文件内的解析输出） |
| `playback_service.dart` | `selectBestUrl`（三态权益选最大 URL）+ 主链→备链→降档链/试听真实消费 + 35104 → noPrivilege + 31833 单列签名失败语义 |
| `mv_anonymous.dart` | 修 import / raw POST / dfid 脱敏 / 匿名参数补全，使其可编译可调用 |
| `endpoint_registry.dart` | §1 清单的注释与契约说明修正（不删被 `field_truth_test` 语境断言的常量；死声明仅打标），新增/变体一律标「待实测」 |
| `tool/api_field_probe_v2.dart`（新） | 三态真实调用已接只读端点，落 `docs/api_samples_v2/*.json`（脱敏顶层键 + 关键字段） |
| `docs/API_FIELD_CAPTURE_3STATE.md`（新） | 逐端点三态矩阵 |

## 6. 阶段1 明确「不修」项（受硬规范约束）

- `playlist_write_endpoints.dart` `_ok()`（不在允许清单，见 §3）；
- `lib/surface/**`、`lib/session/**`、`lib/core/cache/**`、`lib/core/storage/**`、
  `lib/logic/catalog/**`、`lib/bridges/**`（六桥）、`lib/core/net/kugou_client.dart`、
  `mv_endpoints.dart`、`play_models.dart`、`tool/local_gate.sh`、`tool/field_truth_test.dart`、
  `.github/**`、`README.md`、`docs/plan_*`；
- 不新增 `/v6/priv_url` 声明（VIP 9 档属新端点，非「版本变体」且未三态实测，超出批范围）。
