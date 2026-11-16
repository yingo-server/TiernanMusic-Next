# B2 批 · 交叉汇总（搜索 / 榜单 / 推荐 跨层）

> 2026-11-17。三视角：`bB2_c1.md`（架构）、`bB2_c2.md`（正确性）、`bB2_c3.md`（痛点）。均已落盘。

## 0. 阶段 A 修复的跨层验证

| 修复 | 结论 | 证据 |
|---|---|---|
| kugou_client 只缓存成功响应 | ✅ 生效（C2 确认底层 mid/srcappid 20006、suggest/hot 字段解析已对齐） | C2 |
| rank/recommend logic 空结果不落缓存 | ✅ 生效（rank_logic:54,93 `if isNotEmpty`、recommend:61 `if cacheable&&isNotEmpty`） | 主会话核实 |
| **search/search_typed logic 缓存** | ❌ **遗漏面**：`search_logic.dart:63`、`search_typed_logic.dart:68,108` 仍 `_cache.put(key,res)` 无条件写，空结果/失败固化——与已修的 rank/recommend 不一致 | C2 + C3 + 主会话核实 |

## 1. 关键问题

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **search/search_typed 失败空结果写 LruCache 固化**（阶段A修复遗漏面） | C2 + C3 + 主会话 | **P1** | `search_logic.dart:63` + `search_typed_logic.dart:68,108` |
| X2 | **搜索/推荐三态在 L7 坍缩**：错误态重试成死代码、未登录显示"暂无"、登录Required 态被 L5 降级为 List 后 L7 吞成同一句空态 | C2 + C1 | **P1** | `search_page.dart` + `recommend_logic.dart` |
| X3 | **分页断链**：L4/L5 全支持 page，L7 全部写死 1（无分页/下拉刷新） | C1 + C3 | **P1** | `search_page.dart:87-88` + `home_page.dart:55,97` |
| X4 | **热搜有端点无 UI 出口**：hotSearch() 全仓零调用，UI 用硬编码分类词替代；且非歌曲段套 SongBrief 致点击播放必失败 | C1 + C2 + C3 | **P1** | `hotSearch()` 零调用 + `search_page` 分类段 |
| X5 | **榜单点击仅播放不进详情**（无 playlist detail 入口） | C3 | **P1** | `home_page.dart` |
| X6 | **端点分文件违 §0-6**：无 rank_endpoints.dart，榜单仍混装 misc_endpoints(rank+lyric+krc) | C1 | **P0(架构)** | `misc_endpoints.dart` |
| X7 | **搜索状态机全在 L7 Widget**（历史/联想/结果/分段），L5/L6 无归属无持久化 | C1 | **P0(架构)** | `search_page.dart:65,68` |
| X8 | bootstrap 预读键与实际请求参数不一致 + logic 用独立 LruCache → 榜单预读零收益 | C1 | **P2** | `bootstrap.dart` 预读段 |
| X9 | 搜索联想 Future 竞态（旧结果覆盖新）、分类搜索端点双来源+注册表 2 死声明 | C1 + C3 | **P2** | `search_page.dart:82-97` |
| X10 | 文案未接线：4 文件 73 行中文硬编码，零 S.of 接线 | C3 | **P2** | search/home 页面 |

## 2. 76 合规裁决（C1 权威）

- 合规：六桥无越级直连、四层 try/catch+Log 齐备、无超 1500 行文件。
- 违规：端点分文件（X6，rank 混装）、状态机归属（X7，搜索状态在 L7）——两条 §0 铁律未落实。

## 3. 与用户痛点对应

| 用户原话 | B2 定位 |
|---|---|
| 「什么功能都用不了」 | 分页写死1、热搜无入口、榜单点击不进详情、非歌曲段点击播放失败、错误态坍缩成"暂无" |
| 「文案没改」 | 73 行中文未接 S.of |
| 阶段A修复验证 | 磁盘缓存修复生效，但 logic 独立缓存遗漏（X1）——又一次"单点修复≠链路通" |

## 4. B2 结论
三视角全落盘。真 P1×5 + 架构 P0×2 + P2×4。阶段 A 缓存修复遗漏 search logic 独立缓存面（X1），需阶段 B 全审完后亲修。

## 5. 下一步
阶段 B 继续 B3（播放主链路跨层）。所有修复待 B1~B7 全完后主会话亲做。B2 定时器 `0ab97790` 已取消（三份齐）。
