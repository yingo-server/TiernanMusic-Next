# 批3-C3 上游 MV 证据检查

> 事实更正：指定文件 `module/trackermv.js` 与 `module/mv_url.js` 在仓库中**不存在**（`rg --files` 全树确认）。MV tracker 侧唯一源码是 `module/video_url.js`（x-router `trackermv.kugou.com`，/v2/interface/index），KMR 侧是 `kmr_audio_mv.js` / `video_detail.js` / `video_privilege.js`。以下以实际存在文件为证据。

## 1. 上游源码逐行证据

### video_url.js（= MV tracker /v2/interface/index，全 21 行）
- 参数构造（L4-10）：`backupdomain:1, cmd:123, ext:'mp4', ismp3:0, hash, pid:1, type:1`。
- 请求（L13-19）：GET `/v2/interface/index`，`encryptType:'android'`、`encryptKey:true`、`x-router: trackermv.kugou.com`。**无 notSign、无匿名豁免**；hash 取 `params.hash`。
- 响应解析：本仓库无该端点解析代码；键名 `downurl/backupdownurl/filesize/status/privileges` 来自 field_truth_test.dart L620-649 **实测留样**（data[hash] 桶结构，downurl 单串、backupdownurl 数组）。
- 注意：**源码中没有 domain/r/tag/price_api 等参数**——这些是别处（web tracker）的参数，本仓库 android 链不存在，报告中不作断言。
- 清档位键名不在 video_url.js；`ld/sd/hd/fhd/qhd/qhd_265/mkv_qhd` 档位键实证在 `video_detail.js`（/v1/video，`show_resolution:1`），field_truth_test L600-617 固化 7 档。

### kmr_audio_mv.js（全 20 行）
- POST `/kmr/v1/audio/mv`，`x-router: openapi.kugou.com, KG-TID:38`（L17）；`data=[{album_audio_id}]`（L5），`fields` 透传（L8）。**无签名 key、无 token 要求**（cookie 可空，L15）→ 匿名可用（中，未实测）。

### video_detail.js（/v1/video）
- POST `kmr.service.kugou.com/v1/video`，`data=[{video_id}]`、`show_resolution:1`、`mid`、`uuid=md5(dfid+mid)`、`key=signParamsKey`（时间 md5，非盐 key）→ **匿名可构造**（key 只依赖 clienttime，token 可省）。

### song_url.js 匿名路径（全 52 行）
- L51 `notSign:true`、L50 `encryptKey:true`、L49 `/v5/url` @ trackercdn；L52 cookie 注入 `dfid: randomString(24)`（随机 dfid，无需注册）。
- L32 `IsFreePart: params?.free_part ? 1 : 0` → 试听片段开关（匿名可拿 128 试听）。
- 匿名风险：field_truth_test L403-408 实测匿名 20028 `fail_process:['pkg']`（需 pkg 校验时失败），即匿名不是无条件成功。

## 2. 「只取音频流」真实支持评级

- **ismp3 参数语义**：video_url.js L7 `ismp3:0` 是上行请求参数（声明返回 mp4），把 `ismp3:1` 改为要 mp3 转码档属**推断**——无响应样例或文档佐证。评级：**推断**。
- **路径 A（强）**：`kmr_audio_mv.js` 拿 MV hash → `video_url.js` 拿 downurl mp4（A5-3 实测留样直接验证此链前半），播放 mp4 由播放器解音轨/容器播（need_climax 无关）。此为 MV 完整播放，非"只取音频"，但实测证据最强。
- **路径 B（中）**：`video_detail.js` 7 档 hash（L600-617 实测）→ 对最低档 `ld` hash 打 `/v2/interface/index`，mp4 容器内 AAC 音轨用 ffmpeg/播放器 demux 提取。mp4→音轨可行性是容器常识+有真实 URL 留样，评级：**中**。
- **路径 C（推断）**：`ismp3:1` 或 `ext:'mp3'` 让 tracker 直接返回音频流；无任何源码/留样证据，评级：**推断**。
- 结论：匿名 MV 音频首选 B（有实测 URL 样本），C 仅作探针验证项。

## 3. field_truth_test.dart 受批3 影响的 MV 断言

- L620-659（A5-3 mv play url 组）：downurl/backupdownurl/filesize 断言基于 2026-11-12 留样；若批3 改 `/v2/interface/index` 参数（ismp3/ext）或换 key 算法，`mvKey.playKey 拼接顺序`（L647-655）与盐锚点需同步。
- L600-617（A5-2 fromFlat 7 档）：档位键名若批3 引入 ismp3 档（如新增 `mp3_*` 键）需扩 `MvQuality.fromFlat`。
- L588-596（A5-1 MvBrief）：不受影响（kmr 侧键稳定）。
- 具体：失效风险集中在 **field_truth_test.dart L620-655**；仅当批3 改动 mv_endpoints.dart 的 key/cmd 时 L647-655 必改。

## 4. 匿名设备注册 r_register_dev（register_dev.js，131 行）

- 参数：30+ 设备指纹字段全有默认值（brand=Redmi、device=marble、manufacturer=Xiaomi、imei/uuid=cookie KUGOU_API_GUID、内存/电量/传感器布尔+值，L13-96）。
- 请求：POST `https://userservice.kugou.com/risk/v2/r_register_dev`（L104-105），body= playlistAesEncrypt(dataMap)（L98），query `part:1, platid:1, p`（rsaEncrypt2({aes,uid,token})，L100）；响应 arraybuffer AES 解密（L111-114），`body.status==1` 时 `data.dfid` 写入 cookie（L119-122）。
- **可匿名**：userid 默认 0、token 空。当前 Next 代码缺的步骤：未调用该端点，也未实现 playlistAesEncrypt（明文歌单 AES 同款）+ rsaEncrypt2 的 Dart 移植；song_url 用 randomString 伪 dfid 绕过，存在 20028/pkg 风险。

## 必修 TOP5

1. 建立真实 dfid 链：移植 playlistAesEncrypt/rsaEncrypt2，调 `/risk/v2/r_register_dev` 取 dfid（匿名），替换 song_url 随机 dfid。
2. MV URL key/cmd 锁定：以探针确认 `/v2/interface/index` 匿名缺 key 的响应（40003 Empty key vs 成功），定稿 mv 端点参数。
3. 路径 B 探针先行：kmr_audio_mv → video_detail(ld hash) → video_url → mp4 URL 可播性验证，再接播放器音轨。
4. 探针验证 ismp3:1 / ext:'mp3' 变体（路径 C），证伪则删除该猜测、更新 plan 文档。
5. field_truth_test L620-655 增补匿名 MV 失败形态锚点（对照 playAnon 20028 模式），防批3 改动静默破坏。

## 探针脚本设计（tool/probe_mv_audio.dart，纯 Dart，只打印脱敏字段）

调用序：
1. `POST /kmr/v1/audio/mv`（album_audio_id=32029511）→ 只打印 `data[0][0].video_id` 与 mvhash 长度。
2. `POST /v1/video`（video_id，show_resolution:1）→ 只打印各档 `{ld,sd,hd,fhd,qhd}*_hash` 前 8 位与 filesize，URL 全脱敏。
3. `GET /v2/interface/index`（cmd:123, ext:mp4, ismp3:0）×{无 key, 带 playKey} → 打印 status/errcode/error，downurl 仅打印 host（正则截 `^https?://[^/]+`）与 filesize。
4. 变体：`ismp3:1`、`ext:'mp3'` 重复步骤 3 → 打印响应 Content-Type（HEAD 探测）与 status；mp3→mp4 差异键名如实记录。
5. 失败形态留样（40003/20028/35104）全量键名打印，值脱敏。
脱敏规则：一切 URL 只留 scheme+host；hash 截前 8 位；不含 token/userid/mid 明文；输出 `probe_mv_audio_YYYYMMDD.json` 供 field_truth 收样。
