# A4 · MV 响应解包 P0 复核与修复（主会话，2026-11-17）

> 背景：B4-C2 报「阶段A四重断点请求侧全修对，但 L4 `getMvBySong`/`getVideoQualities` 响应解包仍按 data 是 Map 写，实测/留样 data 是数组 → dataOf 回空 → 恒空」，B4-C3 却判「四重断点已修通、能播」。二者冲突，主会话用实测留样复核。

## 证据（三重印证，C2 权威）

1. **`dataOf` 实现**（`models_util.dart:57-66`）：`root['data']` 仅当 `Map` 才返回，否则 `const {}`；A2-C2 早已报此盲区，`field_truth_test.dart:915` 自证「dataOf 对数组 data 回空 Map（旧 bug 根因）」。
2. **实测 §A5-1**：响应 `data` 为嵌套数组 `data[0][]`；§A5-2：`data[0]` 是平铺档位 Map。
3. **探针留样** `api_samples*/summary.json`：`mv_by_song/vip` → `found=false`（getMvBySong 返回 null）。

## 裁定

- ✅ **C2 为真 P0，采纳**：阶段 A 只修了请求侧（MvBrief.videoId 字段+门槛、getVideoQualities int 入参、两段式、注册守卫），**没修响应解包**。`getMvBySong` 用 `dataOf(res)` 对数组 data 拿到空 Map → `dd=null` → list 空 → 恒 return null，MvBrief.fromMap（阶段 A 加了 videoId）根本到不了；`getVideoQualities` 同样 dataOf 回空 → 档位恒空。
- ❌ **C3「能播」为误判**：C3 只看请求侧源码改动，没读 L4 响应解包层；正常网络下也拿不到 data，不能播。
- 这是阶段 A MV 修复的**第五重断点**（响应解包层），比 A1/A3 报的四重更底层。

## 修复（已实施，待 CI 验证）

- `mv_endpoints.dart getMvBySong`：弃用 `dataOf(res)`，直接 `listOf(res['data'])`（search_endpoints 同款修法），兼容嵌套数组 `data[0][]` 与对象兜底形态。
- `mv_endpoints.dart getVideoQualities`：直接取 `res['data'][0]`（Map）作 `MvQuality.fromFlat` 入参，弃用 dataOf。
- 两处逻辑用 §A5-1/A5-2 实测留样核对通过（构造相同形态的 map 仿真：data=[[mvItem]] → listOf 取到 mvItem → videoId=596344；data=[videoDetail] → fromFlat 取到档位）。

## 待补（诚实登记）

- **端点级测试锚点**：`field_truth_test` 现有断言只测 `MvBrief.fromMap(mvItem)`（单 item），没测「构造完整响应 `{'data':[[mvItem]],'status':1}` → getMvBySong → videoId==596344」。本次修复用留样仿真核过逻辑，但该盲区长期逃过门禁的根因是缺端点级测试。阶段 B 修复收口时应补（需 mock KugouClient 或提取纯解包 helper）——登记为待办，不阻塞本次修复。
- 真机播放终验（禁跑 dart，留 CI/用户真机）。

## 对汇总的影响

B4 的 P0 从「请求侧四重已修通」改判为「请求侧四重已修、但响应解包第五重断裂，修复后才有望真通」。这是阶段 B 又一次「单点修复≠链路通」的实证。
