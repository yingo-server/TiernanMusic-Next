# A3 批 · C2 实现正确性视角 · bA3_c2.md

> 审查范围：`lib/core/net/endpoints/` 全部 26 个 dart 文件（实际 26，任务书误记 25）。
> 视角：实现正确性（字段解析对齐 / 缺参 / 空结果 / 空安全 / 异常吞没 / 端点三态 / MV 契约 / auth 标注）。
> 契约基准：`docs/DEEP_AUDIT_14_BATCH_PLAN.md`、`docs/API_TEST_REPORT.md`、`docs/API_FIELDS_TRUTH.md`、`docs/api_samples/*`、`docs/deep_audit/A2_P0_VERIFICATION.md`。
> 纪律：只读审查；禁跑 dart/analyze/test；禁改源码。每条发现实时 append。
> 去重：AES Rcon bug（crypto_aes.dart）、RSA BigIntL.mul 已在 A2_P0_VERIFICATION 定稿（一真一误报），本视角不重复报。

---
## <视角 C2> · lib/core/net/endpoints/mv_endpoints.dart:57,287 · <P0> · 字段解析与真实契约错位／MV 功能不可达（用户点名）
证据：契约 `docs/API_FIELDS_TRUTH.md` §A5-1 实测（kmr/v1/audio/mv 的 data[0][] 项 27 键）明确记载「⚠️ MV 项本身**无 hash 键**——播放 hash 来自歌曲侧 mvdata[].hash 或 deprecated.video_hash，或由 video_id 走 A5-2 取档位 hash」，且该项标识键是 `video_id`（数字，如 596344）。代码 `MvBrief.fromMap` L57 只取 `m['hash'] ?? m['mvhash'] ?? m['video_hash']`，三个键均不在实测键集内（代码注释 L55-56 自己承认「MV 摘要项本身标识键是 video_id」却未读它）；`getMvBySong` L287 `if (mv.hash.isEmpty) return null`。链路：`getMvBySong`（playback_service.dart:291 / 上层）→ MvBrief.hash 恒空 → 恒返回 null → `resolveMvAudioFallback`（L292-293）走 `PlaybackError.notFound`。
问题：按歌查 MV 端点在契约正确返回下也恒返回 null，MV 播放兜底链路整体不可达——直接对应「什么功能都用不了，MV 等等」痛点。
建议：MvBrief 增 `videoId` 字段读取 `m['video_id']`（实测数字），`getMvBySong` 不再以 hash 非空为成功门槛，改以 videoId 非空判定；hash 若上游 mvdata 有则透传，无则留给 getVideoQualities 用 videoId 查询。勿用 32 位 hash 冒充 video_id。
76 合规：本条在 L4 端点层内部，未越级；不违反 76。但端点字段解析错导致 L5/L7 MV 链路断，属底层功能不可达，修复须止于 L4。

## <视角 C2> · lib/core/net/endpoints/mv_endpoints.dart:305,324 · <P1> · 参数语义错配（video_id vs hash）
证据：`getVideoQualities(client, String mvHash)` L306 将入参小写化，L324 直接作 `data:[{'video_id': h}]`。契约 §A5-2 实测 body 为 `{appid,clientver,clienttime,mid,uuid,dfid,key,show_resolution:1,data:[{video_id:596344}]}`，video_id 是**数字 MV id**，非 32 位字符串 hash。函数签名/参数名（mvHash）、上层传入（`playback_service.dart:297 getVideoQualities(_client, mvBrief.hash)`、`mv_logic.dart:48 getVideoQualities(_client, h)`）均为 hash 语义，与端点要求 video_id 数字语义冲突。
问题：即便 MvBrief 拿到 hash，以 32 位十六进制 hash 作 video_id 请求 /v1/video 也大概率返回空 data → 清晰度恒空 → MV 不可播。
建议：入参改 `int videoId`（或 `{int videoId, String? hash}`），body 传 `{'video_id': videoId}`；缓存键、上层调用同步改为以 videoId 为标识。保留 hash 仅用于 videoUrl 的 downurl hash（来自档位，契约一致）。
76 合规：未越级；属 L4 端点参数语义错误，不违反 76。

## <视角 C2> · lib/core/net/endpoints/auth_endpoints.dart:38,273-546 · <P1> · 待实测端点冒充可用／needsProbe 从不置位
证据：文件头 L8-16 明确 6 个登录端点（sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout 等）全部「待实测 → needsProbe」「未实测**禁止外发真实凭据**」；而 L38 `const bool kAuthEndpointsProbed = true` 开关放行真实网络调用，各函数（如 L286 sendSmsCode、L352 smsLogin、L437 loginByPwd、L489 loginByToken、L528 devLogout）无条件 `client.request` 外发 token/pwd。全文件 grep：`needsProbe` 仅出现在字段声明/默认值 false/toMap/toString，**无任何返回点置 `needsProbe: true`**——即端点自己承认未实测，却对外表现得像可用结果。交叉：这些函数全部依赖 `AesCbc.encryptHex/decryptHex`（crypto_extra.dart:5 导出 crypto_aes.dart），而 `docs/deep_audit/A2_P0_VERIFICATION.md` 已确认 AesCbc 的 Rcon 恒 0x01 为**真 bug**，与标准 AES 不互通 → 登录链端到端不可能成功。
问题：YKG 之外的现有登录端点「标注待实测却冒充可用」，会真实外发凭据且注定失败，误导上层与用户；needsProbe 语义形同虚设。
建议：未实测端点开关改 false 或在每个返回点按实测状态置 `needsProbe: true`，UI 明确提示「登录端点待实测/不可用」，禁止静默外发真实凭据；登录权重构前先替换已确认有 defect 的 AesCbc。
76 合规：L4 端点层，未越级；但「标注不可用却放行」违反功能诚实性，非 76 条款问题，属实现正确性 P1。

## <视角 C2> · lib/core/net/endpoints/translation_endpoints.dart:137-152 · <P1> · 死代码／函数冒充可用（恒返回空）
证据：`fetchTranslation(client, lyricId, accessKey)` L146 构造 `LyricResult(id: id, accessKey: key)`——**content 未注入，恒为空串**；L151 随即 `fetchTranslationFromContent(probe)` → L66 `extractOriginalLines` 对空 content 直接返回空列表 → L161 `trans.isEmpty` → 恒返回 `const TranslationResult()`。上层 `logic/lyrics/translation_logic.dart:2` 注释已自认「fetchTranslation 恒返回空」；真正可用的是 `fetchTranslationFromContent(LyricResult)`（需外部传 content）。
问题：`fetchTranslation` 名义是「逐行翻译获取」端点，实际无论传什么都返回空 TranslationResult，是死代码；bridge_core.dart:83 仍把它导出给 L5，调用方若走此路径永远无译文。
建议：删除 `fetchTranslation` 或改其签名为必须传入完整 LyricResult（含 content），内部委托 fetchTranslationFromContent；若保留兼容壳必须显式返回「端点未实现」语义（如 Result 带 unimplemented 态），不得静默返回空成功体。
76 合规：L4 内部，未越级；不违反 76。

## <视角 C2> · lib/core/net/endpoints/user_endpoints.dart:209,340 · <P1> · HTTP200 业务失败被当成功（成功判定用 || 且默认兜底过宽）
证据：`uploadPlayHistory` L209 `final ok = status == 1 || err == 0;`；`reportListen` L340 `safeInt(res['status'],-1)==1 || safeInt(res['error_code'],-1)==0`。契约 §R1-A-2/R1-A-3（文件头注释引用）：匿名态 `error_code=20010`，登录态 `status=1 error_code=0`。用 `||` 意味着：只要 `error_code==0`（很多失败/空响应缺省值）即判成功，即使 `status` 缺失或非 1；`safeInt(x,-1)` 的 -1 缺省反而让 err==0 分支在「两键都缺」时为 false，但「status=0/error_code 缺」与「status 缺/error_code=0」等形态仍会误判。对比同文件 `getUserDetail` L130 用严格 `status==1 && error_code==0`，同目录 `playlist_write_endpoints._ok` L21 已「三态实测收紧」为 `s==1 && ec==0`——本文件两处未同步收紧。
问题：写操作/上报在业务失败（status!=1）时可能返回 ok=true，上层统计/上报状态失真。
建议：改为 `status == 1 && (error_code 缺 || error_code == 0)` 的严格合取，与 getUserDetail/_ok 口径一致；错误码非 0 一律 false 并 Log.w。
76 合规：L4 端点层，未越级；不违反 76。

## <视角 C2> · lib/core/net/endpoints/comment_endpoints.dart:250-256 · <P2> · 猜测参数冒充真实口径／可能污染评论请求
证据：`getCommentFloor` 注释 L237-239 自认「childrenid/mixsongid 的正确口径（歌曲 id vs 评论 id）**待实测**，按最小参数集随传，不作成功门槛」，但 L254-255 实传 `'childrenid': commentId, 'mixsongid': commentId`——把「评论 id」同时塞给两个语义未定的字段。对比 L272 `getCommentCount` 实测契约明确「传 mixsongid/childrenid 恒 0」，故这些键名/口径本身可疑。
问题：楼中楼评论参数靠猜测，命中率/正确性无保证；且与实际 song mixsongid 混淆，可能取错数据或恒空。
建议：标注该端点为 needsProbe 并在实测前不发起含猜测参数的请求（或返回带受限态空结果），待留样后按真实字段（歌曲 mixsongid + 评论 tid）重写。
76 合规：L4 端点层；不违反 76。

## <视角 C2> · lib/core/net/endpoints/mv_anonymous.dart:119-190 · <P1> · 待实测的匿名播放链冒充可用（对应 play_url 历史 20028）
证据：`anonymousPlayUrl` 全函数标注「⚠️ 待实测」，L52 依 song_url.js 传 `IsFreePart:1`，解析 `status/priv_status/urls`；但 `docs/API_TEST_REPORT.md` §四/§五与 `API_FIELDS_TRUTH.md` §A3-1 实测：匿名 play_url（即使带 key+dfid）恒 `errcode=20028`「本次请求需要验证」，无 URL。返回镜像 `ParsedPlayUrlShim.isPlayable`（L225）`status==1 && urls.isNotEmpty` 在匿名态恒 false。此函数无 status/errcode 显式判定或 needsProbe/受限态，调用方拿到的是「空 shim」而非明确失败原因。
问题：匿名试听端点在未实测且上游实测恒拒绝的前提下封装为可用 API，失败被吞成空 shim，调用方难区分「无试听」与「解析失败」。
建议：在实测打通前给 ParsedPlayUrlShim 增加 errcode/受限态并显式标注 needsProbe；20028 时返回明确「需验证」态而非空成功体；参照 getPlayUrlV5 的 privKnown/errcode 落点。
76 合规：L4 端点层；不违反 76。

## <视角 C2> · lib/core/net/endpoints/play_endpoints.dart:319-322 · <P1> · 缺随机 dfid 的历史 20028 风险在端点层无法自证（参数已带，依赖底座）
证据：`getPlayUrlV5` 参数集（L58-82）含 hash/quality/album_audio_id/area_code/behavior 等，但**无 dfid**——按 KugouClient 默认参数自动注入（历史教训「play_url 缺随机 dfid→20028」属网络底座职责，A2 批范围）。端点层未对 session 缺失 dfid 做校验或留痕。
问题：本条为观察项而非本文件确证缺陷：dfid 由底座注入，端点层无法保证；若底座未注入随机 dfid，play_url 会稳定 20028。已在 API_TEST_REPORT 记为历史 bug，此处仅标注端点层无防御。
建议：若需在端点层加固，可在 getPlayUrlV5 入参前检查 `client.session.dfid` 非空且非 '0'/'-'，否则 Log.w 留痕；真正修复在 A2/KugouClient 层。
76 合规：L4 端点层；不违反 76（不越界去改底座）。

## <视角 C2> · lib/core/net/endpoints/search_endpoints.dart:98-120 · <P2> · searchSuggest 数组分组解析 与 契约对齐（已修，记录为确认正确）
证据：`searchSuggest` L104-120 先 `listOf(res['data'])`（数组分组）再 `listOf(group['RecordDatas'])` 取 `item['HintInfo']`，与契约 §R1-A-8「data 是数组分组 {RecordDatas[],LableName}，词条在 RecordDatas[].HintInfo」一致；`searchHot` L128-143 取 `data.list[].keywords[].keyword`、`group['name']`，与 §A1-3「分组 {name,keywords[]}，热词 keywords[].keyword」一致。注释记录了历史「data['records'] 对数组恒 null」已修。
问题：无缺陷——按用户重点要求核对 search/searchSuggest/searchHot 真实字段路径，确认已对齐，作为交叉确认项留存（不建议改动）。
建议：无。
76 合规：L4 端点层；不违反 76。

## <视角 C2> · lib/core/net/endpoints/lyric_models.dart:8-27 / misc_endpoints.dart:191-214 · <P2> · 歌词 id 为字符串被 safeInt 折叠（0 与 null 风险）
证据：契约 §A3-3/§A3-2 实测 `candidates[].id` 为字符串（如 "167469123"）。`misc_endpoints.lyricSearch` L197 `id: safeInt(c['id'])` 把字符串转 int；`LyricResult.id` 为 int（lyric_models.dart L18），下载端点 L183 要求 `id != 0`。当 id 字符串非纯数字或超 32 位时 safeInt 回退 0 → `lyricDownload` L172 `if (id == 0 ...) return 空`。当前探针样本为纯数字串可容错，但契约原文建议「safeStr 透传」。
问题：歌词 id 以 int 承载，字符串非纯数字/超大值会折叠为 0 → 下载直接失败，属可空/类型碰撞隐患。
建议：LyricResult.id 改 String（或增 idStr 字段）并对下载 id 用字符串透传；下载参数 id 保持原字符串值。
76 合规：L4 模型层；不违反 76。

## <视角 C2> · lib/core/net/endpoints/playlist_endpoints.dart:100-120 · <P2> · playlistDetail data 为数组——已修（确认项）
证据：`playlistDetail` L107-110 `final direct = listOf(res['data'])` 优先取 res['data'] 数组，再 `listOf(data['data']...)` 兜底，与契约 §A2-2「/v3/get_list_info 响应 data 为数组、首项含 name/pic/list_create_username/list_ver」一致；tags 逗号字符串解析（L114-130）与 field truth 一致。注释记录「旧写法 data['data'] 对数组恒 null→详情恒空」已修。
问题：无缺陷——核对 playlistDetail 数组解析正确，作为交叉确认项留存。
建议：无。
76 合规：L4 端点层；不违反 76。

## <视角 C2> · lib/core/net/endpoints/play_models.dart:96-109 / play_endpoints.dart:309-311 · <P2> · privKnown 三态判定——已实现（确认项，重点查 0/null 碰撞）
证据：`PlayResult.privKnown = res.containsKey('priv_status') && res['priv_status'] != null`（L309-311），`needsVerification` L104-109 `errcode==20028 || (status==2 && !privKnown && urls.isEmpty)`，显式区分「anon 无 priv_status（errcode 20028）」与「非VIP priv_status=0」；`playable` L88 `status==1 && privStatus==1 && urls.isNotEmpty`。与 API_TEST_REPORT 三态矩阵（anon status0/priv0/err20028、非VIP status2/priv0、VIP status1/priv1/urls2）吻合。交叉 A2_P0_VERIFICATION 明确 RSA 侧误报不涉此。
问题：无缺陷——端点三态/priv_status 0 与 null 碰撞已正确防护，作为确认项。
建议：无。
76 合规：L4 端点层；不违反 76。

## <视角 C2> · lib/core/net/endpoints/translation_endpoints.dart:114-133 · <P2> · 内嵌翻译轨「同一时间轴成对行」抽取可能失效
证据：`extractEmbeddedTranslatedLines` 依 `_firstTimeTag` 取 KRC `[start,dur]` 或 LRC `[mm:ss.xx]` 相同才算译文；但同一时间轴的译文行若用不同 dur（KRC `[start,dur2]`）则 prev.$1 != cur.$1 → 漏抽。curl 契约 §A3-5 krc 明文为「逐字 <s,e,0>」时间标签在逐字层、行头 `[start,dur]` 的 dur 每行可能不同。此为启发式风险，非确定性 bug（无译文留样佐证）。
问题：基于「首标签字符串完全相等」判译文，dur 不同即漏译；译文抽取结果可能恒空但未留痕。
建议：改为按 start 时间（行头第一个数字）比对而非整串；补一条真实带译文 KRC 留样作回归锚点后再定稿。
76 合规：L4 端点层（纯算法）；不违反 76。

## <视角 C2> · lib/core/net/endpoints/recommend_endpoints.dart:126-142 · <P2> · errMsg 非空即 error 态的判定偏激进（确认有兜底）
证据：`getDailyRecommend` L133-141：200103 返回 loginRequired（正确，对应 §四「未登录 errcode=200103、data 为字符串」）；但 L134 `errMsg.isNotEmpty` 且 L140 `items.isEmpty` 时返回 error 态，而 L137-138 注释「有数据时仍按列表返回」。契约要求「端点按错误码归空、不得当成功空列表」——此处 errcode!=0 已判 error，逻辑自洽；仅当服务端「成功但附带非关键 msg + 空推荐」会误报 error。
问题：边界行为——空推荐且服务器附带提示信息时归 error 而非 empty，UI 可能显示「加载失败」而非「暂无推荐」。非致命。
建议：以 errcode 为唯一业务失败门槛，errMsg 仅 Log 留痕、不参与 error 态判定（除非 errcode 非 0）。
76 合规：L4 端点层；不违反 76。

---
## 本视角结论
1. 【P0·最严重】mv_endpoints.dart MvBrief.fromMap 不读契约实测的 `video_id`、却以不存在的 `hash` 为成功门槛（L57/L287），导致按歌查 MV 恒返回 null；上层 MV 播放兜底链路整体不可达，直接命中用户「MV 用不了」痛点。
2. 【P1】getVideoQualities 以 32 位字符串 hash 冒充 video_id 数字语义（L305/324），即便上一层修好也会让 /v1/video 取档位恒空，需连同上层签名一起改。
3. 【P1】auth_endpoints.dart 6 个登录端点全部「标注待实测」却 `kAuthEndpointsProbed=true` 放行真实凭据外发、needsProbe 从不置位（L38 及全文），且依赖已确认有 Rcon bug 的 AesCbc，登录链注定失败且误导用户（YKG 新方式须另起干净实现）。
4. 【P1】translation_endpoints.dart `fetchTranslation` 构造空 content 的 probe 后恒返回空结果，是死代码，仍经 bridge_core 导出（L137-152）。
5. 【P1】user_endpoints.dart uploadPlayHistory/reportListen 成功判定用 `status==1 || error_code==0`，比同目录 getUserDetail/_ok 的严格合取宽松，业务失败可能误判成功（L209/L340）。
6. 【已确认对齐，非缺陷】search/searchSuggest（RecordDatas[].HintInfo）/searchHot（group.name+keywords[].keyword）、playlistDetail（data 为数组）、play_url 三态 privKnown/priv_status 0-vs-null、歌词 status=200 语义、每日推荐 200103 loginRequired 均按真实契约实现正确。
7. 【去重】AES Rcon 真 bug、RSA BigIntL.mul 误报见 A2_P0_VERIFICATION，本视角未重复报；仅在 auth 条目交叉引用 AesCbc 对登录链的影响。

## 未覆盖
- 各端点**真实网络实测**未做（本轮只读、禁跑 dart/联网）；对「待实测」端点的运行时行为均为静态推导，标注为观察项。
- `api_samples/anonym.json/nonvip.json/vip.json` 原始逐行内容未逐字展开（仅读 summary.json 汇总 + API_FIELDS_TRUTH/API_TEST_REPORT 事实），字段结论以后两份文档留样为准。
- `.test_creds/` 下探针留样 JSON（n2b_mv_dump.json 等）在只读检索中未列出文件（可能未随仓库提供），MV 结论以 API_FIELDS_TRUTH §A5-1/§A5-2 文字留样为准。
- 上层 MV 页「传错 hash」的具体代码（C3 结论）属 A7/L7 范围，本视角只确认端点契约本身（确有问题，见结论 1/2）；未展开 surface 层。
- 密码学实现细节（crypto_*.dart）属 A2 批，本视角仅交叉引用既有定论，未独立审查。

## 76 合规小结
- 本批 26 个文件全部位于 `lib/core/net/endpoints/`（L4 core·net），经桥导入 `bridge_kernel.Log`，未发现越级 import logic/surface、未发现影子桥、未发现反向依赖；端点一文件一模块，符合 76 §0 第 6 条。
- 各端点统一「字段容错 safe* / try-catch + Log / 失败返回空结果或带 error 态」，符合桥接II「失败必 Log 留痕不静默吞」的精神；仅 mv/auth/translation 的「空结果冒充成功/待实测冒充可用」属实现诚实性问题（已列 P0/P1），非 76 条款违规。
- `translation_endpoints.dart`/`quality_endpoints.dart`/`song_models.dart` 等纯数据模块「零 IO、零上层依赖」，层职责正确。
- 结论：本视角未发现违反 76 原则的架构问题；核心缺陷集中在字段契约对齐与功能可达性（MV）、端点诚实性（auth/translation）、成功判定口径（user）三处。
