// L6 surface/pages · 首页（Spotify 架构全量重写）
// 结构：大标题 → [快捷入口网格(收藏/下载/最近)] → 每日推荐(横滑) → 推荐歌单(横滑)
//       → 排行榜(横滑) → 新歌/热搜(列表) ；每区块骨架/空态独立，互不拖垮。
// 数据：沿用注入的 logic；封面经模型层归一化（SpCover 零处理）。
// 纪律：回调全 try/catch；不 import 下层非桥；页面层禁止硬编码颜色（只用 Sp）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show
        LogicFacade,
        Log,
        RankLogic,
        RankBrief,
        PlaylistLogic,
        PlaylistBrief,
        RecommendLogic,
        SearchLogic,
        SearchSuggestItem,
        SongBrief;
import '../registry.dart';
import '../ui/spotify_ui.dart' as sp;
import 'home_detail_sheets.dart' show showPlaylistTracksSheet, showRankTracksSheet;

const String _tag = 'surface.home';

/// 工厂：装配层调用（签名不变，供 registry 热插拔）。
SurfaceModule buildHomeModule({
  required RecommendLogic recommend,
  required RankLogic rank,
  required SearchLogic search,
  required PlaylistLogic playlist,
  required void Function(SongBrief) onPlay,
  required void Function() onOpenSearch,
  void Function(SongBrief)? onSongAction,
}) =>
    HomePageModule(
      recommend: recommend,
      rank: rank,
      search: search,
      playlist: playlist,
      onPlay: onPlay,
      onOpenSearch: onOpenSearch,
      onSongAction: onSongAction,
    );

class HomePageModule implements SurfaceModule {
  HomePageModule({
    required RecommendLogic recommend,
    required RankLogic rank,
    required SearchLogic search,
    required PlaylistLogic playlist,
    required void Function(SongBrief) onPlay,
    required void Function() onOpenSearch,
    void Function(SongBrief)? onSongAction,
  })  : _recommend = recommend,
        _rank = rank,
        _search = search,
        _playlist = playlist,
        _onPlay = onPlay,
        _onOpenSearch = onOpenSearch,
        _onSongAction = onSongAction;

  final RecommendLogic _recommend;
  final RankLogic _rank;
  final SearchLogic _search;
  final PlaylistLogic _playlist;
  final void Function(SongBrief) _onPlay;
  final void Function() _onOpenSearch;
  final void Function(SongBrief)? _onSongAction;

  @override
  String get id => 'home';
  @override
  String get route => '/home';
  @override
  NavEntry? get navEntry => const NavEntry('首页', 'home');
  @override
  bool enabled(LogicFacade logic) => true;
  @override
  WidgetBuilder builder(LogicFacade logic) => (ctx) => SpHomePage(
        recommend: _recommend,
        rank: _rank,
        search: _search,
        playlist: _playlist,
        onPlay: _onPlay,
        onOpenSearch: _onOpenSearch,
        onSongAction: _onSongAction,
      );
}

/// 首页主体（Spotify 垂直区块流）。
class SpHomePage extends StatelessWidget {
  const SpHomePage({
    super.key,
    required this.recommend,
    required this.rank,
    required this.search,
    required this.playlist,
    required this.onPlay,
    required this.onOpenSearch,
    this.onSongAction,
  });

  final RecommendLogic recommend;
  final RankLogic rank;
  final SearchLogic search;
  final PlaylistLogic playlist;
  final void Function(SongBrief) onPlay;
  final void Function() onOpenSearch;
  final void Function(SongBrief)? onSongAction;

  void _safe(void Function() f, String what) {
    try {
      f();
    } catch (e, st) {
      Log.e(_tag, '$what failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: sp.Sp.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: sp.Sp.pagePad),
            child: Row(
              children: [
                Expanded(
                  child: Text('首页',
                      style: TextStyle(
                          color: sp.Sp.text,
                          fontSize: sp.Sp.fPageTitle,
                          fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: sp.Sp.text, size: 26),
                  tooltip: '搜索',
                  onPressed: () => _safe(onOpenSearch, 'onOpenSearch'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: sp.Sp.green,
        backgroundColor: sp.Sp.card,
        onRefresh: () async => _safe(() {}, 'refresh'),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _Section(
              title: '每日推荐',
              future: () => recommend.daily(1, pageSize: 12),
              buildRow: (items, ctx) => sp.SpCardRow(
                children: [
                  for (final s in items)
                    sp.SpCoverCard(
                      coverUrl: s.cover,
                      title: s.name,
                      subtitle: s.singer,
                      onTap: () => _safe(() => onPlay(s), 'play daily'),
                    ),
                ],
              ),
            ),
            _Section(
              title: '推荐歌单',
              future: () => playlist.recommend(1, pageSize: 12),
              buildRow: (items, ctx) => sp.SpCardRow(
                children: [
                  for (final p in items)
                    sp.SpCoverCard(
                      coverUrl: p.cover,
                      title: p.name,
                      subtitle: '${p.trackCount} 首',
                      onTap: () => _safe(
                          () => showPlaylistTracksSheet(
                              ctx, playlist, p, onPlay),
                          'open playlist'),
                    ),
                ],
              ),
            ),
            _Section(
              title: '排行榜',
              future: () async =>
                  (await rank.rankList()).take(12).toList(growable: false),
              buildRow: (items, ctx) => sp.SpCardRow(
                children: [
                  for (final r in items)
                    sp.SpCoverCard(
                      coverUrl: r.cover,
                      title: r.name,
                      subtitle: r.updateTime,
                      onTap: () => _safe(
                          () => showRankTracksSheet(ctx, rank, r, onPlay),
                          'open rank'),
                    ),
                ],
              ),
            ),
            _Section(
              title: '热门搜索',
              future: () async {
                final all = await search.hotSearch();
                return <SearchSuggestItem>[for (final h in all.take(20)) h];
              },
              buildList: (items, ctx) => Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    sp.SpSongTile(
                      index: i + 1,
                      title: items[i].keyword,
                      subtitle: items[i].type,
                      onTap: () => _safe(onOpenSearch, 'hot→search'),
                    ),
                ],
              ),
              asList: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// 区块壳：统一 未来加载 → 骨架 / 空态 / 数据（横滑行或列表）。
class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.future,
    this.buildRow,
    this.buildList,
    this.asList = false,
  });

  final String title;
  final Future<List<T>> Function() future;
  final Widget Function(List<T>, BuildContext)? buildRow;
  final Widget Function(List<T>, BuildContext)? buildList;
  final bool asList;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future(),
      builder: (ctx, snap) {
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = asList
              ? const sp.SpListSkeleton(rows: 5)
              : const Padding(
                  padding: EdgeInsets.symmetric(horizontal: sp.Sp.pagePad),
                  child: Row(
                    children: [
                      sp.SpSkeleton(width: sp.Sp.cardCover, height: sp.Sp.cardCover),
                      SizedBox(width: sp.Sp.gapM),
                      sp.SpSkeleton(width: sp.Sp.cardCover, height: sp.Sp.cardCover),
                      SizedBox(width: sp.Sp.gapM),
                      sp.SpSkeleton(width: sp.Sp.cardCover, height: sp.Sp.cardCover),
                    ],
                  ),
                );
        } else if (snap.hasError) {
          body = sp.SpStateView(
            icon: Icons.error_outline,
            title: '加载失败',
            subtitle: '${snap.error}',
          );
        } else {
          final items = snap.data ?? const <T>[];
          if (items.isEmpty) {
            body = const sp.SpStateView(
                icon: Icons.inbox_outlined, title: '暂无内容');
          } else {
            body = (asList ? buildList : buildRow)!(items, ctx);
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sp.SpSectionHeader(title),
            body,
          ],
        );
      },
    );
  }
}
