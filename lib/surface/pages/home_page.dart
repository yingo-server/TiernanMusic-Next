// L6 surface/pages · 首页聚合模块（功能对齐批5-C · FEATURE_PARITY「首页聚合」）
// 装配方式：assembly 经 buildHomeModule(...) 构造后 SurfaceRegistry.install
//（id='home', route='/home', navEntry('首页','home')）；deps 注入四个 logic
//（Recommend/Rank/Search/Playlist）+ onPlay/onOpenSearch 回调，模块间零直接
// import。四区块统一经 _FutureBlock 三态壳（加载/空/数据），各自 try/catch+Log
// 留痕互不拖垮；仅经 bridge_logic/bridge_core 引下层，播放经回调交控制器。

import 'package:flutter/material.dart';
import '../../bridges/bridge_logic.dart'
    show LogicFacade, Log, RankLogic, RankBrief, PlaylistLogic, PlaylistBrief,
        RecommendLogic, SearchLogic, SongBrief;
import '../registry.dart';
import '../theme/tn_motion.dart' show TnMotionStaggered;
import '../theme/tn_theme.dart' show TnDims, TnColors, tnPadS, tnPadM, tnPadL;
import '../widgets/tn_app_bar.dart' show TnAppBar;

const String _tag = 'surface.home';

/// 工厂：由装配层调用（主会话 assembly），返回可热插拔的首页模块。
SurfaceModule buildHomeModule({
  required RecommendLogic recommend,
  required RankLogic rank,
  required SearchLogic search,
  required PlaylistLogic playlist,
  required void Function(SongBrief) onPlay,
  required void Function() onOpenSearch,
}) =>
    HomePageModule(
      recommend: recommend,
      rank: rank,
      search: search,
      playlist: playlist,
      onPlay: onPlay,
      onOpenSearch: onOpenSearch,
    );
/// 首页模块。
class HomePageModule implements SurfaceModule {
  HomePageModule({
    required RecommendLogic recommend,
    required RankLogic rank,
    required SearchLogic search,
    required PlaylistLogic playlist,
    required void Function(SongBrief) onPlay,
    required void Function() onOpenSearch,
  })  : _recommend = recommend,
        _rank = rank,
        _search = search,
        _playlist = playlist,
        _onPlay = onPlay,
        _onOpenSearch = onOpenSearch;
  final RecommendLogic _recommend;
  final RankLogic _rank;
  final SearchLogic _search;
  final PlaylistLogic _playlist;
  final void Function(SongBrief) _onPlay;
  final void Function() _onOpenSearch;
  @override
  String get id => 'home';
  @override
  String get route => '/home';
  @override
  NavEntry? get navEntry => const NavEntry('首页', 'home');
  @override
  bool enabled(LogicFacade logic) => true;
  @override
  WidgetBuilder builder(LogicFacade logic) => (ctx) => _HomePageBody(
      recommend: _recommend, rank: _rank, search: _search,
      playlist: _playlist, onPlay: _onPlay, onOpenSearch: _onOpenSearch);
}
class _HomePageBody extends StatelessWidget {
  const _HomePageBody({
    required this.recommend, required this.rank, required this.search,
    required this.playlist, required this.onPlay,
    required this.onOpenSearch});
  final RecommendLogic recommend;
  final RankLogic rank;
  final SearchLogic search;
  final PlaylistLogic playlist;
  final void Function(SongBrief) onPlay;
  final void Function() onOpenSearch;
  void _safe(void Function() f, String what) {
    try {
      f();
    } catch (e, st) {
      Log.e(_tag, '$what failed', e, st);
    }
  }
  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: TnAppBar(title: '首页',
          actions: <Widget>[IconButton(icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () => _safe(onOpenSearch, 'onOpenSearch'))]),
        body: ListView(padding: const EdgeInsets.only(bottom: TnDims.padXL),
            children: <Widget>[
          _SearchEntry(onTap: () => _safe(onOpenSearch, 'searchEntry')),
          _SectionTitle('每日推荐'),
          _FutureBlock<List<SongBrief>>(
            load: () async {
              try { return await recommend.daily(1, pageSize: 5); }
              catch (e, st) {
                Log.e(_tag, 'daily load failed', e, st);
                return const <SongBrief>[];
              }
            },
            empty: '今日暂无推荐',
            builder: (items) => Column(children: <Widget>[
              // 列表项交错入场（TnMotionStaggered，30ms/项，封顶 6）；
              // 其余区块（榜单速览/热搜词/推荐歌单）同法可套。
              for (var i = 0; i < items.length; i++)
                TnMotionStaggered(
                  index: i,
                  child: ListTile(dense: true,
                  leading: Text('${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  title: Text(items[i].name, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(items[i].singer, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () => _safe(() => onPlay(items[i]), 'daily play'),
                ))]),
          ),
          _SectionTitle('榜单速览'),
          _FutureBlock<List<RankBrief>>(
            load: () async {
              try {
                final all = await rank.rankList();
                return all.take(6).toList(growable: false);
              } catch (e, st) {
                Log.e(_tag, 'rank load failed', e, st);
                return const <RankBrief>[];
              }
            },
            empty: '暂无榜单',
            builder: (items) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: tnPadL),
              child: GridView.count(crossAxisCount: 3, shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: tnPadS, crossAxisSpacing: tnPadS,
                childAspectRatio: 1.4,
                children: <Widget>[
                  for (final r in items)
                    Container(alignment: Alignment.center,
                      padding: const EdgeInsets.all(TnDims.padXS),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(tnRadiusS)),
                      child: Text(r.name, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center)),
                ])),
          ),
          _SectionTitle('热搜词'),
          _FutureBlock<List<String>>(
            load: () async {
              try {
                final all = await search.hotSearch();
                return <String>[for (final h in all.take(10))
                  if (h.keyword.isNotEmpty) h.keyword];
              } catch (e, st) {
                Log.e(_tag, 'hot load failed', e, st);
                return const <String>[];
              }
            },
            empty: '暂无热搜',
            builder: (words) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: tnPadL),
              child: Wrap(
                spacing: tnPadS, runSpacing: tnPadS,
                children: <Widget>[
                  for (final w in words)
                    ActionChip(
                      label: Text(w, overflow: TextOverflow.ellipsis),
                      onPressed: () =>
                          _safe(() => onOpenSearch(), 'hot chip kw=$w'),
                    ),
                ],
              ),
            ),
          ),
          _SectionTitle('推荐歌单'),
          _FutureBlock<List<PlaylistBrief>>(
            load: () async {
              try { return await playlist.recommend(1, pageSize: 6); }
              catch (e, st) {
                Log.e(_tag, 'playlist load failed', e, st);
                return const <PlaylistBrief>[];
              }
            },
            empty: '暂无推荐歌单',
            builder: (items) => SizedBox(height: 160,
              child: ListView.separated(scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: tnPadL),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final p = items[i];
                  return SizedBox(width: TnDims.coverS, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(tnRadiusS),
                          child: p.cover.isNotEmpty
                              ? Image.network(
                                  p.cover,
                                  width: TnDims.coverS,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
                                )
                              : const ColoredBox(
                                  color: TnColors.placeholder,
                                  child: Icon(Icons.music_note),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(p.name, maxLines: 1,
                          overflow: TextOverflow.ellipsis)]));
                },
              ),
            ),
          ),
        ]),
      );
    } catch (e, st) {
      Log.e(_tag, 'build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});
  final void Function() onTap;
  @override
  Widget build(BuildContext context) {
    try {
      return Padding(padding: const EdgeInsets.fromLTRB(tnPadL, tnPadM, tnPadL, TnDims.padXS),
        child: InkWell(borderRadius: BorderRadius.circular(TnDims.padXL), onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: tnPadL, vertical: tnPadM),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(TnDims.padXL)),
            child: const Row(children: <Widget>[
              Icon(Icons.search, size: 20),
              SizedBox(width: tnPadS),
              Expanded(child: Text('搜索歌曲 / 歌手 / 专辑 / MV')),
            ]))));
    } catch (e, st) {
      Log.e(_tag, 'searchEntry build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(tnPadL, tnPadL, tnPadL, TnDims.padXS),
      child: Text(title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)));
}
/// 区块通用 FutureBuilder 三态壳：加载圈 / 空态 / 数据构建，互不拖垮。
class _FutureBlock<T> extends StatelessWidget {
  const _FutureBlock(
      {required this.load, required this.empty, required this.builder});
  final Future<T> Function() load;
  final String empty;
  final Widget Function(T data) builder;
  @override
  Widget build(BuildContext context) {
    try {
      return FutureBuilder<T>(
        future: load(),
        builder: (ctx, snap) {
          try {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(tnPadL),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)));
            }
            if (snap.hasError) {
              Log.e(_tag, 'block error $empty', snap.error!, StackTrace.current);
              return _placeholder(empty);
            }
            final d = snap.data;
            if (d == null || (d is List && d.isEmpty)) {
              return _placeholder(empty);
            }
            return builder(d);
          } catch (e, st) {
            Log.e(_tag, 'block build failed $empty', e, st);
            return _placeholder(empty);
          }
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'block crashed $empty', e, st);
      return _placeholder(empty);
    }
  }
}
Widget _placeholder(String msg) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: tnPadL, vertical: tnPadS),
      child: Text(msg, style: const TextStyle(color: TnColors.placeholder)),
    );
