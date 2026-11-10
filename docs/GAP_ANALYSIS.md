# 功能面对比差距分析（GAP_ANALYSIS）

> 基线：旧项目 TiernanMusic（归档，最终版 v5.5.0+56，50 直连端点）vs 新项目 TiernanMusic-Next（26.11.10.02 LTS，六层五桥）
> 信息来源：旧 docs/api_verified.md、docs/PROGRESS.md（底部至 v5.5.0）、docs/archive/PLAN_v2_final.md（v2.0 LTS 收尾总规划「现状盘点」——旧项目最新功能完成度口径）；
> 新 docs/ARCHITECTURE.md、docs/KUGOU_API.md §3、lib/core/net/kugou_client.dart EndpointRegistry、lib/surface/pages/* 头注释、changed/26.11.10.02.md。
>
> **纪律声明：零代码复用，仅功能目标对齐。** 旧项目 LICENSE 禁止复用代码；本分析只对齐「功能目标」，实现路径全部基于新项目六层五桥分层（core/net 端点封装 → logic 门面 → surface 模块）与 docs/KUGOU_API.md 三态实测知识，不从旧仓库搬运任何一行。

---

## 一、功能点对比总表

| # | 功能点 | 旧项目 | 新项目 | 差距说明 | 建议实现路径 |
|---|---|---|---|---|---|
| 1 | 关键词搜索 | 有 | 已实装 | search_song/search_complex 端点 + LRU 缓存 + data.lists[] 已实测对齐 | 已闭环；增强走 search_complex v6 |
| 2 | 搜索联想 | 有 | 已实装 | search_suggest 端点 + 搜索页防抖 300ms | 已闭环 |
| 3 | 热搜榜 | 有 | 已实装 | search_hot 端点 + 搜索页空态 | 已闭环 |
| 4 | 播放引擎（URL/多音质/队列状态机） | 有 | 已实装 | play_url v5/v6 + privilege_lite 三态实测；reducer 队列 3 模式 | 已闭环 |
| 5 | 歌单（推荐/详情/曲目/收藏/加歌） | 有 | 已实装 | playlist_* 五端点 + specialid/data.songs[] 实测 | 已闭环 |
| 6 | 榜单 | 有 | 已实装 | rank_list/rank_info | 已闭环 |
| 7 | 播放页 UI | 有 | 已实装 | 大封面/seek/模式切换/MiniBar | 已闭环 |
| 8 | 歌词 KRC 逐字 | 有 | 已实装 | KRC 解密 + 逐字时间轴 + LRC 回退 + 三级缓存 | 已闭环 |
| 9 | 下载管理 | 有 | 已实装 | 并发 3/分块进度/断点续传语义/校验 + UI | 已闭环 |
| 10 | 曲库/最近播放/历史持久化 | 有 | 已实装 | Isar SongDao + historyRecent | 已闭环 |
| 11 | QR 登录（协议/轮询/token 续期） | 有 | 已实装 | login_qr_key/login_qr_check/login_token + AES 固定 key/iv | 已闭环 |
| 12 | **QR 二维码渲染** | 有 | **部分** | changed/26.11.10.02.md Known Issues：QR 渲染器为**占位实现** | surface：设置页登录区接真实二维码渲染（纯 Dart 生成二维码位图，≤500 行自实现）；logic：bridge_logic 暴露 qrPayload 流 |
| 13 | **多账号** | 有（多账号切换） | **缺** | 新项目仅单登录态，无账号档案切换 | core：Isar AccountDao（多 token/userid 档案）；logic：AccountLogic 切换/失效隔离；surface：设置页账号卡片 + 切换弹层 |
| 14 | **评论**（浏览/楼层/计数/写评论） | 有（含热词 chips、-404 修复经验） | **缺** | EndpointRegistry 无 comment/*；KUGOU_API.md §3 已收录知识，需补端点声明 | core/net：comment_music/comment_floor/comment_count 三端点（参数走 **query** 非 body）；logic：CommentLogic 分页/热词；surface：播放页评论区入口 + 评论页模块 |
| 15 | **收藏歌曲/MV 收藏** | 有（含 cancel_collect 二进制 body 经验） | **部分** | 有 playlist_add_songs（收藏歌到歌单），无歌曲/MV 收藏与取消 | core/net：collect + cancel_collect 端点；logic：CollectLogic 防重+登录守卫；surface：播放页收藏按钮 |
| 16 | **MV**（详情/URL/清晰度/播放页） | 有（三态+取消收藏闭环） | **缺** | EndpointRegistry 无 kmr/audio/mv、video/detail、video/url | core/net：mv_detail/video_url 两端点（x-router kmr.service / trackermv）；logic：MvLogic 清晰度档位；surface：mv_player 模块（video_player 属例外白名单需评估，或自实现播放壳） |
| 17 | **翻译歌词** | 有（lineIndices 契约、条数防御经验） | **缺** | lyric_download 未含译文通道；无译文错行防御 | core/net：歌词翻译端点声明；logic：译文与原文 lineIndices 对齐契约（条数不等不落缓存）；surface：歌词页译文行 |
| 18 | **多语言（旧 10→11 语，385 键）** | 有 | **缺** | 新项目无 arb/l10n 体系 | surface：l10n 目录 + arb 10 语（en/zh 先行，其余 8 语分批翻译批）；gen 键 CI 校验 |
| 19 | **封面取色/动态主题** | 有（视觉体系成熟） | **缺** | 新主题仅亮暗双态常量表 | core：图像主色提取（纯 Dart 像素采样，≤500 行）；logic：ThemeLogic 挂 riverpod；surface：播放页封面联动 |
| 20 | **每日推荐** | 有（everyday_recommend 实测） | **部分** | EndpointRegistry 已声明 recommend_songs（everyday_song_recommend），但无 logic 门面与 UI | logic：RecommendLogic 消费既有端点；surface：曲库 tab 或首页模块 |
| 21 | **个人 FM** | 有（评估/基础版） | **部分** | EndpointRegistry 已声明 personal_fm（/v1/fm/play），未接线 | logic：FmLogic（跳过/喜欢）；surface：播放页 FM 模式入口 |
| 22 | **歌手页**（详情/歌曲/专辑） | 有 | **部分** | artist_list 端点已声明；缺 artist/detail、audios、albums 三端点与页面 | core/net：补 artist_detail/artist_audios/artist_albums（⚠️ audios 签名需 defaultParams+body 合并）；logic：ArtistLogic；surface：artist_page 模块 |
| 23 | **专辑页** | 有 | **部分** | album_detail 已声明；缺 album/songs | core/net：album_songs（v1/album_audio/lite）；surface：album_page 模块 |
| 24 | **相似推荐/相似歌单** | 有（规划项） | **缺** | 无 relate 类端点 | core/net：privilege_lite relate 字段已有，补相似歌单端点；surface：歌单详情页底部推荐 |
| 25 | **云盘** | 无 | **缺** | 双方均无，属新增目标（非对齐旧项目） | core/net：云盘列表/上传端点（需先探针实测再声明）；logic：CloudLogic |
| 26 | **长音频** | 无（仅专项评估，未实装） | 缺 | 双方均未实装 | 先 tool 探针实测 multitrack 音质与分片协议，再定端点；不定即砍 |
| 27 | **乐谱** | 无 | 缺 | 双方均无 | KUGOU_API.md 无相关知识 → 列为探针前置，探不通即砍 |
| 28 | **场景电台** | 无 | 缺 | 无 | 个人 FM 扩展（scenario 参数探针）→ 探不通砍 |
| 29 | **青年模式** | 无 | 缺 | 无 | 纯本地功能：core 偏好存储 + logic 时段限制 + surface 弹层，不依赖端点 |
| 30 | 音质档位选择（14 档弹层） | 有 | 部分 | play v6 qualities 9 档已在协议层，无 UI 选择器 | surface：播放页音质弹层写偏好；logic：QualityLogic 持久化 |
| 31 | 登录（短信/密码/TCaptcha） | 有 | 缺（仅 QR） | 新项目登录仅二维码 | core/net：短信/密码登录端点（探针前置）；surface：登录方式切换 |
| 32 | 离线播放 | 有 | 已实装 | 下载 + 本地优先编排 | 已闭环 |
| 33 | 设置（主题/缓存清理/关于） | 有 | 已实装 | settings_page 六模块之一 | 已闭环 |

## 二、汇总

- 功能点总数：**33**
- 新项目已实装：14 · 部分：8 · 缺：11
- P0（核心闭环缺口：QR 渲染/多账号/评论/收藏/MV/翻译歌词/10 语言/封面取色）：**8 项**（#12–19）
- P1（内容发现：每日推荐/FM/歌手专辑/相似/云盘）：**6 项**（#20–25）
- P2（扩展：长音频/乐谱/场景电台/青年模式 + 音质弹层/其他登录方式）：**4 项**（#26–29；#30–31 并入 P1 尾批备选）

## 三、分批纪律（沿用旧项目 5 批 × 3 子代理，每批一个主题三代理并行，串行出批，报告落盘）

**批 1（P0-a，闭环补全 1）**
- 子代理 A：评论端点封装（core/net，三端点 + query 参数语义）+ CommentLogic
- 子代理 B：MV 端点封装 + MvLogic 清晰度档
- 子代理 C：QR 真渲染（纯 Dart 二维码位图）+ surface 接线

**批 2（P0-b，闭环补全 2）**
- 子代理 A：多账号（AccountDao + AccountLogic + 切换 UI）
- 子代理 B：翻译歌词（lineIndices 契约 + 条数防御 + 歌词页译文行）
- 子代理 C：收藏体系（歌曲/MV 收藏与取消 + 播放页按钮 + 防重锁）

**批 3（P0-c，收尾）**
- 子代理 A：l10n 体系（10 语 arb 骨架 + gen CI 校验）
- 子代理 B：封面取色（纯 Dart 主色采样 + 主题联动）
- 子代理 C：音质档位弹层 + 每日推荐接线（consume 已声明端点）

**批 4（P1，内容发现）**
- 子代理 A：歌手页（三端点 + artist_page 模块，注意 audios 签名合并陷阱）
- 子代理 B：专辑页 + 相似推荐
- 子代理 C：个人 FM 接线（FmLogic + 播放模式入口）

**批 5（P2，探针前置扩展，探不通即砍）**
- 子代理 A：云盘/长音频探针（tool 脚本实测，产出端点知识增补 KUGOU_API.md）
- 子代理 B：乐谱/场景电台探针（同上，只探不实装）
- 子代理 C：青年模式（纯本地，不依赖探针结果）

每批交付纪律：只报告不盲修、边读边落盘、禁止本地起服务、禁止网络请求（探针批除外且须主代理批准）、layer_audit 全绿方可出批。

---

*本文档只读对比产出，未修改任何代码。*
