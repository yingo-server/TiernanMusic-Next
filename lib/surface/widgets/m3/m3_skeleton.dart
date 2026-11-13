// L6 surface/widgets/m3 · M3 骨架屏（shimmer）
// 用途：首屏/列表加载时的占位，替代空白与转圈；动画遵循 M3 时长令牌。
// 纪律：只 import flutter/material + 本目录；每组件 dispose 控制器，零泄漏。
import 'package:flutter/material.dart';

import '../../theme/tn_theme.dart' show TnDims;

/// 微光容器：给子件叠加水平扫光（单个 AnimationController，dispose 释放）。
class M3Shimmer extends StatefulWidget {
  const M3Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<M3Shimmer> createState() => _M3ShimmerState();
}

class _M3ShimmerState extends State<M3Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color base = cs.surfaceContainerHigh;
    final Color hi = cs.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect r) {
            final double dx = (_c.value * 2 - 1) * r.width;
            return LinearGradient(
              colors: <Color>[base, hi, base],
              stops: const <double>[0.35, 0.5, 0.65],
              begin: Alignment(-1 + dx / r.width, 0),
              end: Alignment(1 + dx / r.width, 0),
            ).createShader(r);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 单个占位块。
class M3SkeletonBox extends StatelessWidget {
  const M3SkeletonBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 12,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 列表骨架：封面方块 + 两行文本占位。
class M3ListSkeleton extends StatelessWidget {
  const M3ListSkeleton({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return M3Shimmer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: TnDims.padL),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: TnDims.padM),
        itemBuilder: (context, i) => Row(
          children: <Widget>[
            const M3SkeletonBox(width: 56, height: 56, radius: 10),
            const SizedBox(width: TnDims.padM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  M3SkeletonBox(width: 160.0 + (i % 3) * 40, height: 14),
                  const SizedBox(height: 8),
                  const M3SkeletonBox(width: 96, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 横向卡片骨架（首页每日推荐/歌单区用）。
class M3CardRowSkeleton extends StatelessWidget {
  const M3CardRowSkeleton({
    super.key,
    this.count = 3,
    this.cardWidth = 150,
    this.cardHeight = 150,
  });

  final int count;
  final double cardWidth;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return M3Shimmer(
      child: SizedBox(
        height: cardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: TnDims.padL),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: TnDims.padM),
          itemBuilder: (_, __) =>
              M3SkeletonBox(width: cardWidth, height: cardHeight, radius: 16),
        ),
      ),
    );
  }
}
