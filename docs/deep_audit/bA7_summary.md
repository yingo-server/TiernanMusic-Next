# A7 批 · 交叉汇总（L7 surface 18 文件 + l10n 10 语 arb）· 阶段 A 收官

> 2026-11-16。三视角：`bA7_c1.md`（架构）、`bA7_c2.md`（正确性）、`bA7_c3.md`（MD3/动画/文案，**报告主体由主会话补齐**，子代理尾注丢失已重建）。
> 子代理回调有 2 次限流/DNS 失败与 1 次报告覆盖丢失：C1 报告完整落盘可用；C2 完整；C3 结论在回调、细节由主会话用 material-3 skill 亲自补全并**修正了 Theming 误判理由**。

## 0. 关键裁定

- **MD3 合规 40/100 fail**（十类：Color2/Typo5/Shape6/Elevation4/Components6/Layout3/Navigation5/Motion2/Accessibility4/Theming3）。
- **修正 C3 误判**：`Sp.theme()`（tokens.dart:70-148）**确实** `useMaterial3:true` + `ColorScheme.fromSeed` + 五级 surfaceContainer + 全套组件主题；低分真因是「主题数据存在但页面用 `Sp.*` 静态色绕过它消费 + 亮暗切换色不跟随 → 白底白字」，**不是没有 ThemeData**。修复方向是让页面改用 `Theme.of(context).colorScheme.*`，不是重写主题函数。

## 1. 关键问题

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **MV 四重断点在 UI 侧坐实**：`mv_page.dart:18` 注册守卫「id 存在即 return」+ builder 空 hash；上层传歌曲 hash 而非 videoId | C1 + C2 + A1/A3/A5/A6 | **P0** | `mv_page.dart:12-35,75-130` |
| X2 | **收藏假按钮**：player_page 收藏纯本地 setState，不读态/不落库/不调 CollectLogic | C2 + A1/A3/A5 | **P0** | `player_page.dart:62-83` |
| X3 | **下载全 surface 零入口**：library_page 空态「在歌曲菜单里选择下载」指向不存在的菜单 | C2 + A1/A3 | **P0** | `library_page.dart:302-303` |
| X4 | **L7 职责大面积越界**：≥10 个页面在 Widget 内持有状态机/定时器/取数编排/IO（login_sheet QR四态+轮询、lyrics 200ms轮询+解析、mv_page 选档+播放器四态、playlist/search/settings 取数+写入）；app_root 握 SurfaceDeps 装配图、shell 注册 8 模块 | C1 | **P1(架构)** | 见 C1 结论 3/5 |
| X5 | **surface 绕过 bridge_surface**：18 文件零 import bridge_surface，全部直取 bridge_core/logic/session 三座下桥 | C1 | **P1(架构)** | C1 结论 2 |
| X6 | **MD3 fail**：20 处硬编码静态色架空 ColorScheme、亮色白底白字、Motion 六档全缺、无自适应布局 | C3 | **P1** | `tokens.dart:12-33,65-66,70` |
| X7 | **文案通道全断**：约 119 处硬编码中文（212 令牌命中），10 语 arb + TnStrings 全仓零接线；登录页把「端点待实测/待后端就绪」开发状态暴露给用户 | C3 + C1 + C2 | **P1** | `login_sheet.dart:318,350,431` |
| X8 | **YKG UI 零入口**：登录页无导出/导入、无密码弹层、无风险提示、文案 key 全缺 | C2 + C3 | **P1(需求)** | `login_sheet.dart` |
| X9 | 登录三 Tab 断点、搜索假分段/无分页/Future 竞态、评论菜单死链、歌词页 Timer 无 mounted 保护、SpSongTile 死代码 | C2 + C1 | **P1/P2** | 见 C2 报告 |
| X10 | 1500 行门禁达标（最长 playlist_page 576）、依赖方向/无影子桥/无反向 import 合规 | C1 | 合规 | C1 结论 1/6 |

## 2. 与用户痛点对应（阶段 A 七批总答案）

| 用户原话 | 已定位根因 |
|---|---|
| 「什么功能都用不了，MV 等等」 | MV **四重断点**（模块id抢占/端点恒null/hash冒充videoId/UI传错hash）；20028 验证死链；收藏假按钮；下载零入口；VIP 恒 false；boot 失败误判；十余个 logic/端点空壳 |
| 「UI 很不舒服」 | MD3 40/100 fail；`Sp.*` 静态色架空 ColorScheme、亮色白底白字；取色链 100% 断（ThemeController 不接 L4） |
| 「动画也是，细节瑕疵，不经看」 | Motion 2/10：仅 120/220ms 两档自定义时长，无 MD3 六档 easing/曲线/spring；业务轮询冒充动画、无中断治理 |
| 「相关文案也没改」 | 不是没翻译：10 语 arb 齐、键集一致，但 surface 零接线；~119 处硬编码中文；YKG/错误态 key 全缺；开发状态文案外泄 |
| 「YKG 浏览器链接登录」 | 全仓零实现；设计稿已定（成熟库算法 + 自有封装），L4 crypto / L5 ykg_logic / L6 注入接口 / L7 UI 四层落点待建，凭据素材现成 |

## 3. 阶段 A 结论（七批全收口）

A1–A7 共 21 份视角报告 + 7 份汇总 + 4 份复核裁定，全部落盘 `docs/deep_audit/` 并提交 git。
**质量 gate**：子代理静态发现 → 主会话可执行证据复核 → 证实的才进修复清单。
- 撤销误报 1：BigIntL.mul 溢出（RSA 改了会坏）。
- 确认并修正后果 2：AES Rcon 真 bug、QR off-by-one 真 bug（后果从"码字丢失"改为"布局错位"）。
- 确认跨层 P0 3：boot 失败误判、20028 验证死链、MV 四重断点。

**真 P0 修复清单（主会话亲修）**：
1. boot 失败误判（bridge_boot.dart:64 rejected=false）
2. 20028 验证死链（VerificationLogic + playback_session 接线）
3. MV 四重断点（模块注册 upsert / MvBrief.videoId / getVideoQualities(int) / UI 传 videoId）
4. 收藏假按钮 + 下载零入口（接真逻辑 + 补入口）
5. AES Rcon（换成熟库或补 Rcon 表 + FIPS 向量回归）
6. VIP 恒 false（bootstrap 传 session + KugouSession 补 vip 字段）

**真 P1 修复清单**：QR off-by-one、缓存固化/降级粗键、inflight clear 竞态、下载索引崩溃空窗、resource_cache 写失败静默、缓存域分散、L5 IO 直连 6 处、L6 越权状态机、main 跨层直连、取色链断、MD3 重构（页面改用 ColorScheme + motion 令牌 + 自适应）、i18n 接线 + YKG/错误态 key、TnStrings 死代码、端点层文案硬编码、登录端点待实测假承诺、YKG 四层实现。

## 4. 下一步（用户既定流程）

1. **主会话亲自修复**上述 P0/P1，跑本地门禁（tool/local_gate.sh 十道 + field_truth + 契约测试）+ 提交。
2. 修复验证通过后，**启动阶段 B 七批功能跨层检查**（B1 登录+YKG → B2 搜索榜单 → B3 播放 → B4 MV → B5 下载收藏歌单缓存 → B6 UI/M3/动画/取色 → B7 i18n/设置/导航/错误空态）。
3. A7 定时器 `a994eb00` 已取消（三份齐）。

---
*阶段 A 七批深度审查全部完成。修复由主会话执行，不用子代理改代码（用户既定规矩）。*
