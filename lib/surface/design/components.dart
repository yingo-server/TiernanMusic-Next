// L7 surface/design · 共享控件（封面/曲目行/区块标题/三态/播放键）
// 页面层只组合这些，不各自造轮子；颜色字号一律取 Sp。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SongBrief;
import 'tokens.dart';

/// 封面图（网络图 + 占位；无 URL 显示音乐图标）。
class SpCover extends StatelessWidget {
  const SpCover({
    super.key,
    this.url,
    this.size = Sp.tileCover,
    this.radius = Sp.rS,
  });

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.cs.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.music_note, size: size * 0.4, color: context.cs.onSurfaceVariant),
    );
    if (u.isEmpty) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => box,
        loadingBuilder: (_, child, progress) => progress == null ? child : box,
      ),
    );
  }
}

/// 曲目行（封面 + 歌名/歌手 + 可选尾部操作）。
class SpSongTile extends StatelessWidget {
  const SpSongTile({
    super.key,
    required this.song,
    this.onTap,
    this.onMore,
    this.showCover = true,
    this.dense = false,
    this.trailing,
  });

  final SongBrief song;
  final VoidCallback? onTap;
  final VoidCallback? onMore;
  final bool showCover;
  final bool dense;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Sp.pagePad,
          vertical: dense ? Sp.gapS : Sp.gapM,
        ),
        child: Row(
          children: <Widget>[
            if (showCover) ...<Widget>[
              SpCover(url: song.cover, size: dense ? 40 : Sp.tileCover),
              const SizedBox(width: Sp.gapM),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    song.name.isEmpty ? song.hash : song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (song.singer.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      song.singer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (onMore != null)
              IconButton(
                onPressed: onMore,
                icon: const Icon(Icons.more_vert, size: 20),
                color: context.cs.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                tooltip: '更多',
              ),
          ],
        ),
      ),
    );
  }
}

/// 区块标题（大标题 + 右侧可选操作）。
class SpSectionHeader extends StatelessWidget {
  const SpSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Sp.pagePad,
        Sp.gapXL,
        Sp.pagePad,
        Sp.gapM,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: context.cs.primary,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// 骨架块（灰块占位）。
class SpSkeleton extends StatelessWidget {
  const SpSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = Sp.rS,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.cs.surfaceContainer,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// 列表骨架（固定行数的灰块）。
class SpListSkeleton extends StatelessWidget {
  const SpListSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (int i = 0; i < rows; i++)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.pagePad,
            vertical: Sp.gapS,
          ),
          child: Row(
            children: <Widget>[
              const SpSkeleton(width: 40, height: 40, radius: Sp.rS),
              const SizedBox(width: Sp.gapM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    SpSkeleton(width: 180, height: 12),
                    SizedBox(height: 6),
                    SpSkeleton(width: 110, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// 状态视图（空 / 错 / 受限，三态统一）。
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
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.gapXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: context.cs.onSurfaceVariant),
            const SizedBox(height: Sp.gapM),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
              const SizedBox(height: Sp.gapS),
              Text(subtitle!, style: t.bodySmall, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: Sp.gapL),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 圆形播放/暂停按钮（绿底黑图标）。
class SpPlayButton extends StatelessWidget {
  const SpPlayButton({
    super.key,
    required this.playing,
    required this.onTap,
    this.size = 64,
  });

  final bool playing;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Material(
      color: context.cs.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Icon(
          playing ? Icons.pause : Icons.play_arrow,
          size: size * 0.5,
          color: Colors.black,
        ),
      ),
    ),
  );
}

/// 圆形小按钮（上一首/下一首/循环/随机）。
class SpRoundButton extends StatelessWidget {
  const SpRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(icon, size: 24),
    color: active ? context.cs.primary : context.cs.onSurface,
    visualDensity: VisualDensity.compact,
  );
}
