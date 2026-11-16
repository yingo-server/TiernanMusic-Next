# 阶段 B · 7 批功能跨层深度审查 · 任务书

> 立规来源：用户 2026-11-16 指令「阶段 A 七批按层修完后，再来 7 批以功能计的跨层检查」。
> 阶段 A 已完成并 CI 全绿（HEAD ca4c9c6）。本阶段契约与阶段 A 相同，见 `docs/DEEP_AUDIT_14_BATCH_PLAN.md` §0–§3（76 原则、纪律、三视角、落盘格式）。

## 0. 阶段 B 与阶段 A 的区别

- 阶段 A：**按层**（L1→L7）自底向上审，找单层内问题。
- 阶段 B：**按功能**跨层追踪「L7 入口 → L6 会话编排 → L5 逻辑 → L4 端点/存储 → L4 网络」，验证：
  1. 阶段 A 的修复是否在**整条链路上真正生效**（不是单点改对、别处仍断）；
  2. 跨层**接缝**的新问题（签名不一致、状态不同步、错误态丢失、缓存与 UI 不同步）。
- 三视角固定：C1 架构合规 / C2 实现正确性 / C3 用户痛点（同阶段 A）。

## 1. 通用纪律（与阶段 A 相同，重申）

1. **只读**：`file_read` + shell `ls`/`rg --files`/`rg`/`wc`；禁止改源码、git 写、跑 dart/analyze/test/门禁、联网。唯一允许写＝**追加**自己的报告到 `docs/deep_audit/bB{N}_c{1|2|3}.md`（严禁覆盖）。
2. **一口气读完**：开工先把本批跨层范围内文件按清单连续读完再下结论。
3. **60 分钟硬超时**：到点用已有发现收口，未查完标「未覆盖」，不无限加调用。
4. **证据化**：每条带 `文件:行` + 代码/字段事实；禁止空话。
5. **交叉**：3 视角独立取证，主会话比对（共识=确认，分歧=复核）。
6. **只审不改**：任何"怎么改"只写建议，不动代码；修复由主会话在阶段 B 全部审完后亲做。
7. **76 原则**：单列「76 合规」小节，指出跨层接缝的越级/反向/职责错位。
8. **聊天汇报 <200 字**，完整结论落盘。

## 2. 阶段 A 修复基线（验证是否真正生效，重点核验）

| 修复 | 提交 | 阶段 B 要验证的跨层链接 |
|---|---|---|
| boot 失败误判 | 5181120 | main → bridge_boot → bootloader → 错误页，失败原因是否端到端可见 |
| 20028 验证死链 | 5181120 | playback_session → VerificationLogic → L7 是否真有验证 UI 出口（当前仅到 required 状态，端点仍待实测） |
| MV 四重断点 | 5181120 | L7 查看MV → L6 模块注册 → L5 videoIdOfSong/qualities/playUrl → L4 端点两段式 → video_player 渲染，全链路是否通 |
| 收藏假按钮 | 5181120 | L7 FavoriteButton → L6 appGraph.collect → L5 toggle → L4 collect 端点 → 持久化镜像 → 重启是否保持 |
| 下载零入口 | 5181120 | L7 ⋮菜单 → L6 appGraph.downloads → L5 enqueue → L4 download_store → 文件落盘 + 列表页是否显示进度 |
| AES Rcon | 5181120 | 依赖 AES 的登录/歌单加密端点端到端（标准向量已验，需端到端确认） |
| VIP 恒 false | 5181120 | 登录回写 vip_token → settings → bootstrap 注入 PlaybackService → 音质档位选择是否真提档 |
| YKG 登录 | 5181120 | L7 导出弹层 → L5 编排 → L4 加解密 → base64 链接 → 导入另一设备 → 凭据注入 client → 真能请求 VIP 曲 |
| i18n 接线 | 5181120 | 10 语 arb → strings.dart → S.of门面 → 各页面；存量 119 处硬编码中文是否仍大量未接 |
| 取色链断 | 未修（转 B6） | L4 color_extract → L6 theme_controller → L7 tn_theme，是否仍 100% 断 |

## 3. 七批功能范围（按功能跨层追踪）

| 批 | 功能 | 跨层链路（追踪到底） | L7 入口文件 |
|---|---|---|---|
| **B1** | 登录全链路 + **YKG 新方式** + 文案 | login_sheet/ykg_sheet → auth_session → auth_logic/ykg_logic → auth_endpoints/ykg_codec/settings/crypto | `lib/surface/pages/login_sheet.dart`, `ykg_sheet.dart` |
| **B2** | 搜索 / 联想 / 热搜 / 榜单 / 推荐 | home_page/search_page → search/search_typed/rank/recommend logic → 对应 endpoints → 三态 | `home_page.dart`, `search_page.dart` |
| **B3** | 播放主链路 | player_page/mini_bar → playback_session → play_resolver/playback_service/quality_policy/queue → audio_gateway/play_url → 通知栏/历史 | `player_page.dart`, `design/mini_bar.dart` |
| **B4** | **MV 播放**（用户点名，验证四重断点修复） | player_page 查看MV → module_registry → mv_page → mv_logic → mv_endpoints 两段式 → video_player | `mv_page.dart` |
| **B5** | 下载 / 收藏 / 歌单 / 缓存 | library_page/playlist_page → download/collect/playlist_write logic → download_store/collect_endpoints/cache_service | `library_page.dart`, `playlist_page.dart` |
| **B6** | UI / M3 / 主题 / 动画 / 动态取色 | tn_theme/tokens/components/全部页面动效 ← theme_controller ← color_extract | `design/tokens.dart`, `theme/tn_theme.dart` |
| **B7** | i18n 文案 / 设置 / 导航 / 错误空态 | settings_page/shell/各 state_view → nav_state → S门面/strings.dart → 全 arb | `settings_page.dart`, `shell.dart` |

## 4. 落盘规范

- 每子代理一个文件：`docs/deep_audit/bB{N}_c{1|2|3}.md`，**append 写入**，带时间戳小节。
- 交叉汇总：主会话写 `docs/deep_audit/bB{N}_summary.md`。
- 全局状态：`docs/DEEP_AUDIT_STATE.md`（主会话维护）。

## 5. 推进

- 每批派 3 子代理 → 挂 50 分钟单次定时器催总结（留 10 分钟收口）→ 收口写 summary → 派下一批。
- DNS 抖动/app 重启致代理失败或 job 丢失 → 重派对应视角，正文实时落盘不丢。
- 14 批全完成后向用户总汇报。
