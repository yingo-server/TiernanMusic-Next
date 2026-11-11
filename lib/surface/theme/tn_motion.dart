// L6 surface/theme · 动效规范组件库（批10-C）
// 依赖 tn_theme.dart 的 TnMotion 常量（fast=150/normal=250/slow=350，
// curve=easeOutCubic）；Log 经 bridge_logic 取（surface 层合法跨层通道）。
// 纪律：AnimationController 必须 dispose；禁止裸 Duration（确需自定义时长须注释）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;
import 'tn_theme.dart' show TnMotion;

const String _tag = 'surface.tn_motion';

/// 动效规格：三态时长 + 统一曲线，与 TnMotion 常量一一对应。
class TnMotionSpec {
  const TnMotionSpec._(this.duration, this.curve);
  final Duration duration;
  final Curve curve;

  /// 快速反馈（150ms）：点按、缩放、开关。
  static const TnMotionSpec fast = TnMotionSpec._(TnMotion.fast, TnMotion.curve);
  /// 常规转场（250ms）：页面切换、列表入场。
  static const TnMotionSpec normal =
      TnMotionSpec._(TnMotion.normal, TnMotion.curve);
  /// 慢速强调（350ms）：大封面、大区块过渡。
  static const TnMotionSpec slow = TnMotionSpec._(TnMotion.slow, TnMotion.curve);
}

/// 列表项交错入场：Fade + Slide（自下 12px 上移），每项延迟
/// index * step（默认 30ms），最多封顶 6 项（index≥6 与 index=5 同步，
/// 避免长列表尾部等待）。controller 在 dispose 释放，构建失败 Log 留痕。
class TnMotionStaggered extends StatefulWidget {
  const TnMotionStaggered({
    super.key,
    required this.child,
    this.index = 0,
    this.step,
    this.curve,
  });

  final Widget child;
  final int index;
  final Duration? step;
  final Curve? curve;

  @override
  State<TnMotionStaggered> createState() => _TnMotionStaggeredState();
}

class _TnMotionStaggeredState extends State<TnMotionStaggered>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctl;
  Animation<double>? _fade;
  Animation<Offset>? _slide;

  static const int _maxItems = 6;
  static const Duration _defaultStep = Duration(milliseconds: 30); // 交错步长，非三档时长，特意自定义

  @override
  void initState() {
    super.initState();
    try {
      final i = widget.index.clamp(0, _maxItems - 1);
      final step = widget.step ?? _defaultStep;
      final delay = step * i;
      final ctl = AnimationController(vsync: this, duration: TnMotion.normal);
      final curve = widget.curve ?? TnMotion.curve;
      _fade = CurvedAnimation(parent: ctl, curve: curve)
          .drive(const Tween<double>(begin: 0, end: 1));
      _slide = CurvedAnimation(parent: ctl, curve: curve)
          .drive(const Tween<Offset>(begin: Offset(0, 0.06), end: Offset.zero));
      _ctl = ctl;
      Future<void>.delayed(delay, () {
        if (mounted) ctl.forward();
      });
    } catch (e, st) {
      Log.e(_tag, 'staggered init failed, render child directly', e, st);
      _ctl = null;
    }
  }

  @override
  void dispose() {
    try {
      _ctl?.dispose();
    } catch (e, st) {
      Log.e(_tag, 'staggered dispose failed', e, st);
    }
    _ctl = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    if (ctl == null || _fade == null || _slide == null) {
      return widget.child; // 动画初始化失败兜底：直接渲染内容
    }
    return FadeTransition(
      opacity: _fade!,
      child: SlideTransition(position: _slide!, child: widget.child),
    );
  }
}

/// 页面转场：fade + 轻微上滑（24px），TnMotion.normal + easeOutCubic。
/// 供 Navigator.push 使用：`Navigator.push(context, TnPageRoute(page))`。
class TnPageRoute<T> extends PageRouteBuilder<T> {
  TnPageRoute(Widget page)
      : super(
          transitionDuration: TnMotion.normal,
          reverseTransitionDuration: TnMotion.fast,
          pageBuilder: (ctx, anim, secondary) => page,
          transitionsBuilder: (ctx, anim, secondary, child) {
            try {
              final curved =
                  CurvedAnimation(parent: anim, curve: TnMotion.curve);
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: curved.drive(
                      const Tween<Offset>(begin: Offset(0, 0.04), end: Offset.zero)),
                  child: child,
                ),
              );
            } catch (e, st) {
              Log.e(_tag, 'page transition failed, fallback plain', e, st);
              return child;
            }
          },
        );
}

/// 点按反馈：按下缩到 0.96，松开回弹，TnMotion.fast。
class TnPressable extends StatefulWidget {
  const TnPressable({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<TnPressable> createState() => _TnPressableState();
}

class _TnPressableState extends State<TnPressable> {
  bool _down = false;

  void _set(bool v) {
    try {
      if (mounted) setState(() => _down = v);
    } catch (e, st) {
      Log.e(_tag, 'pressable state failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1.0,
          duration: TnMotion.fast,
          curve: TnMotion.curve,
          child: widget.child,
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'pressable build failed', e, st);
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }
  }
}
