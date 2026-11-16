# B1 批 · C3 用户痛点专项（登录全链路 + YKG + 文案 跨层审查）

> 审查视角：C3 用户痛点（跨层 L7→L6→L5→L4）
> 记录时间：2026-11-17 07:05 LCL
> 纪律：只读取证（file_read / rg / wc / ls）；不跑 analyze/test/门禁；结论 append 不覆盖。
> 基线对照：`docs/DEEP_AUDIT_PHASE_B_PLAN.md`、`docs/YKG_LINK_CRYPTO_DESIGN.md`、`docs/deep_audit/bA7_c3.md`（MD3 40/100 + 119 处硬编码基线）。
> 说明：阶段 A 已把 YKG 从「零入口」做成「第4 Tab + 导出/导入弹层 + S.of 门面 + 56 键 10 语 arb」，本批验证真实用户体验与接线质量。

---

## YKG体验走查

> 记录时间：2026-11-17 07:05 LCL

按用户视角逐步走 YKG 链路，逐点标注是否符合设计稿与是否困惑：

| 步骤 | 设计稿要求 | 实现现状 | 判定 |
|---|---|---|---|
| ① 发现入口 | 登录页第4 Tab「YKG 链接登录」 | `login_sheet.dart:105` TabBar 第4 Tab = `s.t('ykgTitle')`；`:468` _YkgTab | ✅ 易发现（第4 Tab 与前三登录方式并列） |
| ② 风险提示 | 强制+清楚，勿公开分享 | `_YkgTab`(:475-481) + `_YkgSheet`风险Container(:129-134) 均显示 `ykgRisk` | ⚠️ 展示了但无强制确认勾选 |
| ③ 导出密码设置 | ≥6 位 + 强度提示，已有密码需验证 | arb `ykgPasswordHint`写「至少6位」；代码**只校验非空、无长度校验**；`verifyPassword()`零调用 | ❌ 见 YKG-01/02 |
| ④ 导出链接可见/复制 | 复制/分享/二维码 | `Clipboard.setData`(:69) 可用；**导出模式不显示链接文本框**；二维码未实现 | ❌ 见 YKG-03/05 |
| ⑤ 有效期展示 | 建议显示「有效期至 YYYY-MM-DD」 | `ykgValidUntil`键存在但 UI **零使用** | ❌ 见 YKG-04 |
| ⑥ 导入是否先输密码 | 先验密码再解密 | 先校验 isYkgLink→再校验密码非空→ decrypt，顺序正确 | ✅ 密码门成立 |
| ⑦ 错误提示统一不泄露 oracle | 密码错/链接损坏统一文案 | catch 统一 `ykgWrongPassword`，底层串不外显 | ✅ 但过期被误报（YKG-06） |
| ⑧ 剪贴板生命周期 | 建议60s自动清空 | 未实现，凭据长期留剪贴板 | ❌ 见 YKG-07 |
| ⑨ 导入来源标记 | 标记来源 `ykg` | `ykgSourceTag`键存在但 UI 零使用；账号区不显示来源 | ❌ 见 YKG-08 |

**YKG 体验困惑/误用点合计：8 处**（②③④⑤⑦⑧ + ⑦过期误报 + 图标语义不一致见 MD3-02）。

---

## <视角 C3> · lib/surface/pages/ykg_sheet.dart:64-75 · P1 · YKG体验/可用性
证据：`_doExport()` 成功后 `await Clipboard.setData(...)`、`_link.text = link`（:71），但 build 中链接输入框被 `if (!isExport) ...<Widget>[ TextField(controller:_link...) ]`（:139-149）包裹——导出模式 isExport=true，该 TextField 不渲染。
问题：用户点「导出登录链接」并把链接写入剪贴板后，弹层内**看不到生成的链接本身**，无法核对/手动复制/分享给他人，只能盲信已复制成功（仅硬编码之外的 `ykgCopied` 提示）。
建议：导出模式下也渲染一个只读链接框（或单独 Text/SelectableText）展示 link，并提供「复制/分享/二维码」按钮；让 `_link` 在两种模式都可见。
76 合规：L7 纯 UI，不涉及越层；属交互缺陷。

## <视角 C3> · lib/logic/auth/ykg_logic.dart:118-127 / lib/surface/pages/ykg_sheet.dart:59-63 · P1 · YKG体验/安全误导
证据：`verifyPassword()` 在 ykg_logic.dart:118 定义，全仓 `rg verifyPassword` 仅命中定义处，**零调用**；`exportLink()`(:71-110) 每次用输入的任意密码调 `newYkgVerifier()` 覆盖 `_kYkgVerifier`。UI `_doExport` 只判 `_pwd.text.isEmpty`。
问题：设计稿 §5「已有导出密码 ⇒ 直接输入验证」未落地。用户以为在「复用上次密码」，实际任意新密码都静默覆盖旧 verifier；且 arb 明示「至少6位」却无一处做 `length>=6` 校验（ykg_logic/ykg_codec/sheet 均无），用户可设 1 位弱口令而不自知。
建议：导出前先调 `verifyPassword()` 校验旧密码（有旧 verifier 时）；在 L7 与 L4 加 `password.length>=6` 校验并给专门提示 key；强度提示做成实时反馈。
76 合规：涉及——验证逻辑归 L5 正确，但 UI 未调用，属跨层接缝断链。

## <视角 C3> · lib/core/net/ykg_codec.dart:88 / lib/logic/auth/ykg_logic.dart:77 · P2 · YKG体验/有效期
证据：encode 写 `'exp': now + ttlSec`（默认7天，ykg_codec.dart:88 / ykg_logic.dart:73），decode 检查 `exp < now → fail('link expired')`（:113）。arb 有 `ykgValidUntil`「有效期至」，但 `rg ykgValidUntil` 显示 UI 零引用（仅 arb + strings.dart）。链接 payload 内 exp 为秒级时间戳，用户无法从链接肉眼看出有效期。
问题：设计稿 §5「建议显示有效期至 YYYY-MM-DD」完全没做；拿到链接的人（尤其导入方）不知道链接是否过期、何时过期，只能靠导入失败反推。
建议：导出成功后把 `exp` 解析为日期展示 `ykgValidUntil + YYYY-MM-DD`；导入检测到 `link expired` 时给专门文案而非统一「密码错误」（见 YKG-06）。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/ykg_sheet.dart:95-112 / lib/core/net/ykg_codec.dart:113-151 · P1 · YKG体验/错误反馈
证据：decode 对多种失败给出不同 error 串：`invalid link`/`unsupported version`/`link expired`/`invalid payload`/`integrity mismatch`/`wrong password or damaged link`（ykg_codec.dart:98-151）。但 ykg_logic.importLink 把 `r.error` 原样塞进 `$1`（:135 `return (false, r.error ?? '')`），UI `_doImport` **无论何种失败都 `_set(s.t('ykgWrongPassword'))`**（:113），忽略 r.$2。
问题：统一「不泄露 oracle」的文案本身正确，但把「链接已过期」「不是有效链接」「版本不支持」也统统显示成「密码错误或链接已损坏」——用户反复怀疑自己记错密码，真正的过期/损坏原因被掩盖，反而造成误用与困惑。这是「防 oracle」与「可诊断性」的失衡。
建议：区分「非密码类」失败（过期、格式非法、版本不支持）用独立中性文案（如 `ykgInvalidLink`/`ykgExpired`），仅对「密码错/GCM tag 失败/完整性不符」保持统一 `ykgWrongPassword`（仍不区分这三者，保住 oracle 防护）。
76 合规：证据链 L4→L5→L7 完整，错误码未丢，属 UI 呈现策略问题。

## <视角 C3> · lib/surface/pages/ykg_sheet.dart:1-191 · P2 · YKG体验/二维码
证据：`rg qr_codec|QrCodec` 在 ykg_sheet.dart / ykg_logic.dart 零命中；设计稿 §9.5「链接是否需要二维码形式——倾向要，扫码导入体验最好」，`lib/core/algorithms/qr_codec.dart` 已存在可复用。
问题：YKG 链接是一长串 base64（`ykg://import/` + base64url JSON），跨设备只能靠剪贴板/聊天转发，**没有二维码扫码导入**。设计稿明确倾向要 QR，落地缺失，跨端体验打折。
建议：导出弹层加「生成二维码」（复用 qr_codec.dart，注意基线提到的 off-by-one 必修）；导入 Tab 加「扫码导入」入口。
76 合规：不复涉及（QR 编解码属 L4，UI 入口属 L7，分工清晰）。

## <视角 C3> · lib/surface/pages/ykg_sheet.dart:69 · P2 · YKG体验/凭据生命周期
证据：`Clipboard.setData(ClipboardData(text: link))`（:69）后无任何 Timer/延时清空；`rg Clipboard` 在 ykg_sheet 仅此一处。设计稿 §6「建议60秒后自动清空（仅当内容仍等于本链接）」未实现。
问题：YKG 链接等价 bearer 凭据（含可解密登录 cookie，仅靠独立密码保护），长期滞留系统剪贴板，任何此刻的粘贴/剪贴板读取都可能外泄；与「风险提示勿公开分享」的强调自相矛盾。
建议：导出后起 60s Timer，到点比较 `Clipboard.getData` 仍等于该 link 才 clear，弹层 dispose 时 cancel Timer。
76 合规：L7 承载剪贴板 IO 属于 UI 合理职责；但 Timer 编排建议下沉，注意不违背「L7 只画控件」。

## <视角 C3> · lib/surface/pages/login_account_section.dart:27-88 / lib/core/l10n/strings.dart · P2 · YKG体验/来源标记
证据：`ykgSourceTag`「来源 YKG 链接」键在 10 份 arb + strings.dart 齐备，但 UI 零引用；`AccountSection` 只显示 displayName + '账号 $accountId'（:66-71），`AccountRecord` 无来源字段渲染。
问题：用户从 YKG 导入登录后，在「已登录账号」区看不出该账号来自 YKG 链接，和设计稿 §6「标记来源为 ykg」的凭据管理诉求脱节；不利于用户识别/吊销导入凭据（设计稿 §6 的「吊销本机已导入 YKG 凭据」也无入口）。
建议：账号区对 ykg 来源账号显示 `ykgSourceTag` 徽标；补「吊销本机已导入凭据」入口并文案化。
76 合规：涉及——来源标记需 L5 落字段、L7 展示，当前字段未贯通。

---

## 登录体验走查

> 记录时间：2026-11-17 07:05 LCL

### 开发状态暴露给用户（用户「登录文案暴露开发状态」核验）
阶段 A 未清理，登录页仍有 **3 处**把后端/端点开发状态直接显示给用户（与 bA7_c3.md 行号基线一致）：
- `login_sheet.dart:323` `'验证码发送失败（接口待实测）'`
- `login_sheet.dart:355` `'验证码登录端点待实测（needs probe）'`
- `login_sheet.dart:436` `'密码登录待后端就绪'`
另外注释/日志里 `:6`「端点待实测」、`:404`「批2-F1 尚未合入」是源码注释不面向用户，不计入暴露数。

## <视角 C3> · lib/surface/pages/login_sheet.dart:355 · P1 · 登录体验/开发状态外泄
证据：`_toast(res.needsProbe ? '验证码登录端点待实测（needs probe）' : ...)`——`needsProbe`（端点待实测的技术标记）直接映射成用户可见中文串。
问题：验证码登录失败时给用户弹「端点待实测（needs probe）」，把内部技术状态/英文术语暴露给终端用户，用户完全无法理解「needs probe」是什么，也得不到可行动信息（该重试还是换方式）。这正是用户反复抱怨的「文案没改/暴露开发状态」。
建议：needsProbe 归一到用户友好文案（走 S.of，如 `errorGeneric`「操作失败请重试」或专门的「该方式暂不可用，请稍后重试」）；needsProbe 只进 Log 不进 UI。
76 合规：不涉及（纯文案呈现）。

## <视角 C3> · lib/surface/pages/login_sheet.dart:323 / :436 · P1 · 登录体验/开发状态外泄
证据：`:323` catch 内 `_msg = '验证码发送失败（接口待实测）'` 后 `_toast(_msg)`；`:436` catch 内 `Text('密码登录待后端就绪')`。两处均为用户可见 SnackBar/Text。
问题：「接口待实测」「待后端就绪」是研发进度术语，不应出现在登录界面。更糟的是密码 Tab `_login()`（:430-437）无论真实异常是什么（网络错/账号错/端点错）都被 catch 成「密码登录待后端就绪」，掩盖真实失败原因。
建议：改为面向用户的中性错误（走 S.of，如 `errorNetwork`/`errorGeneric`），并在 catch 保留 Log 记录真实 e；技术状态只留日志。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/login_sheet.dart:217-220 · P2 · 登录体验/QR过期反馈
证据：QR `expired` 分支：首次 `_recreatedOnce=false→true`，提示「二维码已过期，正在自动刷新…」并自动 `_createQr()`；第二次过期提示「二维码已过期，请下拉重试或退出重开」。
问题：① 文案「请下拉重试」——但该 Tab 是 ListView，没有下拉刷新（RefreshIndicator）控件，「下拉重试」是不存在的操作，误导用户；实际可点的是下方「刷新二维码」TextButton。② 自动重建只做一次，二次过期后要求「退出重开」体验生硬。③ 这些提示全是硬编码中文，未走 S.of（见文案接线清单）。
建议：改为「请点击『刷新二维码』按钮重试」并接 S.of；或加 RefreshIndicator 让文案成立；二次过期后允许无限手动刷新。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/login_sheet.dart:124 / :430-437 · P1 · 登录体验/密码登录成功无闭环
证据：TabBarView 第3项是 `_PwdTab()`（:124），**未传 onLoginSuccess**（QR/SMS 都传了）；`_PwdTabState._login()`（:430-437）`await auth.signInByPwd(pwd)` 后注释「就绪后此处接 onLoginSuccess」，没有调用 `widget.onLoginSuccess`、没有 `saveCurrent()`、没有 `bumpAuth()`、没有 `pop()`；且 `signInByPwd(pwd)` 只传密码、UI 里输入的 `_account`（:445）根本没传给后端（`auth_logic.dart:286` 签名只有 pwd + code，无账号参数）。
问题：从用户视角，密码 Tab 输入账号+密码点「登录」，即使后端成功，弹层也不关闭、账号区不刷新、登录态不生效——**用户会以为登录失败/卡死**。账号输入框填了却没用，也是明显误导。
建议：给 _PwdTab 传 onLoginSuccess，成功路径复用 `_onLoginSuccess()`；确认 signInByPwd 是否需账号参数（与后端对齐），若不需要则去掉账号输入框或说明用手机号即密码登录标识。
76 合规：涉及——登录成功编排（saveCurrent/bumpAuth/pop）在 L7 手工串联本就脆弱，建议下沉 L6。

## <视角 C3> · lib/surface/pages/login_sheet.dart:80 / :90 · P2 · 登录体验/账号区反馈文案硬编码
证据：切换/移除账号 SnackBar：`Text(ok ? '已切换账号 $accountId' : '切换失败')`（:80）、`'已移除账号 $accountId' / '移除失败'`（:90），均硬编码中文，未走 S.of；且直接回显 accountId（原始 uid）。
问题：账号区操作反馈未国际化（切换语言后仍中文），且把内部 accountId 裸显给用户（应为脱敏或显示名）。登录后账号区虽列了 ListTile（displayName + "账号 $accountId"），信息可读，但反馈文案质量与国际化缺失。
建议：反馈走 S.of（新增 key），账号 ID 脱敏显示；与文案接线清单一起处理。
76 合规：不涉及。

---

## 文案接线清单（用户「文案没改」核验）

> 记录时间：2026-11-17 07:05 LCL
> 阶段 A 已建 S.of 门面 + 56 键 10 语 arb；本批核实登录/YKG 相关页面**还有多少硬编码中文没接 S.of**。

### 逐文件计数（用户可见中文字符串字面量，已排除纯注释）

| 文件 | 硬编码中文(用户可见) | 已接 S.of 处 | 判定 |
|---|---|---|---|
| `login_sheet.dart` | **32** | 9 | 大量未接（QR/SMS/Pwd 全部提示、label、SnackBar） |
| `login_account_section.dart` | **4** | 0 | 全部未接（已登录账号/暂无账号/账号x/移除账号） |
| `ykg_sheet.dart` | **0** | 20 | ✅ 全部走 S.of（接线到位，正面样板） |
| **合计** | **36** | 29 | YKG 弹层已接线，**登录主面板与账号区 36 处仍硬编码** |

### login_sheet.dart 未接 S.of 的硬编码中文逐行（32 处，节选代表性全集）

- `:80` `'已切换账号 $accountId'` / `'切换失败'`
- `:90` `'已移除账号 $accountId'` / `'移除失败'`
- `:158` `'正在获取二维码…'`
- `:170` `'登录能力未装配'`
- `:178` `'请使用酷狗音乐 App 扫码'`
- `:192` `'二维码获取失败，请重试'`
- `:211` `'已在手机上扫码，请在手机端确认登录'`
- `:217` `'二维码已过期，正在自动刷新…'`
- `:220` `'二维码已过期，请下拉重试或退出重开'`
- `:259` `'二维码加载中'`
- `:278` `'刷新二维码'`
- `:316` `'请输入手机号'`
- `:323` `'验证码发送失败（接口待实测）'`
- `:327` `'验证码已发送至 ...'` / `'发送失败，请稍后重试'`
- `:343` `'请输入手机号与验证码'`
- `:349` `'登录能力未装配'`
- `:355` `'验证码登录端点待实测（needs probe）'`
- `:356` `'登录失败：...'` / `'未知错误'`
- `:362` `'验证码登录失败：$e'`
- `:375` `'手机号'` / `:376` `'用于登录酷狗账号'`
- `:386` `'验证码'` / `:392` `'发送验证码'`
- `:397` `'登录'`
- `:427` `'请输入账号与密码'`
- `:436` `'密码登录待后端就绪'`
- `:447` `'手机号 / 用户名'` / `:454` `'密码'`
- `:462` `'登录'`

### login_account_section.dart 未接 S.of（4 处）
- `:34` `'已登录账号'`、`:47` `'暂无账号，登录后将自动保存到这里'`、`:67` `'账号 $accountId'`、`:79` tooltip `'移除账号'`

### 结论：接线进度
- 阶段 A 的门面 + 56 键**确实接通了 YKG 弹层**（ykg_sheet 20 处全走 S.of，零硬编码），说明接线机制可用。
- 但**登录主面板（32）+ 账号区（4）= 36 处未接**，且 `qrLogin`/`smsLogin`/`pwdLogin` 这 3 个 Tab 标签键已存在 arb 并被使用（正面），Tab 内内容却全是硬编码。用户「文案没改」的体感在登录页**仍未消除**。
- 缺专门 key：QR 各状态提示、账号区提示、switch/remove 反馈均无对应 arb key，需补 key 后再接。

---

## <视角 C3> · lib/l10n/app_*.arb（10 语）· P2 · 文案质量/YKG译文
证据：
- 键集一致：10 份 arb 均 56 键（逐文件 rg -c 全 =56），结构齐。
- zh/zh_Hant/en 三语 YKG 译文到位：`ykgRisk` zh「此链接包含你的登录凭据 拿到链接并知道密码的人都能登录 请勿公开分享」/ Hant「此連結包含你的登入憑據…」/ en「This link contains your credentials. Anyone with the link and password can sign in. Do not share publicly.」——准确表达风险，`ykgWrongPassword` 三语均为统一不区分文案，符合 §3.3 防 oracle。
- 其余 7 语（de/es/fr/ja/ko/pt/ru）**新增 YKG 键全为英文占位**：`ykgPassword` 在 de/ja/ko/ru 均为 `"LinkPassword"`（en 为 "Link Password"，连空格都丢了）；而基础键已本地化（de search=Suchen、ja=検索、ko=검색、ru=Поиск）。
问题：用户「10语YKG译文」诉求只兑现了 zh/Hant/en 三语；其余 7 语的 YKG 相关键是英文占位（甚至 "LinkPassword" 粘连），按用户日常版纪律「只保证 zh/Hant/en」可接受，但需明确这是有意的占位而非遗漏，并修掉粘连空格。
建议：CI 翻译管线补齐 7 语 YKG 键；临时至少把 "LinkPassword" 这类粘连串修正为 "Link Password"；zh 的 ykgRisk 用空格代替标点（「凭据 拿到」「都能登录 请勿」读起来断裂），建议改中文标点以提升可读性。
76 合规：arb/strings.dart 在 L4 符合；接线问题另计。

---

## MD3 局部（登录页 / YKG 弹层）

> 记录时间：2026-11-17 07:05 LCL
> 基线：bA7_c3.md MD3 40/100 fail。本批只核登录/YKG 局部。

## <视角 C3> · lib/surface/pages/ykg_sheet.dart:129-134 · P2 · MD3/风险提示配色
证据：风险提示 Container 用 `color: Sp.cardHigh`（背景）+ `Text(..., style: TextStyle(color: Sp.orange))`（:133），Sp.orange=#F2A25C 是自定义静态橙，非 ColorScheme 语义角色；未用 `colorScheme.error` / `errorContainer` / tertiary。
问题：MD3 风险/警告提示应使用语义色（error/errorContainer 或 tertiary 系），这里绕过 ColorScheme 用自定义 Sp.orange（延续 bA7_c3「Sp.* 架空 ThemeData」的通病）。浅色主题下 Sp.orange 硬编码值不随主题变，对比度不可控；且风险提示只是「橙色文字」，层级偏弱——这是**凭据安全的关键警示**，视觉权重不足。
建议：改用 `Theme.of(context).colorScheme.error`/`errorContainer`，并加图标（Icons.warning_amber）+ 更大字重，提升风险提示层级；纳入统一主题源。
76 合规：不涉及（配色在 L7，符合）。

## <视角 C3> · lib/surface/pages/login_sheet.dart:24-31 / ykg_sheet.dart:16-21 · P2 · MD3/弹层尺寸与键盘避让
证据：login_sheet 用 `isScrollControlled:true` + `SizedBox(height: screen*0.7)`（:29），全屏 70% 固定比例；ykg_sheet 用 `isScrollControlled:true` + `SingleChildScrollView` + `viewInsets.bottom` 键盘避让（:120-127）——ykg 处理正确，login 用固定高度未考虑键盘弹起时 TabBar 被顶出/内容遮挡。
问题：登录弹层固定 70% 高度，在验证码/密码 Tab 软键盘弹起时可用区被压缩、Tab 标签可能不可见；未像 ykg_sheet 那样做 viewInsets 避让。契约一致对待键盘的方式不统一。
建议：登录弹层也按 viewInsets 动态调整高度或用 `constraints: BoxConstraints(maxHeight: ...)`，保证键盘态下 Tab 与输入框同时可见。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/login_sheet.dart:452-460 / ykg_sheet.dart:150-161 · P2 · MD3/密码框可见性切换
证据：两处密码框都用 `obscureText:_obscure` + `suffixIcon: IconButton(visibility/visibility_off)` 切换，图标在两文件中**方向相反**：PwdTab（login_sheet.dart:457）`_obscure ? visibility_off : visibility`，YkgSheet（ykg_sheet.dart:155）`_obscure ? visibility : visibility_off`。
问题：Material 规范语义是「图标表示点击后动作」——隐藏态应显示 visibility（点它显示），显示态显示 visibility_off（点它隐藏）。YkgSheet 方向不符合此约定（隐藏态却显示 visibility_off），PwdTab 才符合。两处不一致会让用户困惑「这个眼睛是告诉我当前状态还是要执行的动作」。
建议：统一为 Material 约定（隐藏态 visibility、显示态 visibility_off），两文件对齐；并加 semanticLabel（见无障碍）。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/ykg_sheet.dart:164-170 / login_sheet.dart:393-397,458-462 · P2 · MD3/按钮层级与触控目标
证据：主操作用 `FilledButton`（ykg :165 / login :397,:462），YKG 导出用 `OutlinedButton.icon`（:180）作次操作，层级区分正确（正面）。但 QR Tab「刷新二维码」用 `TextButton`（login :276-279）；TabBar 用默认 Material Tab（触控目标约 48dp 合规）。风险提示 Container 无点击态。
问题：按钮主次层级基本合理。但 TextButton「刷新二维码」触控高度通常 <48dp（MD3 建议最小 48dp），且 TabBar 文本标签仅靠颜色区分选中态（无指示条粗细审计），暗色下可读性依赖固定 Sp 色。整体延续基线 Accessibility 4/10。
建议：刷新按钮增大 hitTest 区域至 48dp；审计 Tab 选中/未选中对比度；补齐 48dp 逐控件枚举（本批未全覆盖，见未覆盖）。
76 合规：不涉及。

---

## 无障碍（A11y）

## <视角 C3> · lib/surface/pages/ykg_sheet.dart:150-170 / login_sheet.dart:452-462 · P1 · 无障碍/密码框与错误提示语义缺失
证据：`rg Semantics|semanticLabel` 在 login_sheet/ykg_sheet/login_account_section 三文件**零命中**（仅 account_section:79 有一个 tooltip）。密码框 suffixIcon 的 IconButton 无 semanticLabel；错误/风险 Text 无 `Semantics(liveRegion:true)`；风险提示纯色块无 label。
问题：TalkBack 用户面对「眼睛」图标按钮读不到「显示密码/隐藏密码」的含义；密码输入错误、导入结果、风险提示出现时无 liveRegion 播报，视障用户不知道操作结果；风险提示色块读屏时可能只念出文字而丢失「这是警告」的语境。
建议：给 IconButton 加 `semanticLabel`（显示/隐藏密码，随状态变）；错误/结果 Text 包 `Semantics(liveRegion:true, assertive:true)`；风险 Container 加 `Semantics(container:true, label:'警告：...')`。
76 合规：不涉及（纯 L7 无障碍标注）。

## <视角 C3> · lib/surface/pages/login_sheet.dart:105-112 · P2 · 无障碍/Tab 标签可读性
证据：TabBar 4 个 Tab 文案 `s.t('qrLogin'/'smsLogin'/'pwdLogin'/'ykgTitle')`（:107-110）——已国际化（正面），但无 semanticLabel/语义图标，选中态靠颜色。
问题：Tab 标签文本本身可读且已国际化；但读屏下 4 个纯文本 Tab 缺少「登录方式」的分组语境，选中态纯靠颜色对低视力用户不友好（延续 MD3 Accessibility 短板）。
建议：给 TabBar 加 `Semantics`，选中项加语义标记；考虑给 Tab 加图标增强区分。
76 合规：不涉及。

---

## 本视角结论（C3 用户痛点 · B1）

> 记录时间：2026-11-17 07:05 LCL

1. **YKG 体验**：入口易发现、密码门顺序正确、错误文案不泄露 oracle——这三点做对了；但有 **8 处困惑/误用点**：导出后看不到链接（P1）、密码≥6位与旧密码验证形同虚设（P1）、有效期不展示（P2）、过期/非法链接被误报为「密码错误」（P1）、无二维码导入（P2）、剪贴板凭据不清空（P2）、导入来源不标记（P2）、可见性图标语义方向不一致（P2）。
2. **登录体验**：三种登录 Tab 的**开发状态暴露 3 处**（接口待实测/端点待实测 needs probe/待后端就绪，P1）；QR 二次过期提示「下拉重试」指向不存在的操作（P2）；密码 Tab 登录成功不闭环（无 onLoginSuccess/saveCurrent/pop，账号输入未传后端，P1）——这是最影响用户的断点。
3. **文案接线**：阶段 A 的 S.of 门面 + 56 键机制**在 YKG 弹层真正生效**（20 处全接、零硬编码，正面样板）；但**登录主面板 32 + 账号区 4 = 36 处硬编码中文未接 S.of**，用户「文案没改」体感在登录页仍未消除。10 语 arb 键集齐（各 56），zh/Hant/en 的 YKG 译文到位，其余 7 语 YKG 键为英文占位（含 "LinkPassword" 粘连）。
4. **MD3 局部**：按钮主次层级合理；但风险提示用自定义 Sp.orange 绕过 ColorScheme（P2）、登录弹层键盘避让缺失（P2）、两处密码可见性图标方向相反（P2）。延续基线 MD3 40/100 fail 的「Sp.* 架空 ThemeData」通病。
5. **无障碍**：三文件零显式 Semantics——密码可见性切换、错误/风险提示 liveRegion、Tab 分组语境全缺（P1/P2）。TalkBack 用户基本无法获得关键反馈。

## 未覆盖

- 登录 3 个 Tab 的实际网络请求/端点连通性（本视角只看 UI 与编排接缝，未跑 analyze/test/门禁、未联网）。
- 每个控件 48dp 触控目标逐控件枚举（仅抽样 TabBar/按钮）。
- 实机 TalkBack 读屏验证、精确 WCAG 对比度数值测量（需真机/工具，纪律禁止）。
- 其余 surface 页面（home/player/mv/search 等）的硬编码中文计数——属 B2–B7 范围，本批只数登录/YKG 三文件。
- `AccountRecord` 是否已有来源字段（只核了 UI 未渲染 `ykgSourceTag`，未逐字段读取 model 定义）。
- QR 码图片（官方 qrcode_img base64）解码内容正确性——属实现正确性 C2，本视角未验证。

## 76 合规小结

- **职责错位/越级**：密码登录成功的登录态编排（saveCurrent/bumpAuth/pop）在 L7 `_onLoginSuccess()` 手工串联，QR/SMS 传 onLoginSuccess、Pwd 漏传，暴露「编排在 UI 层」的脆弱性（建议下沉 L6）——P1。
- **跨层接缝断链**：① `verifyPassword()`（L5，ykg_logic.dart:118）定义了却零调用，UI 未接，导致旧密码验证缺失；② 来源标记 `ykgSourceTag`（L4 arb）到 L7 账号区未贯通；③ YKG 错误码 L4→L5 传达到位但 L7 一律压成「密码错误」，诊断性丢失（防 oracle 与可用性失衡）。
- **合规正面**：YKG 密码学全在 L4（cryptography 成熟库 PBKDF2/AES-GCM，无自研原语），编排在 L5、UI 文案在 L7 走 S.of，层落位与设计稿 §7 一致；`AppGraph.ykg` 经 bootstrap 注入、onImported 由 L6 注入 notifyAuthChanged，未反向依赖——分层骨架正确。
- **i18n 归属**：arb + strings.dart + S.of 门面在 L4/L7 分工合规；问题在「接线不全」而非层级。
- **剪贴板 IO / Timer**：在 L7 承载属 UI 交互合理，但剪贴板 60s 清空 Timer 若补，建议编排下沉以守「L7 只画控件」。

---
*本报告由 B1-C3 子代理只读审查生成，全部结论 append 落盘，未改动任何源码。*
