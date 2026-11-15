# API 返回字段捕获 / 三态 / 最大权益 URL 调研报告

> 只读调研 · 2026-11-15 · 依据 docs/API_FIELDS_TRUTH.md（A1–A6、R1-A）、docs/API_TEST_REPORT.md、docs/API_CONTRACT_MATRIX.md、lib/core/net/endpoints/* 与 lib/logic/player/playback_service.dart。

## 1. 字段捕获矩阵（端点 → 实测键 → 代码取的字段 → 被丢弃的字段）

### 1.1 play_url v5（play_endpoints.dart:57–140，play_models.dart PlayResult）

实测成功响应顶层 22 键：`url[]、backupUrl[]、bitRate、extName、timeLength(s)、status、priv_status、hash、std_hash、std_hash_time、fileHead、fileName、fileSize、hash_token、hash_token_query、q、volume、volume_gain、volume_peak、classmap、tracker_through{musicpack_advance}、trans_param{qualitymap,ogg_*,union_cover,hash_offset,...}、auth_through[]`；失败态另有 `fail_process:[pkg]`、`hash_offset`(试听 clip_hash/offset_hash/end_ms=60000)、`error_code`(35104)。

**已捕获**（play_endpoints.dart:95–135）：status、priv_status（含 privKnown 判缺）、errcode（含 error_code 兜底，play_endpoints.dart:111）、error、url[]、backupUrl[]、bitRate、extName、timeLength、tracker_through.musicpack_advance→isVipTrack。✅ 覆盖良好。

**丢弃/未捕获（文件:行）**：
- `q`（实际返回档位）— play_endpoints.dart 无读取，恒以请求 quality 回填 PlaySource（playback_service.dart:122 `quality: quality`），服务端降档（quality_degradable）不可感知。
- `fileSize / fileName / fileHead / std_hash / std_hash_time / hash_token / hash_token_query` — 全丢（仅 A3-1 留样）。
- `volume / volume_gain / volume_peak`（响度均衡）— 全丢，播放器未做 gain 补偿。
- `classmap / trans_param.qualitymap / auth_through[]`（可用档位图，是「最大权益 URL」决策的关键输入）— 丢弃。
- `hash_offset`（试听 clip_hash/start_ms/end_ms）— 丢弃；试听判定只靠请求侧 IsFreePart 标志（play_endpoints.dart:131 透传入参），未以返回 timeLength/hash_offset 实测为准（A3-1 ⚠️：IsFreePart=1 VIP 号仍回全长）。
- `fail_process`（失败处置码，pkg/12 等语义）— 丢弃，仅匿名态含此键时被忽略。
- `is_hash_backup`、`priv_status` 与 `backupUrl` 的关联（备链是否低权益）— 未记录。
- flac 档 `bitRate=0`（实测恒 0，不可用 bitrate 判档，A3-1 ⚠️）— 代码无此防御，若用 bitrate 判档会误判。

### 1.2 搜索 /v3/search/song（search_endpoints.dart:17–41，models.dart SongBrief.fromSearchList）

item 57 键。**已捕获**：FileName/SingerName/FileHash/FileSize/ExtName/Duration/Bitrate/AlbumID/AlbumName/MixSongID/Audioid(三级兜底)/Image/AlbumImage/Singers/HQ/SQ/Res/trans_param.musicpack_advance/isVip。**丢弃**：OriSongName、OtherName、Suffix、Auxiliary、PublishAge、PublishDate、TagContent、RankId、Accompany、HeatLevel、PayType、FailProcess、IsOriginal、mvdata[]（歌曲侧 MV 入口，MV 页另查接口浪费一次请求）、trans_param.ogg_*(ogg 直链 hash)、hash_offset、bitflag、Grp、Scid、correctiontype。代价最大的是 `mvdata[].hash` 与 `HQ/SQ/Res` 档位 hash 的丢弃（后者本可免一次 privilege 查询做音质预判）。

### 1.3 评论（comment_endpoints.dart）

- 实测项键：`id/content/addtime(格式化字符串)/reply_num/like{count,haslike,likenum}/user_name/user_pic/user_id`。
- like.count ✅ 已取（comment_endpoints.dart:62–65）；**丢弃**：haslike、likenum、reply_num（楼中楼数）、addtime（字符串不解析→timeMs 恒 0）、user_id、hot_word_list[].count。
- 楼层键 `tid`：getCommentFloor 已按实测 `tid` 传参（comment_endpoints.dart:170–176），但 childrenid/mixsongid 口径待实测，恒随传；CommentItem.floor 的 floo/floor 键**无实测章节**，恒 0。
- comment_count：顶层以 hash 键取值 ✅（comment_endpoints.dart:226–229），mixsongid 形参保留但实测恒 0。

### 1.4 收藏回执（collect_endpoints.dart:126–160，playlist_write_endpoints.dart:180–200）

- 加歌回执 `data.info[]`：fileid/number/hash/name/audio_id/cover/singerinfo[]/tagmap/language/task/fsort/sort/csong/bpm_type/ipmap —— 代码只取 `fileid`（audio_id 兜底，collect_endpoints.dart:140–150），**丢弃** name/cover/hash 回显（可用于本地镜像校验）。
- 收藏计数 `/count/v1/audio/mget_collect`：实测 `data.list[]{mixsongid,count,count_text}`，getFavoriteCount 求和 ✅（collect_endpoints.dart:225–243）；丢弃 mixsongid 级别的 per-song 收藏态（可判断「是否已收藏」而无需查歌单）。
- `list_ver`：detail 取了（playlist_endpoints.dart:198）、写端点默认传 0（addSongsToPlaylist listVer 参数默认 0），**实际并发编辑/幂等保护未用实测递增的 list_ver**。

### 1.5 MV 域（mv_endpoints.dart）

- getMvBySong（/kmr/v1/audio/mv，data[0][] 嵌套，27 键）：MvBrief 只取 video_id→hash 兜底、mv_name、singername、duration(ms)、hdpic/thumb（mv_endpoints.dart:40–63）。**丢弃**：hit/hot/play_times/download_total/collection_total、is_recommend/is_ugc、publish_time、desc/other_desc/remark、user_*、have_mp4、audio_id/album_audio_id/songid。MV 项本身无 hash——hash 需从歌曲侧 mvdata[].hash 或 A5-2 档位取，当前仅靠 `m['hash'] ?? mvhash ?? video_hash` 三兜底（mv_endpoints.dart:47），**A5-2 videoDetail 的档位 hash 与 getMvBySong 未打通**（getVideoQualities 的请求 body 是 `{hash}`，实测契约应是 `data:[{video_id}]`+show_resolution=1，见 §4.4）。
- videoDetail 平铺 88 键：MvQuality.fromFlat 抽 ld/sd/hd/fhd/qhd（含 *_265、mkv_qhd）的 hash/filesize ✅；**丢弃** bitrate/width/height（每档 `{tier}_bitrate/_width/_height`）、audio_hash/audio_*、video_name、thumb_mp4/thumb_hd_mp4、track、classification[]、authors[]、heat/play_times。
- videoUrl（/v2/interface/index）：data[hash].downurl + backupdownurl ✅ 去重（mv_endpoints.dart:318–340）；丢弃 privileges{hash:0/1}（**MV 无权限信号被丢弃**）、filesize。

### 1.6 其余端点要点
- 歌单 tracks（nofilt，41 键）：丢弃 mvdata/mvhash/mvtrack、bpm、feetype、level、heat、collecttime、has_obbligato、trans_param、fileid（fileid 丢了导致「从歌单删歌」只能退回 album_audio_id 口径）。
- rank_audio：丢弃 user_download、video_info、copyright、musical、remarks、is_publish。
- 歌词 candidates 27 键：丢弃 product_from/hitlayer（官方 vs UGC 源标识）、nickname、language、krctype、parinfo；id 为字符串但 lyricSearch 用 safeInt（misc_endpoints.dart:128）——大 id 有溢出风险，建议 safeStr 透传。
- userDetail：丢弃 follows/fans/constellation/p_grade/birthday/city 等 30+ 键；userid/level 响应无此键已如实处理。

## 2. 三态登录态

留样覆盖（API_TEST_REPORT 三态矩阵 + api_samples/{anonymous,nonvip,vip}.json）：
- **完整三态留样**：play_url_v5（anon=0/31833 或 20028、nonvip=2/priv 0、vip=1/priv 1/urls=2）、search_song、search_suggest、search_hot、rank_list、user_detail、favorite_count、song_climax、user_cloud、fm_play、daily_recommend。
- **仅 vip 态留样**：comment_music、comment_count、mv_by_song、album_detail。
- **三态实测但有独立章节**：歌词（A3-2，匿名=非VIP=VIP 均 200，匿名命中 UGC 轨/VIP 命中官方轨）、privilege_lite（A3-2：privilege 三态同值=10，不用于权限判定）、歌单写（A6/R1-A-4/5）、rank_audio（R1-A-6 匿名可用）、searchSuggest（R1-A-8）、QR 登录。
- **三态下失败被吞成空的端点**（风险点）：
  - `daily_recommend`：匿名 errcode=200103、data 为字符串——recommend_endpoints.dart:107 已显式 loginRequired ✅，但 API_TEST_REPORT 三态 items 全为 0，登录态样本本身也是空，端点疑似不可用，需复测。
  - `fm_play`（/v1/fm/play）：三态 items=0；fm_endpoints 的真实可用口径是 /v2/personal_recommend（registry personalFm 声明的是 /v1/fm/play，两者路径不一致，见 §3）。
  - `user_cloud`、`song_climax`、`favorite_count`：三态全空/0，user_endpoints.dart:246–300 不设成功门槛容错返回空——「失败=空列表」与「真的没数据」不可区分（无 blockedReason 机制，只有评论域有）。
  - 匿名写端点（add_list/add_song/delete_songs/user_playlists）=20010：getUserPlaylists 匿名返回空列表（playlist_write_endpoints.dart:305），上层无法区分「没歌单」与「未登录」。

**「按登录态选权益最大 URL」机制：不存在。**
- getPlayUrlV5 请求只带单个 quality（调用方指定的 preferQuality），无降级重试：playback_service.dart:97 失败直接返回 error，不尝试 320→128、不尝试 IsFreePart 试听、不读 trans_param.qualitymap/tracker_through.all_quality_free 判断可降档。
- URL 选择恒 `urls[0]`：playback_service.dart:121 `urls: pr.urls` 主链即第一条；backupUrls 仅透传给 PlaySource，无切换/健康检查逻辑。
- 响应侧无 `q` 捕获（§1.1），服务端实际给的档位是否=请求档位不可知。
- privilege_lite 结果未接入任何决策路径（仅 Log，play_endpoints.dart:180）。
- 结论：**当前恒取 urls.first + 单一请求 quality，无权益最大化机制**。可用的决策输入（status/priv_status、tracker_through.musicpack_advance、trans_param.qualitymap、hash_offset 试听、backupUrl、q）大多已捕获或留样但未消费。

## 3. 未接入端点（registry 声明 vs 实际消费）

registry 共 50 个端点声明。声明了但 L4 端点封装/L5/L7 完全无消费或形同虚设：

| 端点 | 状态 |
|---|---|
| `videoDetailKmrV2`（/kmr/v2/videos） | 仅作 getVideoQualities fallback；R1-A-7 实测三态 404，**永远命中不了，死代码** |
| `fmSongs`（/v1/fm/songs） | registry 声明「待实测不猜参数」；fm_endpoints.getFmSongs 用的是注释里另一路径（app_song_list_offset 口径）但请求走该声明，契约未留样 |
| `personalFm` 声明路径 /v1/fm/play | API_TEST_REPORT 显示 /v1/fm/play 三态 items=0；fm_endpoints 注释声称真实路径是 /v2/personal_recommend + x-router persnfm——**registry 与实际契约不一致** |
| `loginToken`（/v5/login_by_token） | **无任何封装函数/消费**（auth_endpoints.dart 无引用） |
| `smsLogin` / `sendSmsCode` | 封装存在（auth_endpoints.dart:73/104）但「未三态实测」注释与 kAuthEndpointsProbed=true 矛盾；UI 无短信登录入口 |
| `songClimax` | 有封装（user_endpoints.dart:216）但三态 hasResult=False，无契约留样 |
| `userCloud` | 有封装但三态 items=0；CONTRACT_MATRIX 标注真实路径是 /v1/get_list + mcloudservice + AES 解密，与 registry /v1/user_cloud 不一致 |
| `playHistoryUpload` | 封装✅实测✅（R1-A-2），但无 L5 定时上报接线（仅端点层） |
| `listenReport` | 封装✅实测✅，且语义是「获取收听列表」非上报——无 UI 消费 |
| `playlistSimilar` | 封装✅（album_endpoints.getSimilarPlaylists）双形态容错，UI 相似歌单入口无消费（GAP #24 待接） |
| `collectSong` / `cancelCollect`（/v2/collect、/v2/cancel_collect） | **上游无此端点**，registry 自注「本地镜像实现为准」；真实收藏走 cloudlist /v6/add_song（collect_endpoints 已接线）——两条死声明 |
| `favoriteCount` | 有封装但「待实测」注释；三态 count=0，字段契约无 API_FIELDS_TRUTH 章节 |
| `searchComplex`（/v6/search/complex） | 实测不可达 152；searchComplexV6 已降级为 v3/song 薄委托（search_typed_endpoints.dart:114） |
| `artistAlbums`（/v1/author/albums） | 实测 502/403，无消费，走 albumDetail 降级 |
| `commentCount` 的 mixsongid 口径、`playlistTags` | tags 有消费；comment_count 需 FileHash，mixsongid 形参恒无效 |
| MV `search_mv`（/v1/search/mv） | searchTyped 支持 type=mv，但 MvBrief 模型缺位（A1-5 键集固化于文档，无模型）——MV 搜索链路实际不可用 |
| 登录态 QR | loginQrKey/loginQrCheck 已实测并修复（data.status==4），已接线 ✅ |

**特别标注**：MV（模型缺位+档位接口契约错位）、登录（smsLogin 未实测、loginToken 无封装）、FM（registry 路径与真实契约不一致、三态空样本）、云盘（路径不一致+AES 契约未实现）、高潮（三态空、无留样）、评论写（无任何点赞/发评论端点声明，纯缺失）、收藏写（/v2/collect 死声明，真契约已走歌单）。

## 4. 成功/失败语义问题点

1. **playlist_write_endpoints.dart:19 `_ok()`「失败被当成功」**：`if (s == 1 || s == 0) return true` —— status=0（明确失败，如 20010 需登录时顶层 status=0）被当成功；error_code 缺失时 safeInt 缺省 -1→s=-1→又靠注释「按成功容错」。写操作据此判 ok 是高危。
2. **空结果落缓存**：recommend 的 cacheable 包含 `empty` 态（recommend_endpoints.dart:63），空推荐会落缓存；其余端点（search/fm/playlistTracks）失败返回空后是否落缓存取决于 L2/L5 缓存层未在此检查——`searchTyped` 失败返回空 SearchResult，若 logic 层按 (type+page) 键缓存则会固化空页。
3. **lyricSearch 状态语义**：status=200 才成功 ✅（misc_endpoints.dart:116），但 status 缺失时 `safeInt(res['status'], safeInt(res['errcode'], -1))`，errcode=200（成功态之一）时若 status 缺失则误判 ok=200——恰好侥幸正确，属巧合非设计。
4. **getVideoQualities 契约错位**（mv_endpoints.dart:236–252）：body 只传 `{hash}`，而 A5-2 实测契约是 clearDefaultParams + 全参 body `data:[{video_id}], show_resolution:1, key=...`；`_parseQualities` 找 `list/files/translations/videos` 数组，而实测 data[0] 是**平铺档位**——主路径解析恒空 → 恒走 kmr/v2/videos fallback（404）→ **MV 清晰度链路实际全断**，MvQuality.fromFlat 在生产路径无人喂入。
5. **userPlaylists/_ok 同款**：匿名 20010 时 data 为字符串/缺失，dataOf 返回空 → items 空，与「没歌单」不可区分。
6. **comment WAF**：KugouApiException(-3) 已归一 blockedReason ✅（唯一做对的诚实化样板），但 getCommentFloor/getCommentCount catch 仍返回空且无 reason（comment_endpoints.dart:187/237）。
7. **getPlayUrlV5 匿名态**：status=0/errcode=20028 或 31833 均正确映射（playback_service.dart:155–175），privKnown 防误判 ✅；但 `_mapError` 里 `pr.urls.isEmpty && pr.isVipTrack → noPrivilege` 兜底在 nonvip 带 key 态（error_code=35104）会落 notFound（35104 未单列），与 A3-1「非VIP 失败形态=35104」不符——35104 应映射 noPrivilege 而非 notFound。

## 5. 必修 TOP10（均可离线修复）

1. **playback_service / play_endpoints**：增加降档重试链（请求 quality 失败 → 320→128→IsFreePart 试听），以 trans_param.qualitymap + tracker_through.all_quality_free 为前置判断；捕获 `q` 字段回填 PlaySource.quality（play_endpoints.dart:95–135、playback_service.dart:90–127）。
2. **playback_service.dart:172**：`error_code=35104`（非VIP Hash not found）单列映射 noPrivilege，防止被 notFound 误导重试。
3. **playlist_write_endpoints.dart:19 `_ok()`**：删除 `s==0` 分支，改为 `s==1 || (s==-1 && error_code==0)`，写操作禁止把 status=0 当成功。
4. **mv_endpoints.getVideoQualities**：body 改为 A5-2 实测契约（data:[{video_id}], show_resolution:1, clearDefaultParams 全参 + key），解析改 MvQuality.fromFlat(data[0])；打通 getMvBySong(video_id) → getVideoQualities(video_id) → getVideoUrl(hash) 链。
5. **mv_endpoints / registry**：删除 videoDetailKmrV2 fallback（实测三态 404 死代码）；MV 主路径失败显式返回错误态而非静默空数组。
6. **registry vs fm_endpoints**：personalFm 路径对齐真实契约（/v2/personal_recommend + x-router persnfm），fmSongs 契约探针后固化；userCloud 同理（/v1/get_list + mcloudservice + AES）。
7. **collect/playlist**：歌单 tracks 解析补 `fileid` 捕获（SongBrief 增字段或旁路表），取消收藏不再依赖 album_audio_id 猜测；addSongsToPlaylist 传实测递增 list_ver 做乐观并发。
8. **comment_endpoints**：getCommentFloor/getCommentCount 补 blockedReason 机制（对齐 getMusicComments）；CommentItem 补 reply_num/haslike/addtime 解析（字符串日期存原文）。
9. **misc_endpoints.dart:128**：lyricSearch/lyricDownload 的 id 改 safeStr 透传（实测字符串 id，safeInt 大数溢出风险）；candidates.product_from/hitlayer 捕获用于「官方歌词优先」排序。
10. **user_endpoints/favorite_count**：getFavoriteCount/getSongClimax/getUserCloud 增加「未留样契约」显式 blockedReason/state，禁止三态空样本被当「真的没数据」；recommend empty 态移出 cacheable（recommend_endpoints.dart:63）。

## 6. 结论

字段捕获总体质量高（play_url 关键权限键、收藏 fileid、评论 like.count/tid 均已接），但**「最大权益 URL」机制不存在**（恒 urls.first + 单 quality，无降档/试听/备链切换），MV 档位链路因契约错位实际全断，`_ok()` 的 status=0 判成功是写操作最高危点，registry 有 6+ 条死声明/契约不一致待清。
