# 批1-F1 · 三态只读字段捕获探针（完成，2026-11-15）

范围：仅 `tool/api_field_probe_v2.dart` + 实跑产出 `docs/api_samples_v2/{anonymous,nonvip,vip}.json`。报告归 F2，本文件只登记实施过程。

- [x] 复用依据：docs/six_b1_c2.md §F1 规格；tool/api_probe.dart 调用样式（_loadCreds/_sessionOf/ProbeRow）；docs/six_b1_c3.md 结论（不进 CI verdict，脱敏沿用白名单）。
- [x] 环境：Dart SDK 3.13.7（/opt/dart/bin/dart，linux_arm64）可用。
- [x] 脚本落盘（第 1 步）：`tool/api_field_probe_v2.dart`。纯 Dart、零新增依赖；三态 17 个只读端点（平移 api_probe.dart 15 个 + lyric_search + privilege_lite），复用现成 `client.request` 调用样式与 EndpointRegistry 参数；每响应记 `_topKeys`（敏感键名掩码）+ 关键字段 present/type/len（+ 白名单数值 value，URL/封面类只留域名+长度）。异常统一分类为 `SKIP: waf/non-json | network | request-error | credentials missing`，凭据值不打印（lib print 在 Zone 内截流为长度摘要）。禁登录/写操作。
- [x] 本地校验（第 2 步）：`dart analyze tool/api_field_probe_v2.dart` → No issues found；`python3 tool/analyze_gate.py` → project-type errors: 0（不进 CI verdict，仅按 six_b1_c3.md §TOP3 做本地静态核验）。
- [x] 实跑一次（第 3 步，2026-11-15 21:34）：`dart run tool/api_field_probe_v2.dart --out docs/api_samples_v2` 完成，产出 `docs/api_samples_v2/{anonymous,nonvip,vip}.json`（各 17 行，schema 完整）。三态凭据齐备、匿名 userid='0'。每态 12 个端点 ok（search_song、search_suggest、search_hot、rank_list、daily_recommend、user_detail、song_climax、mv_by_song、album_detail、lyric_search、privilege_lite、play_url_v5），5 个按规矩标 SKIP 不伪造：favorite_count / comment_count = `SKIP: network`；user_cloud / fm_play / comment_music = `SKIP: waf/non-json`。play_url_v5 三态差异已捕获：anonymous status=0、nonvip status=2 priv_status=0、vip status=1 priv_status=1 url=2（仅留 host）。样本全量扫描：无凭据值、无完整 URL query、无长 token；字符串值/敏感键名只留掩码+长度/域名，白名单数值保留。dart analyze 复核 No issues found。
- [x] 范围收口：仅本任务允许的脚本、过程登记文件与 `docs/api_samples_v2/` 三份样本；未改 lib/、其它 tool/、CI、其它 docs。未覆盖：5 个 SKIP 端点的响应字段（网络/WAF 不通，按规矩不补齐）；F2 报告汇总不在本任务范围。
