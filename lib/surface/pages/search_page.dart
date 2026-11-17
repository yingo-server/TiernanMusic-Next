// L7 surface/pages · 搜索页（Spotify 深色 + M3）
// 只画控件；数据只经 bridge_logic 的 logic 单例取；颜色/字号/间距只用 Sp.*。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SearchType;
import '../../bridges/bridge_logic.dart'
    show Log, SearchResult, SongBrief, SearchSuggestItem;
import '../../bridges/bridge_session.dart'
    show NavState, PlaybackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens.dart' show Sp;
import 'search_tile_widgets.dart'
    show SearchSongTile, SearchEmptyBox, SearchErrorRetry;

const String _tag = 'surface.search';

/// 页面模块注册。
class SearchPageModule extends SurfaceModule {
  @override
  String get id => 'search';
  @override
  String get route => '/search';
  @override
  NavEntry? get navEntry => const NavEntry('搜索', 'search');
  @override
  bool get enabled => true;
  @override
  WidgetBuilder? get builder =>
      (BuildContext ctx) => const SearchPage();
}

/// 结果分段显示名。
const List<String> kSearchSegments = <String>['歌曲', '歌单', '专辑', '歌手', '歌词'];

/// 结果分段 → 六类分类搜索端点（SearchType）。
const List<SearchType> kSearchSegmentTypes = <SearchType>[
  SearchType.song,
  SearchType.special,
  SearchType.album,
  SearchType.author,
  SearchType.lyric,
];

/// 热门分类（前端关键词触发对应歌曲搜索；不臆造服务端分类端点）。
const List<String> kHotCategories = <String>[
  '华语',
  '流行',
  '摇滚',
  '民谣',
  '电子',
  '轻音乐',
  '古风',
  '情歌',
];

/// 搜索页：大胶囊搜索框 + 热门分类 + 历史记录 + 分段结果。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _ctrl = TextEditingController();
  final List<String> _history = <String>[];
  String _query = '';
  int _segment = 0;
  Future<SearchResult>? _resultF;
  Future<List<SearchSuggestItem>>? _suggestF;
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _doSearch(String kw) {
    final String q = kw.trim();
    if (q.isEmpty) return;
    try {
      final se = appGraph.search;
      final typed = appGraph.searchTyped;
      final SearchType type = kSearchSegmentTypes[_segment];
      setState(() {
        _query = q;
        _suggestF = null;
        _resultF = (_segment == 0)
            ? (se?.search(q, 1) ?? Future.value(const SearchResult()))
            : (typed?.typed(type, q, 1) ?? Future.value(const SearchResult()));
      });
      _history
        ..remove(q)
        ..insert(0, q);
      if (_history.length > 12) _history.removeLast();
    } catch (e, st) {
      Log.e(_tag, 'search failed kw=$q', e, st);
    }
  }

  void _clearHistory() => setState(_history.clear);
  void _onChanged(String text) {
    final String t = text.trim();
    if (t.isEmpty) {
      setState(() {
        _suggestF = null;
        _resultF = null;
        _query = '';
      });
      return;
    }
    try {
      final se = appGraph.search;
      setState(() {
        _suggestF =
            se?.suggestions(t) ?? Future.value(const <SearchSuggestItem>[]);
      });
    } catch (e, st) {
      Log.e(_tag, 'suggest failed', e, st);
    }
  }

  void _play(List<SongBrief> songs, int index) {
    try {
      PlaybackSession.instance.playAll(songs, index);
    } catch (e, st) {
      Log.e(_tag, 'playAll failed', e, st);
    }
  }

  void _openAlbum(String albumId) {
    if (albumId.isEmpty) return;
    try {
      NavState.instance.setAlbum(albumId);
    } catch (e, st) {
      Log.e(_tag, 'setAlbum failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cs.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _searchBar(context),
            _suggestBox(context),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Sp.pagePad,
        Sp.gapM,
        Sp.pagePad,
        Sp.gapS,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: Sp.gapM, right: Sp.gapS),
              decoration: BoxDecoration(
                color: context.cs.surfaceContainer,
                borderRadius: BorderRadius.circular(Sp.rFull),
                border: Border.all(color: context.cs.outlineVariant),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search, size: 20, color: context.cs.onSurfaceVariant),
                  const SizedBox(width: Sp.gapS),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: TextStyle(
                        fontSize: Sp.fItem,
                        color: context.cs.onSurface,
                      ),
                      cursorColor: context.cs.primary,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索歌曲、歌单、歌手',
                        hintStyle: TextStyle(
                          fontSize: Sp.fItem,
                          color: context.cs.onSurfaceVariant,
                        ),
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: _doSearch,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Sp.gapS),
          SizedBox(
            width: 44,
            height: 44,
            child: Material(
              color: context.cs.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _doSearch(_ctrl.text),
                child: const Icon(
                  Icons.arrow_forward,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestBox(BuildContext context) {
    final Future<List<SearchSuggestItem>>? f = _suggestF;
    if (f == null) return const SizedBox.shrink();
    return FutureBuilder<List<SearchSuggestItem>>(
      future: f,
      builder: (BuildContext c, AsyncSnapshot<List<SearchSuggestItem>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final List<SearchSuggestItem> items =
            snap.data ?? const <SearchSuggestItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 208,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
            itemCount: items.length,
            itemBuilder: (BuildContext c, int i) {
              final SearchSuggestItem it = items[i];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.history,
                  size: 18,
                  color: context.cs.onSurfaceVariant,
                ),
                title: Text(
                  it.keyword,
                  style: TextStyle(fontSize: Sp.fItem, color: context.cs.onSurface),
                ),
                onTap: () {
                  _ctrl.text = it.keyword;
                  _doSearch(it.keyword);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _body() {
    if (_resultF == null) return _idleBody();
    return Column(
      children: <Widget>[
        _segmentBar(),
        Expanded(child: _resultBody()),
      ],
    );
  }

  Widget _segmentBar() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
        itemCount: kSearchSegments.length,
        itemBuilder: (BuildContext c, int i) {
          final bool sel = i == _segment;
          return Padding(
            padding: const EdgeInsets.only(right: Sp.gapS, top: Sp.gapS),
            child: ChoiceChip(
              label: Text(
                kSearchSegments[i],
                style: TextStyle(
                  fontSize: Sp.fSub,
                  color: sel ? Colors.black : context.cs.onSurface,
                ),
              ),
              selected: sel,
              showCheckmark: false,
              backgroundColor: context.cs.surfaceContainer,
              selectedColor: context.cs.primary,
              side: BorderSide(color: context.cs.outlineVariant),
              onSelected: (_) {
                setState(() => _segment = i);
                if (_query.isNotEmpty) _doSearch(_query);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _idleBody() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Sp.gapXL),
      itemCount: 2,
      itemBuilder: (BuildContext c, int i) {
        if (i == 0) return _hotCategories();
        return _historySection();
      },
    );
  }

  Widget _hotCategories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(
            Sp.pagePad,
            Sp.gapL,
            Sp.pagePad,
            Sp.gapM,
          ),
          child: Text(
            '热门分类',
            style: TextStyle(
              fontSize: Sp.fSection,
              fontWeight: FontWeight.w700,
              color: context.cs.onSurface,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
          child: Wrap(
            spacing: Sp.gapS,
            runSpacing: Sp.gapS,
            children: <Widget>[
              for (final String name in kHotCategories)
                ActionChip(
                  label: Text(
                    name,
                    style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurface),
                  ),
                  backgroundColor: context.cs.surfaceContainer,
                  side: BorderSide(color: context.cs.outlineVariant),
                  onPressed: () {
                    _ctrl.text = name;
                    _doSearch(name);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _historySection() {
    if (_history.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(Sp.pagePad, Sp.gapXL, Sp.pagePad, 0),
        child: Text(
          '暂无搜索历史',
          style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Sp.pagePad,
            Sp.gapXL,
            Sp.pagePad,
            Sp.gapM,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                '历史记录',
                style: TextStyle(
                  fontSize: Sp.fSection,
                  fontWeight: FontWeight.w700,
                  color: context.cs.onSurface,
                ),
              ),
              TextButton(
                onPressed: _clearHistory,
                child: Text(
                  '清空',
                  style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
          child: Wrap(
            spacing: Sp.gapS,
            runSpacing: Sp.gapS,
            children: <Widget>[
              for (final String h in _history)
                ActionChip(
                  label: Text(
                    h,
                    style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurface),
                  ),
                  backgroundColor: context.cs.surfaceContainer,
                  side: BorderSide(color: context.cs.outlineVariant),
                  onPressed: () {
                    _ctrl.text = h;
                    _doSearch(h);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultBody() {
    final Future<SearchResult>? f = _resultF;
    if (f == null) return const SearchEmptyBox('暂无结果');
    return FutureBuilder<SearchResult>(
      future: f,
      builder: (BuildContext c, AsyncSnapshot<SearchResult> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: context.cs.primary),
          );
        }
        if (snap.hasError) {
          return SearchErrorRetry(
            message: '搜索失败',
            onRetry: () => _doSearch(_query),
          );
        }
        final SearchResult r = snap.data ?? const SearchResult();
        final List<SongBrief> items = r.items;
        if (items.isEmpty) {
          return SearchEmptyBox('没有找到与「$_query」相关的歌曲');
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: Sp.gapXL),
          itemCount: items.length,
          itemBuilder: (BuildContext c, int i) => SearchSongTile(
            song: items[i],
            onTap: () => _play(items, i),
            onAlbum: () => _openAlbum(items[i].albumId),
          ),
        );
      },
    );
  }
}

/// 歌曲行（SpSongTile 风格）：封面 + 名称 + 歌手 + 专辑跳转 + 播放。
