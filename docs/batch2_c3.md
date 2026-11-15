# 批2-C3 登录链参数契约检查（只读）

> 源码行号以 KuGouMusicApi（仓库内 `util/crypto.js`、`module/*.js`）与 TiernanMusic-Next 为准。全部只读提取，未实测；版本变体一律标注「待实测」。

## 1. 密码登录 /v9/login_by_pwd（module/login.js）

- **请求**：POST `https://login.user.kugou.com`（x-router，login.js L46）/v9/login_by_pwd，`encryptType:'android'`（L45），cookie 透传 `params?.cookie`（L47）。
- **AES key/iv 派生**（util/crypto.js cryptoAesEncrypt L127-145）：不传固定 key 时生成随机 `tempKey`（16 位小写，L134），`key = md5(tempKey).hex` 前 32 位，`iv = key.substring(key.length-16)`（即 md5 后 16 字符，L135-136）。AES-128-CBC/PKCS7，明文为 JSON 字符串 UTF-8（L141-145，`normalizeBuffer` JSON.stringify）。返回 `{str: hex, key: tempKey}`（L148）——**外发的是原 tempKey**，服务端用 md5(tempKey) 派生解密。
  - login.js L11：`cryptoAesEncrypt({pwd, code, clienttime_ms})` → params 串。
  - ⚠️ auth_endpoints.dart 现用**固定 key/iv 对**（90b8…/f063…），与上游随机派生不符，探针需改为「随机 tempKey + md5 派生」。
- **RSA pk**（crypto.js cryptoRSAEncrypt L229-247 + rsaRawEncrypt L104-112）：明文 = JSON `{"clienttime_ms":ms,"key":tempKey}`（login.js L19），**无填充 padding**（textbook RSA，左补零到 keyLength，crypto.js L241-244），公钥 `publicRasKey`（crypto.js L3-4；lite 用 `publicLiteRasKey` L5-6），输出 hex 大写（login.js L19 `.toUpperCase()`）。「t1/t2/t3 拼接」实为**三个静态常量字段并列**（login.js L16-18）：t1=256hex 常量、t2=196hex 常量、t3=`MCwwLDAsMCwwLDAsMCwwLDA=`，不做拼接运算。
- **签名类型**：android 通用签名（useAxios encryptType），另有 `clienttime_ms` 顶参（L13）。
- **Cookie 要求**：登录前无强制；响应后 `res.cookie.push(token/userid/vip_type/vip_token)`（L34-37）。
- **响应**：`status==1` 且 `data.secu_params`（L28）→ 用同一 tempKey 的 md5 派生 key 解密（cryptoAesDecrypt crypto.js L158-161：`key=md5(key).substring(0,32)`，iv=key 后 16）→ 得 `{token, userid, vip_type, vip_token, t1, ...}`（对象则合并进 data 并逐个写 cookie，L29-41）。
- **证据行**：L11（AES 载荷）、L12-21（dataMap/t1/t2/t3/pk）、L45-48（url/method/sign/cookie）、L27-37（secu_params 解密与 cookie 写入）。
- 版本变体：v9→v7→v6（待实测，勿冒充可用）。

## 2. token 续期 /v5/login_by_token（module/login_token.js）

- POST `http://login.user.kugou.com/v5/login_by_token`（L58-60），android 签名。
- 参数（L38-52）：`dfid`（cookie.dfid 或 '-'）、`p3`=AES({clienttime(秒), token})，**普通版固定 key/iv** `90b8382a1bb4ccdcf063102053fd75b8` / `f063102053fd75b8`（L4-5）；lite 用 `c24f74ca2820225badc01946dba4fdf7` / `adc01946dba4fdf7`（L7-8）；`plat:1`、`t1`/`t2`（仅 lite，AES 固定对加密，L10-13, L30-34；普通版传 0）、`t3:'MCwwLDAsMCwwLDAsMCwwLDA='`、`pk`=RSA({clienttime_ms, key=encryptParams.key})（encryptParams 为空对象 AES，L27-28）、`params`（空对象 AES str）、`userid`、`clienttime_ms`；lite 额外 `dev`（L55-57）。
- 响应（L62-77）：`data.secu_params` 用 encryptParams.key 解密 → token/userid/vip_type/vip_token/t1，全部写 cookie。
- 版本降级候选：v5→v4→v3（待实测）。

## 3. 短信链

- **sendSmsCode**（module/captcha_sent.js L1-17）：POST `http://login.user.kugou.com/v7/send_mobile_code`，body `{businessid:5, mobile, plat:3}`，android 签名，cookie 带 mid。⚠️ 任务口径写的 `/v4/send_mobile_smscode` 与源码不符，源码唯一事实是 `/v7/send_mobile_code`。
- **smsLogin**（module/login_cellphone.js L1-76）：POST `https://loginserviceretry.kugou.com/v7/login_by_verifycode`（L57-58），UA `Android16-1070-11440-130-0-LOGIN-wifi`（L61）。参数（L25-44）：`plat:1`、`support_multi:1`、`t1`/`t2`（lite 固定对加密，L14-23；普通版 0）、`clienttime_ms`、`mobile`（**脱敏**：前 2 位+`*****`+第 11 位，L15）、`key=signParamsKey(dateTime)`（L28）、`pk`=RSA({clienttime_ms, key}) 大写（L29）、`params`=AES({mobile(原文), code})（L14，随机 tempKey 派生）、`userid` 可选（L41）；lite 加 dfid/randomString(24)/dev/gitversion，普通版 `t3`（L42-46）。
- **响应**：`secu_params` 用 encrypt.key 解密 → token/userid/vip_type/vip_token/t1，写 cookie（L65-75）。
- **当前代码已接**（auth_endpoints.dart）：sendSmsCode 已接 `{businessid, mobile, plat}`（L83-90）✅；smsLogin 已接 params/pk 构造（L134-160）、UA 契约注释、token 掩码（toString 只打 tokenLen，L44-47）✅。
- **缺口**：① AES 用固定 key 而非随机 tempKey+md5 派生（且固定对错用了 login_token 的对）；② params 里多塞了 dfid/mid/uuid（上游仅 `{mobile, code}`）；③ `key=signParamsKey` 字段未发（有 smsSignParamsKey 函数 L184-195 但未接）；④ `plat/support_multi/t1/t2/t3` 未发；⑤ mobile 未脱敏；⑥ EndpointRegistry.sendSmsCode 路径须核实为 /v7/send_mobile_code、smsLogin 为 /v7/login_by_verifycode@loginserviceretry；⑦ secu_params 解密逻辑未实现（现直接读明文 token 字段）。

## 4. 门禁风险

- **auth_endpoints.dart 现 167 行**（wc 实测）；上限 500 行（smoke_check `_checkLineBudget` L390-397）。加 4~5 个 Endpoint 封装约 +150~250 行，仍在预算内，但若加登录二维码+device 链建议拆 `auth_qr_endpoints.dart` / `auth_device_endpoints.dart`（76 原则铁律 6：每端点一 dart 模块）。
- **新封装函数位置**：放 `lib/core/net/endpoints/`（L4 core，网络域），同层 import models/kugou_client 合法；不得被 L5/L6 直接 import——须经 `bridge_core` 暴露门面（layer_audit LAYER_ALLOWED_BRIDGES：L5 只许 bridge_logic/bridge_core/bridge_kernel；L6 加 bridge_session）。
- **版本变体注释规范**：参照 plan_upstream_endpoints_a.md 口径——「源码版本 / 猜测版本 / 待实测」三段式，写成 `// ⚠️ 端点实测状态：… 未三态实测 → needsProbe`（auth_endpoints.dart L6-16 现有范式可复用）；探针开关 `kAuthEndpointsProbed` 单点翻转，实测通过前返回语义失败不伪造成功。
- **写操作外发脱敏**：token 永不入日志——`toString` 只打 `tokenLen`（L44-47 范式）；mobile 打前 2 后 1 掩码；Log.d 不含完整 params/pk 明文；测试号须可回滚（token 只写会话内存 + 可主动 dev_logout/kick，见 login_device_kick.js）。

## 5. 批2 后端实施顺序建议

1. **修 smsLogin 契约**（优先：现外发结构错——固定 key、params 多字段、缺 key/plat/t3；探针开关已 true，风险最高）
2. **secu_params 解密链**（AES hex→md5 派生 key 解密→token/userid/vip_token 入 cookie/会话）
3. **sendSmsCode 路径核实 + token 续期 /v5/login_by_token**（固定 key 对，契约最简单，保活必需）
4. **密码登录 /v9/login_by_pwd**（随机 tempKey + textbook RSA，实现面最大）
5. **二维码 /v2/qrcode + /v2/get_userinfo_qrcode**（web 签名，独立支线，最后接）

## 必修 TOP5

1. smsLogin 的 AES 改随机 tempKey+md5 派生，params 只含 {mobile, code}，补 key/plat/support_multi/t3，mobile 脱敏。
2. 实现 secu_params 解密（解不出 token 即判失败，勿读明文字段冒充成功）。
3. EndpointRegistry.sendSmsCode 路径改为源码事实 `/v7/send_mobile_code`（login.user.kugou.com），smsLogin 用 loginserviceretry 子域。
4. 新端点文件保持 ≤500 行并按「每端点一模块」拆分，新函数只放 L4 endpoints/，暴露走 bridge_core。
5. 所有版本变体（v9/v7/v6、v5/v4/v3、v7 send_mobile_code）注释按「源码版本/猜测版本/待实测」标注，探针未过不外发真实凭据。
