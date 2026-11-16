# A3 批 · C1 架构合规视角 · 深度审查报告

> 视角：C1 架构合规（76 原则逐条核）
> 范围：`lib/core/net/endpoints/` 全部 dart 文件
> 契约：`docs/DEEP_AUDIT_14_BATCH_PLAN.md` + `docs/SEVEN_SIX_RULE.md` §0
> 纪律：只读审查（file_read + ls/rg/wc），不改源码、不跑分析器/门禁/测试、不联网。
> 说明：本文件为重派续写；上一实例仅写开头，本次从头执行并追加。

---

## 2026-11-16 · 开局事实

证据：`rg --files lib/core/net/endpoints -g '*.dart' | wc -l` = **26**（任务书写「25 个」，实际 26）。`wc -l` 最大 `auth_endpoints.dart` = 546 行，其余均 < 546。
问题：范围文件数 26 ≠ 任务书描述的 25（含 models*.dart 等），以实际枚举为准，全部纳入审查。
建议：主会话核对批次数目口径；本次按实际 26 文件全量审。
76 合规：符合第 5 条（单文件 1500 行门禁全部通过，无超限文件）。

---

## 2026-11-16 · 全局静态扫描（C1 交叉核）

证据：
- L4 禁令：`rg 'package:flutter|BuildContext|Widget'` endpoints 全部 dart → **NONE**，零 Flutter 依赖，符合 L4。
- 反向依赖：`rg 'import.*(logic/|session/|surface/)'` → **NONE**；唯一跨层 import 是 23 个文件的 `import '../../../bridges/bridge_kernel.dart' show Log;`（合法桥通道，L4→L3）。
- 明文 http：`artist_endpoints.dart:493` 是 `img.startsWith('http://')` 判断（非发请求）；`cover_url.dart:3-4` 是注释。注册表 `loginToken`/`sendSmsCode` 用 `http://login.user.kugou.com`（陈述见合规项）。
- 硬编码 IP：`rg '\d+\.\d+\.\d+\.\d+'` → **NONE**。
- 内联 Endpoint 绕过注册表：`artist_endpoints.dart:436`、`search_typed_endpoints.dart:68` 就地 `Endpoint(router: 'complexsearch.kugou.com')`（官方域名，但注册表已有 `searchComplex` 声明）。
- try/catch 异常：`quality_endpoints.dart` try=0/catch=0（137 行，下文核是否含公开端点函数）；model 文件 lyric_models/models/translation_models try=0（纯数据类，合理）；`user_endpoints.dart:53` 有 `rethrow`。
- Log 调用总量 278 处，覆盖率广。

问题：存在内联 Endpoint 声明（职责分散于注册表之外）、quality 文件零 try/catch 待核。
建议：内联 Endpoint 收敛回 registry；核 quality 是否需补 try/catch+Log。
76 合规：符合第 1/4 条（无反向依赖、无 Flutter）；第 6 条内联端点待细分；第 2 条 quality 待核。

---

## 2026-11-16 · 模型/工具/小端点逐读（C1）

证据：
- `models.dart`（9 行）纯 export 桶；`models_util/song_models/play_models/playlist_models/lyric_models/translation_models` 均为纯数据+容错工厂，统一 `try/catch + Log.e` 兜底无静默吞。`quality_endpoints.dart`（137 行）纯 enum+switch 函数、零 IO —— 前扫「try=0」属合理，非缺陷。
- `cover_url.dart`：`normalizeCoverUrl` 只做 `{size}` 模板替换，`!u.startsWith('http')` 返回空串，实际 CDN URL 由服务端给（http/https 都放行），未硬编码第三方域；唯一收口点，职责单一。
- `album_endpoints.dart`：3 个公开函数（getAlbumDetail/getAlbumSongs/getSimilarPlaylists）均 try/catch+Log.e，参数 albumId/page/pageSize 齐全，全走 EndpointRegistry；同文件封装「专辑详情+专辑歌曲+相似歌单」——相似歌单属歌单域，与专辑域弱相关（职责边界可议）。
- `fm_endpoints.dart:3-6` 注释声称 personalFm→`/v2/personal_recommend`、fmSongs→`/v1/app_song_list_offset`，但 `endpoint_registry.dart` 声明 personalFm=`/v1/fm/play`、fmSongs=`/v1/fm/songs`。实际请求取 registry，注释与声明漂移（误导维护，非运行缺陷）。`_fetch` 显式补 dfid/mid/uuid 参与签名（符合铁律6），full 参数+Log.w 占位齐。
- `recommend_endpoints.dart`：platform 入 query、userid/token 入 body；三参 dfid/mid/uuid 显式补齐；DailyRecommendResult 实现 ListBase 兼容旧 UI（职责含兼容层，属 L4 可接受）。try/catch+Log 齐。
- `search_endpoints.dart`：3 函数全 try/catch+Log；参数 keyword/page/pagesize 齐；注释记录 dataOf 对数组 data 的坑并修正用 res['data']。同文件 song/suggest/hot 属搜索域内聚，合理。

问题：FM 注释路径与 registry 声明不一致；album 文件混入「相似歌单」跨域端点。
建议：同步 FM 注释为 registry 实际路径；相似歌单可迁 playlist 域（仅建议）。
76 合规：均符合第 1/2/4/6 条（同层引用、桥日志、官方域、多参齐）。

---

## 2026-11-16 · 中端点逐读（C1）

证据：
- `search_typed_endpoints.dart:68`：song 走注册表 `searchSong`，其余五类就地 `Endpoint(id:'search_x', path:'/v1/search/<type>', router:'complexsearch.kugou.com')`——官方域，注释说明「不改 kugou_client.dart」故本地声明。`searchComplexV6` 降级为 v3/song 薄委托（实测 v6 不可达），保留签名兼容。全函数 try/catch+Log。
- `comment_endpoints.dart`：CommentItem/CommentPage + 3 端点（music/floor/count）全 try/catch+Log；`commentBlockedReason` 只保留短因不泄凭据；`kCommentCode` 是常量码非 token。职责内聚评论域。
- `playlist_endpoints.dart`：recommend/detail/tracks/addSongs 4 函数 try/catch+Log 齐；`addSongsToPlaylist` 转发到 `playlist_write_endpoints`（同层引用，合法）。body 全参（appid/mid/clientver/key 等）齐。
- `play_endpoints.dart`：getPlayUrlV5/getPrivilegeLite 全 try/catch，20+ 处嵌套 try/catch 逐字段解析，全部 Log.e 不静默；`privKnown` 避免误判；只记 hash/长度无 token 泄漏。参数（hash/quality/isFreePart/22 顶层键）齐全。仅日志偏冗长（P2 可议）。

问题：search_typed 五类端点本地内联声明（注册表外）；无明显架构违规。
建议：如统一收口可将五类 path 补进 registry（仅建议）。
76 合规：符合第 1/2/4/6 条；内联声明属第 6 条「集中 vs 分散」边界灰区。

---

## 2026-11-16 · auth/账号端点逐读（C1）

证据：
- `auth_endpoints.dart`（546 行，本批最长，<1500）：6 函数（sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout + 助手）全 try/catch+Log.e；全走 EndpointRegistry（loginToken/smsLogin/sendSmsCode/loginByPwd/devLogout）。
- token/凭据纪律：`LoginResult.toString`/`SmsLoginResult.toString` 只打 `tokenLen`/`vipTokenLen` 不打值；`maskMobile` 前2后1掩码；`Log.d('smsLogin built mobile=${maskMobile} paramsLen=.. pkLen=..')`、`loginByToken ok tokenLen=..` —— 全文件无 token 明文/cookie 进日志，`rg 'token=\$'` 未见打印 token 值。符合「token 不进日志」。
- AES/RSA 实现在 `crypto_extra.dart`（同层 L4 core/net），未反向 import 上层；`Random.secure()` 生成 tempKey。仅官方域（经 registry）。
- 注意：`endpoint_registry.dart` 中 `loginToken`/`sendSmsCode` base 为 `http://login.user.kugou.com`（明文 http）——声明在 registry（A2 批范围），auth 文件本身只消费。官方域名但非 https（P2，跨批记录）。

问题：auth 端点本体合规；明文 http 声明源头在 registry（非本文件）。
建议：主会话在 A2 批核 registry 的 http:// 是否可升 https。
76 合规：符合第 2/6 条；第 6 条「官方域」符合（http 仍是 kugou.com）。

---

## 2026-11-16 · user 端点逐读（C1）

证据：
- `user_endpoints.dart`（347 行）：6 公开端点（getUserDetail/uploadPlayHistory/getSongClimax/getUserCloud/reportListen + rsaCryptoEncrypt 助手）全 try/catch+Log.e。
- `rsaCryptoEncrypt:53` 的 `rethrow`：catch 中先 `Log.e(_tag, 'rsaCryptoEncrypt failed (plaintext not logged)', e, st)` 再 rethrow（非静默吞），调用方函数各自 try/catch 兜底——符合第 2 条「失败必 Log 留痕不静默吞」，rethrow 后仍有上层捕获。非缺陷。
- token 纪律：`rsaCryptoEncrypt` 仅打 'plaintext not logged'；getUserDetail/reportListen 把 token 加密进 RSA 后只打 uid/status/hash，无 token 明文。合规。
- `getUserCloud` 注释称 `/v1/get_list @ mcloudservice.kugou.com`，但 registry `userCloud` 声明为 `/v1/user_cloud`（无独立 base，走 gateway）——又一处注释与声明漂移（同 fm）。实际请求取 registry。
- 全走 EndpointRegistry；官方域（usercenter/listenservice/expendablekmrcdn 均 *.kugou.com）。

问题：userCloud 注释路径与 registry 声明不一致（同 FM 类漂移）。
建议：同步注释；rethrow 可保留（已有 Log）。
76 合规：符合第 2/6 条。

---

## 2026-11-16 · 末批端点逐读（C1）

证据：
- `playlist_write_endpoints.dart`（371 行）：create/delete/addSongs/removeSongs/getTags/getUserPlaylists 全 try/catch+Log.e；写操作不重试；token 只入 body/RSA 加密，日志仅打 id/n/status。全走 registry，官方域。
- `collect_endpoints.dart`（287 行）：collect/cancel/favoriteListId/getFavoriteCount 全 try/catch+Log；`needsLogin` 恒 false 交 logic 判（职责边界清晰）；复用 playlist_write 同层门面。未直接调 registry 写端点（经门面），合规。
- `translation_endpoints.dart`：纯本地抽取（无网络），fetchTranslation 保留 client 形参兼容装配；try/catch+Log 齐。
- `mv_anonymous.dart:114` `Log.d(_tag, 'registerDevice ok dfid=<$dfid>')`：**dfid（设备指纹）明文进日志**。dfid 非 token/cookie，但属设备标识，严格脱敏口径下宜掩码。
- `mv_endpoints.dart`：MvBrief/MvQuality/MvPlayResult + 3 端点全 try/catch+Log；`getVideoQualities` body 带 token 但日志只打 hash/count。⚠️ 文件尾部 `:415-422` 残留 `/// registerDevice ...` 孤立文档注释（无函数体）——该函数已拆至 mv_anonymous.dart，属拆分后死文档。
- `artist_endpoints.dart`（538 行）：ArtistBrief/ArtistDetail/AlbumBrief + 4 端点全 try/catch+Log；`_baseParams` 显式补 dfid/mid/uuid 参与签名。`:436` 及 `getArtistAlbums` 内 `const Endpoint(id:'artist_albums_search', path:'/v1/search/album', router:'complexsearch.kugou.com')` 内联声明（官方域，降级用）。`albumBriefFromSearchAlbum:493` `img.startsWith('http://')` 是 URL 校验非发请求。
- `misc_endpoints.dart`（237 行）：rankList/rankInfo/lyricSearch/lyricDownload + krc 解码——**跨功能混装**（排行 + 歌词 + 本地解码三域），与「一文件一组紧密相关端点」相悖；但各端点 try/catch+Log 齐。

问题：① mv_anonymous dfid 明文日志（P2）；② misc 跨功能混装（P2）；③ mv_endpoints 尾部死文档（P2）；④ artist/search_typed 内联 Endpoint（P2）。
建议：dfid 掩码；misc 按 rank/lyric 拆；删 mv_endpoints 尾部孤立注释；内联 Endpoint 收进 registry。
76 合规：均符合第 1/2/4/6 条（桥日志/官方域/多参齐）；第 6 条「一组紧密相关端点」misc 存疑。

---

## 本视角结论

1. **L4 层职责干净**：26 文件零 `package:flutter`/BuildContext/Widget import，零 logic/session/surface 反向 import；唯一跨层通道是 23 文件的 `bridge_kernel.dart show Log`（合法，符合铁律 1/4）。
2. **桥日志纪律优秀**：全部 23 个含网络/解析逻辑的文件统一经 `bridge_kernel.Log` 记日志，278 处 Log 调用；公开端点函数均 try/catch + Log 留痕，未见静默吞异常（user_endpoints 的 rethrow 有前置 Log.e，合规）。
3. **token/凭据不进日志落地到位**：auth/user/playlist_write/mv 等登录态端点，token 只入 body 或 RSA/AES 加密载荷，日志只打长度/掩码/uid；`LoginResult.toString` 仅 tokenLen。唯一瑕疵是 mv_anonymous 打明文 dfid（设备指纹，非 token）。
4. **只连酷狗官方域名**：零硬编码 IP、零第三方域；所有请求走 EndpointRegistry（gateway.kugou.com + *.kugou.com router/base）或内联官方域 Endpoint。明文 `http://` 仅存于 registry 的 loginToken/sendSmsCode 声明（A2 批范围，非本文件）。
5. **1500 行门禁**：全部通过，最长 auth_endpoints 546 行。
6. **职责边界**：多数文件内聚（search/auth/play/user/mv/playlist 等）；misc_endpoints 混装 rank+lyric+krc（P2）；album_endpoints 含「相似歌单」（弱跨域）。
7. **端点声明分散**：search_typed（5 类）、artist（降级搜索）就地 `const Endpoint` 而非收进 registry（官方域，非缺陷，P2 建议）。
8. **注释与声明漂移**：fm_endpoints、user_endpoints 头部注释的路径与 registry 实际声明不一致（实际取 registry，运行无碍，误导维护，P2）。

## 未覆盖

- 本视角仅审架构合规（76 原则），**未做**实现正确性（C2）/M3 文案 UI（C3）审查。
- 未验证任何端点的实际网络可达性/三态/字段解析正确性（任务禁止联网/跑测试）；所有「待实测」端点按源码声明审，不判运行成败。
- `endpoint_registry.dart`（503 行）与 `kugou_client.dart`（KugouClient.request）本体属 A2 批范围，本视角只读其对端点的声明/参数约束，未逐审其内部实现（如 encryptKey/tid 注入是否生效）。
- 上游 logic 层（L5）如何消费这些端点的门面对照属 A5 批；本视角未展开。

## 76 合规小结

- **第 1 条（跨层走桥）✅**：无跨层直 import；23 文件经 bridge_kernel 取 Log。
- **第 2 条（try/catch+Log 不静默吞）✅**：公开端点函数全覆盖；quality/纯 model 无 IO 故无 try/catch 属合理。
- **第 3 条（桥唯一在 lib/bridges）✅**：本批无影子桥定义。
- **第 4 条（依赖方向/同层合法）✅**：endpoints 内部同层互引（playlist_write、cover_url、models）合法，无反向依赖。
- **第 5 条（1500 行门禁）✅**：26 文件全 < 546 行。
- **第 6 条（一文件一模块/多参不缺参/只连官方域）⚠️ 基本符合**：多参齐全（dfid/mid/uuid 显式补、body 全参）、全官方域；瑕疵＝内联 Endpoint 分散（search_typed/artist）、misc 跨功能混装、注释路径漂移（fm/user），均为 P2 非阻断。
- **第 7/8/9 条**：与 endpoints 层无关（零源复用/L6 禁状态机/成熟库边界），本批不涉及。
- **第 10 条（子代理只读）✅**：全程 file_read + ls/rg/wc，未改源码、未跑门禁/分析器/测试、未联网。

> 本视角 0 个 P0、0 个 P1；P2 共 4 类（dfid 明文日志 / misc 混装 / mv 死文档 / 内联 Endpoint+注释漂移）。架构合规总体良好。
