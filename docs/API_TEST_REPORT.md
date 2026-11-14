# API 实测报告（三态真实返回）

> 生成时间：2026-11-13T17:58:14.252759Z  
> 样曲：`b3a52a7a958bf0aed0ebfba2e9a818b7`（周杰伦《晴天》，VIP 曲）  
> 状态：anonymous, nonvip, vip  
> 工具：`tool/api_probe.dart`（走代码路径真实调用）→ `tool/api_report.py` 汇总

## 脱敏说明

- 不记录 token / userid / cookie / mid / dfid / signature / 完整播放 URL；
- 播放 URL 只保留 host；昵称/头像只标记「有/无」；
- 写操作（收藏、歌单增删、播放上报）**未执行**，避免改动真实账号数据。

## 一、三态结果矩阵

| 端点 | anonymous | nonvip | vip |
|---|---|---|---|
| `play_url_v5` | ✅ 正确盐下匿名 `status=0, priv_status=0, errcode=20028`（人机验证），urls=0, backupUrls=0；`31833` 仅作**错盐负对照**（签名失败，非匿名正常态，见 §四/§五） | ✅ status=2, priv_status=0, errcode=0, urls=0, backupUrls=0 | ✅ status=1, priv_status=1, errcode=0, urls=2, backupUrls=1 |
| `search_song` | ✅ total=480, items=10, firstHash=1f7e7659b9fff4fb6f71562a61bbc25f, firstName=周杰伦 - 发如雪, firstSinger=周杰伦 | ✅ total=480, items=10, firstHash=1f7e7659b9fff4fb6f71562a61bbc25f, firstName=周杰伦 - 发如雪, firstSinger=周杰伦 | ✅ total=480, items=10, firstHash=1f7e7659b9fff4fb6f71562a61bbc25f, firstName=周杰伦 - 发如雪, firstSinger=周杰伦 |
| `search_suggest` | ✅ items=40, first=周杰伦 | ✅ items=40, first=周杰伦 | ✅ items=40, first=周杰伦 |
| `search_hot` | ✅ items=270, first=慌啥子嘛 | ✅ items=270, first=慌啥子嘛 | ✅ items=270, first=慌啥子嘛 |
| `daily_recommend` | ✅ items=0（未登录：errcode=200103，data 为字符串） | ✅ items=0 | ✅ items=0 |
| `rank_list` | ✅ items=56, first=Instance of 'RankBrief' | ✅ items=56, first=Instance of 'RankBrief' | ✅ items=56, first=Instance of 'RankBrief' |
| `user_detail` | ✅ vipType=0 | ✅ nickname=<has-nickname>, vipType=0, avatar=<has-avatar> | ✅ nickname=<has-nickname>, vipType=6, avatar=<has-avatar> |
| `favorite_count` | ✅ count=0 | ✅ count=0 | ✅ count=0 |
| `song_climax` | ✅ hasResult=False | ✅ hasResult=False | ✅ hasResult=False |
| `user_cloud` | ✅ items=0 | ✅ items=0 | ✅ items=0 |
| `fm_play` | ✅ items=0 | ✅ items=0 | ✅ items=0 |
| `comment_music` | — | — | ✅ total=0, items=0 |
| `comment_count` | — | — | ✅ count=0 |
| `mv_by_song` | — | — | ✅ found=False |
| `album_detail` | — | — | ✅  |

## 二、调用方式

| 端点 | 方法 | 域名 | 路径 | 参数键 |
|---|---|---|---|---|
| `play_url_v5` | GET | gateway.kugou.com | `/v5/url` | hash, quality |
| `search_song` | GET | gateway.kugou.com | `/v3/search/song` | keyword, page, pagesize |
| `search_suggest` | GET | gateway.kugou.com | `/v2/getSearchTip` | keyword |
| `search_hot` | GET | gateway.kugou.com | `/api/v3/search/hot_tab` | — |
| `daily_recommend` | POST | gateway.kugou.com | `/everyday_song_recommend` | — |
| `rank_list` | GET | gateway.kugou.com | `/ocean/v6/rank/list` | — |
| `user_detail` | POST | gateway.kugou.com | `/v3/get_my_info` | — |
| `favorite_count` | GET | gateway.kugou.com | `/count/v1/audio/mget_collect` | mixsongids |
| `song_climax` | GET | expendablekmrcdn.kugou.com | `/v1/audio_climax/audio` | hash |
| `user_cloud` | POST | gateway.kugou.com | `/v1/user_cloud` | — |
| `fm_play` | POST | gateway.kugou.com | `/v1/fm/play` | — |
| `comment_music` | GET | gateway.kugou.com | `/mcomment/v1/cmtlist` | mixsongid, page |
| `comment_count` | GET | gateway.kugou.com | `/v1/comment/count` | mixsongid, hash |
| `mv_by_song` | POST | gateway.kugou.com | `/kmr/v1/audio/mv` | album_audio_id |
| `album_detail` | POST | gateway.kugou.com | `/kmr/v2/albums` | album_id |

## 三、延迟（单次样本，ms）

| 端点 | anonymous | nonvip | vip |
|---|---|---|---|
| `play_url_v5` | 1267 | 451 | 436 |
| `search_song` | 283 | 187 | 237 |
| `search_suggest` | 539 | 458 | 438 |
| `search_hot` | 184 | 176 | 151 |
| `daily_recommend` | 179 | 95 | 107 |
| `rank_list` | 363 | 352 | 279 |
| `user_detail` | 4 | 454 | 237 |
| `favorite_count` | 126 | 97 | 100 |
| `song_climax` | 325 | 373 | 283 |
| `user_cloud` | 6 | 111 | 123 |
| `fm_play` | 105 | 97 | 87 |
| `comment_music` | — | — | 414 |
| `comment_count` | — | — | 103 |
| `mv_by_song` | — | — | 133 |
| `album_detail` | — | — | 101 |

## 四、失败与已知不可用（如实记录）

1. **评论 WAF**：`comment_music`（`/mcomment/v1/cmtlist`）上游返回 `Access Deny !!!` 纯文本（HTTP 200 但非 JSON），已由 `KugouClient._requestRaw` 归一为 `KugouApiException(-3, 'invalid json ...')` 解析错（旧版裸 `FormatException` 已修），上层按空列表兜底；UI 应显示受限提示而非「暂无评论」。
2. **每日推荐**：未登录态 `errcode=200103`、顶层 `data` 为**字符串**（非数组）；端点层按错误码归空，不得当成功空列表。
3. **匿名播放**：正确盐下匿名 `errcode=20028`（人机验证态）；`31833` 是此前**错盐**样本的签名失败负对照，不代表匿名正确口径，不得作为匿名态结论。
4. **其余空样本**（FM/云盘/高潮片段/MV/专辑详情/收藏计数）：本次样本为空，标注「待补测」，不写成可用。

## 五、结论

1. **搜索/联想/热搜/榜单**：三态均返回真实数据（480 条结果、40 条联想、270 条热搜、56 个榜单）。
2. **播放权限三态完整复现**：正确盐下匿名 `status=0 errcode=20028`（人机验证）；非VIP `status=2 priv_status=0`；VIP `status=1 priv_status=1 urls=2`（host=fsandroid.kugou.com，128k mp3，269s）。`31833` 为错盐负对照（签名失败），`privKnown` / `20028` 判定见 `endpoints/play_models.dart`。
3. **评论**：上游 WAF 返回 `Access Deny !!!`（非 JSON），`KugouClient` 已归一解析错；当前代码按空列表兜底——UI 不应显示「暂无评论」，应显示受限提示。
4. **每日推荐**：未登录 `errcode=200103`、键为 `errcode`（非 `error_code`）、`data` 为字符串；需按错误码如实提示，不得当空列表。
5. **其余（FM/云盘/高潮片段/MV/专辑详情/收藏计数）**：本次样本为空，标注「待补测」，不得写成可用。
6. **关键修复**：`srcappid` 默认注入导致搜索等端点全线 `20006`，已改为默认不注入（网络层真 bug，影响所有版本）。

## 六、批5 说明

- **批5 未新增三态实测**：本报告的三态矩阵（anonymous / nonvip / vip）仍为 2026-11-13 那次 `tool/api_probe.dart` 产物，批5 未新增任何端点的三态实测样本。
- **未实测端点清单**：见 `docs/API_CONTRACT_MATRIX.md`（端点×状态覆盖矩阵）与 `docs/batch5_c2.md`（批5 只读检查中列出的未实测/字段待核端点）。
- 口径不变：匿名正确盐为 `errcode=20028`（人机验证），`31833` 仅为**错盐负对照**（签名失败），不代表匿名正常态。

## 七、对照文档

- 旧版调用面：`docs/API_DICT_LEGACY.md`
- 新版调用面：`docs/API_DICT_CURRENT.md`
- 字段契约：`docs/API_FIELDS_TRUTH.md` / `docs/API_FIELD_DICT.md`
