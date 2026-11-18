> 🗄️ **已归档（2026-11-19）** — 本篇为重写前的规模/契约检查，含 Sp.* 旧控件与「design/ 3 文件」旧清单。
> 权威新文档：[层与桥参考](architecture/LAYERS_AND_BRIDGES.md) ·
> [架构总览 · 诚实现状](architecture/ARCHITECTURE_OVERVIEW.md#诚实现状不是已实现功能请勿当作已交付)。

# 项目完整阅读 · 76 原则合规检查与层级结构分析（2026-11-19）

## 1. 项目规模

| 层 | 目录 | 文件数 | 行数 | 职责（契约） |
|---|---|---|---|---|
| L1 | `lib/init/` | 1 | 161 | main、runBoot 触发、错误页 |
| L2 | `lib/bootloader/` | 2 | 198 | 启动序列、依赖装配 |
| L3 | `lib/kernel/` | 1 | 35 | Log、生命周期 |
| L4 | `lib/core/` | 54 | 13145 | 存储/DB/缓存/网络/音频/算法/l10n |
| L5 | `lib/logic/` | 35 | 6107 | 纯后端逻辑、状态机数据 |
| L6 | `lib/session/` | 9 | 1318 | 编排会话层：播放编排/装配图/模块注册表/导航状态 |
| L7 | `lib/surface/` | 20 | 5457 | 仅 UI 控件与 ThemeData |
| — | `lib/bridges/` | 6 | 717 | 六桥：跨层唯一通道 |

合计 128 个 dart 文件（含 bridges），约 23138 行。

## 2. 权威契约（docs/SEVEN_SIX_RULE.md §0）

七层低→高：init(1) / bootloader(2) / kernel(3) / core(4) / logic(5) / session(6) / surface(7)。
六桥：bridge_boot(1↔2) / bridge_kernel(2↔3) / bridge_core(3↔4) / bridge_logic(4↔5) /
bridge_session(5↔6) / bridge_surface(6↔7)。
方向：surface(7) → session(6) → logic(5) → core(4)，**禁止反向**。
注意：契约 §4/§8 内部有措辞矛盾（"播放编排属 L7 session" / "L6 只有 Widget"），
以 §1 表格与 §0 铁律 8 为准：**session(L6)=编排，surface(L7)=仅控件**。

## 3. 门禁状态（实际运行结果）

- `python3 tool/layer_audit.py` → **PASS strict seven-six（128 文件）**。检查：跨层 import 非桥、
  影子桥、桥函数 try/catch+Log、1500 行、层白名单、regions。
- `dart run tool/smoke_check.dart` → 本地无 dart 跳过（CI 跑）。
- `bottom_bar_gate.py` → PASS（底栏系统层+Flutter层深色双锁门禁）。
- 其它 6 个纯 Dart 契约测试（boot/session/resolve/play/download/feature_reachability）→ CI 全绿历史确认。

## 4. 实际跨层依赖图（脚本从 import 提取）

```
from -> to              count   合规判定
  logic   -> bridges      75    ✅ L5 经桥取 L4（合法）
  core    -> bridges      47    ✅ L4 经 bridge_kernel 取 Log（合法）
  surface -> bridges      39    ✅ L7 经桥取 L6（合法）
  session -> bridges      14    ✅ L6 经桥取 L5/L4（合法）
  bridges -> kernel        6    ✅ bridge_* 取 Log（合法）
  bridges -> session       6    ✅ bridge_surface/session 门面（合法）
  bootloader -> bridges    5    ✅ L2 经 bridge_boot/kernel（合法）
  init    -> bridges       2    ✅ L1 经桥（合法）
  bridges -> surface       2    ⚠️  bridge_surface 装配门面引用 app_root/tn_theme
                                   （契约 §2 定义 bridge_surface 暴露 AppRoot/lightThemeData，
                                    故属登记例外，非违规）
  init    -> bootloader    1    ✅ 契约 §1 明确登记的例外（main → register）
```

**无任何低层 → 高层的反向 import**（core 不 import logic/session/surface；
logic 不 import session/surface；session 不 import surface——全部只在注释中出现这些词）。

## 5. 层级结构与各层明细

### L1 init（1 文件）
- `main.dart`：runApp 入口、path_provider（L1 特例）、runBoot、错误页 `_BootErrorApp`。

### L2 bootloader（2 文件）
- `bootloader.dart`：`Bootstrap.run` 装配 core 单例（client/dao/store/settings/paths）、
  `BootResult(rejected, ...)`、`dbOpenFuture` 透传 main await。
- `register.dart`：installBootBridge。

### L3 kernel（1 文件）
- `kernel.dart`：Log/LogE/LogW/LogD、KernelContext、Kernel.assemble。

### L4 core（54 文件，最大层）
- `net/`（37）：`kugou_client.dart`（统一请求/缓存/单飞）、`signing.dart`（酷狗签名+MD5）、
  `crypto_*.dart`（AES/RSA/BigInt）、`ykg_codec.dart`（YKG 成熟库封装）、`inflight.dart`、
  `endpoint_registry.dart`（53 端点声明）、`endpoints/`（26 个每端点一模块，符合铁律 6）、
  `models*.dart`、`cover_color.dart`、`network_phase.dart`、`database_opener.dart`。
- `storage/`（4）：`settings_store`（单例）、`download_store`（原子索引）、`resource_cache`、`paths`。
- `cache/`（1）：`cache_service.dart`（唯一缓存门面；L1 LRU→L2 磁盘→L3 网络）。
- `audio/`（2）：`audio_gateway`（just_audio）、`notification_gateway`（audio_service）。
- `algorithms/`（2）：`color_extract`、`qr_codec`（纯 Dart）。
- `memory/`（2）：`lru_cache`、`cache_keys`。
- `database/`（3）：`dao`/`db`/`entities`（Isar）。
- `l10n/`（1）：`strings.dart`（TnStrings 56 键×10 语，由 gen_i18n.py 生成）。

### L5 logic（35 文件）
- `auth/`（4）：account/auth/verification/ykg_logic。
- `catalog/`（13）：album/artist/collect/comment/fm/mv/playlist(+write)/rank/recommend/search(+typed)/user。
- `download/`（6）：manager/commit/job/models/paths/song_sync。
- `lyrics/`（3）：lyrics_logic/parser/translation。
- `player/`（9）：playback_service/resolver/source_parser/reducer/state/queue/quality/url_health/history。
- ⚠️ 已知架构债：download 域 4 文件用 `dart:io`/HttpClient 直连 IO（第 6 节详述）。

### L6 session（9 文件）
- `bootstrap.dart`：AppGraph 装配（全部 logic 单例）、模块注册、PlaybackSession/AuthSession attach。
- `graph.dart`：AppGraph（依赖集合纯数据）。
- `module_registry.dart`：模块热插拔（install 覆盖、active 按 navOrder 排序）。
- `playback_session.dart`：播放编排（resolve→engine→历史→通知→MV兜底），ChangeNotifier 快照。
- `theme_controller.dart` / `locale_controller.dart`：主题档位(0-3)/语言码状态。
- `auth_session.dart`：登录态快照 + 监听器。
- `nav_state.dart`：tabRequest/bumpAuth。
- `contracts.dart`：NavEntry/SurfaceModule 纯契约（零 flutter 依赖）。

### L7 surface（20 文件）
- `app_root.dart`：MaterialApp、双 ValueListenableBuilder（theme+locale）、SystemChrome 系统栏锁暗。
- `shell.dart`：Scaffold、body(SafeArea bottom:false + mini bar)、bottomNavigationBar 硬锁深色。
- `design/`（3）：tokens（Sp 令牌+Sp.theme）、components（共享控件）、mini_bar。
- `pages/`（13）：home/home_state_views/library/login_account_section/login_sheet/lyrics/mv/
  player/playlist/search/search_tile_widgets/settings/ykg_sheet。
- `l10n/s.dart`：S.of(context) 取词门面、tr() 无 context 版。
- `theme/tn_theme.dart`：spErrorThemeData（统一走 Sp.theme，消除第二套构造）。

### bridges（6 文件）
- 每桥 try/catch + Log（铁律 2）；无影子桥（铁律 3）。
- bridge_core/bridge_logic 采用"export 白名单"暴露下层门面。
- bridge_surface 引用 app_root/tn_theme 暴露给 L1（契约 §2 明确定义，登记例外）。

## 6. 契约 vs 实际的偏差（诚实登记）

| # | 偏差 | 性质 | 说明 |
|---|---|---|---|
| 1 | L5 download 4 文件 `dart:io`/HttpClient 直连 | **真违规** 铁律「logic 无 IO 直连」 | url_health/download_commit/download_paths/download_manager；历史审查已多次登记，未修 |
| 2 | `bridge_core` export 大量 core 门面给所有上层 | 契约内（§2 "供上层经白名单复用"）但面过宽 | 历史 B1 报过"越权导出"，属设计取舍非硬违规 |
| 3 | L7 `login_sheet.dart` import `dart:convert` | 轻微 | 仅用于 base64 解码二维码，非网络/IO 直连；可在 L4 封装后移除 |
| 4 | 契约 §6 说 L7 "仅占位"（页面全部不建），实际 13 页全建 | 契约已过时 | V2 后期用户要求 UI 独立模型已重写完毕，§6 是历史约定 |
| 5 | `bridge_surface → surface` 反向 import | 登记例外 | 契约 §2 定义 bridge_surface 暴露 AppRoot/theme，必须引用 |

## 7. 结论

- 76 原则**主干健康**：七层六桥齐全、方向正确（零反向依赖）、门禁 PASS、无影子桥、
  端点一文件一模块、1500 行全过、成熟库边界遵守（just_audio/audio_service/cryptography）。
- 主要未清债：①L5 download IO 直连（4 文件）；②i18n 全量接线率≈0%（翻译数据就绪）；
  ③M3 页面级消费已迁移（190 处）但动画体系仍弱。
- 底栏问题已确认真凶在 CI 生成的原生主题（见 docs/ui_diagnosis.md），非 76 层级问题。
