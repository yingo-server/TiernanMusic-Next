# TiernanMusic-Next 动效规范（批10-C）

统一动效常量与组件，杜绝散落的裸 `Duration(milliseconds:)` 与无编排动画。

## 1. 三档时长与曲线

来源：`lib/surface/theme/tn_theme.dart` 的 `TnMotion`。

| 档位 | 时长 | 曲线 | 用途 |
|---|---|---|---|
| fast | 150ms | easeOutCubic | 点按反馈、缩放、开关 |
| normal | 250ms | easeOutCubic | 页面转场、列表入场、滚动定位 |
| slow | 350ms | easeOutCubic | 大封面/大区块过渡 |

曲线全局唯一：`TnMotion.curve = Curves.easeOutCubic`，不得自造曲线。

规格封装：`lib/surface/theme/tn_motion.dart` 的 `TnMotionSpec.fast / normal / slow`。

## 2. 列表项交错入场 —— TnMotionStaggered

- Fade + Slide（自下 12px 上移，即 `Offset(0, 0.06)`）。
- 每项延迟 = `index * step`，默认步长 **50ms**（M3 `Durations.short1`，批M1 由 30ms 迁移）。
- 封顶 **6 项**：index ≥ 6 与 index = 5 同步，长列表尾部不再等待。
- controller 在 dispose 释放；初始化失败 Log 留痕并直接渲染子内容（不静默吞）。
- 首帧后常用材质的 raster 端 SkSL 预编译由 `TnShaderWarmup`（批11-B，
  `tn_shader_warmup.dart`）在 AppRoot initState 调度，与本组件库互补：
  本组件消除「首次入场动画」编译开销，TnShaderWarmup 消除「渐变/圆角/圆形
  材质首绘」编译开销，两者共同保证动态第一屏全程无 GPU 编译 jank。

用法：
```dart
TnMotionStaggered(index: i, child: ListTile(...))
```
首页四区块已全部接线（批11-A 动态第一屏，commit 872de34）：
「每日推荐」index 从 0 起；「榜单速览」+2、「热搜词」+3、「推荐歌单」+4
整体错开基准，首屏自上而下按区块依次入场，互不争抢。

## 3. 页面转场 —— TnPageRoute

- `Navigator.push(context, TnPageRoute(page))`。
- fade + 轻微缩放（共享轴 Z：0.92→1.0），入场 `Durations.medium1`（250ms）、
  出场 `Durations.short3`（150ms），曲线 emphasizedDecelerate/Accelerate（M3 官方）。
- 转场构建失败 Log 留痕并回退为无动画直出，不阻塞导航。
- 已接线（批R2-B 全量统一 push 转场）：MiniBar 展开播放页（mini_bar.dart
  `_defaultExpand`）；歌单页 tracks/本地镜像（playlist_page.dart）；评论页楼中楼
  （comment_page.dart `_openFloor`）；歌手页→专辑页（assembly.dart onOpenAlbum）。
  项目内不再存在裸 `MaterialPageRoute` push。

## 4. 点按反馈 —— TnPressable

- `TnPressable(child: ..., onTap: ...)`：按下缩至 0.96，松开回弹，
  时长 `Durations.short3`（150ms）+ `Easing.standard`，AnimatedScale 实现。
- 已接线：播放页大封面（240×240 CoverImage）+ 播放页倍速徽标（player_page.dart）。

## 5. 纪律（两条硬约束）

1. **禁止无 dispose 的 AnimationController**：凡创建 controller，
   State.dispose 必须释放；组件封装已内置，散写 controller 同样遵守。
2. **禁止裸 `Duration(milliseconds:)` 用于动效**：动效一律取
   `TnMotion.fast / normal / slow`；确需非三档自定义时长（如轮询、防抖），
   保留裸值但必须注释说明为何不属动效范畴。

## 6. 落地约束

- 新组件仅存在于 `lib/surface/theme/tn_motion.dart`（≤200 行），
  Log 经 bridge_logic 合法跨层，业务逻辑/签名零改动。
- 非 surface 层不得引用本组件库。

## 7. 批R2-B 审查补充（动画规范一致性）

### 7.1 交错入场 index 基准（0/+2/+3/+4 区块错开模式）

| 页面 / 区块 | index 基准 | 说明 |
|---|---|---|
| home 每日推荐 / 榜单 / 热搜 / 推荐歌单 | 0 / +2 / +3 / +4 | 原有，保留 |
| search 结果列表 | 0 | 单区块页从 0 起 |
| playlist 推荐网格 / 本地镜像列表 | 0 / 0 | 两 tab 独立入场，互不同屏 |
| playlist tracks 页歌曲列表 | 0（SongTile 自带序号） | 二级页单区块 |
| artist 热门歌曲 / 专辑 tab | 0 / +4 | 两 tab 错开基准 |
| album 歌曲列表 / 相似歌单横滑 | 0 / +4 | 区块错开 |
| library 本地曲库 / 最近播放 tab | 0 / 0 | tab 独立入场 |
| comment 热词区后评论流 | +2 | 热词 chips 无动画，评论 +2 衔接 |
| player / lyrics / settings / mv | 不适用 | 非长列表页，无列表入场 |
| MiniBar | 不适用 | 常驻悬浮条，不做入场动画 |

### 7.2 点按反馈边界（防双重反馈）

TnPressable 只用于「可点但无 InkWell ripple」的元素；已有 InkWell/ListTile
ripple 的元素不再叠加 TnPressable。播放页倍速徽标（无 ripple）用 TnPressable；
大封面（无 ripple）用 TnPressable；MV 封面、各列表 tile 走 InkWell ripple，不叠加。

### 7.3 加载态统一（M3 规范：页面级 Linear、局部 Circular）

- 页面/tab 级首屏加载：`LinearProgressIndicator(minHeight: 2)` ——
  专辑页（原 Circular 已改）、曲库本地/最近 tab（原 Circular 已改）；
  search/home/artist 页顶已是 Linear，保持。
- 局部加载（列表尾部分页 loading、按钮内、局部区块）：CircularProgressIndicator
  —— playlist 网格尾项、tracks 尾项、artist 列表尾项、comment 加载尾项、
  mv 封面中心、common.dart `loadPlaceholder`（局部占位语义），保持 Circular。

### 7.4 dispose 审查结论（批R2-B）

全部 StatefulWidget 核对：AnimationController 仅存在于 tn_motion.dart（内置
dispose）；Timer.periodic 三处（lyrics_page 200ms 轮询 / settings_qr_dialog 1.5s
轮询 / player_controller 1s ticker）均在 dispose cancel；ScrollController、
TabController、listener、StreamSubscription 均已 dispose/cancel。零泄漏，无修复项。
