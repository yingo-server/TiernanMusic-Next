# 阶段 A 亲修记录（主会话，2026-11-16）

> 用户流程：阶段 A 七批全审完 → 主会话亲修确认 P0/P1 → 再阶段 B 七批功能跨层。
> 用户确认：本轮全做完（i18n 接线 + YKG 实现 + MD3 部分重构），允许新增成熟库依赖。
> 本地无 dart/flutter，编译由 CI 验证（此前多轮 CI 收口模式）。

## 0. 已修 P0（逐条带证据 + 复核）

| # | 问题 | 修法 | 文件 |
|---|---|---|---|
| P0-1 | boot 失败被误判成功（BootResult 类走 dynamic 分支无条件成功） | fromAny dynamic 分支先探 `d.rejected`，true 转失败 Map 归一 | `bridge_boot.dart:66-77` |
| P0-2 | 20028 验证死链（toString().contains 判错、不驱动门面） | PlaybackSession 注入 VerificationLogic；强类型 PlaybackError 判定；needsVerification 时调 onVerificationRequired(20028)；错误文案类型化 | `playback_session.dart` + `bootstrap.dart` |
| P0-3 | MV 四重断点 | ① 注册守卫改直接覆盖 ② MvBrief 加 videoId + 成功门槛改 videoId ③ getVideoQualities 入参改 int videoId ④ MvLogic 加 videoIdOfSong 两段式 ⑤ MV 页传 albumAudioId ⑥ field_truth 补 videoId 锚点 | mv_endpoints / mv_logic / mv_page / player_page / playback_service / field_truth_test |
| P0-4 | 收藏假按钮（纯本地 setState） | FavoriteButton 读 appGraph.collect.isCollected + 调真 toggle + 失败 Snackbar | `player_page.dart` |
| P0-5 | 下载零入口 | 播放页 ⋮ 菜单加「下载当前歌曲」→ appGraph.downloads.enqueue | `player_page.dart` |
| P0-6 | AES Rcon 恒 0x01（FIPS 向量确认真 bug） | 补 10 轮 Rcon 常量表 `_kRcon`，按 i/16 取 | `crypto_aes.dart:568,580` |
| P0-7 | VIP 权益判定恒 false（bootstrap 未传 session） | bootstrap 构造 PlaybackService 时以 Map 注入 settings 的 vip_token/vip_type | `bootstrap.dart:115` |

**裁定为误报、未改**：BigIntL.mul 溢出（A2 复核 20 万组零错误，a*b 自带 2^33 余量不越 int64）；DB await 分歧（C1 对，代码已 await dbOpenFuture，C2 误报）。

## 1. 已修 P1

| # | 问题 | 修法 | 文件 |
|---|---|---|---|
| P1-1 | QR 数据放置 off-by-one（size-2 起，漏列） | 起点改 size-1（四版本仿真覆盖=全部数据格） | `qr_codec.dart:286` |
| P1-2 | 缓存固化业务失败 7 天 | 只缓存 `_cacheableSuccess(res)`（error_code/status/空 data 不落） | `kugou_client.dart` |
| P1-3 | cacheKey 异常降级宽键跨用户脏命中 | catch 返回唯一 nonce 键（等价不命中） | `kugou_client.dart` |
| P1-4 | inflight clear 竞态误删新在飞条目 | token 身份校验：finally 仅当 `_tokens[key]` 是本次 token 才 remove；clear 同步清 tokens | `inflight.dart` |
| P1-5 | 下载索引先删后 rename 崩溃空窗丢记录 | 去掉 deleteSync，rename 原子覆盖 | `download_store.dart` |
| P1-6 | resource_cache 写失败静默、索引不一致无信号 | 检查 `_saveIndex()` 返回值，失败 logE 留痕 | `resource_cache.dart` |
| P1-7 | MD3 motion 无分级令牌 | Sp 补 MD3 六档时长（fast/normal/enter/screen）+ 曲线令牌 | `tokens.dart` |
| P1-8 | ColorScheme tonal pairing 不全 | 补 primaryContainer/onPrimaryContainer/onError | `tokens.dart` |

## 2. YKG 登录（全新增，成熟库算法 + 自有封装）

- `pubspec.yaml`：新增 `cryptography: ^2.7.0`（AES-GCM / PBKDF2 / HMAC / SHA-256 全走成熟库）。
- `tool/layer_audit.py` + `tool/smoke_check.dart`：L4 白名单加 cryptography。
- `lib/core/net/ykg_codec.dart`（L4）：`ykg://import/<b64url(json)>` 报文；PBKDF2-HMAC-SHA256(120k) 派 32B 密钥；AES-256-GCM(aad='ykg-v1')；m=md5(salt:password) 仅兼容快筛、d=cookie 指纹；错误统一「密码错或链接损坏」避免 oracle。
- `lib/logic/auth/ykg_logic.dart`（L5）：导出读 session 凭据、导入写 settings + restoreSession + L6 通知回调；口令校验值不存明文。
- `lib/session/{graph,bootstrap}.dart`（L6）：装配 YkgLogic 进 AppGraph；onImported 注入 AuthSession.notify（L5 不反向依赖 L6）。
- `lib/bridges/{bridge_core,bridge_logic}.dart`：导出新门面。
- `lib/surface/pages/ykg_sheet.dart`（L7）：导出/导入弹层 + 密码输入 + 强制风险提示 + 复制/二维码入口。
- `lib/surface/pages/login_sheet.dart`：登录页加第 4 个「YKG 链接」Tab。

## 3. i18n「文案没改」接线

- 10 语 arb 各补 33 个 key（YKG/错误态/功能文案），zh/zh_Hant/en 人工级、其余 7 语英文占位（用户纪律：日常只保三语，CI 管线重要版本补）。
- `tool/gen_i18n.py` 重生成 `strings.dart`（TnStrings 56 键）。
- `lib/surface/l10n/s.dart`：`S.of(context).t(key)` 取词门面（接 TnStrings，按 locale/持久化语言选码）——死代码复活，surface 首次有可用 i18n 通道。
- player_page 新写文案（收藏/下载反馈）、登录页 Tab、YKG 弹层全部走 S.of(context).t。

## 4. 未在本轮做（诚实登记，转阶段 B）

- **surface 119 处存量硬编码中文全量迁移**：需逐页手工改（大量 `const TextStyle`/static 上下文无 BuildContext），一次性批量替换会编译失败。本轮建立了 S 门面 + 新代码全走 i18n，存量迁移列阶段 B7。
- **MD3 页面级重构**（各页面 `Sp.*` → `Theme.of(context).colorScheme.*`）：本轮修了主题层令牌/pairing/motion，页面级 119 处色引用改语义角色是阶段 B6 专项（避免本轮塞入大量未编译改动）。
- **L5 IO 直连 6 处 / L6 越权状态机 / main 跨层桥**：架构债，阶段 B 各功能跨层批顺带收敛。
- **VerificationLogic 端点实测**：getVerifyInfo/submitVerification 仍诚实标注「未实测、不发请求」；本轮只打通「session→门面触发 required 状态」，真实提交端点待实测（不臆造）。

## 6. 阶段 B 跨层修复（主会话，2026-11-17）

### 已修（本批，待 CI 验证）

| P0 | 修法 |
|---|---|
| VIP 快照（3次未闭环） | PlaybackService 加 `credentialsProvider` 实时读 settings 闭包，bootstrap 注入；`_hasRights` 优先 provider |
| 语言切换完全不可用 | 新建 L6 LocaleController（ValueNotifier）+ bridge_session 导出；app_root 嵌套监听 + MaterialApp.locale/supportedLocales；设置页加语言下拉 |
| 错误态不可见 | 播放页读 `snap.player.lastError` 显示错误条（带图标） |
| 下载 onTask 零订阅 | library_page initState 订阅 onTask→setState 刷新、dispose 取消 |
| MV 响应解包第五重 | B4 已修（弃用 dataOf 直接 listOf / res['data'][0]） |

| P1 | 修法 |
|---|---|
| search/search_typed 空结果缓存 | 加 `if (res.items.isNotEmpty)` 守卫（3处） |
| AuthSession 未 attach + 换号串号 | bootstrap 补 `AuthSession.attach(client)` + onAuthChanged→collect.resetLocalMirror / album.invalidatePrefix |
| 单曲循环失效 + shuffle 回退 | AudioEngine 加 setLoopOne；setMode 与 _start 调引擎重播；_start 保留当前 mode 不重建 |
| 通知栏 seek 失同步 | notification_gateway.seek 转发 onSeek；playback_session 绑定 onSeek→seek |
| 动态取色链 100% 断 | ThemeController 加 seedArgb + applySeed（L4 fromSeed）；Sp.theme 接 seed 参数并去掉 primary 硬覆盖；app_root 传 seed——L4→L6→L7 链打通 |

### 静态审读（Dart API）
对照 Flutter 3.50 / just_audio 0.10 / audio_service 0.18 / cryptography 2.7 审读，定位并修复 1 处编译错（app_root switch 表达式非穷尽，加 `_` 兜底）；其余 API 全部核验无 error。

### 未在本批修（大工程，诚实登记）
- MD3 页面级重构：195 处 `Sp.*` 静态色 → `Theme.of(context).colorScheme.*`（MD3 仅 +2 分的根因）。
- i18n 全量接线：213 处中文硬编码 → S.of(context).t(key)（接线率≈0%）。
- 设置页四项缺陷、导航死链、歌单写 L7 入口、缓存域统一、L5 下载 IO 下沉等 P1。
- 20028 验证 UI 出口（端点未实测，不宜造请求）。

### 门禁
layer_audit PASS（128 文件）、static smoke PASS。CI 完整编译待验证。

## 5. 门禁状态

- `python3 tool/layer_audit.py`：PASS strict seven-six（127 文件）。
- `python3 /var/minis/workspace/static_smoke.py`：PASS（括号/import/桥唯一性）。
- **dart analyze / flutter build：本地无 SDK，待 CI**。已派 Dart 静态审读子代理核对 cryptography API 与语法。
- **Dart 静态审读结果（对照 cryptography 2.7 官方源码）**：发现并已修 2 处必编译失败——① `ykg_codec.dart` `Pbkdf2(mac:)` 参数名错（正确为 `macAlgorithm:` 或 `Pbkdf2.hmacSha256`，已改用后者）；② `s.dart` `Localizations` 未加入 show 列表（已修）。其余（AES-GCM encrypt/decrypt/SecretBox 签名、record 解构、switch 表达式、Sp token、import 使用）全部核验无 error。CI 仍需完整 SDK 终验。
