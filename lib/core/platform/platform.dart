// lib/platform · 平台层：平台差异实现（怎么做）
//
// 契约（docs/UI_REWRITE_PLAN.md §1–§2）：
// - 本目录只被 lib/core/capability/** 依赖，不得反向依赖 logic/session/surface。
// - surface/logic 禁止 Platform.isXxx 判断，一律走能力网关。
// - 平台实现用条件导入 + stub，保证单一平台编译无死代码报错。
//
// 文件：
//   platform.dart        统一入口 facade（对外唯一 API）
//   platform_stub.dart   不支持平台的降级实现
//   platform_io.dart     dart:io 平台（Windows/Linux/macOS/Android/iOS）
//   platform_web.dart    Web 实现
//   window/              窗口服务（bitsdojo_window + window_manager）
//   capability/          权限网关的平台实现
library;

export 'platform_stub.dart'
    if (dart.library.io) 'platform_io.dart'
    if (dart.library.js_interop) 'platform_web.dart';
