# B1 · C1 架构合规视角 · 登录全链路 + YKG 新方式 + 文案

> 范围：L7 login_sheet/ykg_sheet/login_account_section/l10n-s · L6 auth_session/bootstrap/graph ·
> L5 auth_logic/account_logic/ykg_logic/verification_logic · L4 auth_endpoints/ykg_codec/settings_store/crypto_*/strings ·
> 桥 bridge_core/bridge_logic/bridge_session。只读审查，未改任何源码。

## 视角 C1 · lib/bridges/bridge_core.dart:107-117 · P1 · 六桥唯一通道/职责错位
证据：bridge_core 同时 export `../core/net/endpoints/auth_endpoints.dart` 的 **端点函数** `sendSmsCode, smsLogin, loginByPwd, loginByToken, devLogout`（112-117 行），以及 `../core/net/ykg_codec.dart` 的 **密码学原语** `encodeYkgLink, decodeYkgLink, passwordVerifier, newYkgVerifier`（181-187 行）。bridge_core 是 L3↔L4 桥，被 L5/L6/L7 全层共用。
问题：L4 网络端点与 YKG 编解码原语经 bridge_core 直达 L7，L7 可绕过 L5 的 `AuthLogic`/`YkgLogic` 编排直接调端点/密码学，六桥「唯一合法跨层通道」的层间约束被打开第二口。
建议：端点函数与 codec 原语只经 bridge_logic（L4↔L5）转出；bridge_core 仅保留模型/常量/纯数据（如 `AccountRecord`、`SmsLoginResult`、`LoginResult`、YkgLinkResult）。若需 L7 用，由 L6 AppGraph 暴露门面。
76 合规：违反第 1 条（不同层级之间必须通过桥接层调用）与第 4 条（每层只依赖其下层经桥暴露的门面）。

## 视角 C1 · lib/surface/pages/login_sheet.dart:13-14 · P1 · L7 越级依赖 L4（已开口未使用）
证据：`import '../../bridges/bridge_core.dart' show AccountRecord, sendSmsCode, smsLogin, KugouApiException;`。文件中 `sendSmsCode` / `smsLogin` / `KugouApiException` 除 import 行外零引用（rg 全文仅第 5 行注释与第 14 行 import 命中），实际调用走的是 `appGraph.auth?.sendVerifyCode / signInByVerifyCode`。
问题：L7 登录页已把 L4 网络端点与异常类型握在手里，只差一次调用即可完全绕过 L5 `AuthLogic`（凭据落 session/写 settings 全部失效）；同时是死 import。
建议：删掉 `sendSmsCode, smsLogin, KugouApiException`（保留 `AccountRecord` 或改由 L6 暴露账号视图模型）；L7 只允许出现 `bridge_surface` + `bridge_session` 门面。
76 合规：违反第 1 条（L7 不经相邻桥直取 L4 能力）；符合第 4 条（同层内引用合法、仅 bridge_core 白名单内）。

## 视角 C1 · lib/surface/pages/login_sheet.dart:15 · P2 · L7→L5 类型直取绕过 L6
证据：`import '../../bridges/bridge_logic.dart' show QrLoginState, QrLoginStatus;` — QrLoginStatus/QrLoginState 定义在 L5 `logic/auth/auth_logic.dart:36-62`，L7 直接经 bridge_logic 取 L5 类型。
问题：L7 的类型来源出现「bridge_session（L6）+ bridge_logic（L5）」两条并列通道，L6 `AppGraph.auth` 已持有 AuthLogic（L5 实例），类型再单独从 bridge_logic 拿，等于 L7 同时挂 L5 与 L6 两级。
建议：把 `QrLoginState/QrLoginStatus` 随 `AuthLogic` 一起由 bridge_logic 转出并在 L6 `AppGraph`/bridge_session 提供只读视图，或统一由 bridge_session 一处提供；L7 不再单独 import bridge_logic。
76 合规：违反第 1 条（相邻桥原则，L7 应只经 bridge_surface/bridge_session）；`tool/layer_audit.py:40` 白名单第 7 层含 bridge_logic/bridge_core，故门禁放行但规则文本不符。

## 视角 C1 · lib/surface/pages/login_sheet.dart:147-247 · P1 · L7 塞登录状态机（状态机归属错位）
证据：`_QrTabState` 内持有 `_qr/_img/_recreatedOnce/_hint/_timer`，`Timer.periodic(1500ms)` 轮询（186-188），`switch (st.status)` 四态分发 waitScan/waitConfirm/expired/success（207-225），并实现「过期只自动重建一次」策略（213-221）。状态枚举 `QrLoginStatus` 与轮询单次调用在 L5 `auth_logic.dart:36-62 / 121-172`。
问题：QR 登录状态机被劈成两半——「状态定义 + 单次取状态」在 L5，「驱动循环 + 状态迁移策略 + 重试策略」在 L7 Widget。轮询节奏、过期重建次数这类业务策略无法单测、无法复用（其他入口如设置页/深链无法复用同一轮询器）。
建议：把「轮询调度 + 过期重建一次 + 四态迁移」整体下沉到 L5 `AuthLogic`（如 `pollUntilTerminal`/`QrPollController`），L7 只按 `QrLoginState` 渲染。
76 合规：违反第 4 条（L7 只画控件）与 SEVEN_SIX_RULE §4「状态机下沉 L5、L6 只暴露状态/回调」的同构要求。

## 视角 C1 · lib/session/auth_session.dart:19-24 · P1 · L6 会话门面未接线（状态机归属落空）
证据：`AuthSession.attach(KugouClient?)` 全仓零调用者（rg `AuthSession` 仅命中 bridge_session 导出、bootstrap 的 `onImported` 回调、类自身；`attach(` 只出现在 `PlaybackSession.instance.attach`）。因此 `_client` 恒为 null → `isLoggedIn` 恒 false（`userid` 返回 ''）。
问题：L6 的登录态会话门面是死壳；真正的登录态快照散落在 L5 `client.session`（`login_sheet.dart:124` 用 `appGraph.auth?.session.userid`），且 L6 另有一套 `onAuthChanged/notifyAuthChanged` 回调表零订阅者（`onAuthChanged` 无任何调用方）。
建议：bootloader/bootstrap 装配时 `AuthSession.instance.attach(client)`；L7 一律读 `AuthSession.isLoggedIn/userid`（L6 快照），不再直取 L5 `client.session`。
76 合规：违反第 4 条（每层只依赖其下层经桥暴露的门面——L7 现经 L6 图拿 L5 session 对象）与第 8 条（L6 应暴露状态/回调而非让 L7 自取 L5 内部对象）。

## 视角 C1 · lib/session/auth_session.dart:52-53 + lib/session/bootstrap.dart:206 + lib/surface/pages/login_sheet.dart:97 · P1 · 登录态广播双机制并存且其一未接线
证据：三处登录态变更通道：(a) L6 `NavState.bumpAuth()`（`nav_state.dart:60`，被 `login_sheet.dart:81,97` 与 `settings_page.dart:81` 使用）；(b) L6 `AuthSession.notifyAuthChanged()`（`auth_session.dart:72`，只被 `bootstrap.dart:206` 的 YKG `onImported` 调用）；(c) L5 `AuthLogic` 落凭据后**不通知任何一方**（`auth_logic.dart:396-420` `_applyCredentials` 只写 session+settings）。
问题：YKG 导入成功走 (b)（0 订阅者，等于广播到虚空），扫码/验证码登录成功走 (a)，切号走 (a)。L7 `settings_page` 只监听 `NavState.authVersion`，故 **YKG 导入后 L7 登录态不刷新**，同一登录域出现两条互不相认的广播总线。
建议：统一到一条：L6 `AuthSession` 作为唯一登录态事件源（`bumpAuth` 由 L5 经注入回调触发），`NavState.authVersion` 改为其镜像；bootstrap 的 `onImported` 改调同一入口。
76 合规：违反第 4 条（层间状态单一事实源）与 SEVEN_SIX_RULE §1「L6 编排会话层：状态/回调唯一出口」。

## 视角 C1 · lib/logic/auth/ykg_logic.dart:43,158 · P2 · 动态调用规避类型契约
证据：构造参数 `required Object auth`（43 行），导入时 `(_auth as dynamic).restoreSession();`（158 行）。而同层 `account_logic.dart:11-18` 合法地 `import 'auth_logic.dart' show kSettingToken, ...`（同层引用合法，76 第 4 条明文允许）。
问题：同层内并无循环依赖（auth_logic 不引用 ykg_logic），却用 `Object` + `dynamic` 抹掉 `AuthLogic` 类型，重命名/改签名不会编译报错，只会在运行期炸（158 行已被 try/catch 吞成 Log.w，导入静默降级）。
建议：`import 'auth_logic.dart' show AuthLogic;` 直接用类型，字段改 `final AuthLogic _auth;`。
76 合规：符合第 4 条（同层内引用合法），但实现方式削弱契约；另与第 2 条（失败必留痕）相邻——此处失败被 Log.w 吞掉。

## 视角 C1 · lib/logic/auth/ykg_logic.dart:27-38,140-152 · P1 · 凭据写入双路径 + 设置键字面量复制
证据：YkgLogic 自行复制一份键名常量（`_kToken='auth.token'` … `_kT1='auth.t1'`，27-38 行），并在 `importLink` 里直接 `_settings.setString(...)` 写 7 个键（140-152 行）；而 `AuthLogic._applyCredentials`（`auth_logic.dart:416-451`）是另一条权威写入路径。`AuthLogic` 的键常量已公开（`kSettingToken/kSettingUserid/kSettingMid/kSettingDfid/kSettingKugouApiMid/kSettingVipToken/kSettingVipType/kSettingT1`），且 `account_logic.dart:11-18` 已同层直取。
问题：(a) 同一批凭据键有两处定义，改一处必漏另一处；(b) YKG 导入路径绕开 `_applyCredentials`，不写 `KUGOU_API_MID`、不写 `auth.t1` 独立键、不做「旧字段清理」，与扫码/验证码登录落库口径不一致 → 跨接缝的持久化状态机分叉。
建议：YkgLogic 改为持 `AuthLogic` 并调用其凭据写入口（或把 `_applyCredentials` 提升为 L5 内部共享写入器）；键名一律 import `auth_logic.dart` 的常量，删除本地副本。
76 合规：违反第 4 条（L5 内单一写入路径）与「参数多参不缺参」的同源口径要求。

## 视角 C1 · lib/logic/auth/auth_logic.dart:93-110,134-140 · P1 · L5 直触网络层 + 端点未分文件
证据：`AuthLogic.createQrLogin/pollQrLogin` 直接 `_client.request(EndpointRegistry.loginQrKey, {...手拼参数...})`，参数含 `appid/type/plat/qrcode_txt/srcappid`；`EndpointRegistry.loginQrKey/loginQrCheck` 定义在 `core/net/endpoint_registry.dart:354-365`，**没有对应的 `core/net/endpoints/*_endpoints.dart` 模块**（rg `EndpointRegistry.loginQr` 在 endpoints/ 目录零命中）。同域其它登录端点（sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout）全部封装在 `core/net/endpoints/auth_endpoints.dart`。
问题：同一登录域两种接法：QR 登录在 L5 拼报文直连 L4 客户端（端点层被跳过），其余走 L4 端点封装；报文知识（appid/plat/qrcode_txt 格式）落在 L5，端点模块缺失。
建议：为 QR 登录补 `core/net/endpoints/qr_endpoints.dart`（每端点一模块），把参数拼装与 `data.status` 语义解析下沉到 L4；L5 只调门面。
76 合规：违反第 6 条（core/net/endpoints/ 每端点一 dart 模块）与第 1 条（L5 不得越过 L4 端点层自触网络）。

## 视角 C1 · lib/surface/pages/login_sheet.dart:424-440 · P1 · L7↔L5 签名不匹配（dynamic 逃逸）
证据：`_PwdTabState._login()`：`final dynamic auth = appGraph.auth; await auth.signInByPwd(pwd);`（431-432），账号输入框 `_account.text` 计算后（426 行 `final acc = ...`）**完全未使用**；`AuthLogic.signInByPwd(String pwd, {String code = ''})`（`auth_logic.dart:286-289`）本身也无账号参数。且 `_PwdTab` 在 `login_sheet.dart:124` 以 `_PwdTab()` 无参构造，**未接 `onLoginSuccess`**（其它三个 Tab 都有），故密码登录成功后不会落账号档案、不 bumpAuth、不关弹层。
问题：L7↔L5 的密码登录契约在两端都不完整（缺账号、缺结果返回形态、缺成功回调），用 dynamic 调用把编译期检查一并关掉；登录域出现「扫码/验证码/YKG 三个入口有统一收口、密码入口没有」的分叉。
建议：`AuthLogic.signInByPwd(account, pwd, {code})` 返回 `LoginResult`；L7 去掉 dynamic，按与其他 Tab 相同的 `_onLoginSuccess` 收口；`account_logic` 侧同样用 `acc`。
76 合规：违反第 1 条（L7 直连 L5 门面且契约不对齐）与第 6 条「参数多参不缺参」。

## 视角 C1 · lib/session/bootstrap.dart:124-129 · P1 · L6 装配期快照 vs 运行时登录态（VIP 凭据不回灌）
证据：`PlaybackService(... session: {'vip_token': settings.getString('auth.vip_token') ?? '', 'vip_type': settings.getString('auth.vip_type') ?? ''})` 在 **bootstrapSession 装配时刻**读取一次。运行时 `AuthLogic._applyCredentials`（`auth_logic.dart:416-451`，其中 447-449 行写 vip_token/vip_type/t1）与 `YkgLogic.importLink`（140-152 行）写入 settings 后，无任何路径把新 vip 值回灌到 `PlaybackService`；`AccountLogic.switchTo`（`account_logic.dart:111-116`）甚至**完全不写 vip_token/vip_type/t1**，切号后旧号 VIP 凭据残留。
问题：VIP 凭据在「启动时已登录」路径有效，在「本次会话内登录/导入/切号」路径失效——装配图是快照不是活引用，跨层接缝的状态不随写入传播。
建议：PlaybackService 不吃快照，改由 L5 提供 `vipToken` 只读 getter（或 L6 订阅登录态变更后重注）；`AccountLogic.switchTo` 补齐 vip_token/vip_type/t1 与 KUGOU_API_MID 的全量回写（对齐 `_applyCredentials`）。
76 合规：违反第 4 条（L6 装配图应反映真实依赖状态）与「参数多参不缺参」的字段一致性。

## 视角 C1 · lib/logic/auth/verification_logic.dart:23-134 · P1 · L5 状态机无 L7 出口
证据：`VerificationLogic` 位于 L5（符合分层），`AppGraph.verification` 已在 `graph.dart:135/171` 暴露，`bootstrap.dart:186-190` 装配、`playback_session.dart:213` 调 `onVerificationRequired(20028, ...)`。但 rg `VerificationLogic|VerificationState` 在 `lib/surface/` **仅 1 处注释命中**（`login_sheet.dart:3` 的文件头说明），**无任何代码引用**；L7 无任何验证 UI，`required` 状态无法被消费。
问题：验证状态机跨层链路止于 L6，无 L7 出口 → 20028 时用户在 UI 上看不到任何提示与出口（与阶段 A 记录一致，阶段 B 复核：断点仍在，只是断在 L7 侧而非 L5 侧）。
建议：L7 增加验证出口（读 `AppGraph.verification.state` → 渲染 TCaptcha → 调 `submitVerification`），或明确记录「验证 UI 未交付」的占位契约。
76 合规：符合第 4 条（L5 状态机归属正确）；违反 SEVEN_SIX_RULE §1「L6 只对外暴露状态/回调 + L7 消费」的闭环要求。

## 视角 C1 · lib/surface/pages/login_sheet.dart:53-500 + login_account_section.dart:35-84 · P1 · i18n 归口：登录链路大量硬编码中文
证据：login_sheet.dart 含硬编码中文的字符串字面量行 29 处（rg 计数），例如「正在获取二维码…」「二维码获取失败，请重试」「请使用酷狗音乐 App 扫码」「请输入手机号」「验证码已发送至 …」「登录失败：…」「请输入账号与密码」「密码登录待后端就绪」「已切换账号/切换失败」等；login_account_section.dart 4 处（「已登录账号」「暂无账号，登录后将自动保存到这里」「账号 ${rec.accountId}」「移除账号」）。对照：ykg_sheet.dart **全部**走 `S.of(context).t(...)`（0 硬编码），Tab 标题也走 `s.t('qrLogin'/'smsLogin'/'pwdLogin'/'ykgTitle')`。
问题：同一登录弹层内 YKG 走 i18n、扫码/验证码/密码/账号区走硬编码，i18n 归口未闭合；L4 `core/l10n/strings.dart` 与 10 份 arb 中并无这些中文键，说明文案根本未进入 L4 常量表。
建议：为上述 29+4 处补 arb 键并由 tool/gen_i18n.py 同步进 `strings.dart`，L7 一律 `S.of(context).t(...)`；补键时把 `errorGeneric` 等既有键复用而非新造。
76 合规：符合 SEVEN_SIX_RULE §5（i18n 常量表在 L4 core/l10n/strings.dart、S 门面在 L7），但登录链路文案未走该链路 → 违反「单一事实源」的归口要求。

## 视角 C1 · lib/surface/pages/login_sheet.dart:190,203-205,322,361 + login_account_section.dart:88 · P2 · 桥日志纪律：失败静默吞 / L7 无 Log 通道
证据：`login_sheet.dart:190` `catch (e)` 后只 setState 文案不 Log；`203-205` `catch (_) { return; }` 轮询失败**完全静默**；`322`/`361` catch 只 toast。`login_account_section.dart:88` 用 `debugPrint('surface.login: account section failed: ...')` 而非 Log。`tool/layer_audit.py:40` 的 L7 白名单 = {bridge_surface, bridge_session, bridge_logic, bridge_core}，**不含 bridge_kernel**，故 L7 拿不到 Log 门面（bridge_logic 转出了 `Log`，但 L7 未用）。
问题：跨层失败在 L7 侧不留痕，轮询瞬时失败连 debugPrint 都没有 → 线上无法定位；根因是 L7 无日志通道（架构约束与「失败必 Log」铁律冲突）。
建议：L7 统一改用 `bridge_logic` 转出的 `Log.e/d`（或把 Log 加入 L7 白名单并更新 `LAYER_ALLOWED_BRIDGES` 注明理由）；轮询 catch 至少 `Log.w` 一次。
76 合规：违反第 2 条（桥接层承担日志任务：失败必 Log 留痕，不静默吞）。

## 视角 C1 · lib/core/net/crypto_aes.dart:1-11,690 · P2 · 成熟库边界：登录链仍用自研 AES
证据：`crypto_aes.dart` 为纯 Dart 自实现 AES-128-CBC（792 行，自带 S 盒/GF(2^8)/ECB/CBC），`crypto_extra.dart` 转出 `AesCbc`，`auth_endpoints.dart:30` `import '../crypto_extra.dart'` 用于登录端点 secu_params 解密；而 YKG 新链路已用成熟库 `package:cryptography/cryptography.dart`（唯一 cryptography 依赖在 `core/net/ykg_codec.dart:25`，位置正确）。
问题：同一登录域并存两套密码学实现——新链路用成熟库、旧链路自研；用户 2026-11-16 指令「算法一律调用成熟库」在登录/歌单加密端点侧尚未落地。
建议：登录端点解密迁到 `package:cryptography`（CBC/PKCS7），`crypto_aes.dart` 仅保留兼容/测试用途并标注退役计划。
76 合规：违反第 9 条（能用成熟库就用成熟库）；YKG 侧 cryptography 依赖仅落 L4，符合第 4 条（cryptography 依赖只在 L4）。

## 视角 C1 · lib/core/l10n/strings.dart:7 + lib/bridges/bridge_core.dart:49 · P2 · L4 自引用式绕桥 + 桥↔core 循环依赖
证据：`strings.dart:7` `import '../../bridges/bridge_core.dart' show KeyValueSettings, StoragePaths;`（取的是同层 L4 的 core/storage 类），而 `bridge_core.dart:49` 又 `export '../core/l10n/strings.dart' show TnStrings;` → bridge_core ↔ core/l10n/strings 互为导入。
问题：L4 内部模块经「L3↔L4 桥」回取同层类，形成 bridge↔core 循环依赖（Dart 允许但易碎），也把 L4 常量表与桥耦合。
建议：L4 内同层引用直接 `import '../storage/settings_store.dart'`（同层合法），去掉经 bridge_core 的回取。
76 合规：符合第 4 条（同层内引用合法），但实现为绕桥自引用 + 桥↔core 循环，不符合「每层只依赖其下层经桥暴露的门面」中「下层」的方向性。

## 视角 C1 · lib/logic/auth/auth_logic.dart:463 / ykg_codec.dart:223 / auth_endpoints.dart:546 / strings.dart:676 / crypto_aes.dart:792 · 符合 · 1500 行门禁
证据：`wc -l` 结果：login_sheet.dart 504、auth_logic.dart 463、ykg_codec.dart 223、auth_endpoints.dart 546、strings.dart 676、crypto_aes.dart 792、bridge_core.dart 187、bridge_logic.dart 147、bridge_session.dart 68、bootstrap.dart 297、s.dart 46、login_account_section.dart 92。门禁阈值见 `tool/smoke_check.dart:439` `maxLines = 1500`。
问题：无。
建议：无。
76 合规：符合第 5 条（单文件超过 1500 行才按功能拆分）。

## 视角 C1 · lib/logic/auth/ykg_logic.dart:118-130 + lib/surface/pages/ykg_sheet.dart:60-90 · P2 · YKG 导出口令校验器写入但从不校验（设计闭环断在 L5/L7 缝）
证据：`YkgLogic.exportLink` 导出后把 `(saltB64, verifier)` 写入 settings（`ykg_logic.dart:105-112`，键 `auth.ykg_salt`/`auth.ykg_verifier`），并提供 `verifyPassword`（118-130）用于「重新导出时验证口令一致」；但 rg `verifyPassword` 全仓仅命中定义处，**L7 `ykg_sheet.dart` 的 `_doExport` 只校验 `logic.canExport` 与口令非空，从不调用 `verifyPassword`**；`newYkgVerifier` 的 salt 由 CSPRNG 生成但每次导出都重新生成并覆盖旧 verifier，旧口令校验形同虚设。
问题：口令校验器被持久化却无人使用；「重新导出需原口令」的安全设计在跨层接缝处断链，且写 settings 的行为给用户一种「已被保护」的错觉。
建议：`_doExport` 在已有 verifier 时先 `await logic.verifyPassword(password)`，失败则拒绝导出；或删除 verifier/salt 持久化与 `verifyPassword`，避免无效安全承诺。
76 合规：符合第 1/4 条（跨层调用均经 L6 appGraph → L5 门面）；属跨层契约未闭合。

## 视角 C1 · lib/surface/pages/ykg_sheet.dart:9-11,60-121 · 符合 · YKG 分层落位（唯一一条干净的链路）
证据：L7 `ykg_sheet.dart` 只 import `bridge_session`（appGraph）+ 本层 `design/tokens` + 本层 `l10n/s.dart`；无 Flutter 之外的网络/存储依赖。L5 `ykg_logic.dart` import `bridge_core`（encode/decode/verifier）+ `bridge_kernel`（Log），无 Widget、无 IO 直连（凭据读写经 L4 `KeyValueSettings` 门面）。L4 `ykg_codec.dart` 纯 dart + `package:cryptography`，零 Flutter/Widget/BuildContext，密码学依赖只在 L4（rg 确认全仓 cryptography 仅 1 处）。L6 `bootstrap.dart:198-208` 注入 YkgLogic（client/settings/auth/onImported）。L5 内 `rg bridge_session` 零命中 → 阶段 A 修掉的「ykg_logic 反向依赖 bridge_session」**无残留**。
问题：无。
建议：无。
76 合规：符合第 1、4 条（六桥唯一通道、依赖方向 surface→session→logic→core，无反向依赖）。

## 视角 C1 · lib/session/graph.dart:83-146 · 符合 · L6 装配图无越权（纯数据图）
证据：`AppGraph` 全部字段为 L5 logic 类型 + L4 client/DAO，`SessionDeps` 聚合 L4 门面；`graph.dart` 只 import `bridge_core`/`bridge_logic`，无 Widget、无 surface 反向 import（`rg surface lib/session/` 仅注释命中）。
问题：无。
建议：无。
76 合规：符合第 4、8 条（L6 装配图/状态暴露，无播放控制/缓存/预读下沉）。

## 视角 C1 · lib/surface/pages/login_sheet.dart:13-20 · 符合 · L7 无 core/logic/session 直连 import
证据：`rg "import '.*(core/|logic/|session/)" lib/surface/` 全目录零命中；login_sheet/ykg_sheet/login_account_section 的跨层 import 全部经 `lib/bridges/` 三座桥（bridge_core/bridge_logic/bridge_session），无影子桥目录（`ls lib/bridges` 仅六座）。
问题：无。
建议：无。
76 合规：符合第 1、3 条（禁止跨层直接 import 非桥文件；桥文件唯一存在于 lib/bridges/）。

---

## 本视角结论

1. **六桥唯一通道有口**：bridge_core 把 L4 端点函数（sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout）与 YKG 密码学原语（encode/decode/verifier）一并 export 到全层，L7 可绕过 L5 直取；login_sheet.dart:13-14 已把 sendSmsCode/smsLogin/KugouApiException 握在手里（虽未用）。属阶段 A 未收口的口子。
2. **QR 登录状态机劈成两半**：状态枚举+单次取状态在 L5（auth_logic），轮询驱动/四态迁移/过期只重建一次在 L7 Widget（login_sheet.dart:147-247）。业务策略落在 surface，不可测不可复用。
3. **L6 登录态门面是死壳 + 双广播总线**：AuthSession.attach 零调用者 → isLoggedIn 恒 false；登录成功走 NavState.bumpAuth，YKG 导入走 AuthSession.notifyAuthChanged（0 订阅者），导致 **YKG 导入后 L7 登录态不刷新**。
4. **凭据写入双路径**：AuthLogic._applyCredentials 与 YkgLogic.importLink 各写一份 settings，YkgLogic 还复制了 8 个键名常量；AccountLogic.switchTo 不写 vip_token/vip_type/t1。
5. **VIP 凭据只在启动快照有效**：bootstrap.dart:124-129 装配时读一次 settings，运行时登录/YKG 导入/切号不回灌 → 「VIP 恒 false」修复仅覆盖冷启动已登录场景。
6. **密码登录链路两头都不完整**：L7 用 dynamic 调 signInByPwd、账号输入未使用、无 onLoginSuccess 收口（login_sheet.dart:124/424-440）。
7. **QR 端点无独立模块**：loginQrKey/loginQrCheck 只有 registry 里的裸 Endpoint，AuthLogic 在 L5 手拼参数直连 _client.request，违反「每端点一 dart 模块」。
8. **i18n 归口只覆盖了 YKG**：ykg_sheet 全走 S.of，登录其余三 Tab + 账号区共 33 处硬编码中文（29+4），且这些键在 10 份 arb / strings.dart 中完全不存在。
9. **桥日志纪律在 L7 破口**：轮询失败 `catch (_) { return; }` 静默吞；账号区用 debugPrint 而非 Log；L7 白名单不含 bridge_kernel 是根因。

## 未覆盖

- 未读全文：`lib/core/net/endpoints/auth_endpoints.dart`（546 行，仅抽读头部与端点索引）、`lib/core/net/crypto_rsa*.dart`、`crypto_bigint.dart`、`crypto_extra.dart`、`lib/core/storage/paths.dart`、`lib/session/nav_state.dart`（仅读关键段）、`lib/session/playback_session.dart`（仅 grep 验证）、`lib/bootloader/bootloader.dart`（仅 grep）。
- 未核对：arb 10 语全量译文质量与键值一致性（仅用脚本确认键集一致，`en`/`zh_Hant` 缺 `@appTitle` 属元数据键，不影响）；YKG 密文协议正确性、PBKDF2/AES-GCM 参数安全强度、TTL 与过期校验实现（属 C2 密码学范畴）。
- 未核对 L7 之外的 UI 细节（M3、动效、触控、硬编码色值）——属 C3/B6。
- 未跑门禁/分析器/测试（工具纪律禁止），所有结论基于静态阅读与 rg/wc。
- 未验证 `bridge_surface` 在本链路是否被绕过（`rg bridge_surface lib/surface/` 仅命中注释与 app_root/tn_theme 说明），登录链路 L7 确实未用 bridge_surface。

## 76 合规小结（本视角）

- 符合：第 3 条（无影子桥）、第 5 条（无文件超 1500 行）、第 6 条部分（auth_endpoints 端点分文件 OK；QR 端点缺失模块）、第 8 条（L6 无播放控制/队列/缓存下沉）、第 9 条部分（YKG 用成熟库 cryptography 且仅在 L4；旧登录链路仍自研 AES）。
- 违反：第 1 条（L7 越级取 L4 端点/L5 类型；L5 直触网络层）、第 2 条（L7 侧失败静默吞、无 Log）、第 4 条（L7 塞状态机；L6 门面未接线；凭据双写入路径；装配快照不回灌）、第 6 条（QR 端点未分模块）、第 9 条（登录端点自研 AES）。
- 阶段 A 修复核验：ykg_logic 对 bridge_session 的反向依赖**已清零**（rg 零命中），符合「L5 不反向依赖 L6」；但「YKG 导入后 L7 登录态刷新」与「VIP 凭据运行时回灌」两条跨层链路**仍未生效**。

---

## 落盘记录

- 2026-11-17 07:05–07:35 (Asia/Shanghai) · 视角 C1 · 全部 20 条发现一次性落盘（本文件首次写入）。
- 复核时刻：`wc -l` 实测 login_sheet.dart=504（任务书所写 461 已过时，以实测为准）；`lib/surface/` 内 `core/|logic/|session/` 直连 import 零命中；`lib/logic/` 内 `bridge_session` 引用零命中（阶段 A 修复生效）。
