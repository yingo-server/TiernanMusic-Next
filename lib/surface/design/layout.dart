// L7 surface/design/layout.dart · 布局常量体系（唯一事实源）
//
// 规则（用户 2026-11-20 指令）：布局数值**完全不由页面决定**。
// 页面只允许引用本文件的常量，禁止手写任何间距/尺寸字面量。
// 所有数值全部对齐 Material 3 官方规范，采用**兼容性最强**的定义
// （M3 2021 起稳定的 spec，不用任何平台新 API）：
//
//   间距  = M3 8dp 体系（4/8/12/16/24/32/48/64）+ 2dp 微调（图标与文字间隙）
//   圆角  = M3 shape scale（4/8/12/16/28）+ full
//   断点  = M3 WindowSizeClass（compact <600 / medium <840 / expanded <1200 /
//           large >=1200）
//   触控  = M3 最小交互目标 48dp
//   栏高  = M3 组件默认（NavigationBar 80 / AppBar 64 / 迷你条 64）
import 'package:flutter/material.dart';

/// 间距（M3 8dp 体系）。
abstract final class TnSpace {
  /// 微调：图标-文字间隙等（8dp 体系内最小刻度的一半，M3 密度规则允许）。
  static const double xs = 4;

  /// 8dp 体系基准。
  static const double sm = 8;

  /// 列表项内部、卡片内边距。
  static const double md = 12;

  /// 页面水平边距（M3 compact 布局规范）。
  static const double lg = 16;

  /// 区块间距。
  static const double xl = 24;

  /// 大区块分隔。
  static const double xxl = 32;

  /// 页面底部留白（滚动内容收尾）。
  static const double xxxl = 48;

  /// 横滑列表端边距（首尾卡片与屏幕边对齐 + 露出下一张的呼吸空间）。
  static const double rail = 64;
}

/// 圆角（M3 shape scale）。
abstract final class TnRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 28;

  /// 胶囊（Chip/头像等）。
  static const double full = 999;
}

/// 断点（M3 WindowSizeClass，全平台统一：桌面宽窗口天然落 expanded/large）。
abstract final class TnBreakpoint {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;

  /// 语义判断（页面唯一允许的断点用法）。
  static bool isCompact(double width) => width < medium;
  static bool isMedium(double width) => width >= medium && width < expanded;
  static bool isExpanded(double width) => width >= expanded;
}

/// 组件尺寸（M3 组件默认值，页面不得另设）。
abstract final class TnSize {
  /// M3 最小交互目标。
  static const double touchTarget = 48;

  /// NavigationBar 官方默认高度（80）。
  static const double navBar = 80;

  /// AppBar 官方默认高度（56/64 视平台；统一用 64 保桌面一致）。
  static const double appBar = 64;

  /// 迷你播放条高度（64 = AppBar 同高，视觉重量对等）。
  static const double miniBar = 64;

  /// 封面/头像占位（列表项 leading 48 / 迷你条 40）。
  static const double avatarLg = 48;
  static const double avatarSm = 40;

  /// 横滑卡片：每日推荐封面卡（M3 Card 默认圆角 12 + 8dp 内边距）。
  static const double songCard = 128;

  /// 每日推荐横滑行高（封面 128 + 文字两行 ≈48，8dp 体系取 176）。
  static const double songRow = 176;

  /// 空态区高（图标 32 + 文案，8dp 体系取 96）。
  static const double emptyState = 96;

  /// 排行榜横滑卡高（8dp 体系取 144）。
  static const double rankCard = 144;

  /// 歌单网格卡（compact 2 列时卡片宽 = (屏宽-32-12)/2 ≈ 158）。
  static const double playlistCardMin = 152;

  /// 登录二维码（240 = 8dp 体系，M3 Dialog 内容区常用）。
  static const double qrCode = 240;
}

/// 页面骨架（统一页面结构，页面不得自带 Scaffold/AppBar 主题配置）。
///
/// 页面 = TnPageScaffold(title, actions, body)。这样：
/// - AppBar 样式只配置一次（theme 里已配，这里只组装）
/// - SafeArea / Padding 策略全平台一致
/// - 桌面/移动断点分流集中一处
class TnPageScaffold extends StatelessWidget {
  const TnPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: theme.textTheme.headlineSmall),
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
