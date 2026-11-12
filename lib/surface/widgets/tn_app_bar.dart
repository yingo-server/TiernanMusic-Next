// L6 surface/widgets · Material Design 3 TopAppBar（批M1-A）
// 设计契约（Google M3 Top app bars）：
// - small / center-aligned 两种：centerTitle 切换；标题用 titleLarge 角色；
// - 静止 elevation=0、surfaceTintColor=scheme.surfaceTint；滚动后
//   scrolledUnderElevation=3 触发 M3 elevation + surface tint（onScroll）；
// - 全宽矩形，无圆角假分层；backgroundColor 与 Scaffold 同色
//   （scheme.surface）；左右 gutter 统一 16dp（tnPadL）；
// - 栏高 64dp（TnDims.topAppBarH），TabBar 等 bottom 追加高度；
// - 禁止各页面裸用 AppBar，一律经本组件（保留 TnAppBar / TnPagePadding 名）。
// 铁律：surface 层只 import flutter/material + 桥 + 本层；try/catch + Log 留痕。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show TnDims, TnTypography, tnPadL;

const String _tag = 'surface.appbar';

/// 全局统一 M3 顶栏。所有 SurfaceModule 页面必须使用，避免 Material 默认
/// 4/16dp 隐式 inset 造成「顶栏与内容左右对不齐」的缝。
class TnAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TnAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = false,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  /// false = M3 small TopAppBar；true = M3 center-aligned TopAppBar。
  final bool centerTitle;

  @override
  Size get preferredSize => Size.fromHeight(
      TnDims.topAppBarH + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      // M3：表面色同源 + 静止无 elevation；surfaceTint 只在滚动
      // （scrolledUnderElevation=3）时由框架按官方公式叠加。
      return AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 3,
        shadowColor: cs.shadow,
        toolbarHeight: TnDims.topAppBarH,
        centerTitle: centerTitle,
        titleSpacing: tnPadL,
        titleTextStyle: TnTypography.titleLarge.copyWith(color: cs.onSurface),
        title: Text(title, style: TnTypography.titleLarge.copyWith(color: cs.onSurface)),
        leading: leading,
        actions: actions == null
            ? null
            : [
                Padding(
                  padding: const EdgeInsets.only(right: tnPadL),
                  child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
                ),
              ],
        bottom: bottom,
      );
    } catch (e, st) {
      Log.e(_tag, 'TnAppBar build failed, fallback M3 AppBar', e, st);
      return AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
        scrolledUnderElevation: 3,
        elevation: 0,
        toolbarHeight: TnDims.topAppBarH,
        title: Text(title),
      );
    }
  }
}

/// 页面统一水平 gutter：Scaffold body 内容一律用此值包 SafeArea，
/// 保证与 M3 TopAppBar 的 16dp 标题区精确对齐（左右不再各差几 dp）。
class TnPagePadding extends StatelessWidget {
  const TnPagePadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    try {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: tnPadL),
        child: child,
      );
    } catch (e, st) {
      Log.e(_tag, 'TnPagePadding build failed', e, st);
      return child;
    }
  }
}
