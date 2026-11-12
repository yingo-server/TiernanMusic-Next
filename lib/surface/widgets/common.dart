// L6 surface/widgets · 通用小组件（歌曲条目 / 加载 / 错误重试 / 空态 / 区块头）
// 批M3 公共组件收口：Card 三态（elevation / surfaceTintColor / surface 容器色）、
//   IconButton 四态、FilledButton、CircularProgressIndicator、Slider 2023 形状、
//   SnackBar 标准时长统一收敛到本文件导出的 M3 样式令牌，五页共用不各写一套。
//   色彩全取 Theme.of(context).colorScheme，文本取 M3 TextTheme 层级（TnText
//   已按 titleMedium/bodyMedium/bodySmall 三档映射），间距取 TnDims 4dp 网格。
// 只依赖 flutter/material + 桥 + 本层主题；不 import logic/core
//（数据经构造参数注入）；零第三方主题依赖，无裸 Duration / Color(0x…) 字面量。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show TnDims, TnText;

const String _tag = 'surface.common';

// ── M3 控件样式令牌（批M3：五页统一取用，避免各页硬编码 / 重复实现）──

/// M3 IconButton 四态（enabled / hovered / focused / pressed）+ disabled：
/// 状态层颜色全部由 ColorScheme 推导；形状与 40dp 命中区沿用 M3 默认。
ButtonStyle tnIconButtonStyle(ColorScheme cs) => IconButton.styleFrom(
      foregroundColor: cs.onSurfaceVariant,
      disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
      hoverColor: cs.onSurfaceVariant.withValues(alpha: 0.08),
      focusColor: cs.onSurfaceVariant.withValues(alpha: 0.10),
      highlightColor: cs.onSurfaceVariant.withValues(alpha: 0.10),
    );

/// M3 Card 三态：rest elevation=1 / surfaceTintColor=scheme.surfaceTint /
/// surface 容器色；hover / focus / press 由子件 InkWell 状态层承担。
/// margin 归零消除默认 4dp 外边距，圆角统一 12dp（TnDims.rMBorder）。
Card tnM3Card({
  required ColorScheme cs,
  required Widget child,
  double elevation = 1,
  Color? color,
  BorderRadius? borderRadius,
}) =>
    Card(
      margin: EdgeInsets.zero,
      elevation: elevation,
      surfaceTintColor: cs.surfaceTint,
      color: color ?? cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? TnDims.rMBorder),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

/// M3 Slider（2023 形状：胶囊轨道 + 把手间隙）形状沿用主题默认，
/// 仅把轨道 / 把手 / 状态层 / 数值气泡颜色收敛到 ColorScheme。
SliderThemeData tnSliderTheme(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return SliderTheme.of(context).copyWith(
    activeTrackColor: cs.primary,
    inactiveTrackColor: cs.surfaceContainerHighest,
    disabledActiveTrackColor: cs.onSurface.withValues(alpha: 0.38),
    disabledInactiveTrackColor: cs.onSurface.withValues(alpha: 0.12),
    disabledThumbColor: cs.onSurface.withValues(alpha: 0.38),
    thumbColor: cs.primary,
    overlayColor: cs.primary.withValues(alpha: 0.12),
    valueIndicatorColor: cs.primary,
    valueIndicatorTextStyle: Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: cs.onPrimary),
  );
}

/// M3 SnackBar 标准展示时长 4s = 8 × Durations.long2(500ms)，
/// 由官方动效令牌组合（M3 规范 4s），禁裸 Duration(milliseconds: …)。
final Duration tnSnackBarDuration = Durations.long2 * 8;

/// 歌曲条目：歌名 / 歌手 / 时长 + 播放按钮回调。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.title,
    required this.artist,
    this.duration = '',
    this.onPlay,
    this.onTap,
    this.leading,
  });

  final String title;
  final String artist;
  final String duration; // 已格式化（mm:ss）
  final VoidCallback? onPlay;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    try {
      final t = TnText.of(context);
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: TnDims.padM, vertical: TnDims.padS),
        child: tnM3Card(
          cs: cs,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: TnDims.padM, vertical: TnDims.padXS),
            leading: leading ?? Icon(Icons.music_note, color: cs.primary),
            title: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
            subtitle: Text(
              duration.isEmpty ? artist : '$artist · $duration',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.aux,
            ),
            trailing: IconButton(
              icon: Icon(Icons.play_circle_fill, size: 32, color: cs.primary),
              style: tnIconButtonStyle(cs),
              onPressed: onPlay,
            ),
            onTap: onTap,
          ),
        ),
      );
    } catch (e, st) {
      _logCrash('SongTile.build', e, st);
      return const SizedBox(height: 48);
    }
  }
}

/// 加载占位（M3 CircularProgressIndicator）。
class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key, this.message = '加载中…'});
  final String message;
  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: TnDims.padM),
            Text(message, style: TnText.of(context).aux),
          ],
        ),
      );
    } catch (e, st) {
      _logCrash('LoadingBox.build', e, st);
      return const SizedBox.shrink();
    }
  }
}

/// 错误 + 重试（M3 FilledButton）。
class ErrorRetryBox extends StatelessWidget {
  const ErrorRetryBox({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: cs.error),
            const SizedBox(height: TnDims.padM),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: TnDims.padL),
              child: Text(message,
                  textAlign: TextAlign.center, style: TnText.of(context).body),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: TnDims.padM),
              FilledButton(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      );
    } catch (e, st) {
      _logCrash('ErrorRetryBox.build', e, st);
      return const SizedBox.shrink();
    }
  }
}

/// 空态（M3 onSurfaceVariant + bodySmall 层级）。
class EmptyBox extends StatelessWidget {
  const EmptyBox({super.key, this.message = '暂无内容'});
  final String message;
  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined,
                size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: TnDims.padM),
            Text(message, style: TnText.of(context).aux),
          ],
        ),
      );
    } catch (e, st) {
      _logCrash('EmptyBox.build', e, st);
      return const SizedBox.shrink();
    }
  }
}

/// 区块标题 + 可选动作（M3 titleMedium + primary 色条，4dp 网格）。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            TnDims.padL, TnDims.padL, TnDims.padL, TnDims.padS),
        child: Row(
          children: [
            Container(
              width: TnDims.padXS,
              height: TnDims.padL,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(TnDims.rXS),
              ),
            ),
            const SizedBox(width: TnDims.padS),
            Expanded(child: Text(title, style: TnText.of(context).title)),
            if (action != null) action!,
          ],
        ),
      );
    } catch (e, st) {
      _logCrash('SectionHeader.build', e, st);
      return const SizedBox.shrink();
    }
  }
}

void _logCrash(String where, Object e, StackTrace st) {
  try {
    Log.e(_tag, '$where crashed', e, st);
  } catch (_) {}
}
