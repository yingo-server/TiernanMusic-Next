# A3 批 · C3 用户痛点专项视角 · `lib/core/net/endpoints/` 端点层审查

> 子代理：A3-C3｜视角：用户痛点（端点可用性 / 功能可达性 / 文案 / YKG / MV 三态）
> 契约：`docs/DEEP_AUDIT_14_BATCH_PLAN.md` §0 76 原则
> 复用：`docs/deep_audit/bA1_c3.md`（YKG/文案/功能断点盘点，本文不重复其结论，只做端点层取证与延伸）
> 本轮只读；唯一写入为本文件（append）。
> 范围说明：任务书写「25 个 dart 文件」，`rg --files lib/core/net/endpoints -g '*.dart'` 实际为 **26 个**（6017 行）。本文按实际 26 个全审。

---

## 2026-11-16 · A3-C3 端点层审查（重派续写 · 逐文件取证）

> 说明：本文件开头报告头为上一实例所写（仅头部，未含结论）。本次重派从头审 26 个端点 dart 文件，结论自此处追加。
> 复用 bA1_c3.md 的 YKG/文案/功能断点结论，本文只做端点层取证与延伸，不重复。

### 视角 C3 · lib/core/net/endpoints/mv_endpoints.dart:139-176 · P1 · 文案 / 画质档位硬编码（用户点名）
证据：`MvQuality.fromFlat` 内 `const tiers` 与 MKV 档 label 直接内嵌中文展示串：
- `:141 'ld': '流畅 270P'`、`:142 'sd': '标清 432P'`、`:143 'hd': '高清 720P'`、`:144 'fhd': '全高清 1080P'`、`:145 'qhd': '超高清 540P'`、`:175 label: 'MKV 超高清'`；`:171-172` H.265 档拼 `'${e.value} H.265'`。
问题：这 6 处 label 是**随 MV 画质选择 UI 直接展示给用户**的文案，硬编码在 L4 网络端点层，`lib/core/l10n/strings.dart` 无对应 key（全仓 i18n 又是死代码，见 bA1_c3）；换语言完全无效。并且档位命名倒挂：540P 标「超高清」却低于 1080P「全高清」，用户无法据 label 判断清晰度高低。
建议：label 改由档位 id（ld/sd/hd/fhd/qhd/mkv_qhd/_265）在 l10n 层映射，端点只回 id；修档位名按分辨率升序（流畅270<标清432<高清720<超清1080，qhd540 应改名或删除）。
76 合规：涉及 —— L4 端点层持有面向用户界面文案，违反 §0「l10n 常量归 L4 core/l10n」的职责归口（虽同层，但落在 net 而非 l10n，且端点应保持纯数据）。

### 视角 C3 · lib/core/net/endpoints/mv_endpoints.dart:236-422 + mv_anonymous.dart:1-227 · P0 · MV 端点三态 / 死代码（用户点名）
证据（两段式接口是否具备）：
- **两段式接口存在且正确**：`getMvBySong(client, albumAudioId)`（`:252`，POST /kmr/v1/audio/mv，body `data:[{album_audio_id}]` → `MvBrief.hash`）；`getVideoQualities(client, mvHash)`（`:301`，POST /v1/video，body `data:[{video_id: h}]` → `MvQuality.fromFlat`）；`getVideoUrl(client, qualityHash)`（`:360`，GET /v2/interface/index → `MvPlayResult.urls`）。即 `albumAudioId → getMvBySong → hash → getVideoQualities → qualityHash → getVideoUrl` 三段接口端点层**齐备且语义正确**（与 bA1_c3 的 MV hash 错配结论一致：错在 MV 页/逻辑层把歌曲 hash 当 video_id，非端点层缺接口）。
- **匿名/VIP 三态端点雏形存在但完全死代码**：`mv_anonymous.dart` 227 行，`registerDevice`（`:57`，取真实 dfid）、`anonymousPlayUrl`（`:144`，/v5/url 试听）两个公开函数 + `ParsedPlayUrlShim`（`:210`）；`mv_endpoints.dart` 顶部还残留拆分后未用的 import（`:31` 引入 `playlistAesEncrypt/rsaEncrypt2/playlistAesDecrypt`、`:32 md5Hex`，正文未调用）。全仓 `rg 'mv_anonymous|anonymousPlayUrl|registerDevice' lib`（见 bA1_c3）零调用点。
- **「待实测」冒充可用**：`mv_anonymous.dart` 顶部注释 + `:128/:131/:194/:198` 全部标 `⚠️ 待实测`；`mv_endpoints.dart` 注释 `:8-9/:14-16` 亦标 anonymousSongUrl/registerDevice 待实测。这些能力**从未被上层调用**，却以完整函数体形态存在。
问题：端点层为 MV 提供了正确的「按歌曲→MV hash→档位→播放地址」三段式能力，但**匿名看 MV / VIP 高清降级这条三态链路只写了端点没有接线**——`anonymousPlayUrl`/`registerDevice` 是死代码，用户「未登录也能看 MV」的诉求在端点层有半成品、在产品层完全不可用。
建议：① 由主会话修 MV 页链路接 `getMvBySong`（见 bA1_c3，端点层无需改）；② 若要做匿名三态，把 `anonymousPlayUrl` 经 bridge_core 暴露给 MvLogic 作为「需登录/VIP」降级试听，并实测去「待实测」标记；③ 清掉 mv_endpoints.dart 拆分遗留的未用 import。
76 合规：不涉及（端点分文件基本合规；死代码属实现问题，MV 页 hash 错配在 L7/L5 层，不在本批）。

### 视角 C3 · lib/core/net/endpoints/comment_endpoints.dart:168-194 · P1 · 文案 / WAF 降级提示（用户点名「评论 Access Deny」）
证据：`commentBlockedReason(Object e)`（`:169`）返回面向用户文案：`:174 '接口返回非 JSON（可能被安全策略拦截，$msg）'`、`:176 '接口响应异常（$msg）'`、`:178 '接口响应异常'`；`getMusicComments`（`:194`）参数守卫返回 `blockedReason: '歌曲标识无效，无法加载评论'`。`CommentPage.blockedReason`（`:93`）透传给 UI。
问题：端点层确实为 WAF/风控（KugouApiException -3，`Access Deny !!!`）做了**降级通道**——`blockedReason` 字段是正确设计（没把 WAF 误报成「暂无评论」）。但降级提示文案硬编码中文、含内部黑话「安全策略拦截」，并把原始异常 `$msg` 拼进用户可见串（可能泄露技术细节）；无 i18n key。
建议：把 blockedReason 改成稳定错误码枚举（waf_blocked/bad_id/network/parse），中文文案移到 l10n/UI 按码取词；`msg` 只进 Log 不进 UI。
76 合规：涉及 —— L4 端点层生成面向用户中文文案（应只产出错误码/状态，文案归口 L4 l10n 或 L7）。

### 视角 C3 · lib/core/net/endpoints/auth_endpoints.dart:36-546 · P0 · YKG 缺失 / 待实测端点冒充可用
证据：
- **全 endpoint 目录 YKG 零实现**：`rg -ni 'ykg' lib/core/net/endpoints` 零命中，无 auth 导出/导入端点雏形、无 base64 cookie 封装、无加盐密码校验端点（与 bA1_c3 全仓 YKG 零实现结论一致）。
- **5 个登录端点全部标「待实测」**：文件头注释 `:9-25` 明示 sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout 均 `待实测 → needsProbe`；`LoginResult.needsProbe`（`:87`）、`SmsLoginResult.needsProbe`（`:116`）把「端点未实测」作为语义失败信号往外抛。凭据相关常量仍空：`kLoginPwdT1=''`/`kLoginPwdT2=''`（`:52-53`，注释「待实测为空时发'0'」），降级候选 v9→v7→v6/v5→v4→v3 均未验证。
- `kAuthEndpointsProbed=true`（`:38`）注释称「三态实测通过后保持 true 放行真实网络调用」，但同文件端点仍标 needsProbe——开关语义与端点实测状态自相矛盾（放行真实请求 vs 未实测）。
问题：登录链路端点层「实现了函数体但没实测」，用 needsProbe 把研发状态往上传导，与 UI 的「端点待实测/后端就绪」占位文案呼应（bA1_c3）：用户点密码登录走的是未验证端点 + 空 t1/t2 常量，成功率无保障。YKG 新登录方式端点层零雏形。
建议：① 登录端点完成三态实测前不要放行真实凭据（kAuthEndpointsProbed 与 needsProbe 统一口径），UI 前置禁用未实测登录方式；② 密码学 KDF/HMAC 缺失见 bA1_c3（新增 crypto_kdf.dart）；③ YKG 端点需新建（本轮只审不改，设计输入见 bA1_c3）。
76 合规：不涉及（端点分文件合规；needsProbe 语义外抛属实现问题）。

### 视角 C3 · lib/core/net/endpoints/recommend_endpoints.dart:26-143 · P2 · 三态建模正面样本
证据：`DailyRecommendState {ok, loginRequired, empty, error}`（`:26`）+ `DailyRecommendResult`（`:33`）用 `ListBase` 兼容旧 UI；`getDailyRecommend`（`:103`）对 errcode 200103 返回 `loginRequired`（`:127`），失败返回 `error`（`:142`），**不把「未登录」冒充「无推荐」**。错误仅进 `Log.w`（`:120,:133`），无用户文案泄漏。
问题：端点层「三态建模」的正面样本（对比 MV/评论的缺口）；无实质痛点。仅 `UnsupportedError('DailyRecommendResult 只读')`（`:59/:66/:70/:74`）含中文，但是开发者异常、不进 UI。
建议：作为 MV/其他端点的三态建模参照模板。
76 合规：不涉及。

---
## 2026-11-16 · 端点可用性清单（C3 · 功能可达性视角）

判定口径：以「有实现但上层 logic/session/surface 零调用」（桥导出不算消费）为死端点；以文件头/注释明文标「待实测」但仍被上层当作可用为「待实测冒充可用」。

### 死端点（有实现 + 桥导出，但上层零调用）
| 端点函数 | 文件:行 | 证据 | 严重度 |
|---|---|---|---|
| `registerDevice` / `anonymousPlayUrl` / `ParsedPlayUrlShim` | `mv_anonymous.dart:57/:144/:210` | 整个 227 行文件无人 import；函数全仓零调用（A1-C3 已证）；仅 EndpointRegistry 注释提及 | P0 |
| `getPrivilegeLite` | `play_endpoints.dart:336` | 仅 `bridge_core.dart:136` 导出，logic/session/surface 零调用 | P1 |
| `getSongClimax` / `getUserCloud` / `reportListen` / `uploadPlayHistory` | `user_endpoints.dart:217/:257/:307/:190` | 仅 `bridge_core.dart:169-173` 导出，上层零调用（听歌历史/云盘/上报/高潮片段用户完全触达不到） | P1 |
| `fetchTranslation` / `fetchTranslationFromContent` | `translation_endpoints.dart:141/:161` | 仅桥导出；`translation_logic.dart:36` 注释声称调 `fetchTranslationFromContent`，实际 `displayFor` 改为直接调 `extractEmbeddedTranslatedLines`（`:49`），两个 fetch 入口均未真正调用 | P1 |

### 待实测冒充可用
| 端点 | 文件:行 | 证据 | 严重度 |
|---|---|---|---|
| 5 个登录端点（sendSmsCode/smsLogin/loginByPwd/loginByToken/devLogout） | `auth_endpoints.dart:9-25,38,52-53` | 注释标「待实测→needsProbe」，但 `kAuthEndpointsProbed=true` 放行真实网络；t1/t2 常量空 | P0 |
| 匿名 MV 端点（anonymousSongUrl/registerDevice） | `mv_endpoints.dart:7-10,416-422`；`mv_anonymous.dart:3-14,104` | 标「待实测」，platid 2 vs 1 未定稿，却写成完整函数体 | P0 |
| 收藏计数 getFavoriteCount | `collect_endpoints.dart:10,90,241` | 无实测章节、不设成功门槛，但上层有调用（favorite list 回填），属「弱验证冒充可用」 | P2 |

### 不可用端点（已降级/已弃用，端点层保留空壳）
- `searchComplexV6`（`search_typed_endpoints.dart:106`）：/v6/complex 恒 152 不可达，已降级为 v3/song 薄委托（保留兼容，非死代码，被 search_typed_logic 调）。
- `getArtistAlbums` 内 /v1/author/albums（`artist_endpoints.dart:455`）：恒 502，已改三步降级链（端点层正面降级样本）。
- `getVideoQualities` 的 kmr/v2 fallback（`mv_endpoints.dart:333`）：三态 404 已删。

### 五条主链路端点层完整性（仅看端点能力是否具备）
| 链路 | 端点能力 | 判定 |
|---|---|---|
| 搜索 | `searchSongs`/`searchSuggest`/`searchHot`/`searchTyped`(6类含MV)/`searchComplexV6`(降级) | ✅ 端点齐备（MV 搜索端点 `SearchType.mv` 存在，但 UI 分段无 MV 段——见 bA1_c3） |
| MV | `getMvBySong`→`getVideoQualities`→`getVideoUrl` 三段式齐备；匿名 `anonymousPlayUrl` 死代码 | ⚠️ 主线端点齐备但上层错用 hash；匿名/VIP 三态端点半成品 |
| 播放 | `getPlayUrlV5`(22 顶层字段全解析)/`getPrivilegeLite`(死) | ✅ 主播放端点齐备（getPlayUrlV5 被 playback_service 实调）；权益批查死端点 |
| 登录 | 5 端点全实现但全「待实测」；YKG 零端点 | ⚠️ 端点齐但未实测；YKG 能力端点层零实现 |
| 下载 | endpoints 目录**无 download 端点**（下载走 audio/db，非本批） | ➖ 端点层无缺口，缺口在上层无入口（bA1_c3） |

---
## 2026-11-16 · 文案泄漏清单（C3 · 端点层面向用户中文）

rg 全量（命令见前文）命中 25 行中文字符串，按是否上屏分级：

### A. 用户可见（应进 i18n，key 落 lib/core/l10n/strings.dart）——10 行 / 2 文件
| 文件:行 | 文案 | 上屏路径 |
|---|---|---|
| `mv_endpoints.dart:141` | '流畅 270P' | MvQuality.label → MV 画质选择 UI |
| `mv_endpoints.dart:142` | '标清 432P' | 同上 |
| `mv_endpoints.dart:143` | '高清 720P' | 同上 |
| `mv_endpoints.dart:144` | '全高清 1080P' | 同上 |
| `mv_endpoints.dart:145` | '超高清 540P' | 同上（命名倒挂） |
| `mv_endpoints.dart:175` | 'MKV 超高清' | 同上 |
| `comment_endpoints.dart:174` | '接口返回非 JSON（可能被安全策略拦截，$msg）' | blockedReason → 评论错误态（含内部黑话+$msg 原始异常） |
| `comment_endpoints.dart:176` | '接口响应异常（$msg）' | 同上 |
| `comment_endpoints.dart:178` | '接口响应异常' | 同上 |
| `comment_endpoints.dart:194` | '歌曲标识无效，无法加载评论' | 同上 |

### B. 内部日志 / 开发者异常（不进 UI，低优先级，可不改）——约 15 行
- `mv_anonymous.dart:128,131,194,198`（待实测 Log）、`recommend_endpoints.dart:59,66,70,74`（UnsupportedError 只读）、`collect_endpoints.dart:140,169,197,203,207`（「我喜欢」Log）、`comment_endpoints.dart:286`（Log）、`misc_endpoints.dart:195`/`search_endpoints.dart:72`（注释）。

结论：端点层用户可见文案泄漏集中在 **MV 画质档位（6）+ 评论 WAF 降级（4）共 10 处**；全仓 i18n 是死代码（bA1_c3），这些 key 一个都没进 strings.dart（20 业务键无 MV 档位/评论错误键）。

---
## 2026-11-16 · MV 端点三态结论（用户点名，单列）

1. **两段式接口正确且齐备**：端点层提供 `getMvBySong(albumAudioId)→MvBrief.hash→getVideoQualities(hash)→MvQuality.hash→getVideoUrl(qualityHash)`（`mv_endpoints.dart:252/301/360`），语义与 bA1_c3 的 A1 结论一致。**端点层无 hash 错配**；错配发生在上层（MV 页把歌曲 hash 当 video_id，见 bA1_c3），不应在本批改端点。
2. **未登录也能看 MV**：端点层**有半成品但不可用**——`mv_anonymous.dart` 的 `anonymousPlayUrl`（/v5/url 试听 + IsFreePart）+ `registerDevice`（取真实 dfid）共 227 行是死代码、标「待实测」、platid 未定稿。VIP 高清链路（getVideoQualities 全档 + getVideoUrl）已实现，但普通档是否需 VIP 由服务端 `priv_status` 决定，端点层已解析（MvPlayResult），无客户端三态判定 UI 提示。
3. **WAF/风控降级**：MV 端点未做（对比评论端点的 blockedReason）——MV 请求失败仅 `Log.e` + 返回空结果，UI 无法区分「被风控拦截 / 需会员 / 真的没有 MV」，与 bA1_c3 的 mv_page 文案黑话问题呼应。
4. 硬编码画质文案 6 处（见文案清单）需 i18n 化 + 修正命名倒挂。

---
## 本视角结论（A3-C3 端点层用户痛点）
1. 实际 26 个 dart 文件全审（任务书称 25），6017 行；逐文件取证完成，无「未覆盖单文件」。
2. **死端点**：`mv_anonymous.dart` 整文件（P0）+ `getPrivilegeLite`/`getSongClimax`/`getUserCloud`/`reportListen`/`uploadPlayHistory`/`fetchTranslation`/`fetchTranslationFromContent` 共 4+2+1 组函数有实现+桥导出但上层零调用，用户触达不到（听歌历史/云盘/上报/权益/翻译网络入口全是空壳）。
3. **待实测冒充可用**：5 个登录端点（auth）+ 匿名 MV 端点，且 `kAuthEndpointsProbed=true` 与 needsProbe 自相矛盾；YKG 全端点目录零实现、零导出/导入雏形（与 bA1_c3 一致）。
4. **MV 端点三态**：两段式接口齐备正确（非 hash 错配源头）；匿名/VIP 三态端点半成品死代码；MV 无评论式 WAF 降级字段。
5. **文案泄漏**：端点层用户可见中文 10 处（MV 档位 6 + 评论错误 4），无 i18n key；档位命名倒挂（540P「超高清」>1080P「全高清」）。
6. **正面样本**：`recommend_endpoints` 的四态结果、`search_typed_endpoints`/`artist_endpoints` 的端点不可达降级、评论 blockedReason 通道，是端点层诚实建模的范例。
7. 五条链路端点能力：搜索/播放齐备；MV 主线齐备但上层错用；登录齐但未实测；下载端点层无缺口（断点在上层无入口）。

## 未覆盖
- 本批严格只读，未验证任何端点的**实际网络可达性**（禁跑 dart/联网）；「端点可用」仅指代码存在+字段容错+上层调用，真实返回以 docs/API_FIELDS_TRUTH.md 实测为准。
- 未审 `lib/core/net/kugou_client.dart` / `endpoint_registry.dart`（属 A2 批），端点声明的路径/签名正确性不在本批。
- 下载/缓存/音频端点不在 `endpoints/` 目录（属 A4 批），「下载链路」仅从端点缺失角度说明。
- 上层（L5 logic/L6 session/L7 surface）的具体修复方案沿用 bA1_c3，本文未重复。

## 76 合规小结
- §0 第 6 条「每端点一 dart 模块 / 多参不缺参 / 只连官方域名」：26 文件基本合规（每域一文件、参数显式、router 均 *.kugou.com）。
- 越级/反向依赖：端点层仅 import `bridge_kernel`(Log) / `kugou_client` / 同级 crypto_* 与 models，未发现 import logic/session/surface，无反向依赖；`ParsedPlayUrlShim`（mv_anonymous.dart:210）是 L4 侧同构镜像但主动声明「不 import L5」，合规。
- 职责越界（本视角重点）：**L4 端点层持有面向用户文案**——MV 画质 label（mv_endpoints.dart:141-145,175）、评论错误串（comment_endpoints.dart:174-178,194），违反「l10n 常量归 L4 core/l10n、端点应纯数据」的归口精神（同属 L4 但落错子域，且 i18n 全仓未接线）。
- 桥导出噪音：bridge_core 导出多个零消费端点（getPrivilegeLite/user 四函数/两 fetchTranslation），属「桥层导出未被消费」，不违反 76 条款但制造死端点假象。
- 影子桥：未发现（端点层无自建桥目录）。
