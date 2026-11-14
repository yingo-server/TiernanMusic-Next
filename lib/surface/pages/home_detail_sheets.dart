// L6 surface/pages · 首页二级弹层（歌单曲目 / 榜单曲目）
// 目的：让首页卡片真正可点（截图基线的信息密度），数据走已注入的 logic，
// 不新增跨层 import、不改模块装配签名。
// 铁律：每方法 try/catch + Log；空/错误态显式展示，不静默。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show Log, PlaylistLogic, PlaylistBrief, RankLogic, RankBrief, SongBrief;
import '../theme/tn_theme.dart' show TnDims;
import '../widgets/m3/m3_skeleton.dart' show M3ListSkeleton;
import '../widgets/m3/m3_state_views.dart' show M3EmptyState, M3ErrorRetry;
import '../widgets/playlist_tracks_sheet.dart'
    as generic_sheet;

const String _tag = 'surface.homeSheet';

/// 歌单曲目弹层（委托通用实现 widgets/playlist_tracks_sheet.dart）。
Future<void> showPlaylistTracksSheet(
  BuildContext context,
  PlaylistLogic playlist,
  PlaylistBrief brief,
  void Function(SongBrief) onPlay,
) async {
  try {
    await generic_sheet.showPlaylistTracksSheet(
      context,
      brief,
      load: () async {
        // 链路修复：先 detail 拿数字 specialId（global_collection_id 实测 20010）。
        final detail = await playlist.detail(brief.id);
        final sid = detail.specialId.isNotEmpty ? detail.specialId : brief.id;
        final page = await playlist.tracks(sid, 1, specialIdOverride: sid);
        return page.items;
      },
      onPlay: onPlay,
    );
  } catch (e, st) {
    Log.e(_tag, 'showPlaylistTracksSheet failed', e, st);
  }
}

/// 榜单曲目弹层：名称 + 更新时间 + 列表（点击播放）。
Future<void> showRankTracksSheet(
  BuildContext context,
  RankLogic rank,
  RankBrief brief,
  void Function(SongBrief) onPlay,
) async {
  try {
    // 审查修复：Future 打开前发起（同 playlist_tracks_sheet）。
    final Future<List<SongBrief>> future = rank.rankInfo(brief.rankId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final t = Theme.of(ctx).textTheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx2, scroll) => Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    TnDims.padL, 0, TnDims.padL, TnDims.padM),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(brief.name.isEmpty ? '榜单' : brief.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleMedium
                                  ?.copyWith(color: cs.onSurface)),
                          if (brief.updateTime.isNotEmpty)
                            Text(brief.updateTime,
                                style: t.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder(
                  future: future,
                  builder: (ctx3, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const M3ListSkeleton(rows: 6);
                    }
                    if (snap.hasError) {
                      return M3ErrorRetry(
                        title: '榜单加载失败',
                        detail: '${snap.error}',
                        onRetry: () => Navigator.of(ctx3).pop(),
                      );
                    }
                    final songs = snap.data ?? const <SongBrief>[];
                    if (songs.isEmpty) {
                      return const M3EmptyState(
                        icon: Icons.leaderboard_outlined,
                        title: '榜单为空',
                        subtitle: '该榜单暂无可播放曲目',
                      );
                    }
                    return ListView.separated(
                      controller: scroll,
                      itemCount: songs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final s = songs[i];
                        return ListTile(
                          leading: SizedBox(
                            width: 28,
                            child: Text('${i + 1}',
                                textAlign: TextAlign.center,
                                style: t.titleMedium?.copyWith(
                                    color: i < 3
                                        ? cs.primary
                                        : cs.onSurfaceVariant)),
                          ),
                          title: Text(s.name.isEmpty ? s.hash : s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.singer,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            try {
                              onPlay(s);
                            } catch (e, st) {
                              Log.e(_tag, 'rank sheet play failed', e, st);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  } catch (e, st) {
    Log.e(_tag, 'showRankTracksSheet failed', e, st);
  }
}
