// L6 surface 级 · 通用小组件（歌曲条目 / 加载 / 错误重试 / 空态 / 区块头）
// 只依赖 flutter + miuix 主题常量；不 import logic/core（数据经构造参数注入）。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart';

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
      return MiuixCard(
        margin: const EdgeInsets.symmetric(horizontal: tnPadM, vertical: tnPadS),
        borderRadius: tnRadiusM,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: tnPadM, vertical: tnPadS / 2),
          leading: leading ?? Icon(Icons.music_note, color: tnPrimary),
          title: Text(title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
          subtitle: Text(
            duration.isEmpty ? artist : '$artist · $duration',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.aux,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.play_circle_fill, size: 32, color: tnPrimary),
            onPressed: onPlay,
          ),
          onTap: onTap,
        ),
      );
    } catch (e, st) {
      _logCrash('SongTile.build', e, st);
      return const SizedBox(height: 48);
    }
  }
}

/// 加载占位。
class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key, this.message = '加载中…'});
  final String message;
  @override
  Widget build(BuildContext context) {
    try {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: tnPrimary),
            const SizedBox(height: tnPadM),
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

/// 错误 + 重试。
class ErrorRetryBox extends StatelessWidget {
  const ErrorRetryBox({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    try {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: tnPrimary),
            const SizedBox(height: tnPadM),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: tnPadL),
              child: Text(message,
                  textAlign: TextAlign.center, style: TnText.of(context).body),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: tnPadM),
              MiuixButton(
                text: '重试',
                borderRadius: tnRadiusS,
                onPressed: onRetry,
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

/// 空态。
class EmptyBox extends StatelessWidget {
  const EmptyBox({super.key, this.message = '暂无内容'});
  final String message;
  @override
  Widget build(BuildContext context) {
    try {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined,
                size: 44, color: TnText.of(context).aux.color),
            const SizedBox(height: tnPadM),
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

/// 区块标题 + 可选动作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    try {
      return Padding(
        padding: const EdgeInsets.fromLTRB(tnPadL, tnPadL, tnPadL, tnPadS),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: tnPrimary,
                borderRadius: BorderRadius.circular(tnRadiusS),
              ),
            ),
            const SizedBox(width: tnPadS),
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
    Log.e('surface.common', '$where crashed', e, st);
  } catch (_) {}
}
