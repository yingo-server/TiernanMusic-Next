# 批1-C2 · 三态探针脚本与凭据格式现状（只读核查，2026-11-15）

范围：tool/api_probe.dart、tool/api_matrix_probe.dart、.test_creds/FINDINGS.md（键名级）、docs/API_TEST_REPORT.md。只读，未执行任何探针。

## ① 旧探针 tool/api_probe.dart 已覆盖内容
- 三态：anonymous（dfid='-'，无凭据）/ nonvip（cj_nonvip.txt）/ vip（cj_vip.txt），每态逐端点跑。
- 已覆盖端点（15 个）：play_url_v5（走 getPlayUrlV5 代码路径，含 key 计算）、search_song、search_suggest、search_hot、daily_recommend、rank_list、user_detail、favorite_count、song_climax、user_cloud、fm_play；交叉端点仅 vip 态：comment_music、comment_count、mv_by_song、album_detail。
- 每行记录：endpoint/state/method/domain/path/paramKeys/ok/ms/captured/error；按态分文件落盘（docs/api_samples/{state}.json + summary.json）。
- 脱敏规则：token/userid/cookie/mid/dfid/signature 不落盘；播放 URL 只留 host（url/backupUrl 换 `<redacted-url>`，留 count）；昵称/头像只记 `<has-*>`；play_url 原始响应白名单键（status/priv_status/errcode/bitRate/extName/timeLength/IsFreePart/end_byte/traceId/tracker_through.musicpack_advance）+ _host + _topKeys。
- 明确不执行写操作（收藏/歌单增删/上报）。

## ② 新 api_field_probe_v2 现状
- **不存在**。tool/ 目录无 api_probe_v2.dart、无 api_field_probe_v2.*（rg 全目录确认）。
- 最近似的两个骨架：
  - tool/api_matrix_probe.dart：批01-C 矩阵骨架，只有 TestState 枚举/Verdict 枚举(ok/noPriv/needVerify/empty/risk/skip)/ProbeRow/CSV 写出器，**main 不发真实请求**（76 原则留待主会话填网络层）。
  - tool/field_truth_test.dart：字段契约校验（未深读，未覆盖项）。
- 缺：字段级捕获（per-field 三态差异）、v2 分档批量（/v6/priv_url 等）、CSV/矩阵 verdict 自动判定接线。

## ③ 凭据文件格式与匿名态构造
- 格式：Netscape cookie TSV（7 列：domain, flag, path, secure, expiry, name, value），如 cj_vip.txt / cj_nonvip.txt。
- 键名（仅键名）：token, userid, t1, vip_type, vip_token, KUGOU_API_MID, KUGOU_API_DEV, KUGOU_API_GUID, KUGOU_API_MAC, KUGOU_API_PLATFORM。
- api_probe._loadCreds：按 `\t` split，取 parts[5] 为键、parts[6:] 拼值；_sessionOf 映射 token/userid/mid=KUGOU_API_MID，Cookie 只带 t1/vip_type/vip_token/userid，dfid 固定 '1234567890ABCDEF12345678'（24 位）。
- 匿名态：_sessionOf(null) → 空凭据、dfid='-'；参考 .test_creds/threestate.py 纯 Python 探针（盐 OIlwieks…，appid=1005，clientver=20489，dfid 随机 24 位 [0-9A-Z]，headers x-router/dfid/mid/kg-thash 等）。
- FINDINGS.md 关键口径：play_url 顶层即数据；匿名 20028（人机验证）、非VIP priv_status=0、VIP status=1 出 URL；privilege_lite 不可作权限判定；musicpack_advance=1 为 VIP 曲判定字段。

## ④ 写操作/登录禁调口径
- api_probe.dart 头注释 + API_TEST_REPORT.md 脱敏说明一致：**不执行写操作**（收藏、歌单增删、播放上报），不改真实账号数据。
- 登录禁调：凭据不入仓库/日志，值不打印（本核查同样只读键名）；.test_creds 下存在写探针脚本（fav_write_probe.py、r1a_probe.py 等）但**不属 tool/ 仓库口径**，仓库侧统一禁写。

## F1 可直接执行的探针规格（≤5 条）
1. 新建 `tool/api_field_probe_v2.dart`：复用 api_probe.dart 的 _loadCreds/_sessionOf/三态循环与 ProbeRow，新增字段级 captured（逐字段三态差异表）+ Verdict 枚举（沿用 api_matrix_probe.dart 的 ok/noPriv/needVerify/empty/risk/skip）。
2. 端点集：先平移 api_probe.dart 全部 15 端点；补 FINDINGS.md「待测」项——非 VIP 免费曲三态 play_url、privilege_lite 三态、/v6/priv_url 多档批量。
3. 脱敏沿用白名单制：URL/签名/凭据不入 JSON，播放 URL 只留 host + count；新增字段差异表同样走白名单。
4. 输出双通道：docs/api_samples/{state}.json（兼容旧报告）+ docs/api_contract_matrix.csv（verdict 列，对齐 API_CONTRACT_MATRIX.md）。
5. 口径固化：匿名 play_url 期望 errcode=20028；禁写操作；daily_recommend 未登录 errcode=200103 按错误归空；评论 WAF Access Deny 归 RISK 不算 EMPTY。

## 未覆盖
- tool/field_truth_test.dart、api_report.py 内容未深读；FINDINGS.md 之外其它 .test_creds 样本 JSON 未核对；未实际运行任何探针验证连通性。
