// L7 surface · 桌面自定义标题栏（官方 bitsdojo 控件 + 语义 token）
//
// 契约：
// - 只用官方控件：bitsdojo_window 的 WindowBorder / WindowTitleBarBox /
//   MinimizeWindowButton / MaximizeWindowButton / CloseWindowButton，
//   搭配 M3 官方 Text / GestureDetector。**不手写按钮**。
// - 颜色只来自 titlebar.* 语义 token（设计语言 §3.3），不挂 ColorScheme。
// - 失焦（窗口未聚焦）整条降对比（titlebar.inactive）。
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show platformCapabilities, windowService;
import 'layout.dart' show TnSize, TnSpace;
import 'tokens_v2.dart';

/// 桌面标题栏（仅 Windows/Linux 自定义框架时使用；macOS/Web 不渲染）。
///
/// 返回 null 表示当前平台不需要自绘标题栏（由调用方回退到默认布局）。
Widget? buildDesktopTitleBar(BuildContext context) {
  if (!platformCapabilities.supportsCustomTitleBar) return null;
  final palette = context.palette;

  return WindowBorder(
    color: palette.titlebarBg,
    child: WindowTitleBarBox(
      child: GestureDetector(
        onDoubleTap: () => windowService.isMaximized
            ? windowService.unmaximize()
            : windowService.maximize(),
        child: Container(
          height: TnSize.titlebarButton,
          color: palette.titlebarBg,
          padding: const EdgeInsets.only(left: TnSpace.md),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'TiernanMusicNext',
                  style: TextStyle(
                    color: palette.titlebarFg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 拖拽区：让标题栏空白处可拖动窗口（官方 startDragging）。
              Expanded(
                child: GestureDetector(
                  onPanStart: (_) => windowService.startDragging(),
                  behavior: HitTestBehavior.opaque,
                ),
              ),
              MinimizeWindowButton(
                colors: WindowButtonColors(
                  normal: palette.titlebarBg,
                  mouseOver: palette.titlebarButtonHover,
                  mouseDown: palette.titlebarButtonHover,
                  iconNormal: palette.titlebarFg,
                  iconMouseOver: palette.titlebarFg,
                  iconMouseDown: palette.titlebarFg,
                ),
              ),
              MaximizeWindowButton(
                colors: WindowButtonColors(
                  normal: palette.titlebarBg,
                  mouseOver: palette.titlebarButtonHover,
                  mouseDown: palette.titlebarButtonHover,
                  iconNormal: palette.titlebarFg,
                  iconMouseOver: palette.titlebarFg,
                  iconMouseDown: palette.titlebarFg,
                ),
              ),
              CloseWindowButton(
                colors: WindowButtonColors(
                  normal: palette.titlebarBg,
                  mouseOver: palette.titlebarCloseHover,
                  mouseDown: palette.titlebarCloseHover,
                  iconNormal: palette.titlebarFg,
                  iconMouseOver: palette.titlebarInactive,
                  iconMouseDown: palette.titlebarInactive,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
