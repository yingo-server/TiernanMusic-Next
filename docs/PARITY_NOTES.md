# 原归档项目功能面对齐 —— 实测知识补充（文档提取，零代码引用）

> 来源：`/var/minis/workspace/TiernanMusic/docs/` 下的**描述性文档**（README / PROGRESS /
> api_verified.md / archive/reviews-v37 功能缺口与阉割报告 / QUALITY_STANDARD）。
> 只提取「功能目标」与「原生 API 实测事实」，不引用、不复用任何旧项目代码。
> 对齐原则：功能面对齐，实现全部按 TiernanMusic-Next 六层五桥重写。

## 1. 旧项目实测过的原生端点（api_verified.md，匿名态）

| 端点 | 关键事实（我们可参考的实测结论） |
|---|---|
| search/song | complexsearch.kugou.com/v3 ✅ |
| search/hot | msearch.kugou.com ✅ |
| rank/list | ocean.kugou.com/v6 info 56 项 ✅ |
| rank/audio | kg-tid 369；签名用 defaultParams+body 合并 ✅ |
| playlist/detail | pubsongs/v3，载荷 data[].global_collection_id ✅ |
| playlist/track/all | pubsongs/v2/get_other_list_file_nofilt ✅ |
| artist/detail/audios/albums | gateway/kmr/v3/author、kmr/v1/author/albums；**audios 签名需 defaultParams+body 合并** ✅ |
| album/detail / album/songs | kmr/v2/albums、v1/album_audio/lite ✅ |
| kmr/audio/mv | openapi + KG-TID:38，body album_audio_id ✅ |
| comment/music | **参数走 query 不是 body**；顶层 list ✅ |
| comment/floor | mcomment/v1/hot_replylist ✅ |
| comment/count | web 签名 + sum.comment.service x-router ✅ |
| privilege/lite | relate_goods 7 项 ✅ |
| song/url | 需 key（signKey）；直连无 20028 ✅ |
| video/detail / video/url | video/detail 清晰度 hash 齐全；video/url downurl ✅ |
| lyric/search | **成功语义是 status=200**（不是 1）✅ |
| yueku | v1/yueku/recommend_v2 ✅ |
| everyday/recommend | platform 必须是 **query 参数** ✅ |
| login/qr/key | web 签名 + login-user.kugou.com ✅ |
| get/verify/info | 假 eventid 正确报错 ec=36001（接口通）✅ |
| top/song | musicadservice.kugou.com ✅ |
| top/playlist special_recommend | ⚠️ 直连恒 200101，旧项目保留 kapi 回退（我们实测已修复：body 全参+key 秒级 → err=0） |

### 签名要点（文档提取，与我们的 signing.dart 一致）
1. android：`md5(salt + sorted("k=v") + bodyStr + salt)`，salt=`OIlwieks28dk2k092lksi2UIkp`；
   签名输入 = **defaultParams + 自定义 params**（body 单独传，不进签名，除非也在 params 里）。
2. web：`WEB_SALT=NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt`，用于 comment/count、login/qr/*。
3. register：`md5("1014" + sorted(values) + "1014")`。

## 2. 音质档位实测（v37_cripple_report，VIP 态全部真实返回 URL）

VIP 可用档位：`128 / 320 / flac / high / super / viper_tape / viper_clear / viper_atmos / multitrack`。
**魔法音效 6 档（magic_piano/acappella/dj/surnay/subwoofer/ancient）匿名/非VIP/VIP 三态全部返回 URL**——免登录用户唯一可得的音效变体。
CDN（fsandroid/fsmobile.tx.kugou.com）原生支持 **HTTP Range 断点续传**（206 Partial Content，Accept-Ranges: bytes），URL 有效期约 5 分钟，过期需重新 resolve 后带 Range 续打。

## 3. 旧项目自检出的「阉割项」（我们要主动补齐，避免重蹈）

- 蝰蛇三档 / 魔法六档 / multitrack：数据链全通但枚举与 UI 无入口（典型「有了却被自己枚举挡住」）。
- 下载时无「本次选更高音质」UI，只能改全局默认音质。
- 20028 验证存在三套平行实现（auth_repository / verification_service / captcha_types），语义不一致——我们应收敛为单一 verification 门面。
- 每日推荐只做了 recommend、缺 everyday_history（听歌日历）。
- 个人 FM / 电台全缺（「不选歌就开始听」入口）。
- 上报/偏好缺（playhistory_upload / user_listen_report）→ 每日推荐个性化退化。

## 4. 旧项目功能域盘点（v37_feature_gap，236 个 Node 模块 ↔ 实现差集）

| 域 | 旧项目状态 | 对齐要求 |
|---|---|---|
| 搜索 | 13 方法全有（联想/热词/歌词/多类型） | 补齐六类搜索 + 综合搜索 v6 + 聚合搜索 |
| 播放链路 | 直连 + dfid 注册闭环 | 补齐 20028 验证收敛 + 全音质档 + 魔法音效 |
| 歌单 | 读链路 + 增删歌/收藏/新建 | 补齐排序、标签、相似、导入、封面改、官方分享 |
| 榜单 | list+audio | 补齐 rank_info/top/vol、全球榜筛选 |
| 每日推荐 | recommend | 补齐 everyday_history / friend / style |
| 歌手 | detail/audios/albums | 补齐视频、荣誉、关注/取关、新歌速递 |
| 专辑 | detail/songs | 补齐数字专辑商店、动态封面（P3） |
| 评论 | 音乐/歌单 + 楼中楼 + 点赞/删除 | 补齐专辑/MV 评论（低频） |
| MV | 搜索播放 + 收藏/取收藏 + 列表 | 补齐弹幕、相关视频 |
| 电台 FM | 全缺 | 全补（P1 大块） |
| 听书长音频 | 全缺 | 全补（9 端点） |
| 用户 | 除 user_detail 外全缺 | 补齐云盘、已购、听歌排行、关注粉丝、等级偏好 |
| 一起听 | 全缺（社交重功能，价值存疑） | 可不做（标注） |
| 场景/主题歌单 | 全缺 | 补齐 scene_* / theme_* / sheet_* |
| 上报/偏好 | 全缺 | 补齐（个性化依赖） |
| 其它 | song_climax / song_barrage / import_playlist / ai_recommend / top_card | 补齐 |

## 5. 用户体验类功能（README 特性，需对齐）

- Material 3 Expressive：深色默认、**封面动态取色**、纯黑模式（我们已有亮暗，缺取色/纯黑）。
- 多账号管理：手机号/密码、酷狗二维码登录、人机验证自动处理。
- KRC 逐字歌词：**逐行翻译（原文/双语/译文）**（我们缺翻译）。
- 10 种语言：简中/繁中/英/日/韩/西/法/德/葡/俄（我们全缺）。
- 智能缓存：音频/图片/视频持久缓存，其他数据 90s 内存缓存。
- MV 播放：代理转发 HTTP 流（我们架构不需要代理，可直接播 CDN）。
- 首页聚合、收藏、评论、MV 页面模块。

## 6. 质量原则（QUALITY_STANDARD 提取）

1. 分层单向依赖、桥接层日志留痕（我们已有）。
2. 错误处理：语义错误唯一翻译、空响应体判失败、写操作禁止回退（防重复提交）、maybeSucceeded 语义。
3. 并发与生命周期：全局 await、token、dispose；世代校验 + 闸门单点释放。
4. 网络契约：三态（anon/nonvip/vip）实测、多参不缺参、签名模式不混用。
5. 审查纪律：完整 file_read、每条问题给位置/事实/契约/后果/级别；静态检查过滤 Flutter 噪音；本地禁编译。
6. 逐文件审查后才提交；代理不 commit/push，主会话统一修。
