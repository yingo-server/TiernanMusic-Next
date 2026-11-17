# 阶段 B 跨层修复总清单（主会话亲修用）

> 14 批审查（阶段 A 底层 7 批 + 阶段 B 功能跨层 7 批）全部完成。
> 核心结论：阶段 A 的单点修复大多生效，但阶段 B 发现大量「跨层接缝未闭环」——能力存在≠用户可用。
> 本清单按「修复优先级 + 可执行性」汇总需主会话亲修的跨层问题，逐条带锚点。

## P0（必修，影响核心可用性）

| # | 问题 | 批次 | 锚点 | 修复方向 |
|---|---|---|---|---|
| 1 | **VIP 快照未刷新**（启动后登录恒匿名音质，三次审查未闭环） | B1/B3 | `bootstrap.dart:118` + `playback_service._session final` | `_hasRights` 改为实时读 settings（去掉 final 快照），或登录成功后回灌 vip_token/vip_type 到 PlaybackService |
| 2 | **20028 验证零 UI 出口**（用户遇验证必卡死） | B1/B3 | `verification_logic.dart` + L7 | L7 加验证提示/出口；端点未实测前明示"验证暂不可用"而非静默卡死 |
| 3 | **语言切换完全不可用**（无入口/无 locale 装配/saveLocale 零调用） | B7 | `app_root.dart:63-73` + `settings_page` | 设置页加语言选择 UI → TnStrings.saveLocale → MaterialApp 接 locale/supportedLocales + rebuild 触发 |
| 4 | **错误态不可见**（写 lastError 但播放页不读；L5 catch 吞错致 snap.hasError 永不成立） | B3/B7 | `playback_session` + 各 logic catch + state_view | 播放页读 lastError 显示；L5 错误态透传给 L7 三态，禁吞成空 List |
| 5 | **下载 onTask 零订阅**（进度/完成/失败不刷新、重启恒空） | B5 | `download_manager.onTask` + `library_page` | library_page 订阅 onTask + 启动时 loadIndex 恢复任务态 |
| 6 | **MV 响应解包第五重断点** | B4 | `mv_endpoints.dart` | ✅ 已在 B4 收口时修复（弃用 dataOf 直接 listOf），**但需补端点级测试锚点** |

## P1（功能闭环）

| # | 问题 | 批次 | 修复方向 |
|---|---|---|---|
| 7 | YKG 导入通知打到未 attach 的 AuthSession | B1 | bootstrap 补 `AuthSession.instance.attach(client)` + onAuthChanged 消费者 |
| 8 | search/search_typed logic 独立 LruCache 无条件 put（阶段A缓存修复遗漏面） | B2 | 仿 rank/recommend 加 `if (res.isNotEmpty)` 守卫 |
| 9 | 分页写死 1 / 热搜有端点无 UI / 榜单点击不进详情 | B2 | L7 接分页 + 热搜入口 + 榜单详情跳转 |
| 10 | 单曲循环失效 + shuffle 切歌回退 | B3 | loopOne 真重播；`_start` 保留 QueueState 不重建 |
| 11 | 通知栏首曲元数据丢失 + onSeek 悬空 + 进度失同步 | B3 | initNotification 完成后补发当前曲 metadata；onSeek 接回会话 seek |
| 12 | 换号收藏串号 / 收藏计数空转 / 收藏 flush 失败无回滚 | B5 | L6 接 AuthChanged→resetLocalMirror；计数改走真实源；flush 失败回滚镜像 |
| 13 | 歌单写链全断（L7 零入口、saveLocalMirror 零调用） | B5 | 加歌单创建/删除/加歌 UI 入口 + 本地镜像写入 |
| 14 | 缓存预读真命中≈0（三套缓存不相交、参数不匹配） | B5 | 统一缓存域或对齐预读键；或删无效 prefetch 避免假象 |
| 15 | 取色链 100% 断 + 主题 4 档塌缩 + 两套 ThemeData | B6 | L6 ThemeController 接 L4 extractDominant + seed 派生 scheme；app_root 修 0/3 映射；统一单一主题工厂 |
| 16 | M3 令牌建而不用（195 处 Sp.* 绕过 ColorScheme，MD3 仅 +2 分） | B6 | 页面级把 Sp.* 静态色改 Theme.of(context).colorScheme.*（大工程，分批） |
| 17 | i18n 接线率≈0%（213 处中文未接 S.of） | B7 | 逐页把硬编码中文改 S.of(context).t(key)（大工程，分批） |
| 18 | 设置页四项缺陷（主题跟随系统/清缓存/音质倍速不落盘/匿名暴露VIP档） | B7 | settings_page 逐项修 |
| 19 | 导航死链（lyrics/comment tab 无效） | B7 | 补真实页面或移除死入口 |
| 20 | YKG UX（过期误报密码错/无二维码/有效期不展示/来源不标记） | B1 | UI 区分错误码；复用 qr_codec（需补解码）；补展示 |

## 架构债（P1/P2，按 76 原则）

- L5 下载 IO 直连（download_manager HttpClient+File）→ 下沉 L4 core（B5）
- bridge_core 越权导出端点/密码学原语（B1）
- L6 playback_session 越界持有状态机（直驱 reducer 18 处）（B3）
- QR 状态机劈两半、搜索状态机全在 L7、设置页越权写操作（B1/B2/B7）
- mv_anonymous 227 行死代码、PlayResolver 681 行死代码（B4/B3）

## 修复执行说明

- 用户选定：本轮全做完 + 允许成熟库依赖（阶段 A 已用 cryptography）。
- 本地无 dart/flutter，编译靠 CI；已建立"静态审读 + CI 逐条修编译错"的收口模式。
- 大工程项（16 M3 全量改造、17 i18n 全量接线）本轮先建通道 + 修高价值页面，存量分批；如用户要求全量则逐页推进。
- 每批修复后跑 `layer_audit.py` + 静态冒烟，最后统一提交推 CI。
