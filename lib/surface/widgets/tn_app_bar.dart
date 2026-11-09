// L6 surface/widgets · 统一顶栏（消除各页面 AppBar 左右留缝）
// 设计契约：
// - 顶栏全宽：backgroundColor 与 Scaffold 同色、elevation=0、无默认 titleSpacing 偏移；
// - 左右内容统一 gutter = tnPadL（16），标题与动作区都按此对齐；
// - 禁止各页面裸用 AppBar（smoke_check 可加规则），一律经本组件。
// 铁律：surface 层；try/catch + Log('surface.appbar')。
import 'package:flutter/material.dart';

import '../bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show tnPadL, tnRadiusM, TnText;

const String _tag = 'surface.appbar';

/// 全局统一顶栏。所有 SurfaceModule 页面必须使用，避免 Material 默认
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
  final bool centerTitle;

  @override
  Size get preferredSize => Size.fromHeight(
      kTextTabBarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      // 关键：scaffoldBackgroundColor 同源 + elevation 0 + surfaceTintColor 透明，
      // 消灭 AppBar 默认材质分层阴影形成的「缝」。
      return AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: centerTitle,
        // 标题区左右 inset 与内容 gutter 完全一致。
        titleSpacing: tnPadL,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Text(title, style: TnText.of(context).title),
        ),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(tnRadiusM),
          ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'TnAppBar build failed', e, st);
      return AppBar(title: Text(title));
    }
  }
}

/// 页面统一水平 gutter：Scaffold body 内容一律用此值包 SafeArea，
/// 保证与顶栏 titleSpacing 精确对齐（左右不再各差几 dp）。
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
