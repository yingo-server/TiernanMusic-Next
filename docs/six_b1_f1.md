# 批1-F1 · 三态只读字段捕获探针（实施中，2026-11-15）

范围：仅 `tool/api_field_probe_v2.dart` + 实跑产出 `docs/api_samples_v2/{anonymous,nonvip,vip}.json`。报告归 F2，本文件只登记实施过程。

- [x] 复用依据：docs/six_b1_c2.md §F1 规格；tool/api_probe.dart 调用样式（_loadCreds/_sessionOf/ProbeRow）；docs/six_b1_c3.md 结论（不进 CI verdict，脱敏沿用白名单）。
- [x] 环境：Dart SDK 3.13.7（/opt/dart/bin/dart，linux_arm64）可用。
- [x] 脚本落盘（第 1 步）：`tool/api_field_probe_v2.dart`。纯 Dart、零新增依赖；三态 17 个只读端点（平移 api_probe.dart 15 个 + lyric_search + privilege_lite），复用现成 `client.request` 调用样式与 EndpointRegistry 参数；每响应记 `_topKeys`（敏感键名掩码）+ 关键字段 present/type/len（+ 白名单数值 value，URL/封面类只留域名+长度）。异常统一分类为 `SKIP: waf/non-json | network | request-error | credentials missing`，凭据值不打印（lib print 在 Zone 内截流为长度摘要）。禁登录/写操作。
- [x] 本地校验（第 2 步）：`dart analyze tool/api_field_probe_v2.dart` → No issues found；`python3 tool/analyze_gate.py` → project-type errors: 0（不进 CI verdict，仅按 six_b1_c3.md §TOP3 做本地静态核验）。
- [ ] 实跑一次（第 3 步，待执行）：产出 `docs/api_samples_v2/{anonymous,nonvip,vip}.json`；网络/WAF 不通则如实登记「实跑未覆盖」。
