# 批1-F1 · 三态只读字段捕获探针（实施中，2026-11-15）

范围：仅 `tool/api_field_probe_v2.dart` + 实跑产出 `docs/api_samples_v2/{anonymous,nonvip,vip}.json`。报告归 F2，本文件只登记实施过程。

- [x] 复用依据：docs/six_b1_c2.md §F1 规格；tool/api_probe.dart 调用样式（_loadCreds/_sessionOf/ProbeRow）；docs/six_b1_c3.md 结论（不进 CI verdict，脱敏沿用白名单）。
- [x] 环境：Dart SDK 3.13.7（/opt/dart/bin/dart，linux_arm64）可用。
