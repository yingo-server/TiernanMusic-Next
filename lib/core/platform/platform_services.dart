// L4 core/platform · 平台服务门面（唯一装配点）
//
// 平台实现按平台条件导入（platform_io / platform_web / platform_stub），
// 在此聚合成单例；bridge_core 只 export 本文件，上层（logic/surface）
// 一律经桥访问，禁止直接 import lib/core/platform/**。
//
// 契约：docs/UI_REWRITE_PLAN.md §1–§3。
library;

import 'platform.dart'
    show buildCapabilityGateway, buildPlatformCapabilities, buildWindowService;
import '../capability/capability_gateway.dart' show CapabilityGateway;
import '../capability/platform_capabilities.dart'
    show PlatformCapabilities, WindowService;

/// 平台能力集合（惰性单例）。
final PlatformCapabilities platformCapabilities = buildPlatformCapabilities();

/// 权限/能力网关（惰性单例）。
final CapabilityGateway capabilityGateway = buildCapabilityGateway();

/// 窗口服务（惰性单例）。
final WindowService windowService = buildWindowService();
