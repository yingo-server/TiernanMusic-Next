# 批3 整理（2026-11-15）

主题：匿名 / MV / 权益播放链。按新规矩复用已有客观报告，主线收口，不重复派代理。

## 检查结论
- `docs/batch3_c1.md`：MV 清晰度链原全断（契约错位 + kmr/v2 404 死 fallback），`MvQuality.fromFlat` 无人喂入；设备注册 `r_register_dev` 未接；匿名推荐顺序 `/v5/url IsFreePart` → 设备注册 → MV 最低档。
- `docs/batch3_c2.md`：主链失败后原无备选源；插入点=L5 `resolveMvAudioFallback` + L6 session 兜底编排，reducer 保持纯函数。
- `docs/batch3_c3.md`：上游无 `trackermv.js/mv_url.js`；MV tracker 唯一源码 `video_url.js`（mp4，ismp3:0）；`ismp3:1` 直出音频属推断；`song_url.js` 是唯一有 notSign+随机 dfid 的匿名路径。
- `docs/batch5_live.md`：权益链 5 项复核全部落盘（登录态选档降级≤2、bitRate 最大主链 + backupUrls 顺序、priv_status=0 无 url 不冒充成功）。

## 修复结果
- `docs/batch3_f1.md` + `lib/core/net/endpoints/mv_anonymous.dart`：videoDetail 契约对齐 data[0] 平铺；删 kmr/v2 死 fallback；新增 `registerDevice`、`anonymousPlayUrl`，均标「待实测」；`MvQuality.fromFlat` 有喂入点。
- `docs/batch3_f2.md`：`PlaybackService.resolveMvAudioFallback`（mvDetail→ld/sd 最低档→videoUrl mp4 URL）；`PlaySource.isFallback`、`PlayerState.sourceKind`。
- `docs/batch3_f3.md`：L6 `_start` 主链失败→MV 兜底 + `_mvTriedOnce` 防循环、失败不连环跳；L7 播放页「试听音源」条件徽标。
- 权益最大 URL/降档/备链：`lib/logic/player/playback_service.dart` + `play_endpoints.dart`（`docs/batch5_live.md` 复核）。
- 批1-F3 已把 play_url 顶层字段（hash_offset/end_byte/fail_process/q/fileSize/volume/classmap）落到公开模型。

## 门禁
- `bash tool/local_gate.sh` → `FINAL-OK`
- `python3 tool/analyze_gate.py` → `analyze_gate ok`
- `dart format --output=none lib tool test` → 通过

## 未覆盖 / 诚实边界
- `registerDevice`、`anonymousPlayUrl`、MV mp4 音频流均未三态实测；mp4 直接播音频属推断。
- `ismp3:1` 无源码证据，未臆造；`trackermv` 相关参数未实现。
- 权益选链未做真机三态验证，保持「待三态实测」注释。
