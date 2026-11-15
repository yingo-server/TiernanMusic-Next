# 后续执行计划书（只规划，不实现）· 2026-11-15

> 依据：docs/research_legacy_login_url.md、research_field_capture_3state.md、research_ui_nav_features.md、SEVEN_SIX_RULE.md 及 lib/surface、lib/session 现状代码（只读核实）。
> 上游参考：/var/minis/workspace/KuGouMusicApi Node 源码（只读参考，不用其包装网关；版本参数为推测，凡未实测一律标「待实测」）。

## 1. 现状证据表（诉求 → 文件:行 → 缺陷）

| # | 诉求 | 证据 | 缺陷 |
|---|---|---|---|
| E1 | 首页下半臃肿 | home_page.dart:120 `itemCount:4`；:285-330 `_hotSection` Wrap 折行 4-8 行；:193-235 `_playlistSection` 3列 GridView shrinkWrap 全展开 ≈800dp+ | 热搜在首页；推荐歌单非横滑；首页总高 >1500dp 约 2 屏 |
| E2 | 热搜应移搜索页 | search_page.dart:312-476 `_idleBody` 仅热门分类+历史；无 hotSearch 调用 | 热搜与搜索历史不在一页；首页热搜点击只 `requestTab('search')` 丢关键词（home_page.dart:322） |
| E3 | 推荐歌单应单行横滑 | home_page.dart:220-233 GridView | 纵向网格占屏 |
| E4 | 排行榜压缩 | home_page.dart:237-283 `_RankCard` width168 高150 渐变卡 | 卡过大 |
| E5 | 亮暗主题不生效 | tokens.dart:105 `theme()` 硬编码 Brightness.dark；app_root.dart:35-41 只传 `theme:` 无 darkTheme/themeMode；settings_page.dart:47 `_themeMode` 页面本地 state，:178-179 只 setState 不外发；各页 Scaffold 硬编码 `backgroundColor: Sp.bg` | 选「亮」无任何全局通知；常量深色色板遍布 |
| E6 | 底部 bar 顺序 | module_registry.dart:37-40 `active()` 按 id 字典序 sort → 实际 home,library,playlist,search,settings | 与期望「首页/搜索/歌单/音乐库/设置」不符；shell.dart install 顺序无效（被 sort 覆盖） |
| E7 | 登录不止扫码 | settings_page.dart:132 `_toast('扫码登录入口待接入')` 纯占位（连已实现的 createQrLogin/pollQrLogin 都未接）；auth_endpoints.dart:105-133 smsLogin 半接线未实测；密码登录 /v9/login_by_pwd 未接线；loginToken（/v5/login_by_token）声明无调用方；微信 /v6/login_by_openplat 未接线；设备注册 r_register_dev 未核实接线 | 登录链路 UI 全缺 + 端点缺半 |
| E8 | 匿名播放（MV 音频流） | legacy 报告 §2：play_url v5 匿名恒 20028；C5 MV downurl（trackermv /v2/interface/index，userid 缺省可传 0，key 匿名可算）是唯一真正匿名可播链 | 用户裁定：匿名播放走 MV 链音频流，只取音频，优先最低清晰度，音质调节不重要 |
| E9 | API 字段捕获不全 | field_capture 报告 §1：play 丢 q/fileSize/volume/classmap/hash_offset/fail_process；search 丢 mvdata[]/HQ/SQ/Res；MV getVideoQualities 契约错位（mv_endpoints.dart:236-252 body 只传 hash，实际应 data:[{video_id}]+show_resolution:1）→ MV 清晰度链全断 | 大量键丢弃；playlist_write_endpoints.dart:19 `_ok()` 把 status=0 当成功 |
| E10 | 三态权益最大 URL | playback_service.dart:97 失败不降档、:121 恒 urls.first；只请求单一 128；v6 /v6/priv_url 未接；vip_token 未回写 | 无按登录态选档机制；35104 误映射 notFound |
| E11 | MV 功能无 UI | mv_logic 已装配（bootstrap.dart:69）但 rg surface 零命中；player_page `_openMenu`（:214-243）菜单只有歌词/评论/FM | L5 能力全、L7 零触达 |
| E12 | 布局差 | search_page.dart:31 kSearchSegments 五分段仅歌曲可用恒空态；library_page.dart:170/176 DAO 未过桥恒空 | 整体可用但空态多 |

## 2. 原则 / 约束

1. **76 原则 §0 全文贴每个子代理任务书开头**（七层六桥、依赖方向、单文件≤500行、桥必 Log、endpoints 一端点一模块、零源仓库复用）。
2. **L7 只画控件**：主题 notifier、NavState、播放/登录意图全部经 bridge_session 暴露的 L6 门面；surface 不持业务状态。
3. **L6 编排**：themeModeProvider、导航权重、登录会话编排放 lib/session；L4 endpoints 一端点一 dart 文件，只连官方域名。
4. **L4 端点**：版本变体（如 /v6/priv_url 未探针、fm /v2/personal_recommend、userCloud AES 契约）一律标「版本可猜测、待实测」，不得冒充可用；探针通过前 UI 显式「未实测」态。
5. **三态凭据脱敏**：token/vip_token/userid 落 session 时脱敏记录（前后 4 位掩码），日志禁止整 token；匿名态凭据固定 `'0'` + 设备 dfid。
6. **写操作不外发**：批 8 前所有 add_song/delete/collect 只做契约校验与本地镜像，真实外发必须经用户确认；写成功语义禁止 status=0 当成功。
7. 子代理只用 file_read/file_write/file_edit/ls；不跑分析器、不提交、不做真实网络调用（探针批 4 的「实测」只规划探针脚本，由用户/后续批执行）。

## 3. 10 批 × 3 目标执行分解

| 批 | A | B | C | 文件边界 | 验收 | 需实测 |
|---|---|---|---|---|---|---|
| 1 | 首页瘦身：删 _hotSection（home_page.dart:285-330, itemCount 4→3）、推荐歌单改横向单行 ListView(height≈200)、排行榜卡压缩(width≈120/height≈110) | 主题真正生效：tokens.dart 加 light 色板工厂；L6 新增 themeModeProvider(ValueNotifier+持久化)；app_root.dart 传 theme+darkTheme+themeMode；各页去硬编码 backgroundColor | 底 bar 顺序：module_registry.dart active() 加显式 navOrder ['home','search','playlist','library','settings']（未知 id 排尾）；contracts.dart 可加 navWeight | home_page.dart / tokens.dart / session/theme* / app_root.dart / shell.dart / module_registry.dart / contracts.dart | 首页 ≤1 屏；选「亮」全 app 变亮；底栏顺序正确 | 否 |
| 2 | 搜索页热搜区：search_page.dart _historySection 后新增热搜（调 appGraph.search.hotSearch()，横向排开每列 10 个 GridView，点击 _ctrl.text=kw;_doSearch(kw)）；搜索历史持久化（经 L4 存储） | 登录 UI：settings_page.dart:132 接真扫码弹层（createQrLogin→pollQrLogin 状态机 0/1/2/4）+ 手机号 tab（VerificationLogic.sendSmsCode/smsLogin）+ 多账号切换（AccountLogic） | 登录端点补齐：/v9/login_by_pwd 密码登录 Endpoint+AuthLogic 载荷（t1/t2/t3 常量）；loginToken 续期接线（启动/401 触发）；logout/设备登出 dev_logout | search_page.dart / session/auth 编排 / core/net/endpoints/auth_endpoints.dart / endpoint_registry.dart / settings_page.dart | 热搜在搜索历史下且点击即搜；扫码弹层可显示官方 qrcode_img；密码登录代码路径存在（标待实测） | 短信/密码/token 续期（版本参数可猜测，标待实测） |
| 3 | 匿名 MV 音频流核心：mv_endpoints 打通 video_id→getVideoQualities(A5-2 契约 data:[{video_id}],show_resolution:1)→getVideoUrl(downurl)；按用户裁定：只取音频流，优先最低清晰度档，忽略音质调节 | 匿名播放链：r_register_dev 设备注册（platid=2、uid='0'、小写hex p、signature含body、AES二进制响应）核/补 + verification_logic 过 20028；匿名凭据 '0' 落 session | playback_service 新增匿名降级路径：正常 play_url 失败(20028/无权)→MV 音频流兜底；35104 单列 noPrivilege | core/net/endpoints/mv_endpoints.dart / auth 端点 / verification_logic.dart / playback_service.dart | MV 音频流从匿名可取最低档并可播放（探针脚本就绪，结果待真机）；35104 不再误判 | 是（设备注册/20028/MV音频档全链） |
| 4 | 三态字段捕获探针：play_url v5 补捕 q/fileSize/volume_*/classmap/hash_offset/fail_process；search 补捕 mvdata[]/HQ/SQ/Res hash | MV 域字段：MvBrief 补 hit/play_times/desc/album_audio_id；videoDetail 平铺档位补 bitrate/width/height；privileges 权限信号；删 videoDetailKmrV2 死代码 | 写语义修复：playlist_write_endpoints.dart:19 _ok() 删 s==0 分支；comment 补 reply_num/haslike/addtime/blockedReason；lyric id 改 safeStr；recommend empty 移出 cacheable | play_endpoints.dart / search_endpoints.dart / mv_endpoints.dart / comment / playlist_write / misc / recommend_endpoints.dart | 留样键全覆盖；写失败不再报成功；mv 模型字段齐 | 探针脚本产出后真机跑（本批只写探针+解析） |
| 5 | play_url v6 多档批量：/v6/priv_url Endpoint（9 档 qualities，tracker_param 带 viptoken/vip_type/priv_vip_type=6/need_xcdn）| 权益最大化：playback_service 按三态选档阶梯（VIP: super→viper→flac→320；非VIP: 320→128→试听）；捕获 q 回填实际档位；降档重试链 + backupUrl 备链消费 | 登录回写补全：AuthLogic 回写 vip_token/vip_type/t1 落 session（对齐旧版 _afterLogin） | play_endpoints.dart / playback_service.dart / auth_logic.dart / registry | 三态各自取到最大可播档；失败自动降档；备链可切换 | 是（v6 未探针） |
| 6 | MV UI：新建 mv_page.dart + MvPageModule(id:'mv') 覆盖占位；player_page `_openMenu` 加「看 MV」（mv_logic.getMvBySong→清晰度选择→播放） | 清晰度链 UI：档位列表 ld/sd/hd/fhd/qhd（含265/mkv）展示 hash/filesize/bitrate；匿名态强制最低档 | 搜索 MV 入口：searchTyped type=mv 建 MvBrief 模型（A1-5 键集）；搜索页 MV 分段或结果卡 | mv_page.dart / player_page.dart / search_page.dart / session 编排 | 播放页可进 MV；匿名只见最低档；MV 搜索有结果 | 是（downurl http→https 处理） |
| 7 | 搜索补数据：六类分段（SearchTypedLogic）接 playlist/album/artist/lyrics 分段；歌单详情补 fileid 捕获（支持精确删歌） | 本地曲库/最近播放：SongDao/HistoryDao 经 bridge 暴露给 library_page（:170/176 空态修复） | 歌单/相似/标签：playlistSimilar 消费入口；每日推荐复测替代源（recommend 端点疑似不可用） | search_page.dart / library_page.dart / playlist_endpoints.dart / session 装配 | 分段不再恒空态；本地曲库/最近播放有数据 | 复测 daily_recommend |
| 8 | 写成功语义收敛：以批 4 的 _ok 修复为基础，收敛 addSong/deleteSongsTo/collect 回执校验（data.info[] 补 name/cover/hash 回显）+ 实测 list_ver 乐观并发 | 收藏/评论 UI：FavoriteButton 接真实 collect（登录态写、匿名 blockedReason）；评论楼层/点赞展示 | 外发闸门：所有写操作确认弹层 + 匿名/未登录显式拦截（20010 语义与「没数据」区分，blockedReason 机制推广全域） | playlist_write_endpoints.dart / collect_endpoints.dart / comment_endpoints.dart / player_page.dart / playlist_page.dart | 写操作只在确认后外发；成功/失败语义准确；未登录有明确提示 | 是（写回执真机验证） |
| 9 | FM/云盘/高潮：registry personalFm 路径对齐 /v2/personal_recommend+x-router persnfm；userCloud /v1/get_list+mcloudservice+AES 契约实现；songClimax 契约固化 | 未接端点收敛：playHistoryUpload 定时上报接线；listenReport UI 消费；favorite_count/ghost 空样本端点全部加 blockedReason | FM/云盘 UI：FmLogic 入口（player 菜单已有 'fm' 占位请求，需真实页）；云盘列表页 | fm_endpoints.dart / user_endpoints.dart / registry / 新 fm_page/cloud_page | registry 声明与契约一致或显式标注；空态可区分原因 | 是（fm/cloud/climax 全未实测） |
| 10 | CI/门禁：layer_audit 与 smoke_check 同步 session 层与六桥白名单；feature_reachability 断言更新 | 文档：更新 KUGOU_API.md/API_FIELDS_TRUTH.md 实测结果与版本变体标注（可猜测/已实测两栏） | 发版收口：版本号、CHANGELOG、全批验收回归清单、遗留待实测清单汇总 | docs/* / CI 脚本 / pubspec | 十道门禁过；文档与代码一致；待实测清单完整 | 是（真机回归） |

## 4. 每批 6 子代理模板（3 检查 + 3 修复）

每批固定派 6 个子代理，文件范围互不重叠；收敛一批再开下一批。

**检查组（C1/C2/C3）任务书模板：**
```
【76 原则 §0 全文】（照贴）
你是检查代理（只读，不改代码）。范围：仅 <本目标对应文件清单>。
用 file_read 逐文件核对：<验收条件逐条列出>。
产出：docs/check_b<N><X>.md，含「文件:行 + 通过/缺陷 + 建议修法」。
硬规范：汇报聊天 <500 字；完整报告落盘 docs/；只用 file_read/file_write/ls；
工具 ≤35；禁止用 shell 读文件；禁止真实网络调用；不提交。
```

**修复组（F1/F2/F3）任务书模板：**
```
【76 原则 §0 全文】（照贴）
你是修复代理。范围：仅 <文件清单，与检查组一一对应且互不重叠>。
按 docs/check_b<N><X>.report 的缺陷逐条修：L7 只画控件 / L4 端点一端点一文件；
版本变体标「待实测」；凭据脱敏；写操作不外发。
硬规范：汇报聊天 <500 字；完整修改说明落盘 docs/fix_b<N><X>.md；
只用 file_read/file_edit/file_write/ls；工具 ≤35；禁止 shell 读文件；不跑分析器；不提交。
```

分配规则：批内 A/B/C 三目标各 1 检查 + 1 修复成对；检查先跑完，报告落盘后修复组才开工；修复组不得触碰其他对文件。批 2/6/9 的 UI 新文件（mv_page/fm_page/cloud_page/登录弹层）与被改页面分属不同代理，避免重叠。

## 5. 风险与停止条件

1. **凭据风险**：三态实测需真账号 token/vip_token；凭据只可经环境变量注入探针脚本，日志/落盘一律脱敏；**不得**把账号凭据写进任何 docs/。
2. **网络风险**：本计划所有「需实测=是」项（设备注册、20028 人机验证、v6 批量、MV 音频档、FM/云盘/高潮、写回执）当前均为文档/代码推断，**不得冒充可用**；探针失败即标「端点未证实」，UI 显式未实测态，禁止静默空数据。
3. **未实测端点停止条件**：任一端点探针三态全空且无留样契约 → 停止该端点 UI 接入，列入批 10 待实测清单，须问用户是否降级为隐藏入口。
4. **真机验收限制**：主题切换/底栏顺序/首页布局可离线验收；播放链、扫码登录、MV 视频流、写操作必须真机（模拟器无麦克风/风控差异），每批验收分「离线可验 / 真机待验」两栏。
5. **必须问用户的决策点**：
   - 密码登录/微信开放平台登录是否真的要接（微信需 appid/secret 配置，用户未给则批 2 只做密码+短信+扫码）。
   - 匿名 MV 音频流的「最低清晰度」口径确认（音频流取 ld 档 hash，还是取 *_audio/265 之外的最低视频轨仅抽音频）。
   - 写操作（收藏/加歌/评论）批 8 是否允许真实外发，还是只到确认弹层为止。
   - MV downurl 为 http，需本地代理转 https 还是直接放行 http（Android 9+ 默认禁明文）。
6. **停止条件**：子代理单批报告发现越层依赖/桥缺失 → 停批上报，不自行补桥；单文件将超 500 行 → 拆文件而非塞注释。

## 6. 追加批次（用户指令 2026-11-15）：10 批完成后额外 2 批

| 批 | A | B | C | 范围 |
|---|---|---|---|---|
| 11 缓存专项 | CacheService 门面与 ResourceCache 职责边界审计（缓存⊃预读是否真正统一；KugouClient 双缓存栈是否重复/竞态） | 键维度审计（cacheKey 是否含 body/token/uid/dfid；TTL 分级：歌词/搜索/榜单差异化；登出失效钩子） | 容量/并发修复（同步 IO 残留、cleanup 旧快照回写、tmp 唯一化、上限策略实测） | core/cache/**、core/storage/resource_cache.dart、core/net/kugou_client.dart、core/net/inflight.dart |
| 12 网络专项 | 全 50 端点契约复核（registry 声明 vs 上游源码 vs 实测留样三方对齐；死声明/版本错位清理） | 传输层审计（签名三模式、clienttime 秒/毫秒、dfid 真随机、Cookie 拼接、UA、超时/重试/405 降级） | 三态留样收口（api_samples 脱敏矩阵补全；「待实测」端点探针脚本产出与执行结果登记） | core/net/**、core/cache 探针接口、tool/api_probe*.dart、docs/API_* |
追加批次同样 3 检查+3 修复、文件边界不重叠、完成一批收敛一批；修复前检查报告落盘 docs/batch{11,12}_c*.md。