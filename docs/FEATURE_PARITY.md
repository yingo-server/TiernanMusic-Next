# FEATURE_PARITY

> 本文由「功能面清单提取子代理」从 TiernanMusic 归档文档提取，只读文档、未读任何 lib/ 源码。旧项目代码按 LICENSE 禁止复用，本文仅记录功能面与质量原则作为新版重写的对齐基线。

## 端点与逻辑功能面（归档文档提取）

### 一、原生 API 端点清单（按域，出处：docs/api_verified.md 实测表；功能域盘点：docs/archive/reviews-v37/v37_feature_gap.md）

**签名与调用基础（api_verified.md）**
- 三种签名模式：android（默认，defaultParams+params 合并排序）、web（NVPh5oo…盐，用于 comment/count、login/qr/*）、register（"1014" 前后缀）。
- signParamsKey = md5(appid+salt+clientver+data)；播放 signKey = md5(hash小写+固定盐+appid+mid+userid)。
- 特殊签名要求：artist/audios 需 defaultParams+body 合并（clearDefaultParams 会 20006）。

| 域 | 端点（原生直连实测结果） | 出处 |
|---|---|---|
| 搜索 | search/song（complexsearch/v3）、search/hot（msearch）；联想/歌词/多类型搜索在 search_repository（13 方法，feature_gap.md） | api_verified.md、v37_feature_gap.md |
| 榜单 | rank/list（ocean/v6，56 项）、rank/audio（kg-tid 369，需 defaultParams+body 签名）、top/song；rank_info/top/vol、全球榜缺 | api_verified.md、v37_feature_gap.md |
| 歌单 | playlist/detail（pubsongs/v3，global_collection_id）、playlist/track/all（v2/nofilt）；读链路+增删歌/收藏/新建有，排序/标签/相似/导入/封面缺 | api_verified.md、v37_feature_gap.md |
| 歌手/专辑 | artist/detail（kmr/v3/author）、artist/audios、artist/albums（kmr/v1）、album/detail（kmr/v2）、album/songs（album_audio/lite）；歌手视频/荣誉/关注缺 | api_verified.md、v37_feature_gap.md |
| 歌词 | lyric/search——**成功语义是 status=200+errcode=200**（非 st=1），KRC 逐字渲染 | api_verified.md、v53_r1 系列 |
| 播放链路 | song/url（/v5/url，需 signKey）、privilege/lite（relate_goods + qualities 数组）；VIP 曲匿名恒 status=2 + fail_process=["pkg","buy"]；IsFreePart=1 给 60 秒试听（end_byte 截断，上游无分段续传） | api_verified.md、v37_paid_song_channel.md |
| 评论 | comment/music（参数必须走 **query** 不走 body）、comment/floor（楼中楼）、comment/count（web 签名 + x-router）；专辑/MV 评论缺 | api_verified.md、v37_feature_gap.md |
| MV/视频 | kmr/audio/mv（KG-TID:38）、video/detail（清晰度 hash）、video/url（trackermv/v2）；MV 播放+收藏闭环（v37_feature_gap §S-4）；弹幕/相关视频缺 | api_verified.md |
| 登录 | login/qr/key（web 签名 + login-user 域）、get/verify/info（20028 验证流水线，假 eventid 报 ec=36001 验证通路） | api_verified.md、v37_feature_gap S-2 |
| 每日推荐 | everyday/recommend（platform 必须是 query 参数）、yueku（recommend_v2）；听歌日历/好友在听/风格推荐缺 | api_verified.md、v37_feature_gap |
| 收藏/库 | MV 收藏 setCollected/cancel（二进制 body）→ 收藏列表，登录态 invalidate（v37_feature_gap §S-4）；歌单收藏/新建/增删歌走 _write 出口（v37_feature_gap P2-1） | reviews-v37/v37_feature_gap.md、reviews-v51 |
| 榜单/歌单广场债务 | top/playlist（special_recommend）直连恒 ec=200101 → 保留 kapi 回退（已知债务） | api_verified.md、v37_feature_gap |
| 行为上报 | playhistory_upload / user_listen_report——**需先三态实测**，不做匿名代发，需幂等去重键 | v37_feature_gap P2-2 |
| 电台/云盘等 | FM（fm_songs/fm_recommend/fm_class）、云盘 user_cloud、场景/主题歌单 scene_*：v37 时点全缺且均属「需先实测」域；一起听/听书明确不做 | v37_feature_gap |

### 二、播放器/业务逻辑功能面

**队列（出处：reviews-v53/v53_r1_a.md、tasks/PLAN_v53_player_refactor.md）**
- 队列状态：手写队列 `_songs/_index` + audio_service queue 副本双轨；播放列表 API 仅「整表替换 playQueue / playSong」，无「下一首播放/追加队尾/移除/跳到指定项」事件模型（v53_r1_a §1.5）。
- 切歌链路：世代闸门（_playToken）+ 互斥闸门（_loading）+ 挂起项（_pendingIndex/_pendingSongHash）+ 失败连击计数（_failureStreak）+ 20028 挂起 hash，7+ 状态变量分散（v53_r1_a §2 全表 30 项）。
- v53 定案重写方向：单一 `PlayerState { idle/loading/playing/paused/failure }` 状态机 + 事件驱动（PlayQueueRequested/Next/Previous/SeekTo/Completed/Failed），队列操作全经状态机事件，UI 只 watch 单一 playerStateProvider。

**音质档位（reviews-v37/v37_flac_deep_verify.md、v37_paid_song_channel.md、v53_r1_b.md）**
- 档位：128 / 320 / flac / high（24bit 母带）/ super（无 DSD 母带时**静默降级为 flac**，无提示）。
- 解析链：直连 /v5/url 单档循环（≤5 档+特殊档试听）→ 失败 kapi /song/url 主链（≤5 档，每档 30s）→ kapi 试听链（free_part ≤5 档），最坏 11+ 次串行、无总时限（v53_r1_b）。
- 试听判定：duration ≤ 65000ms 判试听（60s 官方试听 + 5s 余量，魔法数需具名常量出处）；`IsFreePart=1` 实测 59.98s；试听不得入缓存/入库（三条件闸门 `!preview && bytes>0`，v51_cross_b3_merged）。

**网络与降级（v53_r1_b、PLAN_v53）**
- 统一超时分级 NetworkPhase：resolving 3s / detecting 8s / streaming 30s；>500ms 阶段必须 UI 可见；慢请求 3s 告警；失败必有具体原因 + 重试按钮。
- 20028 验证：get/verify/info → v_type 分发 → 回填重试；历史上三套平行实现需收敛为 verification_service 单一实现（v37_feature_gap S-2）。
- 断点续传：CDN 实测支持标准 HTTP Range（206 + Accept-Ranges）；URL 有效期约 5 分钟，过期 403/302 需重取 URL 后以 Content-Range 校准偏移；200/206 双分支显式处理；续传键需覆盖 hash+quality（v37_feature_gap S-1）。

**后台保活与前台服务（reviews-v37/v37_perm_playback.md、v37_playback_blank_diag.md）**
- audio_service + MediaButtonReceiver，service foregroundServiceType="mediaPlayback"，channelId `com.tiernan.music.channel.audio`。
- `androidStopForegroundOnPause: false`（暂停不降前台，规避 Android 12+）——运行时缺口：Android 13+ POST_NOTIFICATIONS 需运行时请求，被拒则通知/锁屏控制不可见，部分 ROM 不认前台服务。
- 通知栏删除/停止事件必须能到达 App Handler（v53_r1_a A-10：划通知事件因 JAB 未 override 而永不到达，属必修缺陷）；stop() 生命周期必须双向对称（清队列/index/preview/mediaItem/playbackState）。

**音频焦点与耳机控制（v51_cross_B4_b、v53_r1_a）**
- AudioSession 配置（蓝牙/耳机/焦点策略）失败必须留痕（旧缺陷：静默失效，「插耳机不断播」「电话打断不恢复」不可定位）。
- 耳机拔插（BecomingNoisy）暂停、蓝牙按键控制须走注册的媒体会话回调；音频焦点释放须在 Handler 重建时防旧实例占用（双份状态推送缺陷，v51_cross_B4_b）。

**断点/资源快照（v53_r1_a A-04/A-17）**
- 本曲资源快照（lastPlayUrl/lastDeclaredBytes/lastIsPreview）供 completed 回调入库；completed 回调必须带世代校验，否则 A 曲完成会误把 B 曲 URL 入库。
- 暂停/停止/空队列时必须回滚 preview/quality/资源快照，防「幽灵播放态」（有声音没播放器 / 试听角标残留）。

**缓存策略（v51_cross_b3_a/b/c、v51_cross_B5_a、QUALITY_STANDARD）**
- 三级缓存：L1 内存（TTL 90s）/ L2 磁盘 JSON（json=168h、list=90s、歌词 168h）/ L3 永久文件（36500d 占位，cacheUrlFile「已存在直接返回」）。
- TTL 事实源唯一：cacheTtl(scope)，禁多套定义；缓存键四维（ns/userid/排序 query/schemaVer），user 维度必须进键，切号 onUserChanged 清 L1+异步清 L2。
- L1 必须有容量上限（MemoryCache._maxEntries=200）、TTL、淘汰；`__stale` 降级副本不进 L1；in-flight 合并按 fullKey；写后失效 invalidateNs 按 ns 域。
- 试听片段禁止入库（allowPreview 默认 false + URL 形态判定，防御落最内层）；预热键（prefetch ns）必须与实播键可命中。
- 文件缓存防并发损坏：同 (url,bytes) 只一个下载任务（_fileInFlight）、.part 独写、HEAD 405 降级为下载后长度校验。

**三态登录行为（api_verified.md、v37_flac_deep_verify.md、QUALITY_STANDARD 第 68 行语境、probe-samples）**
- 三态 = 匿名（anon）/ 非 VIP 登录（nonvip）/ VIP 登录（vip），probe 直打原生域名需三态 cookie 留样（probe-samples/ 留有 like_playlist、three_playlists、v4_paging 样本）。
- 行为差异实测：匿名可播免费曲全音质；VIP 曲匿名恒 status=2 + fail_process=["pkg","buy"] → 60s 试听墙；VIP 态 128/flac/high/super 全量下载与接口 fileSize/hash 完全一致。
- 「未登录」「已登录但无内容」「请求失败」「确实为空」是不同的业务事实，不得都映射成空集合（QUALITY_STANDARD 第 18 条语境，第 68 行）。
- dfid 属设备不属账号，登出保留；切号需联动缓存失效（v51_cross_b3_merged 终审）。

### 三、质量与回归要求（原则摘录，出处：docs/QUALITY_STANDARD.md 33 条 + v53 播放器专项 + 各审查报告）

## 质量原则（归档文档）

**三态验证（QUALITY_STANDARD、v37_feature_gap 纪律提醒）**
1. 排查接口问题必须用 probe 脚本直打原生域名（三态 cookie），或真机日志核对直连请求。
2. 任何新端点立项前必须 native_probe 三态留样；kapi 对照结果只能标记候选，不得作为实现依据。
3. 写端点（上报/收藏/歌单写）涉及风控，必须三态实测且不可匿名代发。

**错误码处理（QUALITY_STANDARD 第 6–11 条、v53_r1_b）**
1. 禁止吞异常：任何 catch 必须转译领域异常 / 记日志 / 返回明确语义降级值之一，空捕获体不可接受（试听兜底 `catch(_){}` 空吞为反面实锤）。
2. 异常契约单一稳定：跨层统一包装为领域异常（ApiException），保留 ssaCode/eventid 等验证信息，不得抹平为 code=-1。
3. 降级必须有明确触发条件、次优行为、恢复条件；200/206、直连/kapi 回退、stale 降级均属「已知条件下切换已知次优行为」。
4. 成功语义因端点而异（st=1 vs status=200+errcode=200），判定逻辑必须按端点实测结果显式分支，不得统一假设。
5. 失败必须可观测：>500ms 阶段 UI 可见、静默降级留痕、错误文案含「发生了什么 + 下一步」。

**并发闸门与幂等（QUALITY_STANDARD 第 3/12–17 条语境、v53_r1_a、v37_feature_gap P2-2、v51_cross_b3_merged）**
1. 世代闸门：播放链路任何异步回调（completed/catch/详情回填）必须校验世代（playToken/generation），过世结果全部丢弃并回滚已发副流。
2. 在途请求必须可作废：pause/stop/通知删除不仅要清挂起项，还要处理闸门重开与副作用回滚（preview 角标、资源快照、failureStreak）。
3. 幂等：写操作（上报、收藏、歌单写）重试/回放不得重复执行，需去重键；歌单排序为全量序列提交，防重。
4. 生命周期双向对称：play 建立的媒体会话/队列/试听/错误态，stop 必须全部拆除；dispose 幂等且流回调需检查 disposed。
5. 资源释放：Handler 重建必须释放旧实例的音频焦点、平台通道占用与流订阅，防双份状态推送与内存累积。
6. 网络并发控制：同身份请求 in-flight 合并；文件下载同键并发只跑一个任务；dio 全局请求耗时入 verbose 日志 + 慢请求告警。

**缓存与状态一致性（QUALITY_STANDARD 第 5/23/25 条、v51_cross_b3 系列）**
1. 状态单一来源：同一事实只能一处权威存储（试听标记三份、TTL 三套定义均为实锤反面案例）。
2. 缓存键必须覆盖全部影响结果的维度（身份/音质/语言/区域/时间窗/schemaVer），缺维度即串数据。
3. 一切无上限资源（内存条数、磁盘体积、并发数、重试次数）必须有具名常量上限。
4. 登录态切换必须触发缓存失效（onUserChanged 清 L1+异步清 L2），登出保留设备维度数据（dfid）。

**播放器专项（PLAN_v53 质量要求）**
1. 播放状态机单点：队列状态变量只允许存在于状态机文件内；audio_handler 只做引擎适配器，不得 import presentation 层；queue_sheet 不得直调 _api。
2. 每个按钮唯一语义、≥48dp 触控、enabled/disabled/loading 三态。
3. 每个网络阶段（resolving/detecting/streaming）必须有可见 UI 反馈，失败带具体原因与重试。
4. magic number 必须具名并注出处（65s 试听余量）；注释不得复述失效实现。
5. 前台服务保活：androidStopForegroundOnPause=false；Android 13+ 通知权限运行时请求；通知栏事件必须可达 App Handler。
6. 三态登录行为差异必须显式建模（试听墙/全音质/降级），不得用统一空态掩盖。

---
### 引用文档清单
- docs/api_verified.md（直连端点实测 + 签名要点 + 三态行为）
- docs/QUALITY_STANDARD.md（33 条质量准则）
- docs/archive/reviews-v37/v37_feature_gap.md（功能域盘点与缺口）、v37_paid_song_channel.md、v37_flac_deep_verify.md、v37_perm_playback.md、v37_playback_blank_diag.md
- docs/archive/reviews-v51/v51_cross_b3_a/b/c、v51_cross_b3_merged、v51_cross_B4_b、v51_cross_B5_a（缓存三级/90s、音频焦点）
- docs/archive/reviews-v53/v53_r1_a/b/c（队列状态机、解析链、布局三态）
- docs/archive/tasks/PLAN_v52.md（权限网关五级回退）、PLAN_v53_player_refactor.md（播放器重构规划）
- docs/archive/probe-samples/（like_playlist 5x10、reversed、three_playlists、v4_paging 三态样本）

## 原项目功能面（文档提取，零代码引用）

> 本章为补写，与前文端点/原则章节互补。全部内容仅来自归档描述性文档（README.md、docs/REFACTOR_PLAN_V5.md、docs/QUALITY_STANDARD.md、docs/archive/PLAN_v2_final.md、PLAN_v2_lts.md、PLAN_architecture.md、docs/archive/tasks/PLAN_v52.md、docs/archive/reviews-v37/v37_feature_gap.md、v37_cripple_report.md），未读任何 lib/ 源码。每条只写「是什么」+ 出处。

### 域 1：认证登录（7 条）
1. 手机号/密码双 Tab 登录（README 特性、PLAN_v2_final S2.1 L）。
2. 酷狗二维码登录：轮询扫码状态，切 Tab 停轮询（PLAN_v2_final S2.1 L）。
3. 多账号管理：账号选择弹层、切换账号（README、PLAN_v2_final S2.1 L）。
4. 20028 人机验证：flutter_inappwebview 桥接腾讯 TCaptcha，捕获 ssaCode 后自动重试，登录/评论/播放三链路（README、PLAN_v2_lts §2.2）。
5. 登录守卫：收藏/评论/下载等需登录操作的前置拦截（PLAN_v2_final S2.1 D/H）。
6. 登出彻底清理：SecureStorage/CookieJar/AccountManager 四处收敛；dfid 属设备登出保留（PLAN_v2_lts §2.2、v37_feature_gap）。
7. 凭证安全存储 flutter_secure_storage（五键+多账号，REFACTOR_PLAN_V5 §六）。

### 域 2：首页聚合（7 条）
1. 轮播图 Banner（含点击跳转目标设计，PLAN_v2_final S2.1 A）。
2. 每日推荐卡：点击播放整组，长按下载菜单（同上）。
3. 推荐歌单卡：点击进歌单详情（同上）。
4. 排行榜卡：点击进榜单页（同上）。
5. 新歌行：点击播放 + 尾列「更多」菜单（同上）。
6. 下拉刷新：清缓存 + refresh（同上）。
7. Banner Timer 行为：非当前 Tab 停翻页、App 退后台停（WidgetsBindingObserver，同上）。

### 域 3：搜索（6 条）
1. 六类分 Tab 搜索：歌曲/歌单/专辑/歌手/MV/歌词（v37_cripple_report C-11、PLAN_v2_final S1.1）。
2. 搜索联想 suggest（searchtip 分类型联想；原实现走 kapi，属已知债务，v37_cripple_report C-10）。
3. 热搜词展示与点击填入（PLAN_v2_final S2.1 B）。
4. 搜索历史：点击搜索、单删、清空（同上）。
5. 结果分页 + 失败重试按钮（同上）。
6. 空态 EmptyState 与无结果引导（同上）。

### 域 4：播放（12 条）
1. 播放/暂停、上一首/下一首（队列循环模式行为，PLAN_v2_final S2.1 C）。
2. 循环三态（off/all/one）+ 随机 shuffle，图标回显（同上、v37_cripple_report C-9）。
3. 进度条拖动 seek、缓冲色、时长显示；seek 任意点完整（同上）。
4. 播放队列底部弹层、点击切歌（同上）。
5. 迷你播放器：点击进全屏、长按队列、进度条（同上）。
6. 音质五档选择：128/320/flac/high/super（v37_cripple_report C-1）。
7. 60s 试听：IsFreePart=1 试听墙 + 「试听」角标（v37_paid_song_channel、PLAN_v2_final S2.1 C）。
8. 实际播放音质标签显示（actualQuality，PLAN_v2_final S2.1 C）。
9. 后台播放：audio_service 通知栏 + 耳机蓝牙控制，androidStopForegroundOnPause=false（README、v37_perm_playback）。
10. 耳机拔插（BecomingNoisy）自动暂停（v51_cross_B4_b）。
11. MV 入口：有 MV 才显示按钮，点击进 MV 页（PLAN_v2_final S2.1 C）。
12. 评论入口：播放页直达歌曲评论区（同上）。

### 域 5：歌词（7 条）
1. KRC 客户端解密（不上传 krc 到任何服务，README 特性）。
2. KRC 逐字时间轴渲染（words，README、v37_feature_gap）。
3. 逐行翻译：原文/双语/译文三态（README）。
4. 歌词点击行 seek（PLAN_v2_final S2.1 C）。
5. 自动滚动跟随 + 手动滚动 5s 暂停（同上）。
6. 翻译兜底 TranslateApi（v37_cripple_report C-8）。
7. 歌词持久缓存（Hive，键 id:lang@model，REFACTOR_PLAN_V5 §1.2）。

### 域 6：歌单（7 条）
1. 歌单详情页：封面/简介展开收起/歌曲列表（PLAN_v2_final S2.1 D）。
2. 播放全部（同上）。
3. 收藏歌单：登录守卫 + collectPlaylist，单向收藏（上游无取消接口，D7 决策）（同上）。
4. 歌单增删歌曲（AES+RSA 加密体写端点，PLAN_v2_final S1.1 #9）。
5. 用户歌单详情模式：`?user=listid` 走 fetchUserTracks（PLAN_v2_final S2.1 D）。
6. 歌单分页排序：倒序取页+反序拼接，整体从新到旧（PLAN_v2_lts §2.2）。
7. 歌单评论入口（PLAN_v2_final S2.1 D）。

### 域 7：收藏（3 条）
1. 收藏 MV / 取消收藏（setCollected/cancel 二进制 body，v37_feature_gap S-4）。
2. 收藏 MV 列表页（音乐库内，同上）。
3. 收藏歌曲心形按钮（默认收藏歌单，PLAN_v2_lts 阶段 3 P2）。

### 域 8：评论（8 条）
1. 音乐评论列表（comment/music，参数必须走 query，PLAN_v2_final S1.1 #2）。
2. 歌单评论（floor 双端点 song/playlist/album）（同上 #4）。
3. 楼中楼：replyCount>0 进 floor 页（PLAN_v2_final S2.1 H）。
4. 发送评论：登录守卫 + 20028→CaptchaPage（同上）。
5. 回复评论（comment/send/reply，clearDefaultParams+notSignature 签名，S1.1 #5）。
6. 删除自己的评论（PLAN_v2_final S2.1 H）。
7. 分类标签/热词 chips 渲染（PLAN_v2_lts 阶段 3 P1、PLAN_v2_final S2.1 H）。
8. 评论分页 + 世代防串（同上 H）。

### 域 9：MV/视频（6 条）
1. MV 搜索与播放（kmr/audio/mv KG-TID:38，README、api_verified）。
2. MV 详情与清晰度 hash（video/detail，api_verified）。
3. MV 直连 Range 流播放：改直连 + 11 域名 cleartext 放行，修「只能播开头」（PLAN_v2_lts §2.2）。
4. MV 收藏/取消 + 收藏列表闭环（v37_feature_gap S-4）。
5. MV 下载（四类型下载之一，PLAN_v2_final S2.1 I）。
6. MV 视频持久缓存（README「智能缓存」）。

### 域 10：歌手/专辑/榜单/推荐（5 条）
1. 歌手页：头像/粉丝数/歌曲-专辑-简介三 Tab，歌曲分页、播放全部（PLAN_v2_final S2.1 E）。
2. 专辑页：封面/发行日期/歌曲嵌套解析/播放全部（S2.1 F）。
3. 榜单页：rank/list+rank/audio，榜单歌曲列表+播放全部（S2.1 G）。
4. 每日推荐 everyday/recommend（匿名响应不进缓存，PLAN_v2_lts P1-1）。
5. 听歌日历/历史推荐回看（everyday_history，规划项 P1-2 未实现，v37_feature_gap）。

### 域 11：下载与缓存（7 条）
1. 四类型下载：音频/封面/歌词/MV（PLAN_v2_final S2.1 I）。
2. 下载音质取用户默认设置（播放与下载同一事实源，PLAN_v2_lts P1-4）。
3. 下载任务管理：暂停/继续/重试/删除（PLAN_v2_final S2.1 I）。
4. 断点续传：CDN 原生支持 HTTP Range，续传键覆盖 hash+quality（v37_feature_gap S-1）。
5. 存储权限网关：四重检测矩阵 + 五级回退链（L1 根目录→L5 内部私有），设置页显示生效级别与探测历史（PLAN_v52 A）。
6. 三级缓存（L0 内存 LRU/L1 磁盘 JSON/L2 永久文件）+ 清缓存保护 downloads_tmp + 设置页体积统计与一键清（REFACTOR_PLAN_V5 §4、PLAN_v2_lts P1-6）。
7. 离线播放：localPath 兼容 file:// 与 content:// 双协议，队列切回不丢（PLAN_v2_lts §2.2、P1-5）。

### 域 12：设置（8 条）
1. 账号区：登录/退出/切换（PLAN_v2_final S2.1 K）。
2. 外观：主题切换（同上）。
3. 语言选择：10 语言任意切换（同上、README）。
4. 播放：默认音质设置（hires→high+super 协议修复，PLAN_v2_lts P0-2）。
5. 下载管理入口（S2.1 K）。
6. 缓存：统计口径修正 + 一键清理（同上）。
7. 诊断：日志位置/权限状态/最近错误（同上）。
8. 关于：检查更新（同上）。

### 域 13：国际化（3 条）
1. 10 种语言：简中/繁中/英/日/韩/西/法/德/葡/俄，ARB 305 词条 × locale（README、PLAN_v2_lts §2.1）。
2. l10n 完整性静态校验：使用 key vs ARB 定义比对（PLAN_v2_final S0.1）。
3. Ubuntu Mono 全局字体 + CJK 回退链不变形（PLAN_v52 C）。

### 域 14：主题（3 条）
1. Material 3 Expressive，深色为默认（README）。
2. 封面动态取色（同上）。
3. 纯黑模式（同上）。

### 域 15：体验/工程原则（4 条）
1. 启动页动态 SVG 逐笔绘制（PLAN_v2_lts 阶段 3 P0）。
2. 加载必须可见：>500ms 阶段可感知，错误态含「发生了什么+重试」（QUALITY_STANDARD 第 34 条）。
3. 工程分层：五层+两桥（foundation/domain/policy/net+storage/cache/features/app），core 禁 import features 有 CI 断言（REFACTOR_PLAN_V5 §二/§九）。
4. 发布纪律：pubspec 版本与 tag 同名校验、Release 资产核对（3 ABI APK+mapping.txt）（REFACTOR_PLAN_V5 §九、PLAN_v2_final S4）。

### 已知问题/阉割项汇总（出处：reviews-v37/v37_feature_gap.md + v37_cripple_report.md）

**音质域**
1. C-1 蝰蛇音效三档（viper_tape/clear/atmos）VIP 态实测可得但枚举/UI 未暴露（P1）。
2. C-2 魔法音效六档（magic_piano 等）三态全通、匿名可用，参数已备但无入口（P1）。
3. C-3 multitrack 多轨 VIP 可得未暴露（P3）。
4. super 无 DSD 母带时静默降级 flac，无提示（v53_r1_b）。

**播放/队列域**
5. C-6 倍速播放无用户入口（纯客户端能力未接线，P2）。
6. C-7 无「队列播完自动接相似歌」（audio_related 未实测，P2）。
7. 队列只有整表替换，无「下一首播放/追加/移除/跳到指定项」（v53_r1_a）。
8. 解析链最坏 11+ 次串行请求无总时限（v53_r1_b）。

**搜索域**
9. C-10 suggest 走 kapi 中转、仅字符串联想，分类型联想丢失（P1 债务）。
10. C-11 综合搜索 complexsearch 未实现，无聚合「全部」页（P2）。
11. 歌曲搜索无筛选参数（sorttype/category 未透传，P3）。

**歌单域**
12. 歌单排序/标签/相似歌单缺（P2-1）。
13. 歌单重命名缺（C-16）。
14. 歌单导入/封面改/官方分享缺（feature_gap 表）。
15. 歌单广场只有 special_recommend 一路且直连恒 200101，保留 kapi 回退债务（feature_gap）。

**用户/收藏域**
16. C-15 用户详情仅回填 userid，等级/勋章/听歌排行全缺（P2）。
17. C-17 收藏列表仅 MV 一类，收藏专辑/歌手列表缺（P3）。
18. 云盘 user_cloud、已购、听歌排行全缺（feature_gap）。

**歌手/专辑/推荐域**
19. 歌手视频/荣誉/关注缺（P2-3）；相似歌手、歌手粉丝列表上游无端点（C-13 如实记录）。
20. 数字专辑商店 album_shop 缺（P3）。
21. 听歌日历/好友在听/风格推荐缺（feature_gap）。

**MV/内容域**
22. MV 弹幕、相关视频缺（feature_gap）。
23. 专辑/MV 评论缺（feature_gap）。
24. 专辑简介/发行字段 UI 未展示（C-14，P3）。

**整域缺失**
25. 个人 FM/电台 fm_* 全缺（P1-3 规划项，需先实测）。
26. 听书 longaudio 全缺（v3.8 专项评估）。
27. 一起听 listen_together 明确不做（架构 L，价值存疑）。
28. 场景/主题歌单 scene_* 全缺（P2-4）。
29. 播放/听歌行为上报缺（不上报则个性化退化，P2-2，需三态实测）。

**其他**
30. 死开关 wifiAutoHighQuality/cellularLowerQuality（「即将推出」徽标处置，D6）。
31. C-8 音译/罗马音歌词轨未单列（P3）。
32. C-4 下载确认时无音质改选 UI（P2）。
33. 滑块验证 slider_solver 死代码待接线或删除（S-3）；v_type=38 提交/回填端点未实测。
34. 试听分段拼接不做（上游无分段续传接口，D4 决策）；Android 13+ 通知权限运行时请求缺口（v37_perm_playback）。

---
### 补写说明
本章 15 域共 94 条功能点 + 34 条已知问题/阉割项；与前文「端点与逻辑功能面」（接口视角）互补，本章为用户可见功能面视角。全部条目可回溯至上述归档文档，未引用任何 lib/ 源码。
