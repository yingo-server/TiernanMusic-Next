# 批2 整理（2026-11-15）

主题：登录链收口。按用户新规矩，小问题/已有结论主线收口，不再为结构而派 6 个代理。

## 检查结论（复用已落盘客观报告）
- `docs/batch2_c1.md`：扫码 key/check 已声明+已接且实测；短信已封装但 UI 原缺；密码/openplat/设备注册/dev_logout 原缺；token 回写缺 vip_token/vip_type/t1。
- `docs/batch2_c2.md`：L7 登录入口原为 toast 占位；建议 login_sheet 三 Tab + NavState.authVersion 广播。
- `docs/batch2_c3.md`：上游源码契约 5 处实质偏差（AES 派生、secu_params 解密、sendSmsCode 路径、params 字段、mobile 脱敏）。

## 修复结果（已落盘，主线统一验证）
- `docs/batch2_f1.md`：auth_endpoints 5 偏差修复；loginByPwd(/v9)/loginByToken(/v5)/devLogout 封装；AuthLogic vip 回写 + restoreSession 自动续期；openplat 按决策不接。
- `docs/batch2_f2.md`：login_sheet 三 Tab（扫码 4 态轮询/验证码 60s/密码兜底）+ 多账号切换/移除；settings 占位换真弹层；NavState.bumpAuth。
- `docs/batch2_f3.md`：auth_session（isLoggedIn/onAuthChanged）+ bridge_session 导出。
- 批2 fixup（主线）：删重复门面，login_sheet 接 AuthLogic 真门面 `signInByPwd/signInByVerifyCode/sendVerifyCode`，账号区拆 `login_account_section.dart`。
- 主线复核 `rg` 剩余「待实测/needsProbe」均为**真实未实测端点**，按纪律不伪造成功、不外发凭据。

## 门禁
- `bash tool/local_gate.sh` → `FINAL-OK`
- `python3 tool/analyze_gate.py` → `analyze_gate ok (0 project-type errors)`
- `dart format --output=none lib tool test` → 通过

## 未覆盖
- 密码/token/dev_logout/openplat 端点未做三态实测（注释齐全，标待实测）。
- 短信登录链、设备登出真机验证未执行。
