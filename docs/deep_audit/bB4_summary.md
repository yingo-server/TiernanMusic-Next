# B4 批 · 交叉汇总（MV 播放 跨层 · 用户点名）

> 2026-11-17。三视角：`bB4_c1.md`（架构）、`bB4_c2.md`（正确性）、`bB4_c3.md`（痛点）。均已落盘。
> **特别**：C2 的「响应解包第五重断点」与 C3「能播」冲突，主会话用实测留样复核 → **确认 C2 为真 P0，已修**（见 `B4_MV_UNPACK_VERIFICATION.md`）。

## 0. 阶段 A 四重断点修复的跨层验证结果

| 断点 | 结论 | 证据 |
|---|---|---|
| ① 模块注册守卫（占位抢占） | ✅ 已修（守卫删+L6 install 覆盖+时序正确） | C1 |
| ② MvBrief.videoId 读取 | ⚠️ 请求侧字段修对，但**响应解包到不了** → 见第五重 | C2 + 复核 |
| ③ getVideoQualities int videoId | ⚠️ 请求侧修对，响应解包同样断 | C2 + 复核 |
| ④ 两段式 albumAudioId→videoId | ✅ 已修（L5 MvLogic.videoIdOfSong） | C1 |
| **⑤ 响应解包（新发现）** | ❌ **真 P0，主会话已修**：dataOf 对数组 data 回空，getMvBySong/getVideoQualities 恒空 → 阶段A修复未真通 | C2 + 实测留样三重印证 |

## 1. 关键问题

| # | 问题 | 命中 | 定级 | 锚点 |
|---|---|---|---|---|
| X1 | **响应解包第五重断点**（阶段A未真通，主会话已修） | C2 + 复核 | **P0(已修)** | `mv_endpoints.dart getMvBySong/getVideoQualities` |
| X2 | **L5 吞错把网络/风控伪装成「没 MV」**：失败与被风控都返回空，用户看不到真实原因 | C3 + C2 | **P0** | `mv_logic.dart` + `mv_page.dart` 空态 |
| X3 | 降级链只向更低档回退，最低档无链即全灭（应向任意可用档回退） | C3 | **P1** | `mv_logic.playUrl` |
| X4 | 无清晰度选择、无全屏、播放时原声双轨 | C3 | **P1** | `mv_page.dart` |
| X5 | mv_anonymous.dart 227 行匿名链死代码（未登录看 MV 未实现） | C1 + C2 | **P1** | `mv_anonymous.dart` |
| X6 | 选档三套语义冲突（MV页 size降序/兜底 order升序/L7低档优先）、两段式双门面重复封装 | C1 + C2 | **P1** | mv_logic + playback_service |
| X7 | 20028 在 MV 兜底里绕验证；bootstrapSession 重入以 enabled=false 占位反覆盖真 MV 模块 | C1 + C2 | **P2** | `bootstrap.dart` |
| X8 | 文案未接 S.of：mv_page 19 处 + player_page 1 处；arb 有 mv/mvEmpty 等 key 零消费；画质命名倒挂（qhd 超高清 540P < fhd 全高清 1080P） | C3 | **P2** | `mv_page.dart` |
| X9 | QR off-by-one 已修但只能导出、无解码不能扫码导入；78B 容量不足 | C3 | **P2** | `qr_codec.dart` |

## 2. 76 合规裁决（C1 权威）

- 四重断点修复中三项（模块注册、两段式、六桥）合规确认。
- 架构债：mv_anonymous 死代码（X5）、两段式双门面重复封装（X6）。

## 3. 与用户痛点对应

| 用户原话 | B4 定位 |
|---|---|
| 「MV 用不了」 | 阶段A请求侧四重已修，但**响应解包第五重（X1，已修）**才是真正拦路；修通后正常网络+有链可播，但吞错(X2)/降级(X3)仍影响体验 |

## 4. B4 结论
三视角全落盘。真 P0×2（响应解包已修、吞错）、P1×4、P2 若干。**C3「能播」误判已裁定**——真实情况是阶段 A 修复未真通，主会话补修响应解包后才具备可播条件。又一次「单点修复≠链路通」。

## 5. 下一步
阶段 B 继续 B5（下载/收藏/歌单/缓存跨层）。所有修复待 B1~B7 全完后主会话统一亲修 + CI。B4 定时器 `6641bc3c` 已取消。
