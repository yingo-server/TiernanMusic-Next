# B1 批 · C2 实现正确性视角（登录全链路 + YKG 新方式）

> 审查时间：2026-11-17。审查人：阶段B·B1·C2 子代理。
> 范围：L7 login_sheet/ykg_sheet/login_account_section → L6 auth_session/bootstrap/graph → L5 auth_logic/account_logic/ykg_logic/verification_logic → L4 auth_endpoints/ykg_codec/settings_store/signing/crypto_aes。
> 方法：逐文件连续读完 + 跨层追踪；只读取证，未跑编译/测试。以下每条均带时间戳小节。

---

## 视角 C2 · bootstrap.dart:115-128 + playback_service.dart:124,146,173 · P0 · 跨层接缝/VIP 快照（阶段A修复未闭环）
证据：`bootstrap.dart:124` 构造 `PlaybackService(... session: <String,Object?>{'vip_token': settings.getString('auth.vip_token') ?? '', 'vip_type': settings.getString('auth.vip_type') ?? ''})`；`playback_service.dart:124 final Object? _session;` 为 final 字段，构造后不可变；`playback_service.dart:146-160 _hasRights` 每次都读这个固定 Map；`auth_logic.dart:447` 登录成功后 `_applyCredentials` 只写 `settings.setString(kSettingVipToken, vipToken)`，从不回写 PlaybackService。
问题：任务书重点疑点属实——bootstrap 仅在**启动时**把 vip 快照注入 PlaybackService；登录（QR/SMS/密码/YKG 导入）发生在启动之后，vip_token/vip_type 变化后 PlaybackService 持有的仍是启动时的旧 Map，恒为登录前的状态（未登录则恒 false）→ 登录后 VIP 曲仍按匿名音质降级，除非重启 App。阶段A「VIP 恒 false」只修了「没传 session」，没修「传了快照不刷新」，跨层未真正生效。
建议：改为注入动态取值函数（如 `Object? Function() sessionProvider`）而非快照 Map，让 `_hasRights` 每次读 settings/client.session 当前值；或在登录/切号/YKG 导入成功后调用 PlaybackService.refreshRights() 重建快照，并在 L7 登录成功收口与 navState.bumpAuth 一并触发。
76 合规：同层职责错位——L6 bootstrap 把一个会随登录变化的 L5 权益状态当静态依赖注入，违反「状态归所属域、门面取当前值」精神（第0条职责边界）。

---

## 视角 C2 · verification_logic.dart:88-121 + playback_session.dart:213 + L7 surface 全域 · P0 · 跨层接缝/20028 死链（阶段A修复未闭环）
证据：`verification_logic.dart:88` getVerifyInfo 只 `Log.w(... needs probe)` 后 `return false`，从不发请求；`verification_logic.dart:104-119` submitVerification 仅 `_state = solving; return false`，从不外发；`markSolved()`(:123) 全仓零调用（rg 确认）；`playback_session.dart:213 _verification?.onVerificationRequired(20028, cur.hash)` 把状态置 required；但 `rg -n "VerificationLogic|verification" lib/surface/` 仅命中 login_sheet 顶部注释，L7 无任何验证 UI / 消费出口。
问题：阶段A只打通「session→门面触发 required 状态」，L7 验证出口仍不存在。用户遇 20028 的真实体验：播放匿名/VIP 受限曲 → 置 required → 没有任何验证 UI，state 永远停在 required/solving，solved/failed 不可达，播放请求无法重试 → 卡死。端点「未实测」诚实标注了，但跨层结果是功能完全不可用。
建议：L7 增加验证弹层出口（在 player_page 监听 NavState/VerificationLogic.state==required 时弹出），接 TCaptcha 桥捕获 ssaCode 后调 submitVerification，并补真实提交端点 + 提交成功后 markSolved + 重放原播放请求；在端点未实测前至少在 UI 给出「需验证但暂不可用」的明确态，避免静默卡死。
76 合规：L5 状态机（required→solving）已就绪但 L7 未消费，属六层链路「状态生产端有、消费端缺」的断链（第4条相邻桥唯一通道之外的跨层可达性问题）。

---

## 视角 C2 · ykg_codec.dart:105-118,133-140 · P1 · 加密设计/过期与字段未绑定 AAD
证据：`encodeYkgLink` 把 `ts/exp/u/v/d/m` 放在 payload 顶层明文，AES-GCM 只加密 canonical plain（cookie/token/...），`aad: utf8.encode(kYkgAad)` 是固定常量 'ykg-v1'（:76,127），不含 exp/u/ts；`decodeYkgLink:116 if (exp is int && exp < now) return fail('link expired')`。
问题：exp 等元数据未纳入 AAD，tag 不保护它们。持链接者可把 exp 改成极大值绕过 7 天过期（Payload 是 base64url JSON，无需密码即可改），u/d/m 同理可篡改（d 只比对解密出的 plain 的 md5，改 d 反而触发 integrity mismatch，但 exp 完全无校验）。密码错/篡改密文统一拒绝的设计（catch 统一 'wrong password or damaged link'，:141-148）、aad 固定绑定、PBKDF2.hmacSha256 + base64Url.decode 的编译修复本身逻辑正确；但「过期校验」这一环可被明文篡改绕过。
建议：把 exp/ts/u/v/d/m 纳入 AAD（如 aad = utf8.encode('ykg-v1|'+jsonEncode({v,exp,ts,u,d}))），使 tag 一并保护元数据；或对整段 payload 签名。解码时 exp 非 int 也应 fail（当前 `exp is int` 为 false 会跳过过期检查）。
76 合规：L4 密码学封装职责内，无越级；此为算法封装正确性缺陷。

---

## 视角 C2 · ykg_logic.dart:162 + bootstrap.dart:206 + auth_session.dart:50-83 + settings_page.dart:39 · P1 · 跨层接缝/导入后登录态不广播
证据：YKG 导入成功走 `_onImported` → `AuthSession.instance.notifyAuthChanged()`（bootstrap.dart:206）；但 `rg "AuthSession.instance.attach"` 全仓零命中——`AuthSession._client` 从未注入，`userid` 恒返回 ''、`isLoggedIn` 恒 false；且 `onAuthChanged` 的 `_listeners` 无任何注册消费者（settings_page.dart:39 监听的是 `navState().addListener`，不是 AuthSession）。导入路径也不调 `navState().bumpAuth()`、不调 `account.saveCurrent()`。
问题：YKG 导入成功后，通知打到一个「未 attach、无人订阅」的死单例上，等于空转。对比普通登录 `_onLoginSuccess`（login_sheet.dart:95-101：saveCurrent + bumpAuth + 回调 + pop），导入后账号区不显示新账号、设置页/收藏页登录态不刷新、NavState.authVersion 不自增——用户导入后界面仍显示未登录，必须手动重启才一致。
建议：导入成功后复用普通登录的统一收口：在 L7 导入成功分支调 `appGraph.account?.saveCurrent()` + `navState().bumpAuth()` + 回调；或让 AuthSession 真正 attach client 并把各页订阅从 navState 统一到 AuthSession，二选一避免双轨。AuthSession 当前是死代码，应接线或删除。
76 合规：L6 同时存在 AuthSession 与 NavState 两套登录态广播且均未闭环，违反「单一门面」职责（第0条）。

---

## 视角 C2 · ykg_logic.dart:80-96 + auth_logic.dart:436-448 + kugou_client.dart:258-262 · P1 · 凭据链不完整/QR 登录导出无 cookie
证据：`exportLink`(:88) cookie 来自 `s.cookies.entries` 拼串；`pollQrLogin` status=4（auth_logic.dart:150-162）成功时只取 token/userid 调 `_applyCredentials`，vipToken/vipType/t1 全用默认空串；kugou_client.dart 全仓无 Set-Cookie 响应采集（仅 :258 把 session.cookies 写入请求头）。
问题：QR 登录后 session.cookies 为空（登录响应未解析 Set-Cookie/cookie，_applyCredentials 也没写入），此时 YKG 导出的 cookie 字段为空、vip 为空；导入另一端 restoreSession 恢复的 cookie 也为空 → t1 播放权限 cookie 缺失。而 VIP 曲权限实际依赖 token + cookies 中的 t1（kugou_client 只带 token 和 cookies，settings 里的 vip_token 根本不进请求参数）。因此「导入 YKG 后能否请求 VIP 曲」在 QR 登录来源下大概率失败——凭据从源头就缺 cookie/t1。
建议：QR 登录成功解析响应的 cookie/Set-Cookie 并写入 session.cookies + settings（auth.cookie/t1），或明确 YKG 只在「已采集完整 cookie 的登录方式」下可用并在 canExport 增加 cookie 非空校验；端点实测后补齐 vip_token 的实际 usage。
76 合规：跨层「登录→session→导出→导入→请求」凭据字段不一致，属接缝数据契约缺失（第0条）。

---

## 视角 C2 · auth_endpoints.dart:38 + :280-360,400-440,510-540 · P1 · 三态冒充可用（阶段A文案未掩盖）
证据：`auth_endpoints.dart:38 const bool kAuthEndpointsProbed = true`，但 rg 全仓该文件无第二处引用；文件头 :8-16 明确 sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout「待实测 → needsProbe」，而实际返回构造从不到 `needsProbe: true`（smsLogin :340-352、loginByPwd :430-438、loginByToken :510-520 均硬编码 ok/error，无 needsProbe 字段）。
问题：A3 曾定位「5 个登录端点标待实测却 kAuthEndpointsProbed=true 放行真实外发」。阶段A只加了 S.of 文案（PwdTab catch 显示「密码登录待后端就绪」，SmsTab 显示「端点待实测」），但代码仍向酷狗官方域名**真实外发未实测的随机 RSA/AES 载荷 + 真实手机号/密码**，且失败时返回普通 error、needsProbe 恒 false，UI 诚信提示与代码行为脱节。SmsTab 用后端布尔决定「验证码已发送至 138****1234」，可能误导用户以为真的发送。
建议：要么在端点未实测前用 kAuthEndpointsProbed 短路、统一返回 needsProbe:true 不发网络请求；要么完成端点实测后移除「待实测」文案。两者必须一致，避免文案掩盖未实现。
76 合规：UI 文案（L7）与端点真实能力（L4）不一致，属跨层语义断层。

---

## 视角 C2 · ykg_sheet.dart:76-100,110-125 + login_sheet.dart:490-496 · P2 · 导入成功后未关登录弹层/未刷新
证据：`_doImport` 成功仅 `_set('登录成功'); Navigator.of(context).pop()`——只 pop 的是 YKG 子弹层；外层登录弹层 `showLoginSheet` 仍在；`_doExport` 成功后只复制+显示 link。
问题：YKG 导入成功后外层登录页不关闭、账号区不刷新（同 C2 导入不广播条）。用户会看到「登录成功」但仍停在登录弹层且显示未登录，体验割裂。与 F1 结论同源，列 P2 避免重复报点。
建议：导入成功后统一走 `_onLoginSuccess`（关所有弹层 + 刷新）。
76 合规：L7 登录态收口路径不统一。

---

## 视角 C2 · ykg_codec.dart:157-165 + ykg_logic.dart:120-141 · P2 · 口令校验值不参与导出/导入验证
证据：`newYkgVerifier`(:157) 生成独立 salt+verifier 存 settings（_kYkgSalt/_kYkgVerifier），`verifyPassword`(:120) 提供校验，但 rg 全仓 `verifyPassword` 除 ykg_logic 定义外零调用；导入只用 decodeYkgLink 的 GCM tag 验密码。
问题：verifier 存了却无人用，是死逻辑；「重新导出时验证口令一致」的设计未接线。无害但增维护面。
建议：导出前若已有 verifier 则先 verifyPassword 校验，并在 L7 提示；否则删除 verifier 相关死代码。
76 合规：L5 内部死逻辑，无越级。

---

## 视角 C2 · login_sheet.dart:318-420 + auth_logic.dart:264-282 · P2 · 自动续期无取消/竞态
证据：`_tryRefreshToken`(:264) 在 restoreSession 中 fire-and-forget 调 loginByToken，成功则 `_applyCredentials` 覆盖 token/vip；无取消句柄、无 mounted 判断；QR/SMS 登录也会触发登录成功路径。
问题：启动时自动续期与用户随后主动登录可能并发写 session/settings，出现「旧 token 续期成功覆盖新登录凭据」的竞态（登录晚于续期发起时）。概率低但属跨层异步接缝。
建议：给续期加 token 版本校验，_applyCredentials 仅当 client.session.token 仍等于续期发起时的 token 才覆盖；登录成功时取消在飞续期。
76 合规：异步状态写入无版本保护，属接缝竞态。

---

## 视角 C2 · ykg_codec.dart:96-110,133-150 + signing.dart:266 · P2 · 密码学修复核验结论（正向确认）
证据：`_derive`(:190) 用 `Pbkdf2.hmacSha256(iterations:120000, bits:256)` + `SecretKey(utf8.encode(password))` + nonce=salt；`_b64UrlDecode`(:216) 正确补 '=' 后 `base64Url.decode`；AesGcm.with256bits() encrypt/decrypt 的 secretKey/nonce/aad/mac/nonce 均按 cryptography 2.7 签名；md5Hex(signing.dart:266)=Md5.hex 自研但仅用于 d/m 指纹，非安全判据。
结论：阶段A修的两处编译错（Pbkdf2.hmacSha256 / base64Url.decode）逻辑正确，密码错误/密文篡改通过 GCM tag 统一拒绝、aad 固定绑定、d 指纹校验 plain 完整性，设计自洽。**唯一实质缺口是 exp 未入 AAD（已单列 P1）**。
76 合规：算法走成熟库、封装自研，符合「成熟库优先」纪律。

---

## 本视角结论
本视角共出 **8 条**（P0×2 / P1×4 / P2×3 含 1 条正向确认）。最严重三条：
1. **VIP 快照恒旧/恒 false**（bootstrap 注入一次性 Map，登录后不刷新）——阶段A「VIP 恒 false」修复跨层未闭环，P0。
2. **20028 验证死链**（VerificationLogic required→solving 无 UI 出口、端点不发请求）——用户遇 20028 必卡死，P0。
3. **YKG 端到端两处断点**：导入后通知打到未 attach/无订阅的死 AuthSession、不改 NavState（P1）；QR 登录来源缺 cookie/t1 导致 VIP 曲凭据不全（P1）。
阶段A 两条编译错（Pbkdf2/base64Url）经核逻辑正确；YKG 密码学封装自洽，唯一缺口是过期等元数据未纳入 AAD 可被明文篡改绕过。

## 未覆盖
- 10 语 arb 逐 key 文案质量核对（本视角只看 zh TnStrings 关键 key 存在性）。
- 10 套登录端点真实网络行为/响应字段（禁止联网，按文档标注推断）。
- crypto_aes Rcon 修复的标准向量复验（阶段A A2 已确认，本视角仅静态核对 _kRcon 表存在）。
- graph.dart 装配字段与 bootstrap 全量一致性逐字段比对（超出登录/YKG 范围）。
- 60 分钟硬超时内已完成范围全读，无因超时遗漏的清单内文件。

## 76 合规小结
- 层落位：L7 只画控件、L4 只做密码学/端点，整体守层；主要越界是 **L6 同时维护 AuthSession（死单例）与 NavState 两套登录态广播且均未闭环**（职责分散），及 **bootstrap 把动态权益状态当静态依赖注入**（状态归属性错位）。
- 跨层接缝：VIP 快照不刷新、20028 状态无消费端、YKG 导入通知空转、QR 登录缺 cookie 传递，均为「单层看着对、链路断在接缝」，是阶段B重点命中形态。
- 成熟库纪律：YKG PBKDF2/AES-GCM 全走 cryptography 2.7，合规；仅 exp 元数据未纳入 AAD 属封装设计缺陷，非越级。
- 凭据安全：token/vip_token 日志仅打长度、手机号脱敏、口令不存明文（verifier 独立 salt），合规；verifier 死代码属冗余非违规。
