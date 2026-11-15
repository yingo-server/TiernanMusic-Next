# 批1-F2「三态字段捕获报告」改动说明（实时落盘）

时间：2026-11-15 · 范围：仅 docs/API_FIELD_CAPTURE_3STATE.md + 本文件。只读消费 C1/C2/C3/research/batch5_live 五份依据，未重新调研。

## 步骤 1 · 依据收集 ✅
- 读 docs/six_b1_c1.md（22 键落点核对）、six_b1_c2.md（探针/凭据现状）、six_b1_c3.md（门禁）、research_field_capture_3state.md（字段矩阵）、batch5_live.md（已修清单）。
- 核对 docs/api_samples_v2/：**不存在**（F1 未产出样本）→ 全报告三态实测值标「实跑未覆盖」，不杜撰。

## 步骤 2 · 主交付落盘 ✅
- docs/API_FIELD_CAPTURE_3STATE.md：逐端点三态表（play_url 22 键逐键 / 搜索 / 评论 / 收藏 / MV / 其余端点）+ 汇总。
- C1 结论 4 条全部登记：urls/backupUrls/bitRate/extName/timeLength 已落点；hash_offset/end_byte/fail_process 已 Expando 侧挂但无下游消费（F3）；响应 q/fileSize/volume/classmap 仍未捕获；PlaySource.quality 按请求档回填。

## 步骤 3 · 仍缺明确登记（不冒充完成）
- 搜索 mvdata/HQ-SQ-Res hash → 仍缺（待批2）
- 评论 reply_num/addtime 等 → 仍缺（待批3）
- 收藏回显/per-song 态/list_ver → 仍缺（待批4）
- MV 档位契约错位（getVideoQualities body={hash} vs 实测 data:[{video_id}]）→ 仍缺（待批2）
- play_url 响应 q/fileSize/volume/classmap → 仍缺

## 未覆盖（不补齐）
- F1 三态实跑样本（api_samples_v2/ 不存在）；歌词 id 溢出、playlist_write `_ok()` s==0 是否已修未核对；floor 的 floo/floor 键无实测章节；其余端点未逐一核代码。
- 写文件仅 2 个（API_FIELD_CAPTURE_3STATE.md、six_b1_f2.md）；未改 api_samples_v2、tool/、lib/、CI（均只读/未动）。
