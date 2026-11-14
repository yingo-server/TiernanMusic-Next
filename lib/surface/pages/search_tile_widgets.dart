// L6 surface/pages · 搜索结果卡片（从 search_page 拆出，控制文件长度）
// 只做渲染；播放/下钻由调用方注入回调，不持有状态。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../../bridges/bridge_core.dart' show SongBrief, SearchType;
import '../theme/tn_motion.dart' show TnMotionStaggered;
import '../ui/spotify_ui.dart' as sp;
import '../widgets/common_widgets.dart' show SongTile;

const String _tag = 'surface.searchTile';

/// 搜索结果项的统一载体（song + 原始类型）。
class SongTileData {
  const SongTileData(this.song);
  final SongBrief song;
}

/// 统一卡片壳（交错入场 + Spotify 卡片）。
Widget searchCard(BuildContext ctx, int i, Widget child) {
  try {
    final cs = Theme.of(ctx).colorScheme;
    return TnMotionStaggered(
      index: i,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(sp.Sp.pagePad, 0, sp.Sp.pagePad, sp.Sp.gapS),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 1,
          surfaceTintColor: cs.surfaceTint,
          color: cs.surfaceContainer,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(sp.Sp.rCard)),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  } catch (e, st) {
    Log.e(_tag, 'card crashed', e, st);
    return const SizedBox.shrink();
  }
}

/// 结果行：song 走 SongTile 播放；歌单/专辑走 ListTile 下钻。
Widget searchCardRow(
  BuildContext ctx,
  SongTileData d,
  int i,
  SearchType type, {
  required void Function(SongTileData) onPlay,
  required void Function(SongTileData, SearchType) onDrill,
}) {
  try {
    final Widget child;
    if (type == SearchType.song) {
      child = SongTile(song: d.song, onPlay: (_) => onPlay(d), index: i + 1);
    } else {
      final owner = d.song.singer.isEmpty
          ? (type == SearchType.special ? '歌单' : '专辑')
          : d.song.singer;
      final id =
          type == SearchType.special ? '${d.song.mixSongId}' : d.song.albumId;
      child = ListTile(
        leading: Icon(
          type == SearchType.special ? Icons.queue_music : Icons.album,
          color: sp.Sp.green,
        ),
        title: Text(d.song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: sp.Sp.text, fontSize: sp.Sp.fItem)),
        subtitle: Text('$owner · ${d.song.durationSec}首 · id=$id',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: sp.Sp.textSub, fontSize: sp.Sp.fSub)),
        onTap: () => onDrill(d, type),
      );
    }
    return searchCard(ctx, i, child);
  } catch (e, st) {
    Log.e(_tag, 'card row crashed type=${type.name}', e, st);
    return const SizedBox.shrink();
  }
}

/// 加载态骨架（统一替代 LinearProgress）。
Widget searchLoadingSkeleton() => const Padding(
      padding: EdgeInsets.symmetric(vertical: sp.Sp.gapS),
      child: sp.SpListSkeleton(rows: 4),
    );


/// 分段搜索的独立状态（滚动控制器 + 分页 + 结果）。
class SearchSegmentState {
  SearchSegmentState() : scroll = ScrollController();
  final ScrollController scroll;
  String kw = '';
  int page = 1;
  int total = 0;
  bool loaded = false;
  bool searching = false;
  bool loadingMore = false;
  bool more = false;
  List<SongTileData> items = const <SongTileData>[];

  void reset(String k) {
    try {
      kw = k;
      page = 1;
      total = 0;
      loaded = false;
      searching = false;
      loadingMore = false;
      more = false;
      items = const <SongTileData>[];
    } catch (e, st) {
      Log.e('surface.searchTile', 'segment reset failed', e, st);
    }
  }
}
