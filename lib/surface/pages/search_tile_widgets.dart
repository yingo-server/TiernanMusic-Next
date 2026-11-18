// L7 surface/pages · 搜索页叶子组件（已内联，保留文件仅为兼容旧 import 路径）。
//
// 迁移说明（无自定义控件铁律）：
// 原 SearchSongTile / SearchEmptyBox / SearchErrorRetry 三个 StatelessWidget
// 已按「不手写控件类」契约改写为 SearchPage 内的官方控件组合方法：
//   - SearchSongTile   → SearchPage._songTile（官方 ListTile + ClipRRect + Image.network）
//   - SearchEmptyBox   → SearchPage._empty（官方 Icon + Text）
//   - SearchErrorRetry → SearchPage._error（官方 Icon + Text + TextButton，
//                        另提供 FilledButton.tonal 语义等价的回调入口）
// 本文件不再定义任何控件类、不再持有裸色值；颜色统一经 design/tokens_v2.dart
// 的 context.cs.* 语义 ColorScheme 取得。任何新代码请直接使用官方 Material 3
// 控件，不要在此恢复自写控件。
library;
