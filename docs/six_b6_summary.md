# 批6 整理（2026-11-15）

主题：网络专项 + 发布收口。按新规矩：已有 `docs/plan_upstream_endpoints_a/b.md`、批2/3 契约修正、线C 网络审计复用；真实小缺口主线直接修，不重复派代理。

## 检查结论（复用）
- `docs/plan_upstream_endpoints_a.md` / `_b.md`：上游 159 个 Node 模块源码提取的官方端点全表（域名/路径/x-router/签名/参数/版本变体猜测），不运行其包装网关。
- `docs/AUTONOMOUS_CACHE_NETWORK_AUDIT.md` §C2/C3：`kugou_client.dart` 键维度缺口（body/token hashCode 不稳定、缺 dfid/mid、rawBody 未进单飞键、登出失效钩子）。
- 批2/3 已修：登录链 5 偏差、videoDetail 契约、kmr/v2 死 fallback 删除、匿名 `registerDevice`/`anonymousPlayUrl` 待实测封装、play_url 顶层字段。
- CI/文档/功能树一致性在批1~5 各 summary 与 `FUNCTION_TREE.md`/`ARCHITECTURE.md` 已对齐；`local_gate.sh` 覆盖 syntax/smoke/layer/analyze_gate/field_truth/reachability/boot/session/play/resolve/download/session 契约。

## 修复结果（主线，批6）
- `lib/core/net/kugou_client.dart`：`_cacheKeyOf` 改用稳定内容摘要 `md5Hex(jsonEncode(排序键))` 替代 `Map.hashCode`/`token.hashCode`；新增 `dfid`、`mid` 维度；`rawBody` 摘要进入单飞键（L2 仍排除 rawBody）；新增 `_stable()`。
- `lib/surface/pages/settings_page.dart`：`_logout()` 登出后调用 `appGraph.cache?.invalidateSession()` → `KugouClient.clearInflight()`，换号不复用旧 token 等待表。
- `clearInflight` 本身已在批5/线C 具备；设置页「清理歌词缓存」已接同一失效链。

## 门禁
- `dart format --output=none lib tool test`：通过
- `bash tool/local_gate.sh`：`FINAL-OK`
- `python3 tool/analyze_gate.py`：`analyze_gate ok (0 project-type errors)`

## 未覆盖 / 诚实边界
- 50 端点声明未逐一与三态实测重新对齐；`docs/API_CONTRACT_MATRIX.md` 中「待实测」项保持。
- 版本变体（vN±1）仍全部标「待实测」，未冒充可用；`api_field_probe_v2` 未实跑，样本未产出。
- 成熟库替换磁盘缓存评估未执行；`dart:io ResourceCache` 保留（全异步原子 rename）。
- 评论写/点赞、微信开放平台登录（按用户超时默认「先不接」）、MV mp4 音频真机解码未验证。

## 发布准备
六批全部整理完成；下一步由主会话/定时器：全门禁 → 推送 → `workflow_dispatch` `stable=true` → 确认 `prerelease=false` + 3 APK + verification.json。
