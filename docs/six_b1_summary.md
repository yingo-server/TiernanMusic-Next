# 批1 整理（2026-11-15）

## 检查结论（3 份报告）
- `docs/six_b1_c1.md`：play_url 主字段（urls/backupUrls/bitRate/extName/timeLength）已在解析路径；hash_offset/end_byte/fail_process 原仅 Expando 侧挂无下游；响应 q/fileSize/volume/classmap 仍缺；搜索 mvdata/HQ-SQ-Res、评论 reply_num/addtime、收藏回显、MV 档位契约仍缺。
- `docs/six_b1_c2.md`：旧 `tool/api_probe.dart` 已 15 端点三态真实调用 + 白名单脱敏；`api_field_probe_v2` 原不存在；凭据 Netscape TSV；写操作/凭据禁调口径成立。
- `docs/six_b1_c3.md`：新增探针不进 CI verdict（网络 flaky/无凭据）；tool 探针被 smoke 豁免；F3 不碰盐公式则不破 field_truth 锚点。

## 修复结果
- F1：`tool/api_field_probe_v2.dart` 与 `docs/six_b1_f1.md` 已落盘；纯 Dart 三态只读探针、脱敏规则在脚本内。**实跑/样本未覆盖**（不杜撰）。
- F2：`docs/API_FIELD_CAPTURE_3STATE.md` + `docs/six_b1_f2.md` 已落盘；逐端点三态表如实标「实跑未覆盖」与仍缺字段。
- F3：`lib/core/net/endpoints/play_endpoints.dart`、`play_models.dart` 与 `docs/six_b1_f3.md` 已落盘；把 hash_offset/end_byte/fail_process 等落到公开字段，补 q/fileSize/volume/classmap 容错读取；未触碰盐公式。

## 门禁（主会话统一执行）
- `dart format --output=none lib tool test`：通过。
- `bash tool/local_gate.sh`：`FINAL-OK`。
- `python3 tool/analyze_gate.py`：`analyze_gate ok (0 project-type errors)`。

## 未覆盖（保留，不冒充完成）
- `api_field_probe_v2` 未实跑；`docs/api_samples_v2/*.json` 未产出。
- 响应 q 等字段的下游消费、搜索/评论/收藏/MV 仍缺项按六批计划留批2/3/4。
