// L6 surface/pages · 搜索页（R3-C 拆出 SearchDetailPage）。综合三段：M3 SegmentedButton、独立缓存、翻页互不串扰。
// M3：颜色/文本/动效走 colorScheme/textTheme/TnMotionStaggered。
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../bridges/bridge_logic.dart' show SearchLogic, SearchSuggestItem, SearchResult, Log, LogicFacade, SearchTypedLogic;
import '../../bridges/bridge_core.dart' show SongBrief, SearchType, KeyValueSettings;
import '../player_controller.dart' show PlayerController;
import '../registry.dart';
import '../theme/tn_motion.dart' show TnMotionStaggered;
import '../theme/tn_theme.dart' show TnDims, tnPadS, tnPadL;
import '../widgets/common_widgets.dart' show SongTile;
import '../widgets/tn_app_bar.dart' show TnAppBar;
import 'search_detail_page.dart' show SearchDetailPage;
import 'search_home_view.dart' show SearchHomeView;
import 'search_tile_widgets.dart'
    show SongTileData, SearchSegmentState, searchCard, searchCardRow, searchLoadingSkeleton;
const String _tag = 'surface.search';
const int _kPageSize = 30;
class SearchPageModule implements SurfaceModule {
  SearchPageModule({required SearchLogic search, required PlayerController player,
      SearchTypedLogic? typed, KeyValueSettings? settings})
      : _search = search, _player = player, _typed = typed, _settings = settings;
  final SearchLogic _search; final PlayerController _player;
  final SearchTypedLogic? _typed; final KeyValueSettings? _settings;
  @override String get id => 'search';
  @override String get route => '/search';
  @override NavEntry? get navEntry => const NavEntry('搜索', 'search');
  @override bool enabled(LogicFacade logic) => true;
  @override WidgetBuilder builder(LogicFacade logic) {
    try { return (ctx) => _SearchPageBody(search: _search, player: _player, typed: _typed, settings: _settings); }
    catch (e, st) { Log.e(_tag, 'builder failed', e, st); return (ctx) => const SizedBox.shrink(); }
  }
}
class _SearchPageBody extends StatefulWidget {
  const _SearchPageBody({required this.search, required this.player, this.typed,
      this.settings});
  final SearchLogic search; final PlayerController player; final SearchTypedLogic? typed;
  final KeyValueSettings? settings;
  @override State<_SearchPageBody> createState() => _SearchPageBodyState();
}
class _SearchPageBodyState extends State<_SearchPageBody> {
  final TextEditingController _kwCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;
  List<SearchSuggestItem> _suggests = const <SearchSuggestItem>[];
  List<SearchSuggestItem> _hot = const <SearchSuggestItem>[];
  List<String> _history = <String>[];
  static const String _kHistoryKey = 'search.history';
  static const int _kHistoryMax = 10;
  final SearchSegmentState _legacy = SearchSegmentState(); // 分类 Tab / typed==null 旧链路
  bool _searching = false; String _committedKw = '';
  static const List<String> _kTypeLabels = <String>['歌曲', '歌单', '专辑', '歌手', 'MV', '歌词'];
  static const List<SearchType> _kTypes = <SearchType>[
    SearchType.song, SearchType.special, SearchType.album,
    SearchType.author, SearchType.mv, SearchType.lyric];
  static const List<SearchType> _kSegTypes = <SearchType>[
    SearchType.song, SearchType.special, SearchType.album];
  static const List<String> _kSegLabels = <String>['歌曲', '歌单', '专辑'];
  static const List<IconData> _kSegIcons = <IconData>[Icons.audiotrack, Icons.queue_music, Icons.album];
  int _tabIndex = 0; SearchType _segment = SearchType.song;
  final Map<SearchType, SearchSegmentState> _segments = <SearchType, SearchSegmentState>{
    for (final t in _kSegTypes) t: SearchSegmentState(),
  };
  @override void initState() {
    super.initState();
    try {
      _scrollCtrl.addListener(_onScroll);
      for (final t in _kSegTypes) { _segments[t]!.scroll.addListener(() => _onSegmentScroll(t)); }
      _loadHot();
      _loadHistory();
      Log.d(_tag, 'initState comprehensive=3 typed=${widget.typed != null}');
    } catch (e, st) { Log.e(_tag, 'initState failed', e, st); }
  }
  @override void dispose() {
    try {
      _debounce?.cancel(); _kwCtrl.dispose(); _scrollCtrl.dispose();
      _legacy.scroll.dispose();
      for (final s in _segments.values) { s.scroll.dispose(); }
      Log.d(_tag, 'dispose');
    } catch (e, st) { Log.e(_tag, 'dispose failed', e, st); }
    super.dispose();
  }
  Future<void> _loadHot() async {
    try { final hot = await widget.search.hotSearch();
      if (!mounted) return;
      setState(() => _hot = hot);
      Log.d(_tag, 'hot loaded n=${_hot.length}');
    } catch (e, st) { Log.e(_tag, 'loadHot failed', e, st); }
  }
  void _onChanged(String kw) {
    try {
      _debounce?.cancel();
      if (kw.trim().isEmpty) { setState(() => _suggests = const <SearchSuggestItem>[]); return; }
      _debounce = Timer(
          // 业务防抖节奏（300ms）：搜索输入防抖非动效时长，不属 TnMotion 三档，保留裸值。
          const Duration(milliseconds: 300), () async {
        try {
          final list = await widget.search.suggestions(kw);
          if (!mounted) return;
          setState(() => _suggests = list);
          Log.d(_tag, 'suggestions n=${list.length}');
        } catch (e, st) { Log.e(_tag, 'suggestions failed', e, st); }
      });
    } catch (e, st) { Log.e(_tag, 'onChanged failed', e, st); }
  }
  Future<void> _submit(String kw) async {
    try {
      final k = kw.trim();
      if (k.isEmpty || _searching) return;
      _recordHistory(k);
      setState(() {
        _searching = true; _committedKw = k;
        _legacy.reset(k);
        for (final s in _segments.values) { s.reset(k); }
        _suggests = const <SearchSuggestItem>[];
      });
      final typed = widget.typed;
      if (typed == null) {
        await _legacyFirst(k);
      } else if (_tabIndex == 0) {
        await Future.wait(<Future<void>>[for (final t in _kSegTypes) _segmentFirst(t, k)]);
        if (!mounted) return;
        setState(() => _searching = false);
        Log.d(_tag, 'comprehensive done kw=$k segments=3');
      } else {
        final res = await typed.typed(_kTypes[_tabIndex - 1], k, 1);
        if (!mounted) return;
        setState(() {
          _legacy.items = _toTiles(res); _legacy.total = res.total;
          _legacy.loaded = true; _legacy.more = _moreOf(_legacy, res.items.length);
          _searching = false;
        });
        Log.d(_tag, 'submit typed=${_kTypes[_tabIndex - 1].name} kw=$k');
      }
    } catch (e, st) {
      Log.e(_tag, 'submit failed kw=$kw', e, st);
      if (mounted) setState(() => _searching = false);
    }
  }
  Future<void> _legacyFirst(String k) async {
    try { final res = await widget.search.search(k, 1);
      if (!mounted) return;
      setState(() {
        _legacy.items = _toTiles(res); _legacy.total = res.total;
        _legacy.loaded = true; _legacy.more = _moreOf(_legacy, res.items.length);
        _searching = false;
      });
      Log.d(_tag, 'legacy first kw=$k got=${res.items.length}');
    } catch (e, st) {
      Log.e(_tag, 'legacyFirst failed kw=$k', e, st);
      if (mounted) setState(() => _searching = false);
    }
  }
  Future<void> _segmentFirst(SearchType type, String kw) async {
    try {
      final s = _segments[type]!;
      if (s.loaded || s.searching || s.loadingMore) return;
      setState(() => s.searching = true);
      final res = await widget.typed!.typed(type, kw, 1);
      if (!mounted || s.kw != kw || _committedKw != kw) return;
      setState(() {
        s.page = 1; s.total = res.total; s.items = _toTiles(res);
        s.loaded = true; s.searching = false; s.more = _moreOf(s, res.items.length);
      });
      Log.d(_tag, 'seg first type=${type.name} kw=$kw got=${s.items.length}');
    } catch (e, st) {
      Log.e(_tag, 'segFirst failed type=${type.name} kw=$kw', e, st);
      if (mounted) setState(() => _segments[type]!.searching = false);
    }
  }
  Future<void> _segmentMore(SearchType type) async {
    try {
      final s = _segments[type]!; final k = s.kw;
      if (k.isEmpty || !s.loaded || !s.more || s.loadingMore || s.searching) return;
      setState(() => s.loadingMore = true);
      final res = await widget.typed!.typed(type, k, s.page + 1);
      if (!mounted || s.kw != k || _committedKw != k) return;
      setState(() {
        s.page += 1;
        s.items = <SongTileData>[...s.items, ..._toTiles(res)];
        s.loadingMore = false; s.more = _moreOf(s, res.items.length);
      });
      Log.d(_tag, 'seg more type=${type.name} kw=$k page=${s.page}');
    } catch (e, st) {
      Log.e(_tag, 'segMore failed type=${type.name}', e, st);
      if (mounted) setState(() => _segments[type]!.loadingMore = false);
    }
  }
  Future<void> _loadMore() async {
    try {
      final k = _committedKw; final s = _legacy;
      if (k.isEmpty || s.loadingMore || _searching || !s.more) return;
      setState(() => s.loadingMore = true);
      final typed = widget.typed;
      final res = (typed != null && _tabIndex > 0)
          ? await typed.typed(_kTypes[_tabIndex - 1], k, s.page + 1)
          : await widget.search.search(k, s.page + 1);
      if (!mounted) return;
      setState(() {
        s.page += 1;
        s.items = <SongTileData>[...s.items, ..._toTiles(res)];
        s.loadingMore = false; s.more = _moreOf(s, res.items.length);
      });
      Log.d(_tag, 'loadMore kw=$k page=${s.page} got=${res.items.length}');
    } catch (e, st) {
      Log.e(_tag, 'loadMore failed', e, st);
      if (mounted) setState(() => _legacy.loadingMore = false);
    }
  }
  bool _moreOf(SearchSegmentState s, int fetched) {
    try { return fetched >= _kPageSize && (s.total <= 0 || s.items.length < s.total); }
    catch (e, st) { Log.e(_tag, 'moreOf failed', e, st); return false; }
  }
  void _onSegmentChanged(Set<SearchType> selected) {
    try {
      if (selected.isEmpty) return;
      final t = selected.first;
      setState(() => _segment = t);
      if (_committedKw.isNotEmpty && !_segments[t]!.loaded) { _segmentFirst(t, _committedKw); }
      Log.d(_tag, 'segment switch type=${t.name} loaded=${_segments[t]!.loaded}');
    } catch (e, st) { Log.e(_tag, 'segment switch failed', e, st); }
  }
  void _onTab(int i) {
    try {
      setState(() => _tabIndex = i);
      if (_committedKw.isNotEmpty) _submit(_committedKw);
      Log.d(_tag, 'tab switch index=$i');
    } catch (e, st) { Log.e(_tag, 'tab switch failed', e, st); }
  }
  void _onSegmentScroll(SearchType type) {
    try { _autoMore(_segments[type]!.scroll, () => _segmentMore(type)); }
    catch (e, st) { Log.e(_tag, 'segment scroll failed type=${type.name}', e, st); }
  }
  void _onScroll() {
    try { _autoMore(_scrollCtrl, _loadMore); }
    catch (e, st) { Log.e(_tag, 'onScroll failed', e, st); }
  }
  void _autoMore(ScrollController c, VoidCallback load) {
    try { if (c.hasClients && c.position.pixels >= c.position.maxScrollExtent - 200) load(); }
    catch (e, st) { Log.e(_tag, 'autoMore failed', e, st); }
  }
  List<SongTileData> _toTiles(SearchResult res) {
    try { return <SongTileData>[for (final s in res.items) SongTileData(s)]; }
    catch (e, st) { Log.e(_tag, 'toTiles failed', e, st); return const <SongTileData>[]; }
  }
  void _play(SongTileData d) {
    try { widget.player.playSong(d.song); Log.d(_tag, 'play ${d.song.hash}'); }
    catch (e, st) { Log.e(_tag, 'play failed', e, st); }
  }
  void _drillDown(SongTileData d, SearchType type) {
    try {
      if (type == SearchType.song) {
        if (d.song.name.isEmpty) return;
        _kwCtrl.text = d.song.name; _submit(d.song.name);
        Log.d(_tag, 'drillDown type=${type.name} kw=${d.song.name}');
        return;
      }
      // 歌单/专辑行 → 详情页导航（Navigator + injected deps，模块间零直接 import）。
      final id = type == SearchType.special
          ? '${d.song.mixSongId}' : d.song.albumId;
      if (id.isEmpty || id == '0') return;
      final nav = Navigator.of(context);
      nav.push(MaterialPageRoute<void>(
        builder: (_) => SearchDetailPage(
          title: d.song.name, kind: type, refId: id,
          player: widget.player, typed: widget.typed),
      ));
      Log.d(_tag, 'open detail type=${type.name} id=$id');
    } catch (e, st) { Log.e(_tag, 'drillDown failed type=${type.name}', e, st); }
  }
  @override Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      return DefaultTabController(length: 7, child: Scaffold(
        backgroundColor: cs.surface,
        appBar: TnAppBar(title: '搜索', bottom: widget.typed == null ? null : TabBar(
          isScrollable: true, indicatorColor: cs.primary, labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: <Widget>[const Tab(text: '综合'),
            for (final label in _kTypeLabels) Tab(text: label)],
          onTap: _onTab)),
        body: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(tnPadL, tnPadS, tnPadL, tnPadS),
            child: TextField(
              controller: _kwCtrl, onChanged: _onChanged, onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
              decoration: InputDecoration(
                hintText: '搜歌曲 / 歌手 / 专辑',
                hintStyle: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _kwCtrl.text.isEmpty ? null : IconButton(
                  icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                  onPressed: () {
                    try { _kwCtrl.clear(); _onChanged(''); }
                    catch (e, st) { Log.e(_tag, 'clear failed', e, st); }
                  }),
                filled: true, fillColor: cs.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: tnPadL, vertical: tnPadS),
                border: OutlineInputBorder(borderRadius: TnDims.rLBorder, borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: TnDims.rLBorder,
                    borderSide: BorderSide(color: cs.primary, width: 2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: tnPadL),
            child: Wrap(spacing: tnPadS, runSpacing: tnPadS, children: <Widget>[
              for (final s in _suggests) Builder(builder: (ctx) {
                try {
                  final chipCs = Theme.of(ctx).colorScheme;
                  return FilterChip(selected: false,
                    avatar: Icon(Icons.trending_up, size: TnDims.iconS, color: chipCs.primary),
                    label: Text(s.keyword, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onSelected: (_) {
                      try { _kwCtrl.text = s.keyword; _submit(s.keyword); }
                      catch (e, st) { Log.e(_tag, 'suggest tap failed', e, st); }
                    });
                } catch (e, st) {
                  Log.e(_tag, 'suggest chip build failed', e, st);
                  return const SizedBox.shrink();
                }
              }),
            ]),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(child: _buildBody()),
        ]),
      ));
    } catch (e, st) {
      Log.e(_tag, 'build crashed', e, st);
      return const SizedBox.shrink();
    }
  }
  Widget _buildBody() {
    try {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      if (_committedKw.isEmpty) return _buildHot();
      if (widget.typed != null && _tabIndex == 0) return _buildComprehensive();
      if (_searching && _legacy.items.isEmpty) return _progress(cs);
      if (_legacy.items.isEmpty) {
        return Center(child: Text('没有找到「$_committedKw」相关结果',
            style: tt.titleMedium?.copyWith(color: cs.onSurface)));
      }
      final type = (widget.typed != null && _tabIndex > 0)
          ? _kTypes[_tabIndex - 1] : SearchType.song;
      return _buildList(_legacy, type, _scrollCtrl, '上拉加载更多');
    } catch (e, st) {
      Log.e(_tag, 'buildBody crashed', e, st);
      return const SizedBox.shrink();
    }
  }
  Widget _progress(ColorScheme cs) {
    try { return Padding(padding: const EdgeInsets.all(tnPadL),
      child: LinearProgressIndicator(color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest));
    } catch (e, st) { Log.e(_tag, 'progress crashed', e, st); return const SizedBox.shrink(); }
  }
  void _loadHistory() {
    try {
      final raw = widget.settings?.getString(_kHistoryKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = <String>[for (final e in decoded) if (e is String && e.trim().isNotEmpty) e.trim()];
        if (mounted) setState(() => _history = list.take(_kHistoryMax).toList());
      }
    } catch (e, st) {
      Log.e(_tag, 'loadHistory failed', e, st);
    }
  }

  void _saveHistory() {
    try {
      widget.settings?.setString(_kHistoryKey, jsonEncode(_history));
    } catch (e, st) {
      Log.e(_tag, 'saveHistory failed', e, st);
    }
  }

  void _recordHistory(String kw) {
    try {
      final k = kw.trim();
      if (k.isEmpty) return;
      final next = <String>[k, ..._history.where((e) => e != k)];
      setState(() => _history = next.take(_kHistoryMax).toList());
      _saveHistory();
    } catch (e, st) {
      Log.e(_tag, 'recordHistory failed', e, st);
    }
  }

  void _removeHistory(String kw) {
    try {
      setState(() => _history = _history.where((e) => e != kw).toList());
      _saveHistory();
    } catch (e, st) {
      Log.e(_tag, 'removeHistory failed', e, st);
    }
  }

  void _clearHistory() {
    try {
      setState(() => _history = <String>[]);
      _saveHistory();
    } catch (e, st) {
      Log.e(_tag, 'clearHistory failed', e, st);
    }
  }

  Widget _buildHot() {
    try {
      return SearchHomeView(
        history: _history,
        hot: _hot,
        onPick: (kw) {
          try {
            _kwCtrl.text = kw;
            _submit(kw);
          } catch (e, st) {
            Log.e(_tag, 'hot pick failed', e, st);
          }
        },
        onRemoveHistory: _removeHistory,
        onClearHistory: _clearHistory,
      );
    } catch (e, st) {
      Log.e(_tag, 'buildHot crashed', e, st);
      return const SizedBox.shrink();
    }
  }
  Widget _buildComprehensive() {
    try {
      return Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(tnPadL, tnPadS, tnPadL, tnPadS),
          child: SegmentedButton<SearchType>(
            segments: <ButtonSegment<SearchType>>[
              for (var i = 0; i < _kSegTypes.length; i++)
                ButtonSegment<SearchType>(value: _kSegTypes[i],
                    label: Text(_kSegLabels[i]), icon: Icon(_kSegIcons[i])),
            ],
            selected: <SearchType>{_segment},
            onSelectionChanged: _onSegmentChanged,
          ),
        ),
        Expanded(child: _buildSegmentList(_segment)),
      ]);
    } catch (e, st) { Log.e(_tag, 'buildComprehensive crashed', e, st); return const SizedBox.shrink(); }
  }
  Widget _buildSegmentList(SearchType type) {
    try {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      final s = _segments[type]!;
      if (s.searching && s.items.isEmpty) return _progress(cs);
      if (s.items.isEmpty) { return Center(child: Text(
          '该分类没有找到「$_committedKw」相关结果',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))); }
      return _buildList(s, type, s.scroll, s.more ? '上拉加载更多' : '没有更多了');
    } catch (e, st) {
      Log.e(_tag, 'buildSegmentList crashed type=${type.name}', e, st);
      return const SizedBox.shrink();
    }
  }
  Widget _buildList(SearchSegmentState s, SearchType type, ScrollController scroll, String footer) {
    try {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      return ListView.builder(controller: scroll, itemCount: s.items.length + 1,
        itemBuilder: (ctx, i) {
          try {
            if (i == s.items.length) {
              final busy = s.loadingMore || s.searching || _searching;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: tnPadL),
                child: Center(
                    child: busy
                        ? searchLoadingSkeleton()
                        : Text(footer,
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant))));
            }
            return searchCardRow(ctx, s.items[i], i, type,
                onPlay: _play, onDrill: _drillDown);
          } catch (e, st) {
            Log.e(_tag, 'list row failed type=${type.name}', e, st);
            return const SizedBox.shrink();
          }
        });
    } catch (e, st) {
      Log.e(_tag, 'buildList crashed type=${type.name}', e, st);
      return const SizedBox.shrink();
    }
  }
}
