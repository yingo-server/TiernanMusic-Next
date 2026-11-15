# 批3-F2 MV 音频兜底解析

## 改动范围（仅 2 文件）
- `lib/logic/player/playback_service.dart`
- `lib/logic/player/player_state.dart`（任务写作 play_models.dart；实际同目录状态模型文件为 player_state.dart，PlayResult 真身在 `core/net/endpoints/play_models.dart` 不可动，故 isFallback 落在 L5 侧 PlaySource）

## 1. playback_service.dart
### PlaySource 增补 isFallback
- `final bool isFallback;` 构造默认 `false`，toMap 透传。现有构造零破坏。

### 新增 `Future<PlaySource> resolveMvAudioFallback(SongBrief song)`
- **职责边界**：只管解析，不判兜底条件。noPrivilege / needsVerification / notFound 的失败语义判断与调用时机由 L6 session（兜底编排）负责，符合 76 原则（L5 写解析逻辑，编排归 L6）。
- 步骤：
  1. `song.albumAudioId <= 0` → Log.w + 返回 notFound 错误源；
  2. `getMvBySong(_client, albumAudioId)`（现有 mvDetail 端点，批N2-B 实测口径）拿 MV 明细 hash；
  3. `getVideoQualities(_client, mvHash)`（批3-F1 修正契约）取档位，按 `ld > sd > hd > fhd > qhd` 优先排序（最低清晰度优先，`_265` 后缀取前缀匹配档位）；
  4. 逐档 `getVideoUrl` 取 downurl（多 CDN 备链全量保留），首个可播即返回。
- 返回：`PlaySource(urls: r.urls, quality: 'mv-audio-low', extName: 'mp4', isFallback: true)`；全档无链返回 notFound 源；异常返回 network 源并 Log.e。
- **证据评级标注（C3）**：
  - MP4 直链含音频轨属**推断**——video/url 端点返回的 mp4 容器通常带音轨，just_audio 可播 mp4 音轨；ext=mp4 的 URL 直接喂引擎，不做转封装。
  - **不臆造** trackermv / ismp3 等参数（无实测证据）。

## 2. player_state.dart
### PlayerState 增补 sourceKind
- `final String sourceKind;` 构造默认 `'kugou'`；取值 `'kugou'` / `'mv-audio'`（其他值视同 kugou）。
- copyWith 透传 `sourceKind`；toString 追加 `src=` 便于调试。
- 采用 String 而非枚举：与任务要求一致，且避免 L7 消费涟漪（快照结构不变）。

## 验收自检
- 两文件均 <500 行（playback_service 240 行 / player_state 101 行）。
- isFallback / sourceKind 均有默认值，不破坏现有构造与 copyWith 调用。
- resolveMvAudioFallback 仅依赖现有 mv 端点（getMvBySong / getVideoQualities / getVideoUrl，均经 bridge_core 导出）与批3-F1 修正契约，无新端点、无臆造参数。
- 未跑分析器（按任务约束）；reducer 未动，保持纯函数。
