# A1 批 · C3 用户痛点专项视角 · 全局资料盘点

> 子代理：A1-C3｜视角：用户痛点（文案 / YKG / 功能可达性 / M3 基线）
> 契约：`docs/DEEP_AUDIT_14_BATCH_PLAN.md` §0 76 原则
> 本轮只读，唯一写入为本文件（append）。

---

## 2026-11-16 · i18n 基础设施：arb 与 strings.dart 一致性核对

### 视角 C3 · lib/l10n/app_zh.arb:1-26 / app_en.arb:1-23 · P0 · 文案 / i18n
证据：
- `lib/l10n/app_zh.arb` 键数 = 21（含 `appTitle`），`lib/l10n/app_en.arb` 键数 = 20（**缺 `@@locale` 之外的差异仅为 zh 多一条 `@appTitle` 元数据**；实际业务键两语同为 20 个：search/playlist/library/settings/player/play/pause/next/prev/login/logout/theme/cache/about/comments/mv/lyrics/download/favorite）。
- 其余 8 语（de/es/fr/ja/ko/pt/ru/zh_Hant）键集与 en 完全相同，均为同一 20 业务键。
- `lib/core/l10n/strings.dart` 内嵌 `_kCatalog`：10 语 × 21 键（含 appTitle）= 209 条目（`rg -c "^\s+'[a-zA-Z]+':"` = 209），与 arb 键集**一一对应，无重复、无缺失、无占位文案**。
问题：arb 与手写常量表本身是**一致的、无缺口**；真正的缺口是**键太少**（20 个业务键覆盖不了全部界面文案）与**整套 i18n 是死代码**（见下条）。
建议：把 arb 扩到覆盖全量界面文案（登录/账号/密码/导出/错误/空态/权限/YKG），并把 `strings.dart` 的 10 语手工复制改为由 arb 生成（CI 校验键集），避免双份维护漂移。
76 合规：不涉及（仅文案层）。

### 视角 C3 · lib/core/l10n/strings.dart:1-327 · P0 · 文案 / i18n · 死代码
证据：
- 全仓 `rg -n 'TnStrings|\.tr\(' lib`（排除 strings.dart 自身）**仅命中 1 处**：`lib/bridges/bridge_core.dart:49: export '../core/l10n/strings.dart' show TnStrings;` —— 即**只有 export，没有任何调用点**。
- `lib/surface/l10n/l10n_helper.dart` **不存在**（`ls lib/surface/l10n` → No such file or directory），但 `l10n.yaml:3-4` 注释仍声称「运行时取词走 lib/surface/l10n/l10n_helper.dart 的硬编码 const Map」——**注释指向的文件已不存在**。
- `pubspec.yaml:30` 有 `generate: true`、`pubspec.yaml:12` 引入 `flutter_localizations`，但全仓 `rg 'AppLocalizations|gen_l10n|localizationsDelegates'` **零命中**（除 pubspec 自身）。
- `lib/core/l10n/strings.dart:249-252` `appLocaleCode()` 返回 `String?`，**无任何消费者**。
问题：运行时**完全不走 i18n**——所有界面文字是硬编码中文；arb/strings.dart 是 209 行死代码；`ui.locale` 设置项（`saveLocale`/`loadLocale`）写入后无人读取，语言切换是「写了不生效」。
建议：① 打通 `MaterialApp.localizationsDelegates` + `supportedLocales`；② 或删除 arb/strings.dart 并承认单语，避免维护两份假 i18n；③ 修正 l10n.yaml 注释指向的失效路径；④ 设置页语言项须真正驱动重建。
76 合规：不涉及（但与 §0 L4「l10n 常量」职责脱节：L4 提供了门面，L7 从不消费）。

---
## 2026-11-16 · 全仓硬编码中文盘点（应进 i18n 未进）

### 视角 C3 · lib/**（36 文件 / 290 行）· P0 · 文案
证据：`rg -nP "('[^'\n]*[\x{4e00}-\x{9fff}][^'\n]*'|\"[^\"\n]*[\x{4e00}-\x{9fff}][^\"\n]*\")" -g '*.dart' lib --stats`
→ **308 matches / 290 matched lines / 36 files**（123 files searched）。按文件计数（行数）：

| 文件 | 中文硬编码行数 | 是否面向用户 |
|---|---|---|
| lib/core/l10n/strings.dart | 44 | i18n 本体（正常） |
| lib/surface/pages/login_sheet.dart | 32 | **是（登录页全部文案）** |
| lib/surface/pages/settings_page.dart | 28 | **是（设置页全部文案）** |
| lib/surface/pages/home_page.dart | 23 | **是** |
| lib/surface/pages/player_page.dart | 20 | **是** |
| lib/surface/pages/search_page.dart | 18 | **是** |
| lib/surface/pages/playlist_page.dart | 18 | **是** |
| lib/surface/pages/mv_page.dart | 18 | **是** |
| lib/surface/pages/library_page.dart | 17 | **是** |
| lib/surface/pages/lyrics_page.dart | 7 | **是** |
| lib/init/main.dart | 6 | **是（启动失败页）** |
| lib/core/net/endpoints/mv_endpoints.dart | 6 | 画质档位 label（**是**，随 UI 展示） |
| lib/core/net/endpoints/comment_endpoints.dart | 5 | **是（错误文案直出）** |
| lib/core/net/endpoints/collect_endpoints.dart | 5 | 否（Log） |
| lib/surface/pages/search_tile_widgets.dart | 4 | **是** |
| lib/surface/pages/login_account_section.dart | 4 | **是** |
| lib/logic/auth/verification_logic.dart | 4 | **是（blockedReason 直出）** |
| lib/core/net/endpoints/recommend_endpoints.dart | 4 | 否（异常消息） |
| lib/core/net/endpoints/mv_anonymous.dart | 4 | 否（Log） |
| lib/logic/catalog/collect_logic.dart | 3 | 否（Log） |
| lib/surface/shell.dart | 2 | **是** |
| lib/surface/design/mini_bar.dart | 2 | **是** |
| lib/session/playback_session.dart | 2 | **是（ErrorAction 文案直出）** |
| lib/logic/player/player_state.dart | 2 | 否（注释/枚举说明） |
| lib/surface/pages/home_state_views.dart | 1 | **是** |
| lib/surface/design/components.dart | 1 | **是** |
| lib/logic/player/playback_service.dart | 1 | 否（Log） |
| lib/logic/download/download_models.dart | 1 | 否（注释） |
| lib/logic/download/download_commit.dart | 1 | 否（Log） |
| lib/logic/catalog/comment_logic.dart | 1 | **是** |
| lib/logic/auth/account_logic.dart | 1 | **是** |
| lib/core/net/signing.dart | 1 | 否（注释） |
| lib/core/net/endpoints/search_endpoints.dart | 1 | 否（注释） |
| lib/core/net/endpoints/misc_endpoints.dart | 1 | 否（注释） |
| lib/core/memory/cache_keys.dart | 1 | 否（注释） |
| lib/core/database/entities.dart | 1 | 否（注释） |

问题：用户可见文案**约 200+ 处**全部硬编码中文，arb 20 键一个都没用上 → 换语言功能等于没有（对应用户原话「相关文案也没改」）。
建议：按「登录 / 账号 / 密码 / 导出 / 错误 / 空态 / 权限」七类建立 arb 键（见文末《文案缺口清单》），L7 只允许通过 `TnStrings.tr(key)` 取词，禁止再出现中文字面量。
76 合规：不涉及。

### 视角 C3 · lib/surface/pages/login_sheet.dart:110-112,318,350-351,431 · P0 · 文案 / 占位文案
证据：
- `login_sheet.dart:110-112`：`Tab(text: '扫码') / '验证码' / '密码'` —— 三个登录 Tab 全是硬编码中文。
- `login_sheet.dart:318`：`_msg = '验证码发送失败（接口待实测）';` —— **把「待实测」这种研发内部状态词直接暴露给用户**。
- `login_sheet.dart:350-351`：`'验证码登录端点待实测（needs probe）'` —— **把英文内部术语 needs probe 暴露给用户**。
- `login_sheet.dart:431`：`SnackBar(content: Text('密码登录待后端就绪'))` —— **用户按下密码登录后被告知「后端就绪」，这是占位文案而非用户语言**。
- `login_sheet.dart:153,165,173,187,206,212,215`：二维码页 6 处状态提示全硬编码（'正在获取二维码…'、'登录能力未装配'、'二维码已过期，请下拉重试或退出重开' 等）。
问题：登录页是用户最常访问、也是唯一「不工作」的重灾区，文案既未 i18n 化又混入了研发口径（待实测 / needs probe / 后端就绪 / 能力未装配），用户完全无法理解发生了什么。
建议：① 全部入 arb；② 「待实测/能力未装配/needs probe」改为面向用户的失败态（例：「登录服务暂不可用，请稍后重试」+ 错误码）；③ 密码登录未就绪时**禁用按钮并给前置说明**，而不是点击后弹「后端就绪」。
76 合规：不涉及。

### 视角 C3 · lib/surface/pages/login_account_section.dart:34,47,67,79 · P1 · 文案 / 账号
证据：`:34 '已登录账号'`、`:47 '暂无账号，登录后将自动保存到这里'`、`:67 '账号 ${rec.accountId}'`、`:79 tooltip: '移除账号'`。
问题：账号区文案全硬编码；且 `账号 ${rec.accountId}` 直接显示内部 accountId（可能是长数字串），对用户无意义。
建议：入 arb；账号展示改为昵称优先、无昵称才回落脱敏标识（不要裸 accountId）。
76 合规：不涉及。

### 视角 C3 · lib/surface/pages/settings_page.dart:65,170-187,199-282 · P1 · 文案 / 登录与设置
证据：`:170 title: Text(_loggedIn ? '已登录' : '未登录')`、`:174 '扫码登录后同步收藏与历史'`、`:183 '登出'`、`:187 '扫码登录'`；`:65 _nickname = name.isEmpty ? (uid.isEmpty ? '' : '酷狗用户 $uid') : name;`；设置页其余 24 处（音质档位/播放倍速/主题模式/跟随系统/亮/暗/纯黑/清理缓存/版本 等）全硬编码。
问题：设置页是用户唯一能感知「这版做成了什么」的地方，全中文硬编码；且登录入口只写「扫码登录」，**没有任何 YKG 链接登录 / 导出入口的文案**（用户明确要求的新能力在 UI 上零提示）。
建议：入 arb；新增「YKG 链接登录 / 导出登录链接 / 输入密码解锁」三组文案并预留入口（见《文案缺口清单》）。
76 合规：不涉及。

### 视角 C3 · lib/surface/pages/mv_page.dart:92-149,226-255,291-298 · P1 · 文案 / MV 空态与错误
证据：`:92 '缺少歌曲 hash，无法查询 MV'`、`:97 '装配图未就绪（MV 门面不可用）'`、`:104 '这首歌暂无可播 MV'`、`:132 'MV 地址不可用（可能被权限拦截）'`、`:139 'MV 地址为空'`、`:149 '不支持的 MV 链接协议：$url'`、`:177 'MV 加载失败：$e'`、`:226 '正在加载 MV…'`、`:235 '暂无 MV'`、`:243 'MV 不可用'`、`:254 '播放器已释放'`、`:291 tooltip '暂停'/'播放'`、`:298 'MV 内嵌播放' / '档位 $_quality'`。
问题：MV 错误文案暴露内部术语「装配图未就绪」「MV 门面不可用」「可能被权限拦截」，且**没有区分 VIP/匿名/无版权三态**，用户看到的是技术黑话而不是「这首歌需要会员」这类可行动提示。
建议：入 arb；错误分三类文案（需会员 / 该歌曲暂无 MV / 网络失败可重试），禁止把 $e 原文直出给用户。
76 合规：不涉及。

### 视角 C3 · lib/surface/pages/search_page.dart:24,33,46-53,188,338,377,396,406,441-459 · P1 · 文案 / 搜索
证据：`:24 const NavEntry('搜索', 'search')`；`:33 kSearchSegments = ['歌曲','歌单','专辑','歌手','歌词']`；`:46-53` 热词硬编码「华语/流行/摇滚/民谣/电子/轻音乐/古风/情歌」；`:188 hintText: '搜索歌曲、歌单、歌手'`；`:338 '热门分类'`；`:377 '暂无搜索历史'`；`:396 '历史记录'`；`:406 '清空'`；`:441 '暂无结果'`；`:452 message: '搜索失败'`；`:459 '没有找到与「$_query」相关的歌曲'`。
问题：导航标题、Tab、热词、搜索历史/空态全部硬编码；**搜索分段缺「MV」段**（用户点名 MV 不可用，而搜索也无 MV 入口）。
建议：入 arb；热词改为可配置/来自接口；分段补 MV 或明确产品决策。
76 合规：不涉及。

### 视角 C3 · lib/surface/pages/{home,playlist,library,player,lyrics}_page.dart · P1 · 文案 / 首页·歌单·曲库·播放·歌词
证据（抽样）：
- `home_page.dart:130 '首页'`、`:139 tooltip '搜索'`、`:192-284` '每日推荐/推荐歌单/排行榜' 及其失败空态（'每日推荐加载失败'、'暂无每日推荐（登录后可能可见）'、'榜单加载失败'、'暂无榜单数据'）、`:343 '未知歌曲'`、`:376 '未命名歌单'`、`:416 '榜单'`、`:426 '每周更新'`。
- `playlist_page.dart:52-53 Tab '推荐'/'我的'`、`:124 '推荐歌单加载失败'`、`:128 '暂无推荐歌单'`、`:208 '我的歌单加载失败'`、`:212 '还没有收藏的歌单'`、`:334 '歌单详情'`、`:361 '该歌单暂无曲目'`、`:418/:460 '未命名歌单'`、`:424 '曲目数未知'`、`:499 '未知歌曲'`。
- `library_page.dart:86-88 Tab '本地曲库'/'最近播放'/'下载管理'`、`:209 '曲库还是空的'`、`:219 '还没有播放记录'`、`:236 '数据能力未装配'`、`:247 '加载失败'`、`:295 '下载管理不可用'`、`:296 '下载能力未装配'`、`:302 '暂无下载任务'`、`:303 '在歌曲菜单里选择下载'`。
- `player_page.dart:87 '取消收藏'/'收藏'`、`:110 '播放速度'`、`:139 '音质'`、`:167 '歌词'`、`:178 '评论'`、`:189 '查看 MV'`、`:205 '个人 FM'`、`:215 'FM 暂无可用曲目（端点待实测）'`、`:247 '暂无播放'`、`:248 '播放队列为空'`、`:295 '试听音源'`、`:366-391 tooltip '随机'/'上一首'/'下一首'/'循环'`。
- `lyrics_page.dart:185 '返回'`、`:192-193 '原文'/'翻译'`、`:211 '歌词加载失败'`、`:218 '暂无歌词'`。
- `lib/session/playback_session.dart:149 ErrorAction('引擎播放失败')`、`:239 '播放源不可播或需登录'` —— **错误文案在 L6 层硬编码**，违反 L4-l10n/文案归口，且用户看到「播放源不可播」这种黑话。
问题：五个主页面 100+ 处硬编码文案；空态/错误态缺「下一步动作」；「端点待实测」「能力未装配」等研发词直接上屏；错误文案下沉到 session 层，跨层违反 76 的「l10n 常量在 L4」归口。
建议：① 全部入 arb 并按七类归组；② 错误文案只在 L4/l10n 定义，session/logic 传错误码不传中文；③ 空态统一「图标+标题+副标题+可行动按钮」。
76 合规：涉及 —— `lib/session/playback_session.dart:149,239` 在 L6 直接写死中文用户文案，l10n 常量归 L4（L4 core/l10n），L6 应只暴露状态/错误码。

### 视角 C3 · lib/core/net/endpoints/mv_endpoints.dart:141-145,175 · P2 · 文案 / 画质档位
证据：`:141 'ld': '流畅 270P'`、`:142 'sd': '标清 432P'`、`:143 'hd': '高清 720P'`、`:144 'fhd': '全高清 1080P'`、`:145 'qhd': '超高清 540P'`、`:175 label: 'MKV 超高清'`。
问题：画质档位的中文 label 硬编码在 **L4 网络端点层**（应属展示层或 l10n 常量）；且档位命名不规范：270P 叫「流畅」、432P 叫「标清」、1080P 叫「全高清」而 540P 叫「超高清」——**超高清 < 全高清，命名倒挂**。
建议：label 迁至 l10n/L7；档位名按分辨率升序规范（流畅 270P / 标清 432P / 高清 720P / 超清 1080P / 极高 540P→建议删或改 4K）。
76 合规：涉及 —— L4 网络端点层不应持有面向用户的中文文案（归口 L4 l10n 常量亦可，但需统一）。

### 视角 C3 · lib/core/net/endpoints/comment_endpoints.dart:174-194 + lib/logic/catalog/comment_logic.dart:81 · P2 · 文案 / 错误
证据：`:174 '接口返回非 JSON（可能被安全策略拦截，$msg）'`、`:176 '接口响应异常（$msg）'`、`:178 '接口响应异常'`、`:194 '歌曲标识无效，无法加载评论'`；`comment_logic.dart:81 '评论门面异常，请稍后重试'`。
问题：后端错误文案直出 UI；「安全策略拦截」「评论门面」是内部黑话。
建议：错误码化 + arb 映射，UI 只显示「评论加载失败，点击重试」。
76 合规：不涉及（文案归属问题）。

---
## 2026-11-16 · YKG 登录：现状盘点 + 密码学设计输入

### 视角 C3 · 全仓 · P0 · YKG 现状
证据：`rg -ni 'ykg' -g '*.dart' .` → **零命中**（仅本报告与 docs 计划文件命中）。
问题：**YKG 协议在本仓 100% 未实现**——没有链接报文结构、没有导出入口、没有 base64 封装、没有加盐密码校验、没有输密码解锁交互。用户在 `docs/research_legacy_login_url.md` 提到的旧版能力尚未迁入。
建议：按本文《YKG 方案设计输入》新建 `lib/core/net/endpoints/ykg_endpoints.dart`（L4，端点一文件一模块）+ `lib/logic/auth/ykg_logic.dart`（L5）+ L7 登录页第 4 个 Tab；严守 76 §0 第 6 条（端点分文件）、第 9 条（能用成熟库就用成熟库：`crypto` 包提供 HMAC/SHA/PBKDF2，避免再手写 MD5 类）。
76 合规：不涉及（新增须落 L4/L5/L7 合法层）。

### 视角 C3 · lib/core/net/signing.dart:70-266 · P1 · 密码学原语 · 可复用性
证据（现有原语清点）：
| 原语 | 现状 | 位置 | 可复用性 |
|---|---|---|---|
| **MD5** | ✅ 纯 Dart 完整实现（RFC 1321，小写 hex） | `signing.dart:70 class Md5`、`:266 String md5Hex(String s)`，经 `bridge_core.dart:141` 导出 `KugouSign, Md5, md5Hex` | ✅ 可直接复用，**但 MD5 不应用于新设计的口令校验**（无抗碰撞/无慢速，只能用于兼容上游签名的 legacy 字段） |
| **AES-128-CBC + PKCS7** | ✅ 纯 Dart 完整实现 | `crypto_aes.dart:684 class AesCbc`、`CryptoException`(:19)、hex 工具(:774,:785) | ✅ 可用于**报文加密**（但 AES-CBC 无认证，需配 HMAC） |
| **RSA (PKCS1-v1_5)** | ✅ 纯 Dart，含 PEM base64 + BigInt 模幂 | `crypto_rsa.dart:50 rsaEncrypt2`、`:133 playlistAesDecrypt`、`:91 PlaylistAesResult`；`crypto_rsa_raw.dart`、`crypto_bigint.dart class BigIntL` | ⚠️ 只有**加密**没有解密实现（`rsaEncrypt2` 仅 public encrypt）；**YKG 解密场景缺 RSA 私钥解密**，但**本方案不需要 RSA**（链接导出方自己加密，导入方需解密 → 见下方候选取舍） |
| **Base64** | ⚠️ 仅 `crypto_rsa.dart:32 _base64EncodePadded` + `:161 _b64ToBytes`，**均为 private**，且 encoder 强制 PKCS#7 式 padding（`pad > 2` 抛异常） | `crypto_rsa.dart` | ❌ 不可直接复用为通用 base64（`_b64ToBytes` 拒绝非 4 倍数长度且要求 padding 合法）→ **新设计应直接用 `dart:convert` 的 `base64UrlEncode/base64Decode`**（YKG 链接需 URL-safe） |
| **HMAC** | ❌ 无 | 全仓 `rg -i hmac` 零命中 | 需引入 `crypto` 包（§0 第 9 条） |
| **SHA-256 / SHA-512** | ❌ 无（`bootloader.dart:66,71` 注释提到构建期用 sha512，但仓内无实现） | — | 需引入 `crypto` 包 |
| **PBKDF2 / scrypt / Argon2** | ❌ 无 | `rg -i 'pbkdf2|scrypt|argon2'` 零命中 | 需引入 `crypto`（PBKDF2-HMAC-SHA256）或 `argon2` 包 |
| **CSPRNG** | ✅ `Random.secure()` 可用 | `crypto_rsa.dart:59`、`:105`、`auth_endpoints.dart:155` | ✅ 可复用（盐/IV/nonce 生成） |
| **常量盐来源** | ⚠️ 现有盐全是**上游协议常量**（`signing.dart:10-16` androidSalt/webSalt/registerSalt/signKeySalt/trackerKeySalt/signParamsSalt），**不是用户口令盐**，不可用于 YKG | `signing.dart:9-16` | ✅ 可用作**域分离盐**（domain separation，见设计输入） |
| **会话/账号凭据存储** | ✅ `AccountRecord`（`entities.dart:113-137`）已持久化 `token/mid/dfid/cookieBlob/vipType`；`account_logic.dart:58` 从 `auth.cookie` 读 cookie 串，`:94` 解析回 `session.cookies` | `lib/core/database/entities.dart:113`、`lib/logic/auth/account_logic.dart:54-120` | ✅ **YKG 导出的原始素材已现成**（cookieBlob + token + mid + dfid），无需新建凭据层 |

问题：可复用的**密码学原语只有 MD5/AES/RSA-encrypt/Base64-private/Csprng**；**没有 HMAC、没有 SHA-256、没有口令 KDF、没有通用 URL-safe Base64**，因此 YKG 的「加盐密码校验」不能靠现有实现直接落地。
建议：新增 `lib/core/net/crypto_kdf.dart`（L4）封装 `crypto` 包的 PBKDF2-HMAC-SHA256 与 SHA-256/HMAC；同时把 base64 统一走 `dart:convert` 的 **base64Url**（避免链接里出现 `+` `/` `=`）。
76 合规：建议落 L4 core/net，与既有 crypto_* 同层同风格（纯 Dart，无 UI 依赖）。

### 视角 C3 · lib/logic/auth/account_logic.dart:54-120 + lib/core/database/entities.dart:113-137 · P1 · YKG 导出素材
证据：`account_logic.dart:58` `..cookieBlob = _settings.getString('auth.cookie') ?? ''`；`:94` `for (final pair in rec.cookieBlob.split(';'))` 解析为 cookie map；`:116` `..setString('auth.cookie', rec.cookieBlob)`；`entities.dart:124-133` 持久化 `token/mid/dfid/cookieBlob`。
问题：账号快照具备导出所需全部字段，但**只存在 Isar 库与 settings 里，没有任何导出/分享/剪贴板路径**（`rg '导出|Clipboard|share'` 在 lib 下零命中）。
建议：新增 `AuthLogic.exportYkgLink(...)`（L5）→ 返回链接字符串；L7 用 `Clipboard` + 系统分享；导出前**必须**走一次「输密码设保护密码 → 生成链接」流程，不得提供无保护导出。
76 合规：不涉及（新增于 L5，经 bridge_logic 暴露）。

---
## 2026-11-16 · 功能可达性初盘（含 MV 点名链路）

### 视角 C3 · lib/surface/pages/mv_page.dart:32 + lib/logic/catalog/mv_logic.dart:32 · P0 · 功能可达性 / MV
证据（入口 → 逻辑 → 网络 三段）：
- **入口**：`lib/surface/pages/player_page.dart:184-200` 播放页 ⋮ 菜单 `ListTile(title: Text('查看 MV'))` → `registerMvModule()` → `Navigator.push(MvPage(songHash: current?.hash ?? ''))`。
- **逻辑**：`lib/logic/catalog/mv_logic.dart:32 qualities(String mvHash)` → `:48 mv.getVideoQualities(_client, h)`；`:67 playUrl(...)` → `:90 mv.getVideoUrl(...)`。
- **网络**：`lib/core/net/endpoints/mv_endpoints.dart:301 getVideoQualities(client, mvHash)` → body `data:[{video_id: h}]`（`:318-322`）。
- **断点**：MV 页把**歌曲 hash**（`current.hash`）当作 **MV video_id** 直接送进 `getVideoQualities`。正确链路必须先 `getMvBySong(client, albumAudioId)` 拿 `MvBrief.hash`（MV hash）再查档位——该链路**只存在于** `lib/logic/player/playback_service.dart:291`（MV **音频**兜底），**MV 页面链路完全没有它**。
问题：用户点「查看 MV」→ 用歌曲 hash 当 video_id 请求 `/v1/video` → 必然返回空 → `mv_page.dart:104` 显示「这首歌暂无可播 MV」。**这就是用户说的「MV 等等用不了」的根因**：不是网络问题，是 hash 语义错配。
建议：MV 页链路改为 `song.albumAudioId → getMvBySong → mvBrief.hash → getVideoQualities → getVideoUrl`；建议把 `playback_service.resolveMvAudioFallback` 的两段式抽到 `MvLogic` 内作为唯一实现（避免两处重复且不一致）。
76 合规：不涉及。

### 视角 C3 · lib/surface/pages/mv_page.dart:31-33 · P1 · 功能可达性 / MV
证据：`:32 WidgetBuilder? get builder => (_) => const MvPage(songHash: '');` —— **模块注册表里的 `/mv` 路由恒以空 hash 构建**；`lib/surface/shell.dart:30` 调用 `registerMvModule()` 注册该模块。
问题：从模块注册表/深链进入 MV 必然落到 `mv_page.dart:92` 的「缺少歌曲 hash，无法查询 MV」。这是一个**已实现但不可用**的入口。
建议：builder 应接受路由参数或从 `PlaybackSession` 取当前曲 hash；无当前曲时给出明确空态而不是请求失败。
76 合规：不涉及。

### 视角 C3 · lib/core/net/endpoints/mv_anonymous.dart（227 行）· P1 · 死代码 / MV
证据：`rg -n 'mv_anonymous' -g '*.dart' lib` → **零命中**（没有任何文件 import 它）；文件内 `registerDevice(:57)` 与 `anonymousPlayUrl(:144)` 两个公开函数**全仓零调用**。
问题：227 行匿名 MV 端点封装（`registerDevice` 取真实 dfid、`anonymousPlayUrl` 取匿名播放地址）是**完全死代码**——用户「匿名/VIP 三态」诉求没有任何实现。
建议：要么接入 MV 链路作为「未登录可看 MV（低清/试听）」的降级路径，要么从桥里摘除并在文档标注；不要让它继续伪装成已实现能力。
76 合规：不涉及。

### 视角 C3 · lib/logic/download/download_manager.dart:89 · P0 · 功能可达性 / 下载
证据：`rg -n 'enqueue\(' -g '*.dart' lib` → **仅定义处 1 命中，零调用点**；`rg -n 'download|下载' lib/surface/pages/*.dart lib/surface/design/*.dart`（排除 library_page/settings_page）→ **零命中**；`lib/surface/pages/library_page.dart:302-303` 空态写「暂无下载任务」/「在歌曲菜单里选择下载」。
问题：**下载功能实现了但没有任何入口**——「歌曲菜单里选择下载」这句文案指向一个**不存在的菜单**。用户点不到下载。
建议：① 在歌曲列表项/⋮ 菜单加「下载」项 → `appGraph.downloads?.enqueue(song, quality)`；② 或至少把空态文案改成真实状态（无入口前不要承诺）。
76 合规：不涉及。

### 视角 C3 · lib/logic/catalog/collect_logic.dart:118 · P0 · 功能可达性 / 收藏
证据：`CollectLogic.toggle(...)`（`:118`）**全仓零调用**；`lib/surface/pages/player_page.dart:81-88` 收藏按钮实现是 `onPressed: () { setState(() => _fav = !_fav); widget.onChanged?.call(); }` —— **纯本地 setState，不落库、不请求**。
问题：收藏按钮**看起来能用、点下去只变图标**，重启即丢；`CollectLogic.toggle` / `collect_endpoints` 一整条链是死代码。这属于用户说的「什么功能都用不了」。
建议：按钮 onPressed 改为调用 `appGraph.collect?.toggle(...)`，成功后再 setState；失败要 Snackbar 报错。
76 合规：不涉及。

### 视角 C3 · 五条主链路接通性速查 · P1 · 功能可达性
证据与结论（入口 → 逻辑 → 网络）：
| 链路 | 入口 | 逻辑 | 网络 | 判定 |
|---|---|---|---|---|
| 搜索 | `search_page.dart:80 appGraph.search` / `:81 searchTyped` | `SearchLogic.search` | `search_endpoints.dart` | ✅ 三段接通（`search_page.dart:87 se?.search(q,1)`）；但分段 `kSearchSegments(:33)` 无 MV 段 |
| 榜单/推荐 | `home_page.dart:52-56 g.recommend?.daily(1) / g.playlist?.recommend(1) / g.rank?.rankList()` | RankLogic/RecommendLogic/PlaylistLogic | `rank_endpoints`/`recommend_endpoints`/`playlist_endpoints` | ✅ 三段接通（首页 3 个 section 均有 loading/empty/error 三态） |
| 播放 | `home_page:68 / search_page:123 / playlist_page:275` → `PlaybackSession.instance.playAll` | `PlaybackService` | `play_endpoints` | ✅ 三段接通；`playback_session.dart:149 '引擎播放失败'` 文案硬编码在 L6 |
| 下载 | **无入口** | `DownloadManager` | `download_store` | ❌ **实现了无入口**（enqueue 零调用） |
| 登录 | `login_sheet.dart:169 createQrLogin / :197 pollQrLogin / :316 sendVerifyCode / :342 signInByVerifyCode / :427 signInByPwd` | `AuthLogic` | `auth_endpoints.dart` | ✅ 三段接通，但 **密码登录与验证码登录端点均标注「待实测」**（`auth_logic.dart:284,315,339`），UI 文案直接说「端点待实测」「后端就绪」 |
| MV | `player_page.dart:189 '查看 MV'` | `MvLogic` | `mv_endpoints` | ❌ **入口在但请求错**（歌曲 hash 当 video_id），另 `mv_anonymous.dart` 全死 |

问题：搜索/榜单/播放/登录 四条接通（登录质量存疑），**下载零入口、收藏假按钮、MV hash 错配**——与用户「什么功能都用不了」高度吻合。
建议：优先修 MV 链路与下载入口，其次收藏按钮接真逻辑；登录端点未实测前不要在 UI 上承诺密码登录。
76 合规：不涉及。

---
