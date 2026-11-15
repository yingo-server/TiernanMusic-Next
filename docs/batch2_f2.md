# 批2-F2 · 登录 UI 修改说明

## 1. 新建 lib/surface/pages/login_sheet.dart（465 行，≤500 ✅）
- `showLoginSheet(BuildContext, {onAuthChanged})`：`showModalBottomSheet(isScrollControlled:true)`，高度 70% 视口。
- `DefaultTabController(length:3)` 三 Tab，默认选中扫码（Tab 首位）。
- **扫码 Tab（_QrTab）**：initState 调 `AuthLogic.createQrLogin()`（真实签名，见 bridge_logic 导出链 auth_logic.dart:63），`qrImageB64` base64Decode 后 `Image.memory` 展示（官方 PNG 图优先，无第三方包；解码失败兜底提示容器）。`Timer.periodic(1.5s)` 轮询 `pollQrLogin(key)`，按 `QrLoginStatus` 四态：waitScan（请扫码）/ waitConfirm（已在手机上扫码）/ expired（自动重建一次，`_recreatedOnce` 标记，仅一次；之后提示手动刷新）/ success（停 Timer → onLoginSuccess）。
- **验证码 Tab（_SmsTab）**：手机号 + `发送验证码`（成功后 60s 倒计时禁点）+ 验证码 + 登录。手机号经 `_maskPhone` 脱敏（138****1234），token 不回显不进日志。
- **密码 Tab（_PwdTab）**：手机号/用户名 + 密码（obscureText + 可见性切换）；`AuthLogic.loginByPwd` 未合入，dynamic 调用包 try/catch，catch 提示「密码登录待后端就绪」，不崩。
- **底部账号区**：`AccountLogic.listAccounts()` 列 displayName/账号 id；点击 `switchTo`，删除按钮 `removeAccount`；空态文案。切换/移除/登录成功均 `navState().bumpAuth()`。
- 登录成功统一收口 `_onLoginSuccess`：`account.saveCurrent()` 落档 → bumpAuth → onAuthChanged 回调 → pop。
- Future 全部在 initState / 按钮回调中持有，build 零新建；全程 `Sp.*` 令牌（Sp.bgElevated/Sp.card/Sp.green/Sp.pagePad/Sp.gapM/Sp.fItem/Sp.fSub/Sp.text*）。

## 2. lib/surface/pages/settings_page.dart（297 行 ✅）
- L181：`FilledButton` onPressed 由 `_toast('扫码登录入口待接入')` 占位改为 `showLoginSheet(context)`；新增 import `login_sheet.dart`。
- 新增 `navState().addListener(_onAuthChanged)`（initState 注册 / dispose 移除），登录成功回调触发 `_loadAccount()` 重读账号卡（displayName/uid/已登录态）。
- `_logout()` 末尾追加 `navState().bumpAuth()`，登出同步广播。
- 说明：本页 _toast 仍有其他用途，未整体删除；任务提及的另一处占位（约 L166）经回读核实本文件仅此一处登录占位文案。

## 3. lib/session/nav_state.dart（107 行 ✅）
- 新增 `int _authVersion = 0;`、`int get authVersion`、`void bumpAuth()`（自增 + `_notify()` + `Log.d`，try/catch 留痕，零 flutter 依赖保持）。

## GAP 备注（未臆造接口）
- `VerificationLogic` 无 sendSmsCode/smsLogin 成员：两函数是 auth_endpoints.dart 顶层函数，且 bridge_logic.dart 仅 `show VerificationLogic, VerificationState`（不含 SmsLoginResult 调用入口）。因此验证码 Tab 用 dynamic 调用 + try/catch，桥补齐导出后自动生效；当前提示「发送/登录链路未就绪（needs probe）」。
- `AuthLogic.loginByPwd` 不存在（批2-F1 未合入），同上 dynamic + try/catch 兜底。

## 验收自检
- ✅ 三 Tab（扫码/验证码/密码）齐全；✅ 扫码轮询四态齐（0/1/2/4 → expired/waitScan/waitConfirm/success）；
- ✅ settings 占位已替换为 showLoginSheet；✅ NavState 有 authVersion getter + bumpAuth；
- ✅ 行数：login_sheet 465 / settings 297 / nav_state 107，均 ≤500；✅ 手机号脱敏、密码 obscureText、token 不回显。
