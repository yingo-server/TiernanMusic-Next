# 批2-F1 登录后端 修改说明（2026-11-15）

## 一、C3 五处偏差修复（auth_endpoints.dart，逐条对照报告行号）

| # | 偏差 | 上游证据 | 修复 |
|---|---|---|---|
| ① | AES 固定 key/iv（错用 login_token 固定对） | crypto.js L127-148：随机 tempKey(16 位小写字母数字)，key=md5(tempKey) 前 32，iv=key 后 16，外发原 tempKey | 新增 `_randomTempKey()` + `_deriveAes()`；smsLogin/loginByPwd 改随机派生；固定对仅保留给 loginByToken（`kLoginTokenAesKey/Iv`） |
| ② | params 多字段（dfid/mid/uuid 多塞） | login_cellphone.js L14：仅 `{mobile, code}` | smsLogin payload 收敛为 `{mobile, code}` |
| ③ | sendSmsCode 路径 /v4/send_mobile_smscode 与源码不符 | captcha_sent.js L1-17：`/v7/send_mobile_code`，body {businessid:5, mobile, plat:3} | registry 已是 /v7（C3 口径源码事实），封装补 mid 顶参，日志 mobile 脱敏（前 2 + ***** + 末 1，`maskMobile`） |
| ④ | 缺 key/plat/support_multi/t1/t2/t3 | login_cellphone.js L25-46：key=signParamsKey、plat:1、support_multi:1、普通版 t1/t2='0'、t3=`MCwwLDAsMCwwLDAsMCwwLDA=` | body 补齐 `key`(smsSignParamsKey)/`plat:1`/`support_multi:1`/`t1:'0'`/`t2:'0'`/`t3` 常量 |
| ⑦ | secu_params 解密未实现（读明文 token 冒充成功） | crypto.js L158-161：key=md5(key).substring(0,32) | `_decryptSecuParams()`：AES hex→JSON；解不出 token 判失败返回错误，三链路（smsLogin/loginByPwd/loginByToken）统一走解密 |

（⑤ mobile 脱敏并入③；smsSignParamsKey 由「备而未接」变为已接入 body。）

## 二、新增封装（auth_endpoints.dart，均标「⚠️ 待实测」）

- **loginByPwd**（/v9/login_by_pwd，login.js L11-48 契约）：AES params({pwd, code, clienttime_ms} 随机 tempKey 派生) + RSA pk({clienttime_ms, key:tempKey}) 大写 textbook hex + t1/t2/t3 并列常量（无拼接）。t1/t2 上游 256/196 位 hex 常量 C3 未留样 → `kLoginPwdT1/T2` 空时发 '0'，注释「待实测」；降级 v9→v7→v6 待实测。
- **loginByToken**（/v5/login_by_token，login_token.js L4-77）：p3=AES(固定对){clienttime 秒, token}、pk=RSA({clienttime_ms, key=固定key})、params=空对象 AES、plat:1/t3 常量/userid/clienttime_ms；secu_params 用固定 key 解密。降级 v5→v4→v3 待实测。
- **devLogout**（/loginservice/v1/dev_logout，research_legacy_login_url.md L7）：最小 body {userid}，参数/签名/响应全未知 → 待实测。
- **openplat**（微信 /v6/login_by_openplat）：按用户决策**先不接**，registry 仅留注释，不加 Endpoint 声明不加封装。
- 三个函数全部 try/catch + Log('ep.auth')；token/vip_token 只打长度，mobile 走 `maskMobile`；未实测语义失败（needsProbe/error）不伪造成功。

## 三、EndpointRegistry（endpoint_registry.dart）

新增 `loginByPwd`（login.user.kugou.com/v9/login_by_pwd）、`devLogout`（loginservice.kugou.com/loginservice/v1/dev_logout）声明；loginToken（/v5）沿用既有声明。播放/MV/搜索端点零改动。bridge_core.dart 补导出 `LoginResult/maskMobile/sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout`（跨层唯一通道）。

## 四、AuthLogic（auth_logic.dart，367 行）

- **回写补缺**（C1 必修#2）：`_applyCredentials` 增加 `vipToken/vipType/t1` 入参；settings 新键 `auth.vip_token` / `auth.vip_type` / `auth.t1`；t1 并入 session.cookies（参与播放权限判定）。KugouSession 无 vipToken 字段，vip_token 先持久化（不动 L4），后续 /v6/priv_url 消费时从 settings 取。
- **门面方法**：`signInByPwd`（空参校验 + 失败抛 KugouApiException 不静默吞）、`renewByToken`（同）、`signOut`（先 devLogout，失败 Log.w 降级，再清本地）。
- **自动续期钩子**：`restoreSession` 成功后 `_tryRefreshToken`——存有 t1 哨兵则异步调 loginByToken 刷新，成功走 `_applyCredentials(source:'tokenRenew')`，失败静默降级用旧凭据（Log.w）。
- **logout** 增清三个新键。restoreSession 恢复时 `_restoreVipExtras` 回填 t1 进 cookies。

## 五、验收自检

- C3 五处偏差逐条已修（对照上表）。
- 3 个新封装函数头均带「⚠️ 待实测」注释（探针开关 kAuthEndpointsProbed 单点，未实测不放行）。
- auth_endpoints.dart 482/500 行 ✅；auth_logic.dart 367 行 ✅；registry 登录段之外零改动 ✅。
- 未跑分析器、未提交、无真实网络调用（静态构造 + 语义失败路径）。
