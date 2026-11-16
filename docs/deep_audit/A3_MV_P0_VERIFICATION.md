# A3 · MV P0 复核裁定（主会话，2026-11-16）

> 背景：A3-C2 报 P0「MvBrief 不读实测的 video_id、以不存在的 hash 为成功门槛，按歌查 MV 恒返回 null」；A3-C3 却判「端点两段式接口齐备正确，hash 错配在上层非端点」。两者冲突，主会话用仓库内实测留样一锤定音。

## 证据（三重印证，均来自仓库自身）

### 1. 字段真值文档 `docs/API_FIELDS_TRUTH.md` §A5-1（L211-224）
```
### A5-1 · /kmr/v1/audio/mv（按歌查 MV）
  video_id、mv_name（⚠️ 非 mvname/filename）、singer、duration(毫秒)
⚠️ MV 项本身无 hash 键——播放 hash 来自歌曲侧 mvdata[].hash 或
  deprecated.video_hash（A4-2），或由 video_id 走 A5-2 取档位 hash。
```
### 2. 项目实测留样锚点 `tool/field_truth_test.dart:748-760`（A5-1 夜曲 MV）
```dart
const mvItem = {
  'video_id': 596344,
  'mv_name': '夜曲',
  'singer': '周杰伦',
  'duration': 231732,
  'hdpic': '...', 'thumb': '...', 'hit': 33229711,
  'have_mp4': 1, 'audio_id': 338638, 'album_audio_id': 32029511,
};
```
**无任何 hash / mvhash / video_hash 键。**

### 3. 实现 `lib/core/net/endpoints/mv_endpoints.dart`
- L57：`hash: safeStr(m['hash'] ?? m['mvhash'] ?? m['video_hash']).toLowerCase()` —— 三个键都不在留样里 → `hash == ''`
- L287：`if (mv.hash.isEmpty) return null;` —— 恒返回 null
- 同文件 L54-56 的注释**自己承认**「MV 摘要项本身标识键是 video_id」，但代码没读它。

## 裁定

- **C2 为真 P0，采纳**：`getMvBySong` 在契约正确返回下也恒返回 null，MV 播放兜底链（`playback_service.resolveMvAudioFallback`）整体不可达。这是用户「MV 用不了」的**端点层根因**（与 A1 找到的上层「模块 id 被占位抢占」「歌曲 hash 当 video_id」叠加，MV 至少三重断点）。
- **C3 为误判**：C3 只看接口形状（函数名/调用顺序齐备），没验 `MvBrief.fromMap` 的字段解析与实测留样对齐，故漏掉此 P0。「两段式接口齐备」在接口层成立，但**第一段 getMvBySong 恒返回 null**，接口实际不可用。
- **测试盲区**：`field_truth_test.dart` 的 A5-1 锚点只断言 name/singer/durationMs/coverUrl，**从不断言 `mv.hash`**，所以这个 bug 长期逃过门禁。修复时必须补 `eq('mv.videoId', mv.videoId, 596344)` 锚点。

## 修复方向（留待阶段 A 全审完后主会话亲修）

1. `MvBrief` 增 `int videoId` 字段，读取 `m['video_id']`（实测数字）。
2. `getMvBySong` 成功门槛从 `mv.hash.isEmpty` 改为 `mv.videoId > 0`。
3. `getVideoQualities` 入参从 32 位 hash 串改为 `int videoId`（C2 P1：`body.data[0].video_id` 实测是数字 596344，不是 hash）；上层 `mv_logic.dart:48`、`playback_service.dart:297` 同步改传 videoId。
4. 档位 hash（`ld_hash/hd_hash/...`）仍来自 A5-2，这部分契约一致，不动。
5. 补 `field_truth_test` 的 `mv.videoId` 断言，堵住测试盲区。

## 对汇总的影响

A3 的 P0 从「仅 C2 独有」升级为「C2 单视角独有但经主会话实测留样复核确认为真」。A3 达成与 A2 同样的质量 gate：子代理单点发现 + 主会话可执行证据复核。
