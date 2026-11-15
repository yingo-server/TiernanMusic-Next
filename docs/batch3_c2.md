# 批3-C2 播放链插入点检查

## 1. 当前失败路径（resolve → _mapError → 状态）
- `playback_service.resolvePlaySource`：本地 DownloadStore 命中（且实体文件存在）→ 本地路径；否则 `getPlayUrlV5`。`status!=1 或 urls 空` → `_mapError` 映射为 `PlaybackError`（needsVerification / noPrivilege / notFound / network，31833 归 network）。
- `playback_session._start`：`src==null || !src.ok` → 仅 `ErrorAction(...)` 落入 PlayerState.lastError 并 **return 终止**。**无重试、无备选源概念**（PlaySource 有 backupUrls，但那是同源 CDN 备链，不是异源 fallback）。
- 即：失败后队列停留在 loading/error，不自动跳下一首，不尝试 MV 音频。

## 2. MV 音频兜底最小插入点 —— 推荐：session._start 层（L6 编排）
理由：
- MV 解析（L5 网络逻辑）应新增为 `playback_service` 的独立方法 `resolveMvAudio(song)`，复用 KugouClient，符合"每方法 try/catch + Log"铁律；PlaybackService 加字段 `mvFallback` 注入。
- 兜底**编排决策**（失败语义哪几类才兜、兜失败再如何）是链路编排，属 L6 session 职责；`_start` 已是唯一翻译点，reducer 保持纯函数不掺 IO。
- 不推荐只在 service 内部兜：service 是"单曲解析器"，不感知队列/历史/通知栏；且 noPrivilege 兜 MV 是产品策略（试听），放 L5 会让解析器掺杂策略。
- 插入形态：`_start` 中 `src.ok==false && error in {noPrivilege, needsVerification?, notFound}` → 尝试 mv fallback → 成功则按 mv url 起播并打 `sourceKind=mvAudio` 标记；失败维持原 ErrorAction。

## 3. PlaybackSnapshot 加 sourceKind？
- **建议加，但最小化**：不加快照字段，而是加到 `PlayerState`（reducer copyWith 透传），快照已含 player，L7 免改消费代码。枚举 `sourceKind: kugou | local | mvAudio`，StartLoad/Playing 动作携带。
- 涟漪面：L7 消费 PlaybackSnapshot 的页面（播放页迷你条/全屏播放器、歌单页 playAll、搜索页 playSong）——仅播放器 UI 需要读 `player.sourceKind` 显示「试听音源」badge；其余页面零改动（快照结构不变，向后兼容）。bridge_session 无需改 export。

## 4. 引擎事件与 MV 流播放失败降级
- 现状：`AudioEventType.completed` → `onCompleted()` → reducer `Completed` + `next()`（自动连播，next 失败仅 Log）；`error` → 仅 `ErrorAction('引擎播放失败')`，**不跳下一首、不标记不可播**。
- MV 流失败降级建议：MV 音频多为试听短链/防盗链 URL，易 mid-stream 失败。最小方案：session 在 error 事件时若 `sourceKind==mvAudio`，标记当前曲 `mvFailed=true`（本会话内不重试 MV），尝试回退 kugou 原源一次；再失败则 `ErrorAction` + 不自动跳曲（避免静默连环跳，符合"失败留痕不静默"）。
- Completed→next 行为对 MV 流天然兼容（试听播完即 Completed → 正常连播）。

## 必修 TOP5 + 推荐插入点
1. 【P0】`_start` 失败即 return，无任何备选链 —— 插入点：`playback_session._start`（src 失败后调 `service.resolveMvAudio`）。
2. 【P0】L5 新增 `resolveMvAudio(song)` 方法（PlaybackService），复用 KugouClient，try/catch+Log。
3. 【P1】`PlayerState` 加 `sourceKind` 字段 + reducer copyWith 透传；L7 播放器 UI 读 `player.sourceKind` 显示试听 badge。
4. 【P1】engine error 事件仅置 ErrorAction 不降级 —— session._onEngineEvent 对 mvAudio 源做单次回退 + 会话级失败标记。
5. 【P2】PlaySource 增补字段（isMvAudio / sourceKind）随 toMap 暴露，便于测试与 L7 断言；ErrorAction 消息现在是 `error.toString()`（如 "PlaybackError.noPrivilege"），建议改为 `error.name` 可读文案。

假设说明：项目内无现成 MV 解析实现可复用（仅读 4 文件），故 TOP5 以"新增 resolveMvAudio"为前提。
