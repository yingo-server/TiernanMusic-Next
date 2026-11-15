# 批1-C3 门禁风险检查（只读）· 2026-11-15

范围：tool/local_gate.sh、tool/smoke_check.dart、tool/layer_audit.py、.github/workflows/ci.yml(verdict)、docs/API_TEST_REPORT.md。参照 docs/SIX_BATCH_PLAN.md 批1 定义。tool/api_field_probe_v2.dart 与 docs/api_samples_v2/ 尚不存在（未实施状态）。

## ① 新增 tool/api_field_probe_v2.dart 的门禁影响

- **同名类检测**：smoke_check 的 `_checkDuplicateClassNames`（smoke_check.dart:346-367）**只扫 lib/**，tool/ 不在内。风险仅在于 probe_v2 若复用 api_probe.dart 中的类名且日后被 lib 引用——实际探针是独立 tool 脚本，无冲突。
- **500 行上限**：`_checkLineBudget` 同样只对 lib/ 文件生效（smoke_check.dart 只遍历 Directory('lib')）。tool/ 文件超 500 行**不触发 VIOLATION**，但按七六铁律精神建议 ≤500。
- **依赖白名单 / 禁 import / 桥唯一性**：全部只扫 lib/。probe_v2 用 dart:io + 网络请求不受限。但 **analyze_gate.py 默认扫 ["lib", "tool"]**（analyze_gate.py:63），若 probe_v2 出现「缺失名属于项目内类型」的真错误会被 CI 抓——探针引用 play_endpoints.dart 等核心类型时须保证名字正确。
- layer_audit.py 只管 lib/ 分层，不受影响。
- **结论：tool/ 新文件基本豁免静态门禁，唯一入口是 analyze_gate 的项目类型错误检查。**

## ② docs/api_samples_v2/*.json 脱敏口径

现有 docs/api_samples/（anonymous/nonvip/vip/summary.json）口径（API_TEST_REPORT.md §脱敏说明）：
- 不记录 token/userid/cookie/mid/dfid/signature/完整播放 URL；
- 播放 URL 只留 host；昵称/头像只标「有/无」；只读端点，不执行写操作。
api_samples 留样以 `endpoint/state/method/domain/path/paramKeys/ok/ms/captured`（仅顶层键+关键字段，如 urls=2/backupUrls=1/bitRate）落盘，无敏感值。
**v2 留样须沿用同一 schema 与脱敏清单，且 F3 要补的 urls/backup/bitRate/hash_offset/end_byte/fail_process 均为数值/计数型字段，天然脱敏安全。** 注意 research_field_capture_3state 若含原始响应，不得整段拷入留样。

## ③ CI verdict 是否加 probe_v2 步骤

**建议不加，保持离线报告。** 理由：
- probe_v2 是真实三态网络调用，需真实凭据（vip 态），CI runner 无凭据且不稳定（API_TEST_REPORT.md 批5 注：三态矩阵靠本地 api_probe.dart 产出）；
- verdict 段（ci.yml:117-164）每条判据都绑定 tee 到 /tmp/*.log 的具体步骤，加网络步骤会产生 flaky 红灯（超时/限频/风控）；
- 现有先例：api_probe.dart / api_matrix_probe.dart 均未进 CI。
可选折中：加一个 continue-on-error 的纯解析步（校验 docs/api_samples_v2/*.json 可解析、键齐全），不进 verdict。**不建议进 verdict 门禁。**

## ④ field_truth_test 的 play_url 锚点 vs F3 改动

锚点位置：field_truth_test.dart:393-397（N2-C play_url 盐负对照）、:691-692（mvKey 与 play_url 同盐断言）。
锚点本质是**纯 Dart 公式断言**：`key = md5(hash + signKeySalt + appid + mid + userid||0)`，依赖盐常量与公式，不依赖 play_models 响应模型字段。
F3 范围 = play_endpoints.dart 顶层字段补齐（urls/backup/bitRate/hash_offset/end_byte/fail_process）——属**响应模型/解析层新增字段**，不动盐常量与 key 公式。
**结论：理论上不打破；唯一红线是 F3 不得改 signKeySalt 常量或 key 计算入口。若 F3 顺带改 play_models 的 status/priv_status 判定语义，需重跑 field_truth_test（N2-C 负对照锚点会先红，属保护性失败）。**

## 门禁风险 TOP3 + 安全实施顺序

**TOP3**
1. **probe_v2 被 analyze_gate 扫到**（默认扫 tool/）：引用 lib 项目类型时名字/构造错误 → CI analyze_gate REAL-ERRORS 直接红。实施后先本地 `python3 tool/analyze_gate.py` 过一遍。
2. **留样脱敏走样**：v2 样本若含完整 URL/token/mid 等即破坏既有口径；用与 api_samples 相同的白名单键集序列化，先 diff 旧样本 schema。
3. **F3 与 N2-C 锚点的隐性耦合**：改 play_endpoints 时若触碰盐常量/key 公式或 status 判定语义，field_truth_test 立即红（CI verdict 有 FIELD-TRUTH 判据，见 ci.yml:144-145）。

**安全实施顺序**
1. 先落 docs/api_samples_v2/*.json schema（对齐旧脱敏口径）→ 2. 写 tool/api_field_probe_v2.dart（≤500 行、复用 api_probe 的类型名须唯一）→ 3. 本地跑 analyze_gate + dart format 确认零新错 → 4. F3 补 play_endpoints 顶层字段（不碰盐常量）→ 5. 跑 field_truth_test 确认 N2-C 锚点绿 → 6. 不改 ci.yml verdict，probe_v2 保持离线报告产出。

## 未覆盖
- tool/api_field_probe_v2.dart 实际代码与 docs/api_samples_v2/ 实际内容（未实施，无法核对）；research_field_capture_3state.md 全文未逐行核对；probe_v2 具体引用哪些 lib 类型未确定。
