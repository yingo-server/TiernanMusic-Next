# LTS 下一阶段规划书：网络层字段实证 + UI 层 Material Design 3 迁移

> 版本目标：v26.11.13.01 LTS（网络层 + UI 层全量收口后发布）
> 纪律：子代理 60 分钟超时，派发后立即设 50 分钟 steer 定时器；本地只跑 layer_audit + smoke_check，静态分析交 CI；完成前不打扰用户。

---

## 一、网络层：字段真实性实证（不允许猜测字段）

### 1.1 问题定义
当前 `core/net/endpoints/` 的模型映射（SongBrief.fromSearchList 等）部分字段是**从文档/上游模块推断**的，未逐一对照真实返回体。本阶段要求：**每个被映射的字段必须有 probe 实测锚点**。

### 1.2 方法
- 凭据：`/var/minis/workspace/.test_creds/`（cj_vip / cj_nonvip / 匿名），probe.py 模式直连官方域名。
- 每个端点跑三态（匿名/非VIP/VIP），dump 响应 key 树 + item[0] 全字段 → 写入 `docs/API_FIELDS_TRUTH.md`（每端点一节：路径、三态行为、字段名/类型/示例值）。
- 代码侧逐字段核对 `models.dart` + 各 endpoint 封装：字段名对不上 → 改；文档里没有的字段绝不映射。
- 产出回归锚点：`tool/field_truth_test.dart`（纯 Dart，用 API_FIELDS_TRUTH.md 的样例 JSON 断言映射结果），CI 跑。

### 1.3 端点清单（按优先级）
| 批次 | 端点 | 实测状态 |
|---|---|---|
| A1 | search v3/song、search special/lyric/album/author/mv、complex v6 | song 已实测（字段树见下），其余待测 |
| A2 | playlist recommend/detail/tracks、rank list/info | 待测 |
| A3 | play_url v5、privilege_lite、lyric download、krc 解密 | 部分实测（FINDINGS.md） |
| A4 | artist detail/audios/albums、album detail/songs、similar | 待测 |
| A5 | comment list/floor/count、MV detail/quality/url | 待测 |
| A6 | fm play/songs、user detail/cloud/climax/upload/report、collect count、playlist write×5 | 部分实测 |

### 1.4 已实测锚点（search /v3/song，2026-11-12）
```
data.lists[]: FileName/SingerName/OriSongName/OtherName/Suffix/Auxiliary/
  FileHash/FileSize/ExtName/Duration/Bitrate/PublishAge/AlbumID/AlbumName
data: pagesize/page/total/correctiontype/...
```
→ 核对 `SongBrief.fromSearchList` 映射是否全部对得上，不猜。

### 1.5 分批（每批 3 代理，60min 超时 + 50min steer）
- 批N1：A1+A2 探针与字段固化（2 代理探针+写文档，1 代理改 models/回归锚点）
- 批N2：A3+A4
- 批N3：A5+A6 + field_truth_test 全量接线 + CI

## 二、UI 层：Material Design 3 全量迁移

### 2.1 范围
- **移除 miuix**：MiuixApp/MiuixTheme/MiuixScaffold/MiuixThemeData 全量替换为 Flutter 官方 `material 3`（`useMaterial3: true` + `ColorScheme.fromSeed`）。
- **控件规范**：间距走 M3 spacing 4dp 网格；组件用 M3 标准件（AppBar→CenterAligned/TopAppBar、NavigationBar（3dp 高度/80dp 高）、Card（Elevated/Filled/Outlined 三态）、FilledButton/OutlinedButton、Chip 四态、BottomSheet 拖拽把手、SnackBar、Dialog）。
- **动画规范**：M3 emphasized easing（`Easing.emphasizedDecelerate/Standard`）、duration 三档（50/100/150/200/250/300/400/500ms 官方表）、容器变换（openContainer 式）、共享轴转场（页面级）。
- **主题**：ColorScheme.fromSeed(品牌紫) + 亮/暗/纯黑三态；Typography 用 M3 三档（display/headline/title/body/label）。
- **页面清单**：home/search/playlist/player/library/lyrics/settings/comment/mv/album/artist + MiniBar + 错误页（L1）。

### 2.2 分批
- 批M1：主题底座（M3 ColorScheme/Tokens/官方动画表替换 tn_motion/tn_theme）+ app_root 壳 + NavigationBar
- 批M2：home/search/playlist/library 四页控件迁移
- 批M3：player/lyrics/settings/comment/mv/album/artist + MiniBar + 错误页迁移
- 批M4（收口）：miuix 依赖卸载、pubspec 清理、全页对照 M3 规范 checklist、CI

## 三、发布门
- 网络层批 N1-N3 全绿 + field_truth_test 全过 → **先发一版**（v26.11.13.01，网络层 LTS）
- UI 层批 M1-M4 全绿 + miuix 零残留 → v26.11.14.01（M3 LTS）
- 两版均：PASS strict six-five + PASS smoke_check + CI analyze/test/build/release 全绿 + 3 APK + 旧 tag 清理

## 四、风险与约束
- probe 直连偶发 502/404（网关风控抖动）：幂等 GET 重试 1 次，失败的端点如实标注「实测不可达」，**不猜字段**。
- miuix 卸载可能牵动 bridge_surface/layer_audit 白名单（flutter_miuix 在 L1/L6_EXTRA）——同步收敛。
- 全程不打扰用户；两版发完一次性汇报。

## 五、六五原则（贯穿两版，硬约束）

- 六层五桥结构不变：新端点封装只落 core/net/endpoints/；M3 主题/组件只落 surface/theme|widgets|pages；跨层一律经相邻桥。
- 每批任务书开头原文粘贴 docs/SIX_FIVE_RULE.md §0 前缀，不得省略。
- M3 迁移中 layer_audit/smoke_check 白名单同步：flutter_miuix 从 L1/L6_EXTRA 移除；material3 属 package:flutter/* 已在 L6 白名单。
- bridge 函数带 try/catch+Log 的铁律不因迁移放松；新 M3 组件同样 dispose 安全。
- 门禁每批必跑：PASS strict six-five + PASS smoke_check；CI analyze 是字段/类型真伪的唯一裁决。
