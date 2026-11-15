# 批3-C1 · MV 音频流检查（匿名播放主链）

> 只读调研 · 2026-11-15 · 依据 plan_upstream_endpoints_a.md §3/§1、research_field_capture_3state.md、mv_endpoints.dart、endpoint_registry.dart。未实测、未联网。

## 1. 上游源码事实 vs 推断（逐条行号）

### 源码事实
- `video_url.js`（module，plan §4 表）：路径 `/v2/interface/index`，x-router `trackermv.kugou.com`，参数 `backupdomain:1, cmd:123, ext:'mp4', ismp3:0, hash, pid:1, type:1`（L4-19）。
- `kmr_audio_mv.js`：POST `/kmr/v1/audio/mv`，由 `album_audio_id` 换 MV hash（L5-17）。
- `video_privilege.js`：POST `/v1/get_video_privilege`，匿名可传 `token:''`/`userid:0`/`vip:0`（L14-23）。
- `register_dev.js`：POST `/risk/v2/r_register_dev`，可匿名（userid 默认 0），返回 `data.dfid`（L99-113、L119-122，plan §3 表）。
- 本地实测佐证（mv_endpoints.dart:229-236 注释、registry:261-267）：videoUrl 必带 `key=md5(hash+signKeySalt+appid+mid+userid||0)`，缺 key 实测 40003 "Empty key"；成功响应 `data[hash].downurl(串)+backupdownurl(数组)+filesize`。

### 推断（无源码直接证据，需实测）
- 响应键 `downurl`/`backupdownurl`/`svr`/`movietype`/`time`：plan §4 自注「此三键名在 module 源码中未直接出现，属仓库通用键」——推断（plan §4.x 第 1 条）。
- MV 清晰度分档键 `ld`/`sd`/`hd`/`fhd`/`qhd`：来自 `video_detail.js` /v1/video（plan §4 表 L8-30）+ 本地批N2-B 实测 data[0] 平铺（mv_endpoints.dart:103-105 注释、MvQuality.fromFlat:107-142），**不是 trackermv /v2/interface/index 的键**。
- `audio_hash`/`audio_*` 音频档键：plan §4.x 明确「rg 全 module 无命中，行业惯例推断，需实测」。
- `ismp3:1`（或 `ext:'mp3'`）可让 trackermv 直接回音频流：纯推断，源码只有 `ismp3:0` 常量（L4-19），无切换逻辑证据。

## 2. 当前 mv_endpoints 实现与契约错位

- `getVideoQualities`（mv_endpoints.dart:196-224）：body 只传 `{'hash': h}`（L209），而 registry:255-258 自注实测契约是 `clearDefaultParams` 全参 body（`data:[{video_id}], show_resolution:1, key=signParamsKey`）——**请求形态错位**。
- `_parseQualities`（mv_endpoints.dart:226-249）：遍历 `list/files/translations/videos/data` 找档位**数组**，而 /v1/video 实测 data[0] 是**平铺档位**——主路径解析恒空 → 恒走 `videoDetailKmrV2` fallback（registry:259-261）→ 该端点三态实测 404（research §3 表「死代码」）→ **MV 清晰度链路全断**。
- `MvQuality.fromFlat`（mv_endpoints.dart:107-142）：已正确实现平铺 ld/sd/hd/fhd/qhd(+265+mkv_qhd) 抽取，但**生产路径无人调用**——_parseQualities 未接入 fromFlat。
- `getVideoUrl`（mv_endpoints.dart:297-345）：实现正确（cmd=123、key 注入、data[hash].downurl+backupdownurl 去重），契约已对齐；丢弃 privileges（无 MV 权限信号，research §1.5）。
- `getMvBySong`（mv_endpoints.dart:155-194）：hash 靠 `hash??mvhash??video_hash` 三兜底，MV 项本身无 hash，A5-2 档位 hash 与此未打通（research §1.5）。

## 3. 匿名播放链缺什么

- **设备注册未接**：registry 无 `registerDev` 声明（/risk/v2/r_register_dev 全文无出现，仅 plan §3 表记录）；KugouClient 匿名态用随机 dfid（plan §1 song_url L51 注入随机 dfid）。**缺 r_register_dev → 无稳定 dfid**，匿名 play_url 20028（需 dfid 参与的风控失败态）没有根治路径。
- **判定顺序应在 L5 playback_service**（research §4.7 已映射 20028/31833 于 playback_service.dart:155-175）：匿名失败先判 error_code（20028=风控/缺 dfid → 触发设备注册重试；31833=匿名不可播 → 走 MV 音频兜底；35104 → noPrivilege 单列）。L6 session 只做编排（选匿名/登录态、决定是否走 MV 兜底链），不做错误码语义判定——符合「L4 端点/封装、L6 编排、L7 画控件」分层。
- MV 音频兜底判定链应在 L5：`play_url 20028/31833 → getMvBySong(album_audio_id) → getVideoQualities(video_id) → getVideoUrl(最低档 hash) → 提取/直播音轨`。

## 4. 最低清晰度取音频流：候选路径（证据强度标注）

- **A. trackermv downurl 直接播**（ismp3 参数试验 / mp4 容器直接喂播放器）：中。videoUrl 链路本身已实测可用（mv_endpoints.dart:297-345 + registry:261-267）；但「mp4 含独立音轨、播放器可解」是推断，需实测。**改动最小，首选验证**。
- **B. /v5/url 匿名试听 IsFreePart**：强。song_url.js 源码明确 `IsFreePart` 参数 + notSign + 随机 dfid（plan §1 L15-38、L48-51），匿名可构造；局限是试听 60s（hash_offset）且 VIP 曲目非全长。作为「匿名可播」主路径而非 MV 兜底。
- **C. MV mp4 转 m3u8 音轨**：弱。纯客户端转封装方案，无任何上游源码证据，依赖 ffmpeg/HLS 服务，移动端成本高。仅作 A 失败后研究项。

## 必修 TOP5
1. getVideoQualities body 改 A5-2 实测契约（data:[{video_id}], show_resolution:1, clearDefaultParams 全参+key），_parseQualities 接入 MvQuality.fromFlat（mv_endpoints.dart:196-249）。
2. 删除 videoDetailKmrV2 死代码 fallback（mv_endpoints.dart:214-218、registry:259-261），失败显式错误态。
3. registry 增加 registerDev（/risk/v2/r_register_dev）声明+封装，L5 在匿名 20028 时注册取 dfid 重试。
4. getMvBySong hash 兜底打通歌曲侧 mvdata[].hash（research §1.2：搜索项 mvdata 被丢弃，需补捕获）。
5. L5 playback_service 匿名判定顺序固化：20028→注册重试；31833→MV 音频兜底；35104→noPrivilege 单列（对齐 research §4.7/§5.2）。

## 匿名播放链推荐实现顺序
1. B：/v5/url 匿名 + IsFreePart 试听（源码证据最强，先保证「能出声」）。
2. 3：r_register_dev 拿稳定 dfid，根治 20028。
3. A：MV 最低档（ld）downurl 直接播验证 mp4 音轨可用性。
4. 若 A 成立，接 MV 音频兜底入 L5 判定链；C 仅作远期备选。
