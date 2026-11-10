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
