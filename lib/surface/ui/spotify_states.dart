// L6 surface/ui · Spotify 加载/空态（骨架脉动 / 状态视图）
import 'package:flutter/material.dart';

import 'spotify_tokens.dart' show Sp;
import 'spotify_widgets.dart' show SpPillButton;

/// 骨架占位（Spotify 加载态：灰块脉动，无转圈）。
class SpSkeleton extends StatefulWidget {
  const SpSkeleton({super.key, this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SpSkeleton> createState() => _SpSkeletonState();
}

class _SpSkeletonState extends State<SpSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.9).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Sp.cardHigh,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// 列表骨架（N 行曲目占位）。
class SpListSkeleton extends StatelessWidget {
  const SpListSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Sp.pagePad, vertical: Sp.gapS),
            child: Row(
              children: [
                const SpSkeleton(width: 48, height: 48),
                const SizedBox(width: Sp.gapM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SpSkeleton(width: 140.0 + (i % 4) * 30, height: 14),
                      const SizedBox(height: 8),
                      const SpSkeleton(width: 90, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 空态 / 错误态（Spotify：居中图标 + 文案 + 绿色动作）。
class SpStateView extends StatelessWidget {
  const SpStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.gapXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Sp.textSub),
            const SizedBox(height: Sp.gapM),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Sp.text,
                    fontSize: Sp.fItem,
                    fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Sp.textSub, fontSize: Sp.fSub)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Sp.gapL),
              SpPillButton(label: actionLabel!, onTap: onAction!),
            ],
          ],
        ),
      ),
    );
  }
}
