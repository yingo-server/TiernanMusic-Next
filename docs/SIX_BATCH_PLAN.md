# 六批执行计划（3 检查 + 3 修复 / 批）· 2026-11-15

> 用户指令：规划好分批目标，仍为每批 3 个子代理检查 + 3 个子代理修复，一共六批。
> 子代理规矩（最新）：**不规定工具调用次数**；限定功能/文件范围；实时把最新结果写入指定 docs 文件；聊天汇报 <200 字；用已有发现收口，未查完标「未覆盖」不补齐；效率与质量优先。
> 不通知中间进度；六批全部完成后由主会话收口：全门禁 → 推送 → `workflow_dispatch` 带 `stable=true` 发布正式 LTS → 确认 `prerelease=false` + 3 APK + verification.json。

## 通用契约
- 76 原则：L1 init / L2 bootloader / L3 kernel / L4 core / L5 logic / L6 session / L7 surface；六桥唯一跨层通道；L7 只画控件。
- 检查代理：只读，报告落盘 `docs/six_b{N}_c{X}.md`，每核完一项实时写一次；不改代码。
- 修复代理：只改任务书指定的文件；改动说明落盘 `docs/six_b{N}_f{X}.md`，每改完一个文件实时写一次；不碰同批其它代理的文件。
- 主会话每批收口：`bash tool/local_gate.sh` + `python3 tool/analyze_gate.py` → `git add -A && git commit` → 派下一批。门禁失败就地修，不带病推进。
- 三态凭据：`/var/minis/workspace/.test_creds/{cj_vip,cj_nonvip}.txt` + 匿名；凭据值禁止打印/落盘；写操作按既定口径允许测试号外发并回滚。
- 版本变体（/vN±1）一律标「待实测」，不得冒充可用。

| 批 | 主题 | C1 检查 | C2 检查 | C3 检查 | F1 修复 | F2 修复 | F3 修复 |
|---|---|---|---|---|---|---|---|
| 1 | 三态字段捕获 | 现有端点字段捕获缺口收口（基于 research_field_capture_3state） | 探针脚本与凭据格式现状（tool/api_probe.dart） | 新增探针/样本对门禁与 CI 的影响 | `tool/api_field_probe_v2.dart` 真实三态只读探针 | `docs/API_FIELD_CAPTURE_3STATE.md` + `docs/api_samples_v2/*.json` 脱敏留样 | `play_endpoints.dart` 顶层字段补齐（urls/backup/bitRate/hash_offset/end_byte/fail_process） |
| 2 | 登录链收口 | 登录端点 vs 上游源码（batch2_c3 收口） | AuthLogic 回写/续期/多账号 | 登录 UI 三 Tab 与 settings 接线 | `auth_endpoints.dart` 参数契约 | `auth_logic.dart` 回写与续期 | `login_sheet.dart`/`settings_page.dart` 收口 |
| 3 | 匿名·MV·权益播放链 | 匿名 /v5/url + r_register_dev | MV 清晰度/视频 URL 契约 | 权益最大 URL/降档/备链 | `mv_anonymous.dart` 匿名封装 | `playback_service.dart` 权益链 | `playback_session.dart` 兜底 + `player_page.dart` 标识 |
| 4 | UI 功能补全 | 评论/收藏/歌单写成功语义 | FM/云盘/高潮/六类搜索可达性 | MV 入口/本地曲库/最近播放/主题四档 | 写回执 `_ok()`/受限透传 | 评论页/云盘/FM 入口 | library/player/shell 收口 |
| 5 | 缓存专项 | CacheService⊃预读 与 ResourceCache 边界 | 键维度（body/token/uid/dfid）与 TTL 分级 | 并发/统计/成熟库替换评估 | `cache_service.dart` 策略门面 | `resource_cache.dart` 原子异步 | `kugou_client.dart`/`inflight.dart` 接线 |
| 6 | 网络专项 + 发布收口 | 50 端点声明 vs 上游 vs 实测三方对齐 | 签名三模式/clienttime/dfid/Cookie/超时 | CI/文档/功能树/验收清单一致性 | `endpoint_registry.dart` 死声明清理 | `kugou_client.dart` 签名/超时 | 文档 + CI verdict + LTS 发布准备 |

## 发布（仅六批全完成后）
1. 主会话跑全门禁 `FINAL-OK` + `analyze_gate ok`。
2. `git add -A && git commit -m 'v2 final: six batches complete' && git push origin main`。
3. GitHub API `POST /repos/yingo-server/TiernanMusic-Next/actions/workflows/412356083/dispatches`，body `{"ref":"main","inputs":{"release":"true","stable":"true","debug":"false"}}`。
4. 定时器瞬时查该 run `conclusion` 与 `releases?per_page=1`：确认 `prerelease=false` 且资产含 3 个 ABI APK + `verification.json`。
5. 失败则下载 run 日志列 error 行/VIOLATION，只收口不提前宣告成功。
