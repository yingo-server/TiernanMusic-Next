// L6 surface/widgets/m3 · M3 空态与错误重试
// 用法：空数据 → M3EmptyState；加载失败 → M3ErrorRetry（带真实错误摘要）。
// 纪律：不吞错误；按钮用 M3 FilledButton/Tonal。
import 'package:flutter/material.dart';

import '../../theme/tn_theme.dart' show TnDims;

/// 空态：图标 + 标题 + 说明 + 可选动作。
class M3EmptyState extends StatelessWidget {
  const M3EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
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
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TnDims.padXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: TnDims.padM),
            Text(title,
                textAlign: TextAlign.center,
                style: t.titleMedium?.copyWith(color: cs.onSurface)),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: TnDims.padL),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误重试：显示真实错误摘要（不静默），按钮触发 onRetry。
class M3ErrorRetry extends StatelessWidget {
  const M3ErrorRetry({
    super.key,
    this.title = '加载失败',
    this.detail,
    required this.onRetry,
  });

  final String title;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TnDims.padXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 40, color: cs.error),
            const SizedBox(height: TnDims.padM),
            Text(title, style: t.titleMedium?.copyWith(color: cs.onSurface)),
            if (detail != null && detail!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                detail!.trim(),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: TnDims.padL),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
