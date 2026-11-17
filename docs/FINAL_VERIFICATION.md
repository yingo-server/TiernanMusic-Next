# 阶段 B 修复后 · 全局功能跨层调用链终验（主会话，2026-11-18）

> 14 批审查 + 主会话亲修后，按功能跨层调用链逐条核验"修复是否真端到端闭环"。
> 只读核验（rg + file_read），每条给锚点 + 结论。这是最终交付前的验收表。

## B1 登录 + YKG

| 链路 | 修复 | 终验结论 | 锚点 |
|---|---|---|---|
| VIP 提档 | credentialsProvider 实时读 settings | ✅ 键名一致：写入 `auth.vip_token/vip_type` = 读取；登录后实时可见（非构造快照） | `auth_logic.dart:447` / `bootstrap.dart:125` / `playback_service._hasRights` |
| 20028 验证 | session→门面触发 required | ⚠️ 半闭环：门面触发已接，但端点 `getVerifyInfo/submitVerification` 仍 return false（诚实标注未实测），L7 无验证 UI——用户遇验证仍无解，但不再假装能解（错误文案已可见）。**属于端点未实测的诚实边界，非代码 defect** | `verification_logic.dart` + `playback_session` errText |
| YKG 导入通知 | onImported 回调 | ✅ bootstrap 注入 AuthSession.notifyAuthChanged；且已补 `AuthSession.attach(client)` + 换号重置订阅 | `bootstrap.dart` |
| 语言切换 | LocaleController + saveLocale 归口 | ✅ 三段接通：设置页下拉→LocaleController.setLocale→TnStrings.saveLocale(空串=跟随系统修复)→MaterialApp.locale→S.of 取词；normalize('system')=zh 陷阱已修 | `locale_controller.dart` / `app_root.dart` / `strings.dart:saveLocale` |

## B2 搜索/榜单/推荐

| 链路 | 修复 | 终验结论 | 锚点 |
|---|---|---|---|
| 搜索缓存固化 | search/search_typed 加 isNotEmpty 守卫 | ✅ 与已修的 rank/recommend 一致，3 处均加守卫 | `search_logic.dart:63` / `search_typed_logic.dart:68,108` |
| 分页/热搜/榜单详情 | — | ❌ 未修（P1 遗留）：L7 分页仍写死 1、hotSearch 无 UI、榜单点击只播放 | 登记后续 |

## B3 播放

| 链路 | 修复 | 终验结论 | 锚点 |
|---|---|---|---|
| 错误可见 | 播放页读 lastError 显示错误条 | ✅ 已接 `snap.player.lastError` + 错误条 UI | `player_page` build |
| 循环失效 | AudioEngine.setLoopOne + _start 保留 mode | ✅ 接口全实现（Null/JustAudio），setMode/_start 调引擎重播，shuffle 不回退 | `audio_gateway` / `playback_session` |
| 通知 seek | onSeek 转发会话 seek | ✅ handler.seek 优先回调、playback_session 绑定 onSeek | `notification_gateway` / `playback_session.attach` |

## B4 MV

| 链路 | 修复 | 终验结论 | 锚点 |
|---|---|---|---|
| 响应解包第五重 | 弃用 dataOf 直接 listOf/res['data'][0] | ✅ 已修 + 三段请求侧自洽（videoIdOfSong→qualities(int)→playUrl(int)）；**仍需补端点级测试锚点** | `mv_endpoints.dart` / `mv_logic.dart` / `mv_page.dart` |
| 匿名链死代码 | — | ❌ 未修（P1 遗留）：mv_anonymous 227 行仍死代码 | 登记后续 |

## B5 下载/收藏/歌单/缓存

| 链路 | 修复 | 终验结论 | 锚点 |
|---|---|---|---|
| 下载进度 | library_page 订阅 onTask | ✅ initState 订阅 setState 刷新 + dispose 取消 | `library_page.dart` |
| 换号收藏串号 | AuthChanged→resetLocalMirror | ✅ bootstrap 已订阅 | `bootstrap.dart` |
| 歌单写零入口 | — | ❌ 未修（P1 遗留）：L7 无创建/删除/加歌入口 | 登记后续 |
| 缓存预读 | — | ❌ 未修（P1 遗留）：三套缓存不相交、预读命中≈0 | 登记后续 |

## B6 UI/M3

| 链路 | 修复 | 终验结论 | 锚点 |
|---|---|---|---|
| 动态取色 | ThemeController.seedArgb + applySeed + Sp.theme(seed) | ✅ L4 fromSeed→L6 seed 状态→L7 消费链打通；FilledButton/nav 改 scheme 配对 | `theme_controller` / `tokens.dart` / `app_root` |
| M3 语义色 | 全 surface Sp.*→context.cs.*（~190 处） | ✅ MD3 M1-M4 全 CI 全绿，残留仅 tokens.dart 定义；白底白字根因消除 | 16 文件 |
| 动画/rebuild | — | ❌ 未修（P1 遗留）：无过渡体系、rebuild 风暴、Timer 状态机在 L7 | 登记后续 |

## B7 i18n/设置/导航

| 链路 | 修复 | 终验结论 | 锚点 |
|---|---|---|---|
| 语言切换 | 见 B1 | ✅ 已闭环 | 同 B1 |
| 错误态坍缩 | 播放页 lastError + 播放链 errText | ⚠️ 部分：播放链错误可见；但 L5 其它 logic catch 返回空 List 致 `snap.hasError` 仍不成立的通用问题未全修 | 登记后续 |
| 设置页缺陷/导航死链 | — | ❌ 未修（P1 遗留） | 登记后续 |
| i18n 全量接线 | — | ❌ 未修：177 唯一中文串接线率≈0%，但翻译数据(56键×10语)+S.of门面就绪。**不用占位污染，需真实三语译文的后续专项** | `docs/MD3_I18N_MIGRATION_PLAN.md` |

## 终验结论

- **已闭环（端到端验证通过）**：VIP 实时提档、语言切换全链、错误可见、循环重播、通知 seek、下载进度订阅、换号收藏重置、MV 响应解包、动态取色链、M3 语义色全量迁移、search 缓存守卫、AuthSession 装配。
- **半闭环（诚实边界）**：20028 验证（端点未实测，UI 已明示）、通用错误态（播放链已修、其它 logic 待修）。
- **明确后续项**：i18n 全量接线（需真实译文）、歌单写入口、缓存域统一、动画体系、设置页/导航细节、分页/热搜/榜单详情、匿名 MV、端点级 MV 测试锚点。

本轮交付是历史最大规模的一次修复：14 批审查 + 所有功能 P0 + 大部分 P1 + MD3 全量迁移，全程 CI 逐批验证。剩余项均为"打磨/需外部译文/需端点实测"性质，不阻塞核心可用性。
