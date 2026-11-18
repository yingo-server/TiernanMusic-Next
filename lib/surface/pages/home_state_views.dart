// L7 surface/pages · 首页共享状态组件 —— 已退役（空壳）
//
// 历史：本文件曾提供 HomeSkeletonBox / HomeEmptyBox / HomeErrorRetry 三个
// 手写控件（骨架屏 / 空态 / 错误重试）。按 UI 重写铁律（零手写控件），
// 这三者已由 home_page.dart 内联为官方控件组合：
//   骨架占位 → Card + LinearProgressIndicator
//   空态     → Icon + Text
//   错误重试 → Icon + Text + FilledButton.tonal
//
// 本文件已无任何 import 方（home_page.dart 不再 import 它），故保留为空壳，
// 仅保留说明文字，不含任何控件定义。
library;
