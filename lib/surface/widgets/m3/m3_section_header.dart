// L6 surface/widgets/m3 · M3 区块标题（截图基线：大标题 + 右侧操作）
// 用法：首页各区块（每日推荐/推荐歌单/排行榜/新歌推荐）统一使用。
import 'package:flutter/material.dart';

import '../../theme/tn_theme.dart' show TnDims;

class M3SectionHeader extends StatelessWidget {
  const M3SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
        TnDims.padL, TnDims.padXL, TnDims.padL, TnDims.padM),
  });

  final String title;

  /// 右侧操作文案（如「清空」「更多」）。
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: cs.primary,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
