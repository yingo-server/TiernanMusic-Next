# 批2-C2 · 登录 UI 检查（只读）

## 1. settings_page 账号段现状
- 未登录卡（截图样式）：settings_page.dart:139-152 — ListTile：person_outline 图标 + 「未登录」+ 副标题「扫码登录后同步收藏与历史」，卡片容器 `_group`（:246）。
- 「扫码登录」按钮：settings_page.dart:132 — `FilledButton(onPressed: () => _toast('扫码登录入口待接入'))`，**纯占位**，无任何 AuthLogic 调用。
- 已登录态：:137-139 — title「已登录」+ subtitle 昵称（activeAccount displayName，兜底「酷狗用户 $uid」），trailing 换成 TextButton「登出」。
- 登出入口：已有 — `_logout()`（settings_page.dart:63-72）调 `auth.logout()` 并 setState 清空 + `_loadAccount()` 重读。

## 2. 登录 UI 最小方案（新建 lib/surface/pages/login_sheet.dart）
- 形态：`showModalBottomSheet`（复用现有弹层风格，参照 `_openQualitySheet`），入口为 settings_page.dart:132 的 onPressed 改为 `showModalBottomSheet(builder: (_) => const LoginSheet())`。
- Tab 切换：`DefaultTabController(length: 3)`，TabBar「扫码 / 验证码 / 密码」；三 Tab 各为 StatefulWidget。
  - 扫码 Tab：initState 调 `appGraph.auth.createQrLogin()`，显示 `QrLoginState.qrImageB64`（Image.memory base64 解码；官方图优先，勿自编码）；Timer.periodic(~2s) 调 `pollQrLogin`，按 QrLoginStatus 4 态文案：expired→「二维码已过期，点击刷新」+ 刷新按钮；waitScan→「请使用酷狗音乐 App 扫码」；waitConfirm→「已在手机上扫码，请确认登录」；success→停止轮询、通知并关闭。
  - 验证码 Tab：手机号 TextField + `VerificationLogic.sendSmsCode` / `smsLogin`（经 bridge_logic 批5-A 已导出，bridge_logic.dart:115-116）。密码 Tab：账号密码表单（若 AuthLogic 无对应方法则标注 GAP，先占位）。
- 成功通知：**建议扩展 NavState**（lib/session/nav_state.dart）加 `authVersion` int + `bumpAuth()`/getter，登录/登出时 `bumpAuth()` 触发 listener——比逐页回调更符合现有 NavState 监听模式（L6 纯 Dart，零 flutter 依赖）。login_sheet 成功后：`auth` 落 token（AuthLogic 内部已管）→ `navState().bumpAuth()` → `Navigator.pop`。
- 行数：约 180-240 行（3 Tab + 轮询 + 表单），单文件可达，无需新通用组件（Sp tokens/components 已够）。

## 3. AccountLogic 多账号 UI 与刷新机制
- 无可复用组件：AccountLogic 的 switchTo/多账号能力已在 L5 装配，但 L7 零 UI（research doc §4 确认）。可在登录弹层加底部「账号列表」分区，或后续批再加切换 sheet。
- 登录后需刷新的页（均监听 NavState.authVersion 后重载）：
  - settings_page：重跑 `_loadAccount()`；
  - home_page：每日推荐区（home_page.dart:203 未登录恒空态，死循环空态）；
  - 收藏/历史（音乐库页）：CollectLogic/HistoryRecorder 相关页登录后拉远端同步。

## 4. 涉及文件与修改点
- lib/surface/pages/login_sheet.dart:新建（~200 行，LoginSheet + 3 Tab 组件）。
- lib/surface/pages/settings_page.dart:132:onPressed 由 _toast 改为打开 LoginSheet；:63 `_logout` 增加 `navState().bumpAuth()`；本页监听 authVersion 触发 _loadAccount。
- lib/session/nav_state.dart:新增 authVersion 字段 + bumpAuth()/clearAuthVersion()（约 +20 行）。
- lib/surface/pages/home_page.dart:203 附近:监听 authVersion，登录后重拉每日推荐。
- 收藏/历史页（音乐库模块文件）:监听 authVersion 重载列表。
- 不改：bridge_logic.dart（AuthLogic/VerificationLogic/AccountLogic/SmsLoginResult 均已导出）、bridge_session.dart（NavState 已导出）。

## 必修 TOP5
1. settings_page.dart:132 占位按钮 → 接入 LoginSheet（唯一登录入口，当前死循环空态根源）。
2. 新建 login_sheet.dart 扫码 Tab：createQrLogin + qrImageB64 展示 + pollQrLogin 4 态轮询。
3. NavState 加 authVersion 广播，登录/登出统一通知。
4. home_page.dart:203 每日推荐登录后重拉（消除「登录后可能可见」死空态）。
5. 验证码 Tab 接 VerificationLogic.sendSmsCode/smsLogin（L5 已装配零 UI）。
