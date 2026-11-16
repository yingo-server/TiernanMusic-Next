## C2 · docs/deep_audit/bB4_c2.md · 开头 · 审查基线（2026-11-17）
证据：只读审查（file_read + rg/wc/ls），未改源码、未跑 dart/analyze/test、未联网。必读四文档已读完：DEEP_AUDIT_PHASE_B_PLAN（B4=MV 播放跨层、验阶段A四重断点）、API_FIELDS_TRUTH §A5（A5-1 data[0][] 嵌套数组/video_id 数字 596344；A5-2 /v1/video body 全参平铺档位；A5-3 data[hash].downurl）、A3_MV_P0_VERIFICATION（确认旧 hash 门槛恒 null）、PHASE_A_FIX_LOG（P0-3 六处修复）。
问题：本视角只审「实现正确性」跨层链路是否真通，C1/C3 归他人。
建议：无。
76 合规：符合第0条纪律。

---

## C2 · lib/core/net/endpoints/mv_endpoints.dart:272-285 · P0 · 阶段A修复未真通（L4解包断裂，四重断点②仍断）
证据：`getMvBySong` 先 `final data = dataOf(res)`（:272），`dataOf`（models_util.dart:57-66）对 `root['data']` 仅当 `Map` 才返回，否则回空 `{}`。随后 :275 `final dd = data['data']`、:281 `listOf(data['list'] ?? data['info'] ?? data['mv_list'] ?? data)` —— 全部基于这个空 Map。但契约/留样：API_FIELDS_TRUTH §A5-1（L216）明确「响应 data 为**嵌套数组** data[0][]」；探针留样 docs/api_samples_v2/vip.json:583-586 `/kmr/v1/audio/mv` captured `_fields.data.type="list", len=1`；field_truth_test.dart:748 锚点注释「data[0][0]」。`dataOf` 对 List 型 data 回空 Map（field_truth_test.dart:915/946 已自证「dataOf 对数组 data 回空 Map(旧 bug 根因)」）——因此 `dd=null`、`list=listOf({})=[]`，:285 `return null` 恒触发。对比 search_endpoints.dart:74-82 早已修同类 bug（直接 `listOf(res['data'])`）。
问题：阶段A把成功门槛从 hash 改成 `mv.videoId>0`（:295）方向对，但函数入口解包仍是「dataOf → data['data']」的错误层级，顶层 data 是数组时 `MvBrief.fromMap` 根本拿不到 item，`getMvBySong` 在契约正确返回下仍恒返回 null——四重断点②（videoId 读取）在真实响应形态下不可达，阶段A MV 修复未真通。
建议：改为 `final list = listOf(res['data']).isNotEmpty ? listOf(res['data']) : ...`（仿 search_endpoints 数组优先），对嵌套 `data[0][]` 取 `listOf((res['data'] as List).first)`；禁止先 `dataOf` 再 `data['data']`。补 field_truth 端点级解包锚点（现有锚点只测 fromMap 单 item，逃过此 bug）。
76 合规：L4 内部解包职责正确、无越级；属实现正确性缺陷（P0）。

---

## C2 · lib/core/net/endpoints/mv_endpoints.dart:341-352 · P0 · getVideoQualities 同样解包断裂（第二段档位恒空）
证据：`getVideoQualities` :341 `final data = dataOf(res)`，:344 `final d0 = data['data'] is List && ... ? (data['data'] as List).first : null`。A5-2（API_FIELDS_TRUTH L233/L241）响应为 `data[0]` 平铺档位——即顶层 `data` 是数组、`data[0]` 是含 ld_hash 等的 Map。`dataOf(res)` 对数组 data 回空 `{}`，故 `data['data']==null` → `d0==null`；:349 兜底 `MvQuality.fromFlat(data)` 传的是空 Map → items 空 → 返回空列表。入参 videoId 数字语义（:315-330）本体正确，但响应解包层级仍错。
问题：即便第一段 getMvBySong 修好，`getVideoQualities` 也拿不到任何档位，MvLogic.qualities→空、MvLogic.playUrl→空、MV 页 `_fail(empty)`；阶段A「入参改 int videoId」修了请求侧却没修响应侧，第二段仍断。
建议：改为 `final d0 = (res['data'] is List && (res['data'] as List).isNotEmpty) ? 该 List.first map化 : dataOf(res)`，再 `MvQuality.fromFlat(d0)`；保留 Map 型 data 兜底。补 A5-2 data[0] 端点级锚点。
76 合规：L4 职责内实现缺陷，无越级（P0）。

---

## C2 · docs/api_samples/summary.json:573-588 · P0 · 探针旁证：getMvBySong 返回 found=false
证据：api_probe.dart:397-400 对 vipClient 逐个 `getMvBySong(vipClient, s.albumAudioId)`，capture 记录 `{found: r != null}`；留样 summary.json:585-587 `mv_by_song/vip` → `"ok": true, "captured": {"found": false}`。`ok=true` 仅代表 HTTP 成功，`found=false` 即 getMvBySong 返回 null——与 :272-285 解包恒空链一致，构成「留样 data.type=list + dataOf 对数组回空 + 探针 found=false」三重印证。
问题：该探针留样早于/不区分阶段A修复，无法证明修复后端点真返回 MvBrief；而阶段A的 field_truth 只补了 fromMap 单 item 断言（:763），没补端点级 getMvBySong 返回值断言，故解包 bug 逃过全部门禁。
建议：在 field_truth_test 增加「构造 `{'data':[[mvItem]],'status':1}` 全响应 → getMvBySong → videoId==596344」的端点级锚点，堵住解包盲区。
76 合规：测试盲区属第2条容错可验证性，无越级（P0 佐证）。

---

## C2 · 四重断点逐段自洽性 · P0/P1 · 阶段A修复「请求侧全对、响应侧断裂」
证据：逐段核对——① 模块注册守卫：module_registry.dart:14-21 `install` 直接 `_modules[id]=module`（重复 id 覆盖），mv_page.dart:11-19 `registerMvModule` 直接 install 无 `byId!=null` 守卫，player_page.dart:229 菜单点击时调用；bootstrap.dart:243-248 先装 `_PlaceholderModule('mv')`（enabled=false），真模块按 id 覆盖——①修对。② MvBrief.videoId：mv_endpoints.dart:50 `videoId` 字段 + :60 `videoId: safeInt(m['video_id'])` + :295 门槛 `mv.videoId>0`——②源码改对，但被 :272-285 解包 bug 阻断（见前 P0）。③ getVideoQualities int 入参：mv_endpoints.dart:311-330 签名 `int videoId`、body `data:[{'video_id': videoId}]` 数字、L5 mv_logic.dart:67 / playback_service.dart:299 均传 int——③请求侧修对，但响应侧 :341-352 解包 bug 阻断。④ 两段式 albumAudioId→videoId：mv_logic.dart:39-52 `videoIdOfSong` + MV 页 :103 调用 + player_page.dart:232-235 传 `current.albumAudioId`——④修对。
问题：四重断点在「请求/调用侧」全部自洽修对，但 L4 两个响应解包函数仍按「data 是 Map」旧假设写，与 §A5「data 是数组」实测冲突，②和③的实际数据通路仍断。阶段A修复属「单点改对、链路未通」，正是阶段B要抓的典型。
建议：主会话复核前两条 P0 后，优先修 L4 解包，再重新端到端验证四重断点。
76 合规：跨层接缝（L4响应形态 vs L5/L7假设）不一致，属第4条接缝正确性（P0）。

---

## C2 · lib/core/net/endpoints/mv_endpoints.dart:365-410 · P1 · hash→downurl 段契约正确（video_id 语义干净）
证据：`getVideoUrl(client, qualityHash)` 入参是档位 hash（来自 MvQuality.hash = ld_hash 等，fromFlat :156-183 抽取），小写化后 :382-392 参数表 `hash/backupdomain=1/cmd=123/ext=mp4/ismp3=0/pid=1/type=1`，endpoint_registry.dart:307-311 `videoUrl encryptKey=true` → kugou_client.dart:214-219 自动注入 `key=playKey(hash,mid,userid)`；响应 :397-410 `dataOf(res)` 取 `data[hash]` bucket → downurl(串)+backupdownurl(数组)+去重。A5-3（API_FIELDS_TRUTH L248-256）契约一致；field_truth urlResp（:804-820）data 是 Map（与 A5-1/A5-2 数组不同），`dataOf` 此处正确。
问题：本段（第三段 hash→downurl）实现与实测契约一致，无 video_id/hash 语义错配；是整条链里唯一解包层级正确的端点。但注意它依赖前两段先产出的 q.hash，前两段若断则本段永不被调用。
建议：保持；修前两段后回归验证本段。
76 合规：符合第6条（官方域名 trackermv + 参数表实测）、第2条（容错），无越级（P1 仅为链路依赖提示）。

---

## C2 · lib/surface/pages/mv_page.dart:139-155 · P1 · _load 竞态：旧异步链未在挂载前 dispose 新控制器
证据：`_load()` 中 `VideoPlayerController.network(url)` 后 `await c.initialize()/setLooping()/play()`（:140-144），catch 中 `await c.dispose(); rethrow`（:145-149）；:150-152 `if (!mounted) { await c.dispose(); return; }` 有 mounted 检查，:154 `_release()` 再释放旧控制器。但 :83-90 `_release` 只 dispose `_ctrl` 指向的旧控制器；`_load` 中正在 initialize 的 `c` 在 `_onClose/didUpdateWidget` 触发 `_release()` 时还未赋给 `_ctrl`，不会被释放（:150 的 mounted 检查兜住了未挂载，但 didUpdateWidget 换 aid 后仍 mounted 的情形下，旧链在 :154 `_release()` 释放的是更早的 ctrl，新链 c 最终赋值——时序上若两条 _load 并发，先完成者 dispose 的 ctrl 可能已被后完成者替换）。
问题：didUpdateWidget（:58-66）换 albumAudioId 会 `_release()+_load()`，但未取消上一条正在 await 的 _load；两条异步链并发时存在控制器覆盖/重复 initialize 的竞态，极端下泄漏一个 decoder；mounted 检查只覆盖「页面已卸载」，不覆盖「同页切换 aid」。
建议：给 _load 加单调 generation token（如 `_loadSeq++`，每 await 后校验是否仍为最新），非最新链命中即 dispose 自制 c 并 return；didUpdateWidget 递增 token 取消旧链。
76 合规：L7 生命周期职责内，无越级；属异步竞态（P1）。

---

## C2 · lib/surface/pages/mv_page.dart:91-165 · P2 · _load 早退路径清点：mounted 检查齐全、空安全到位
证据：逐段核对——:92 aid<=0 → `_fail(empty)` 早退；:99 logic==null → `_fail(error)`；:103 `videoIdOfSong` 后 :104 mounted、:105-108 videoId<=0→empty；:109 qualities 后 :110 mounted、:111-114 空→empty；:137 playUrl 后 :138 mounted、:139-142 !playable→empty；:144-147 raw 空→empty；:152-158 http→https 升级 + 协议校验；:160-176 initialize/play + catch dispose + mounted 二次检查。所有 await 后均 `if(!mounted) return`，_fail 内也 `if(!mounted) return`（:178-184）。`_release`（:85-91）removeListener+dispose 并置空 `_ctrl/_playing`，dispose（:80-83）调用 _release，listener 用 late final（:47）绑定，无重复 addListener。
问题：无中途漏检查的早退，dispose 路径完备，空安全（nullable `_ctrl`/`bool? _playing`）到位。唯一残余是上条 P1 的并发竞态；http→https 升级（:151-153）是合理规避 Android 明文限制（代码注释已说明），但「升级后服务器不支持 https」时会 initialize 失败走 catch→error 态，有兜底。
建议：保持；仅需处理上条竞态。
76 合规：符合第2条（容错）、L7 职责边界；无越级（P2 记录为已核查无问题）。

---

## C2 · lib/surface/pages/mv_page.dart:115-136 + lib/logic/catalog/mv_logic.dart:89-118 · P1 · 选档策略双层叠加：L7「最低档优先」被 L5 playUrl「最高档优先」部分抵消
证据：MV 页 :115-136 先按 ld→sd→size 最小选 `low`，`requested = low.id`（通常 'ld'），调 `logic.playUrl(videoId, requestedId:'ld')`。但 MvLogic.playUrl（:99-107）`sorted = quals..sort((a,b)=>b.size.compareTo(a.size))`（**size 降序=最高档在前**），`idx = sorted.indexWhere(id=='ld')`，`ordered = sorted.sublist(idx)`（从 ld 到更高档的尾部切片）——由于 ld 通常 size 最小排在末尾，`sublist(idx)` 只剩 ld 一个（或含 _265 变体），能取到 ld；但若 L7 选中 sd（无 ld 时），`sorted` 中 sd 仍在较低位，`sublist` 含 sd+所有更高档，playUrl 会**先试更高档**（fhd/hd），违背 L7「最低档优先避 VIP」意图。playback_service 的兜底（:305-310 order=['ld','sd',...] 升序排序）又用第三套顺序。
问题：三处各自实现选档（L7 ld→sd→size、L5 playUrl size 降序 sublist、L5 fallback order 升序），优先级语义不一致：L7 想省流避 VIP，L5 playUrl 却按 size 降序优先试高档；在 VIP 高画质档被权限拦截时会多绕一圈请求，且 requestedId 非 ld 时可能先命中高码率档，与「避开 VIP 高画质」目标冲突（属 C1 已记职责错位的 C2 语义后果）。
建议：统一由 L5 playUrl 按 requestedId 精确命中该档（不 sublist 向高档扩展），或让 L7 只传「最低档意图」由 L5 单一实现降档顺序；三处选档收敛为一处。
76 合规：L7 承载业务选档属第1条轻度越位，语义叠加属第2条接缝（P1）。

---

## C2 · lib/logic/player/playback_service.dart:283-334 + lib/session/playback_session.dart:207-223 · P1 · MV 音频兜底 videoId 改对了，但与 MV 页链路重复且行为不一致
证据：`resolveMvAudioFallback` 阶段A已改——:294 门槛 `mvBrief.videoId<=0`、:299 `getVideoQualities(_client, mvBrief.videoId)` 传数字（对）；L6 playback_session.dart:215-222 仅当 `err∈{noPrivilege,needsVerification,notFound}` 且 `_mvTriedOnce` 未含该 hash 才调兜底，成功后 `_sourceKind='mv-audio'` 直接喂 just_audio 引擎。与 MV 页链（L5 MvLogic.videoIdOfSong→qualities→playUrl）相比：① 两条链各自独立重复 getMvBySong→getVideoQualities→选档→getVideoUrl（C1 已记重复）；② 兜底把 MP4 直链当「MV 音频」喂 just_audio（:317-324，注释自承「mp4 音轨属推断」），MV 页则喂 video_player 看画面；③ 兜底选档 order 升序（ld 优先），MV 页 playUrl size 降序 sublist——同曲两处选档结果可能不同；④ 兜底共用 L4 getMvBySong/getVideoQualities，**同样受前述两个解包 P0 影响**，改对 videoId 仍取不到数据。
问题：videoId 语义改动本身自洽，但因 L4 解包 bug 兜底实际不可达（返回 notFound）；且两链重复实现、选档/消费方式不一致，长期易漂移。20028/needsVerification 时兜底会先 `onVerificationRequired(20028)`（:209-213）再尝试 MV 音频兜底（:215-222）——即验证态与兜底并发触发，语义上「需验证」却跳过验证直接放 MV 音频，可能绕过验证要求。
建议：把 resolveMvAudioFallback 的两段式收敛到 MvLogic 一处（如新增 resolveVideoSource），MV 页与兜底共用；needsVerification(20028) 应优先走验证门面、验证未通过前不触发 MV 音频兜底（除非产品明确允许匿名试听）；两链统一选档。
76 合规：L6 编排兜底属职责内，但两处 L5 重复 + 20028 态绕验证属第2条接缝语义（P1）。

---

## C2 · lib/core/net/endpoints/mv_anonymous.dart:54-190 · P1 · 匿名链仍是死代码，无法支撑未登录看 MV
证据：全仓 `rg 'registerDevice|anonymousPlayUrl|ParsedPlayUrlShim'` 除本文件自身与 endpoint_registry.dart:322/332/338/344 的注释/声明外，无任何可执行调用点；L5 mv_logic.dart、playback_service.dart、L7 mv_page.dart 均未引用。文件头注释多处标「⚠️ 待实测」。`anonymousPlayUrl`（:139-190）是**匿名歌曲试听**（GET /v5/url），`registerDevice`（:54-125）取 dfid——二者都不产 MV 视频档位/画面 URL，与「未登录看 MV 视频」非同一能力。
问题：匿名链 227 行整模块零调用，仍是死代码（阶段A未接线，FIX_LOG §4 未列入修复）。MV 页与兜底都走需 token/mid 的 getVideoQualities（body 含 `token: client.session.token` mv_endpoints.dart:326），未登录时 token 空虽构造合法 body，但真正档位/播放是否匿名可达未经实测；mv_anonymous 无法作为「未登录看 MV」的降级分支因为它只给音频试听 URL。契约 batch3_c3.md:15 记「无签名 key、无 token 要求→匿名可用（中，未实测）」，仍未证实。
建议：若产品要求未登录看 MV，需明确匿名 mvDetail/videoDetail/videoUrl 三端点实测可达性，并把匿名支持做进 MvLogic 链路（而非靠这个只产音频的死模块）；若不支持，则删除或标注 mv_anonymous 避免误导。
76 合规：L4 死代码不构成越级，但违背「功能可达」；待实测能力不得臆造（P1）。

---

## C2 · 全链路空安全/异常/竞态总评 · P2 · 容错普遍到位但「吞错为空态」掩盖根因
证据：L4 三端点 + MvBrief/MvQuality.fromMap 均全字段 safe* 且每函数 try/catch+Log（mv_endpoints.dart 通篇）；L5 videoIdOfSong/qualities/playUrl 各 try/catch（mv_logic.dart:42-52/70-91/96-133）；L7 _load try/catch（:91-176）。无裸空指针、无未捕获异常。但 L5 对任何异常一律 `return 0`/`return []`/空 MvPlayResult（mv_logic.dart:50/89/132），playback_service.dart:332 catch→network。
问题：分层吞错彻底——网络超时/风控 20028/解析失败都被压成「0/空/empty」，L7 一律显示「这首歌暂无可播 MV」（mv_page.dart:106/113/140），用户与日志都难以区分「确实无 MV」与「链路故障」。与 C3 视角（bB4_c3.md:24）共识：弱网/风控下错误被误报为无 MV。属可实现正确性中的错误态传递缺陷（非崩溃）。
建议：L5 返回带语义的结果（如 MvAvailability {notFound|network|needVip|blocked}），L7 按态给 i18n 文案与重试策略；至少日志保留 errcode（20028）不吞。
76 合规：符合第2条（每方法 try/catch+Log）；错误态跨层丢失属第4条接缝（P2）。

---

## C2 · mv_logic.dart:22 · P2 · _pVideoDetail='/v1/video/detail' 是已废弃 404 路径的残留（仅作缓存键，非请求）
证据：mv_logic.dart:22 `const String _pVideoDetail = '/v1/video/detail';`，:72-77 仅用于 `buildKey(path:_pVideoDetail,...)` 生成缓存键。真实请求路径在 L4 EndpointRegistry.videoDetail=`/v1/video`（endpoint_registry.dart:293-299），API_FIELDS_TRUTH §A5-2 明确「/v1/video/detail 实测 404」。
问题：常量名/值与已废弃 404 路径同名，易误导维护者以为仍在请求旧路径；实际只作缓存命名空间，功能无害但可读性/可维护性差。
建议：改名为 `const _cachePath = 'video_detail'`（与端点路径解耦），注释说明仅缓存键用途。
76 合规：L5 缓存键职责内，无越级（P2 可维护性）。

---

## 本视角结论

四重断点「请求/调用侧」四段（① 注册守卫覆盖 ② MvBrief.videoId 字段+门槛 ③ getVideoQualities int 入参 ④ 两段式 albumAudioId→videoId）源码改动全部到位、彼此自洽；但**整条链路并未真正打通**：L4 `getMvBySong`（mv_endpoints.dart:272-285）与 `getVideoQualities`（:341-352）的**响应解包仍按「顶层 data 是 Map」旧假设**写，而 §A5 实测 + 探针留样（vip.json data.type=list）+ field_truth 自证「dataOf 对数组回空 Map」三重印证顶层 data 实为数组。结果：②产不出 MvBrief、③产不出档位，阶段A MV 修复属「单点改对、响应侧仍断」，与 api_probe 留样 found=false 一致。**最严重 2 条 P0 即此 L4 双解包断裂，建议主会话优先修并补端点级测试锚点。**

其余发现：MV 页 _load 生命周期基本健全（mounted 检查齐、dispose 完备），但换 aid 时旧异步链未取消存并发竞态（P1）；选档策略 L7/L5 playUrl/L5 fallback 三套语义不一致，L5 size 降序 sublist 部分抵消 L7「最低档避 VIP」意图（P1）；MV 音频兜底 videoId 改对但与 MV 页链重复、且 20028 needsVerification 时绕过验证门面直接放兜底（P1）；mv_anonymous 227 行匿名链仍死代码、只产音频试听 URL 无法支撑未登录看 MV（P1）；分层吞错把网络/风控压成「暂无 MV」空态（P2）；_pVideoDetail 残留 404 路径常数仅作缓存键（P2）。

## 未覆盖

- 未跑 dart/flutter/analyze/test/门禁（按纪律禁止），所有结论为静态审读 + 仓库留样交叉，需 CI/真机端到端终验。
- 未验证 KugouClient.request 在真实网络下对 /kmr/v1/audio/mv、/v1/video 的原始 JSON 顶层结构（依赖仓库留样推断；若服务端实际某态返回 Map 型 data，则两个 P0 的触发条件收窄，留样已标该端点 data=list 故当前判断成立）。
- 未审 EndpointRegistry 全量声明、signing.dart 签名算法正确性、crypto_rsa 加解密（非本视角 B4 范围）。
- mv_endpoints.dart:411-431 registerDevice 尾部、mv_anonymous 与 endpoint_registry 的逐字段契约一致性未逐行深挖（匿名链已判死代码）。
- 未验证 video_player 插件在 Android 明文/https 升级后的实际解码兼容（属运行时，静态仅确认有 catch+error 态兜底）。

## 76 合规小结

- 第1条（分层职责）：L7 承载选档业务决策轻度越位（P1/P2）；L4/L5/L6 职责边界基本正确。
- 第2条（全字段容错+每函数 try/catch+Log）：全线达标（safe*/try-catch/Log 到位）；但错误态跨层被吞成空态，属可验证性/语义缺陷。
- 第3/4条（六桥唯一通道 + 跨层接缝正确）：无直连、无影子桥、无反向依赖；但 L4 响应解包假设与 L5/L7 消费假设不一致、三处选档语义不一、20028 绕验证，属接缝正确性缺陷（2×P0 + 2×P1）。
- 第5条（1500 行门禁）：B4 九文件最大 player_page.dart 516 行，全部达标。
- 第6条（官方域名 + 多参不缺参）：MV 三端点均连酷狗官方域名、参数表实测对齐，无越级。
- 第9条（成熟库）：video_player 用量合理。
- 总体：无反向依赖/越级调用等架构性违规；核心风险集中在「L4 解包实现与实测契约不符」这一实现正确性 P0，导致阶段A四重断点修复未真通。
