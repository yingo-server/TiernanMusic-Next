# M3 全量迁移执行计划（UI 层第二任务）

> 严格六五原则；每页按 Google Material Design 3 官方控件/间距/动效规范；完成后发布 v26.11.14.01 M3 LTS。不通知用户直到两任务全完成。

## 底座（M1）
- `tn_theme.dart`：去 MiuixThemeData，改 `ColorScheme.fromSeed(seedColor: 品牌紫)` + M3 Typography（display/headline/title/body/label）；亮/暗/纯黑三态。
- `tn_motion.dart`：时长改 Google M3 官方表（short 100 / medium 200 / long 300 / extra-long 500；easing emphasizedDecelerate/Standard），页面转场共享轴、容器变换。
- `tn_app_bar.dart`：M3 TopAppBar（small/center-aligned，surfaceTint、elevation onScroll）。
- `app_root.dart`：`MaterialApp(useMaterial3:true)` + `NavigationBar`（非 BottomNavigationBar）、NavigationDestination 标准图标态；错误页（init/main.dart）同步 M3 全屏。
- `layer_audit/smoke_check` 白名单移除 flutter_miuix；pubspec 卸载 miuix。

## 页面（M2-M3，共 12 页 + MiniBar + 错误页）
| 页 | M3 控件规范 |
|---|---|
| home | Scaffold+TopAppBar、Card 三态、FilledTonalButton、Chip 四态、M3 列表间距 8/16/24dp |
| search | SearchBar/SearchView、FilterChip、ListTile 标准密度、LinearProgressIndicator |
| playlist | ElevatedCard/FilledCard、NavigationBar、BottomSheet 拖拽把手 |
| player | Slider M3、IconButton 四态、FilledIconButton、CircularProgressIndicator、M3 封面容器变换 |
| library | TabBar 二级、Data-like ListTile、SnackBar 标准时长 |
| lyrics | M3 文本层级、高亮色 scheme.primary、滚动 M3 物理 |
| settings | ListTile、Switch、SegmentedButton、Dialog、Radio |
| comment/mv/album/artist | Card、Chip、FilledButton、Async 骨架 M3 shimmer |
| MiniBar | M3 BottomAppBar/Docked FAB 语义 |

## 动效
- `Easing.emphasizedDecelerate/Standard`、`Durations.short1..extralong4` 全部官方常量；禁裸 Duration。
- 交错入场、共享轴转场、容器变换按 M3 Motion 规范。

## 验收门
- `rg flutter_miuix` 全仓=0；每页 checklist 通过；PASS strict six-five + smoke_check + field_truth 155 断言；CI 全绿发 v26.11.14.01，清旧 tag。
