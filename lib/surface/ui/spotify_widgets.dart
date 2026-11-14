// L6 surface/ui · Spotify 基础组件（标题/卡片/曲目行/封面/导航/按钮）
// 设计令牌见 spotify_tokens.dart（Sp 类）；本文件只做渲染，零业务回调持有。
import 'package:flutter/material.dart';

import 'spotify_tokens.dart' show Sp;

/// 页面大标题（Spotify：滚动到顶时大标题，下滚时缩小——先做静态版）。
class SpPageTitle extends StatelessWidget {
  const SpPageTitle(this.text, {super.key, this.trailing});

  final String text;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Sp.pagePad, Sp.gapXL, Sp.pagePad, Sp.gapL),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Sp.text,
                    fontSize: Sp.fPageTitle,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5)),
          ),
          ...?trailing,
        ],
      ),
    );
  }
}

/// 区块标题（首页各行的 label）。
class SpSectionHeader extends StatelessWidget {
  const SpSectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Sp.pagePad, Sp.gapL, Sp.pagePad, Sp.gapM),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Sp.text,
                    fontSize: Sp.fSection,
                    fontWeight: FontWeight.w700)),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                  foregroundColor: Sp.textSub,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(action!,
                  style: const TextStyle(
                      fontSize: Sp.fSub, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

/// 横滑卡片（Spotify 首页主形态）：120dp 方封面 + 标题 + 副标题。
class SpCoverCard extends StatelessWidget {
  const SpCoverCard({
    super.key,
    required this.coverUrl,
    required this.title,
    this.subtitle,
    this.onTap,
    this.size = Sp.cardCover,
    this.round = false, // 歌单方形 / 专辑圆形（Spotify 混用）
  });

  final String coverUrl;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Sp.rCard),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(round ? size / 2 : Sp.rCard),
              child: SpCover(url: coverUrl, size: size),
            ),
            const SizedBox(height: Sp.gapS),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Sp.text,
                    fontSize: Sp.fItem,
                    fontWeight: FontWeight.w500)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Sp.textSub, fontSize: Sp.fSub)),
          ],
        ),
      ),
    );
  }
}

/// 横滑行（首页区块容器）。
class SpCardRow extends StatelessWidget {
  const SpCardRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Sp.cardCover + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: Sp.gapM),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// 曲目行（Spotify 列表主形态）：封面(48) / 序号 + 标题 + 副标题 + ⋮。
class SpSongTile extends StatelessWidget {
  const SpSongTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.index,
    this.isPlaying = false,
    this.onTap,
    this.onMore,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final int? index;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Sp.pagePad, vertical: 2),
      leading: index != null
          ? SizedBox(
              width: 24,
              child: Text('$index',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: isPlaying ? Sp.green : Sp.textSub,
                      fontSize: Sp.fItem,
                      fontWeight: FontWeight.w600)))
          : SpCover(url: coverUrl ?? '', size: Sp.tileCover, radius: 4),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: isPlaying ? Sp.green : Sp.text,
              fontSize: Sp.fItem,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Sp.textSub, fontSize: Sp.fSub)),
      trailing: onMore != null
          ? IconButton(
              icon: const Icon(Icons.more_vert, color: Sp.textSub, size: 20),
              onPressed: onMore)
          : null,
    );
  }
}

/// 封面（统一加载：已归一化 URL；失败/空 → 占位；带内存缓存去重请求）。
class SpCover extends StatelessWidget {
  const SpCover({super.key, required this.url, this.size = 56, this.radius});

  final String url;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: Sp.cardHigh,
          child: Icon(Icons.music_note, color: Sp.textFaint, size: size / 2.4),
        );
    if (u.isEmpty) return placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? Sp.rCard),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder(),
      ),
    );
  }
}

/// 底部悬浮播放条（Spotify：黑底 + 上边框 + 缩略封面 + 绿色播放键）。
class SpMiniBar extends StatelessWidget {
  const SpMiniBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    required this.isPlaying,
    required this.onToggle,
    required this.onNext,
    required this.onExpand,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final bool isPlaying;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        border: Border(top: BorderSide(color: Sp.divider)),
      ),
      child: SizedBox(
        height: Sp.barH,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onExpand,
                child: Row(
                  children: [
                    const SizedBox(width: Sp.gapM),
                    SpCover(url: coverUrl ?? '', size: 40, radius: 4),
                    const SizedBox(width: Sp.gapM),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Sp.text,
                                  fontSize: Sp.fItem,
                                  fontWeight: FontWeight.w600)),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Sp.textSub, fontSize: Sp.fTiny)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Sp.text, size: 28),
              onPressed: onToggle,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Sp.text, size: 26),
              onPressed: onNext,
            ),
            const SizedBox(width: Sp.gapS),
          ],
        ),
      ),
    );
  }
}

/// 底部导航（5 位，Spotify 无标签底色、选中加粗）。
class SpNavDestination {
  const SpNavDestination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 胶囊按钮（Spotify 主 CTA：白底黑字或绿底）。
class SpPillButton extends StatelessWidget {
  const SpPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: filled ? Sp.text : Sp.cardHigh,
        foregroundColor: filled ? Colors.black : Sp.text,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sp.rBtn)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(label,
              style: const TextStyle(
                  fontSize: Sp.fItem, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
