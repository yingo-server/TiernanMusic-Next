// L6 surface/widgets · 收藏按钮（功能对齐收尾，主会话接线）
// 契约：收藏状态由外部 isCollected 提供，点击走 onToggle（CollectLogic.toggle
// 内含防重锁与登录守卫）；按钮自身只防连点（_busy 期间禁用），不持业务状态。
// 铁律：try/catch + Log('surface.favorite')；零第三方依赖。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.favorite';

/// 收藏/取消收藏按钮（受控组件）。
class FavoriteButton extends StatefulWidget {
  const FavoriteButton({
    super.key,
    required this.isCollected,
    required this.onToggle,
    this.size = 24,
  });

  final bool isCollected;
  final Future<void> Function() onToggle;
  final double size;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    try {
      setState(() => _busy = true);
      await widget.onToggle();
    } catch (e, st) {
      Log.e(_tag, 'onToggle failed', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return IconButton(
        icon: Icon(
          widget.isCollected ? Icons.favorite : Icons.favorite_border,
          color: widget.isCollected ? Theme.of(context).colorScheme.primary : null,
          size: widget.size,
        ),
        tooltip: widget.isCollected ? '取消收藏' : '收藏',
        onPressed: _busy ? null : _tap,
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
