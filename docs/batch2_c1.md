# 批2-C1 检查报告：登录端点现状（只读，2026-11-15）

依据：docs/plan_upstream_endpoints_a.md §3、lib/core/net/endpoints/auth_endpoints.dart、lib/core/net/endpoint_registry.dart、lib/logic/auth/auth_logic.dart、lib/logic/auth/account_logic.dart、docs/research_legacy_login_url.md §1、lib/surface/pages/settings_page.dart。四栏 =「端点已声明 / 封装函数已有 / AuthLogic 已接 / UI 已接」。

## 1. 登录端点清单

| 能力 | 端点已声明 | 封装函数已有 | AuthLogic 已接 | UI 已接 | 证据 |
|---|---|---|---|---|---|
| 扫码取 key | ✅ EndpointRegistry.loginQrKey（/v2/qrcode，web 签名，registry.dart:229-231） | ✅（AuthLogic 内直调） | ✅ createQrLogin（auth_logic.dart:68-102） | ⚠️ 仅占位 toast「扫码登录入口待接入」（settings_page.dart:166-167） | |
| 扫码轮询 check | ✅ loginQrCheck（/v2/get_userinfo_qrcode，registry.dart:232-235） | ✅ | ✅ pollQrLogin（auth_logic.dart:108-152） | ❌ 同上未接 | |
| 短信发送验证码 | ✅ sendSmsCode（login.user.kugou.com/v7/send_mobile_code，registry.dart:255-258） | ✅ auth_endpoints.sendSmsCode（auth_endpoints.dart:67-93，注释标「契约待三态实测」） | ❌ 无调用 | ❌ 无 UI | |
| 短信验证码登录 | ✅ smsLogin（loginserviceretry…/v7/login_by_verifycode，registry.dart:245-250） | ✅ auth_endpoints.smsLogin（auth_endpoints.dart:99-146；kAuthEndpointsProbed=true 已外发，但注释仍标未三态实测、响应解 token/userid 未解 secu_params） | ❌ 无调用 | ❌ 无 UI | |
| 密码登录 /v9/login_by_pwd | ❌ 注册表无声明 | ❌ | ❌ | ❌ | research_legacy_login_url.md L4 |
| token 续期 /v5/login_by_token | ✅ loginToken（registry.dart:237-240） | ❌ 无封装函数 | ❌ 无调用方（token 过期不自动续期） | ❌ | research L5 |
| openplat（微信）/v6/login_by_openplat | ❌ | ❌ | ❌ | ❌ | research L6 |
| 设备注册 r_register_dev | ❌（KugouClient 有无 registerDevice 待核） | ❌ | ❌ | ❌ | research L8 |
| 设备登出 dev_logout | ❌ | ❌ | ❌（AuthLogic.logout 仅本地清凭据，不调服务端） auth_logic.dart:180-200 | ❌ | research L7 |

## 2. createQrLogin / pollQrLogin（auth_logic.dart:68-152）

- createQrLogin：`_client.request(EndpointRegistry.loginQrKey, {appid:'1001', type:'1', plat:'4', qrcode_txt:h5 扫码页 URL, srcappid})`；返回字段 `data.qrcode` = 轮询 key、`data.qrcode_img` = `data:image/png;base64,…`（去掉前缀留纯 base64 存 QrLoginState.qrImageB64，:82-93）。返回 QrLoginState{status=waitScan, qrcode=qrcode_txt+key, key, qrImageB64}。
- pollQrLogin：`_client.request(EndpointRegistry.loginQrCheck, {plat:'4', appid:'1001', qrcode:key})`；顶层 status=1 是业务码，登录态在 `data.status`：0=expired / 1(及未知)=waitScan 继续轮询 / 2=waitConfirm / **4=success**（:126-149）。status==4 取 `data.token`+`data.userid`，任一空则抛异常；成功走 `_applyCredentials(token, userid, source:'qr')`（token 回写链）。

## 3. 登录成功后 session 回写（auth_logic.dart:203-232 _applyCredentials）

回写：session.token / session.userid / session.mid（空则 _generateMid=md5(时间+dfid) 生成）；settings 键 `auth.token`/`auth.userid`/`auth.mid`/`KUGOU_API_MID`/`auth.dfid`/`auth.cookie`（cookie 串=既有 session.cookies 序列化）。
对照旧版 _afterLogin（research §3）**缺**：`vip_token`、`vip_type`、`t1`（响应 cookie t1/t2 未并入——代码注释自认「KugouClient 不回传 Set-Cookie，保留既有 cookies」）。后果：/v6/priv_url 的 viptoken 参与缺参，VIP 档位无法解锁；t1 缺失影响播放权限判定。

## 4. UI 现状

- settings_page.dart:165-168（实际 :166-167）：`onPressed: () => _toast('扫码登录入口待接入')` + `child: Text('扫码登录')` —— 登录按钮仅 toast 占位，createQrLogin/pollQrLogin 无任何 UI 消费。
- AccountLogic 多账号：logic 层齐全（saveCurrent/switchTo/listAccounts/activeAccount/removeAccount，account_logic.dart:34-160，switchTo 全量回写 session+settings 并清 cookies 防串号）；但 settings_page.dart 仅有 `appGraph.account` 取引用（:42）与已登录/登出 ListTile，**无多账号列表/切换/保存档案的任何 UI**。

## 必修 TOP5

1. 扫码登录 UI 接入：settings_page 登录按钮 → createQrLogin 显示 qrImageB64 → pollQrLogin 轮询 status 0/1/2/4 → 成功提示；logic 层已实测就绪，纯缺 surface。
2. 登录回写补 vip_token/vip_type/t1：改 _applyCredentials 消费成功响应的 cookie/字段（需 KugouClient 暴露 Set-Cookie 或响应字段），否则 v6 多档与 VIP 判定全缺参。
3. 短信登录闭环：sendSmsCode/smsLogin 已封装但无调用方无 UI；补三态实测留样 + settings 二级页（手机号→验证码→登录）。
4. token 自动续期：loginToken 端点已声明无调用方，写封装 + 启动/401 触发，防 token 过期静默掉登录。
5. 设备登出服务端化 + 多账号 UI：dev_logout 端点/封装/接线全缺（logout 只清本地）；AccountLogic 补多账号列表与 switchTo 入口。
