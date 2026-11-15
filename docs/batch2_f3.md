# 批2-F3 修改说明：登录态会话（2026-11-15）

## 改动
1. **新建 `lib/session/auth_session.dart`（85 行，≤120 达标）**：
   - `AuthSession.instance` 单例；`attach(KugouClient?)` 由 bootloader 装配时注入（经 bridge_core 门面类型）。
   - `bool get isLoggedIn`：读 `client.session.userid`，非空且非 '0' 视为已登录；异常/未注入一律返回 false，不抛。
   - `String get userid`：未注入或异常返回空串。
   - `onAuthChanged(cb)` / `offAuthChanged(cb)`：回调注册表，全程 try/catch + Log。
   - `notifyAuthChanged()`：内部通知入口，供 AuthLogic 登录/登出接线（F2 之外的手动触发点）。

## 未臆造说明（重要）
- 批2-F2 的 `NavState.bumpAuth` **未落盘**（rg 全 lib 无 `bumpAuth`）。按指令：未自行添加、未臆造监听机制。在 `onAuthChanged` 内留 `TODO(批2-F2)` 注释，F2 落盘后改为订阅 NavState.instance 的 bumpAuth 通知。
- c1.md「必修 TOP5」回写：F3 范围仅登录态快照/订阅；TOP5-1 扫码 UI、TOP5-2 vip_token/t1 回写、TOP5-3 短信闭环、TOP5-4 token 续期、TOP5-5 设备登出/多账号 UI 均未动，仍缺。

## 桥出口
2. **`lib/bridges/bridge_session.dart`**：加一行 `export '../session/auth_session.dart' show AuthSession;`（仅此一处改动）。

## 待后续接线
- bootloader 装配处调 `AuthSession.instance.attach(client)`（bootloader 不在本次允许改动清单，未改）。
- AuthLogic._applyCredentials / logout 成功后调 `AuthSession.instance.notifyAuthChanged()`。
