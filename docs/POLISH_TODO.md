# 规范性收尾待办（批10 后）


> 主会话独立盘点，2026-11-11。三项规范性的收口状态与剩余项。

## 已完成
- 六五：五桥齐全、跨层非桥 import=0、显式层-桥白名单、bridge_core/logic 各 3 个带捕获桥函数、§0 未动。
- UI：TnDims/TnColors 设计令牌；home/player/search/settings/common_widgets 收敛 24 padding + 8 圆角 + 2 颜色；search_page 裸 AppBar → TnAppBar。
- 动画：tn_motion.dart（Staggered/PageRoute/Pressable，dispose 安全）、ANIMATION_SPEC.md、player/home 接线。

## 剩余（等 CI 43050367587 结论后统一处理，避免与在跑 CI 撞车）
1. 五页硬编码收敛（共 17 处 EdgeInsets + 1 处圆角），当前仅 TODO 注释：
   - album_page.dart：EdgeInsets 3、BorderRadius.circular(数字) 1
   - artist_page.dart：EdgeInsets 3
   - comment_page.dart：EdgeInsets 9
   - mv_page.dart：0（已合规）
   - playlist_page.dart：EdgeInsets 2
   处理：替换为 tnPadS/M/L / TnDims.padXS/padXL / tnRadiusS，补 `import '../theme/tn_theme.dart';`，不改文案/签名/回调。
2. 全仓剩余硬编码颜色 `Color(0x…)` 17 处（多数在 tn_theme.dart 定义常量处，属合规；页面内若还有则收敛到 TnColors）。
3. 动画：home_page 仅「每日推荐」区块接 TnMotionStaggered；其余三区块与歌词页滚动可同法套用（可选增强，非硬缺口）。
   → **已完成（批11-A 动态第一屏，commit 872de34）**：home_page 四区块全部接线
   （每日推荐 index=0 起 / 榜单速览 +2 / 热搜词 +3 / 推荐歌单 +4，区块间基准错开）；
   歌词页滚动增强仍未做。
4. **已完成（批11-B 着色器编译调度）**：`lib/surface/theme/tn_shader_warmup.dart`
   —— AppRoot initState 首帧后空闲窗口用 PictureRecorder 离屏预编译三类常用材质
   （品牌紫渐变 / 圆角矩形 / 圆形头像）的 SkSL，消除首次出现该材质时的 raster
   端编译 jank。幂等（_scheduled/_done 双闸）、失败仅 Log 留痕由运行期自然编译兜底、
   资源逐项 try 释放。非动效组件，无 AnimationController / 裸动效时长。

## 纪律
- 本地只跑 layer_audit + smoke_check（包无关）；静态分析交 CI（包齐全、不过滤）。
- 每次改动只推一次、CI 只跑一次；报错到时取结果、只修工作区等确认。
