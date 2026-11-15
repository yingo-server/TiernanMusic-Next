# 批3-F3 兜底编排 修改说明

## 范围
只改 2 个文件（第 3 个零改动）：
1. `lib/session/playback_session.dart`（317→356 行）
2. `lib/surface/pages/player_page.dart`（369→377 行）

## 1. playback_session.dart — _start 失败路径兜底（L6 策略层编排）
- 新增字段：`Set<String> _mvTriedOnce`（会话级防死循环标记）、`String _sourceKind`（暂存源类型）。
- `_start` 中 `resolvePlaySource` 失败（`!src.ok`）时：
  - 错误类型为 noPrivilege / needsVerification / notFound（按 `error.toString()` 包含匹配）且当前曲未试过 → 调 `playback.resolveMvAudioFallback(song)`；
  - 该方法为批3-F2 新增，**当前未落盘**，已按降级策略用 try/catch 包住并 `Log.w('fallback not ready')`；
  - MV 解析成功且有 url → 用 MV 音频流起播、`_sourceKind='mv-audio'`、正常走历史/通知栏，`return`；
  - MV 失败或已试过 → 维持原 `ErrorAction`，不静默连环跳曲；
  - 正常链成功时 `_sourceKind` 置 'local'（localPath 命中）或 'kugou'。
- 成功播放后 `onCompleted → next` 保持现状；`_mvTriedOnce` 保证同曲会话内只兜一次，防死循环。

## 2. playback_reducer.dart — 零改动
检查确认 `PlayerState` / `copyWith` 尚无 `sourceKind` 字段（批3-F2 未落盘），按降级策略本文件不动，**待 F2** 落地后补字段与 copyWith 透传；session 侧 `_sourceKind` 已就位，届时一行 `_emit` 带上即可。

## 3. player_page.dart — 条件徽标
- 标题/歌手下方新增：仅当 `snap.player.sourceKind == 'mv-audio'` 时显示 `Text('试听音源', TextStyle(fontSize: Sp.fTiny, color: Sp.textFaint))`，居中、单行。
- 其余 UI 零改动；文件 377 行 ≤500。
- 注：因 reducer 待 F2，此处 `sourceKind` 属性当前编译会缺 —— 与 F2 同批合入即可生效；徽标条件写法已按 F2 规范。

## 验收自检
- [x] session 有 `_mvTriedOnce` 防循环
- [x] 失败不连环跳曲（兜底失败仍 ErrorAction + return）
- [x] 播放页有条件徽标
- [x] 三文件 ≤500 行（356 / 377 / 196）
