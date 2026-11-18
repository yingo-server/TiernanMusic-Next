# 平台能力参考（Reference）

> 审阅：2026-11-19 · 事实源：`lib/core/capability/`、`lib/core/platform/`、`lib/bridges/bridge_core.dart`。
> 本文只陈述事实；「为什么这样落位」见 [架构总览](ARCHITECTURE_OVERVIEW.md)。

## 目录与条件导入

平台差异实现位于 `lib/core/platform/`（早期规划文档写作 `lib/platform/`，**已归档**，以代码为准）：

| 文件 | 角色 |
|---|---|
| `platform.dart` | 统一入口 facade，条件导出：`dart.library.io → platform_io.dart`、`dart.library.js_interop → platform_web.dart`、否则 `platform_stub.dart` |
| `platform_io.dart` / `platform_web.dart` / `platform_stub.dart` | 各平台构建 `*Capabilities / *Gateway / *WindowService` |
| `platform_services.dart` | 唯一装配点，惰性单例 `platformCapabilities` / `capabilityGateway` / `windowService` |
| `capability/io_capability_gateway.dart` | dart:io 平台权限网关实现 |
| `capability/web_capability_gateway.dart` | Web 平台权限网关实现 |
| `window/io_window_service.dart` | `window_manager` 唯一出现处（窗口尺寸/最大化/焦点事件） |

`bridge_core.dart` 只 `export` 平台无关接口与三个单例；上层（logic/surface）禁止直接 import `lib/core/platform/**`，
也禁止 `Platform.isXxx` / `defaultTargetPlatform` 判断，一律问能力集合。

> 注意：文档注释里仍写「lib/platform/**」，那是重写期的措辞；实际落盘路径是 `lib/core/platform/**`。

## 平台能力集合（PlatformCapabilities）

平台无关的「有什么」快照，字段均为 bool：`isDesktop / isMobile / isWeb`、
`supportsCustomTitleBar` / `supportsWindowSize` / `supportsTray` / `supportsGlobalShortcuts` /
`supportsFileDialog` / `supportsDragDrop` / `supportsMultiWindow` / `supportsNotifications` /
`supportsClipboardWrite` / `supportsMediaSession` / `supportsScreenReader` / `requiresGestureNavigation`。
`PlatformCapabilities.none` 为全 false 空实现（不支持平台/测试）。

自定义标题栏仅 Windows/Linux；桌面导航形态为 NavigationRail、移动为底部 NavigationBar（后者仍需落地）。
`supportsCustomTitleBar` 直接驱动 `buildDesktopTitleBar()` 是否渲染。

## 权限/能力网关（CapabilityGateway）

`CapStatus` 五态：

| 状态 | 含义 |
|---|---|
| `granted` | 已授权 |
| `denied` | 未授权，可再次请求 |
| `permanentlyDenied` | 永久拒绝，需引导去系统设置 |
| `restricted` | 策略/系统禁止，无法请求 |
| `unsupported` | 该平台不支持此能力 |

`CapId` 常量：`notification / fileRead / fileWrite / clipboard / network / storage / mediaKeys / openExternal`。

接口：`status(capId)`（查询，不弹窗）、`request(capId)`（触发系统流程）、
`openSettings()`（永久拒绝时跳设置，不支持返回 false）、`watch(capId)`（状态流）。
`CapState.canRequest = denied || granted`；`CapState.needsSettings = permanentlyDenied`。

实现要点：
- `IoCapabilityGateway`：桌面通知默认 granted、移动通知默认 denied；桌面文件能力按「作用域内可用」返回 granted；
  `request()` 不弹系统窗，真实结果由上层 `markResult()` 回写；`openSettings()` 需平台插件，当前返回 false。
- `WebCapabilityGateway`：浏览器权限模型（通知授权、剪贴板需用户手势）。
- `InMemoryCapabilityGateway`：测试与降级实现。

权限三态（已授权/未授权/受限）UI 呈现为「说明文案 + 禁用态 + 去设置动作」，不静默失败。

## 窗口服务（WindowService）

平台无关接口：`isAvailable / nativeHandle / setMinimumSize / setTitle / minimize / maximize /
unmaximize / close / isMaximized / isFocused / events`（`WindowEvent: focused/unfocused/maximized/
unmaximized/closed`），请求类型 `WindowSizeRequest`。

职责分离：
- `window_manager`（`IoWindowService`）管窗口尺寸/最小尺寸/最大化/焦点事件，`ensureInitialized()` 须在 `runApp` 前 await；
  自定义标题栏时隐藏原生标题栏（`TitleBarStyle.hidden`）、隐藏原生窗口按钮。
- bitsdojo_window 的 `appWindow` 原生句柄/拖拽由桌面标题栏 widget 直接用，不被窗口服务重复封装。

## 全平台构建落位

- Android：`ci.yml` 出 split-per-abi APK（shrunk）；仓库不提交原生目录，CI 临时 `flutter create`。
- Windows / Linux：`.github/workflows/desktop-build.yml`（workflow_dispatch）——
  Windows `flutter build windows --release` → zip；Linux 在 ubuntu-22.04（glibc 2.35）上
  `flutter build linux --release` → AppImage（含全部依赖，向前兼容 Ubuntu 22.04）。
- bitsdojo 生效需 patch 原生 runner（Windows `main.cpp` / Linux `my_application.cc` 去装饰），由 workflow 注入。
- 桌面拖拽/多屏用官方 DragTarget + MediaQuery，不引 `desktop_drop`/`screen_retriever`（Android AAR 冲突）。
- macOS/iOS/Web：设计语言与能力模型覆盖，但 CI 当前无对应产物构建；勿当作已交付。
