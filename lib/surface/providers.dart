// L6 surface 级 · 环B破除（审计批04-A F-02）：app_root ↔ assembly 共享符号抽离。
//
// 此前 appNavigatorKey / homeTabRequest / localeRevision / logicFacadeProvider
// 定义在 app_root.dart，assembly.dart 为取这些符号而 import app_root.dart，
// 形成 app_root ↔ assembly 双向环。本文件只依赖 flutter / riverpod /
// bridge_logic，被 app_root 与 assembly 各自单向 import，环解除。
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridges/bridge_logic.dart' show LogicFacade;

/// 全局 Navigator key：assembly 的二级页跳转（专辑/歌手/评论）无需 BuildContext。
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

/// 首页 tab 切换请求（装配层 onOpenSearch 等回调写入；app_root._HomeShellState 消费）。
/// 值 = 目标模块 id（如 'search'）；壳收到后定位对应 tab。
final ValueNotifier<String?> homeTabRequest = ValueNotifier<String?>(null);

/// 语言/区域变更重建信号（设置页切语言后 ++，AppRoot 重建 MaterialApp 生效）。
final ValueNotifier<int> localeRevision = ValueNotifier<int>(0);

/// logic 能力门面（registry.SurfaceModule.enabled/builder 拿这个）
final Provider<LogicFacade> logicFacadeProvider =
    Provider((_) => const LogicFacade());
