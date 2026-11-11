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
- 每项延迟 = `index * step`，默认步长 **30ms**。
- 封顶 **6 项**：index ≥ 6 与 index = 5 同步，长列表尾部不再等待。
- controller 在 dispose 释放；初始化失败 Log 留痕并直接渲染子内容（不静默吞）。

用法：
```dart
TnMotionStaggered(index: i, child: ListTile(...))
```
首页四区块已全部接线（批11-A 动态第一屏，commit 872de34）：
「每日推荐」index 从 0 起；「榜单速览」+2、「热搜词」+3、「推荐歌单」+4
整体错开基准，首屏自上而下按区块依次入场，互不争抢。

## 3. 页面转场 —— TnPageRoute

- `Navigator.push(context, TnPageRoute(page))`。
- fade + 轻微上滑（`Offset(0, 0.04)`），时长 `TnMotion.normal`（250ms），
  返回时 `TnMotion.fast`（150ms），曲线 easeOutCubic。
- 转场构建失败 Log 留痕并回退为无动画直出，不阻塞导航。
- 已接线：MiniBar 展开播放页（player_page.dart `_defaultExpand`）。

## 4. 点按反馈 —— TnPressable

- `TnPressable(child: ..., onTap: ...)`：按下缩至 0.96，松开回弹，
  时长 `TnMotion.fast`，AnimatedScale 实现。
- 已接线：播放页大封面（240×240 CoverImage）。

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
