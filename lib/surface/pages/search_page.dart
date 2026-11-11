// L6 surface/pages · 搜索页模块（SurfaceModule 热插拔）
// 搜索框 onChanged 防抖 300ms 调 suggestions + hotSearch 空态；
// 提交调 search(keyword, page)，列表滚动到底自动翻页；
// 点击结果经注入的 PlayerController 回调 playSong(SongBrief)。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show SearchLogic, SearchSuggestItem, SearchResult, Log, LogicFacade, SearchTypedLogic;
import '../../bridges/bridge_core.dart' show SongBrief, SearchType;
import '../player_controller.dart' show PlayerController;
import '../registry.dart';
import '../widgets/common_widgets.dart' show SongTile;
import '../theme/tn_theme.dart' show TnDims, tnPadM, tnPadS;

const String _tag = 'surface.search';

/// 搜索页模块。deps 注入 SearchLogic 与 PlayerController 工厂。
class SearchPageModule implements SurfaceModule {
  SearchPageModule({required SearchLogic search, required PlayerController player,
      SearchTypedLogic? typed})
      : _search = search,
        _player = player,
        _typed = typed;

  final SearchLogic _search;
  final PlayerController _player;

  /// 可选六类分类搜索门面（批6-B）；为空时保持原单类型搜索（向后兼容）。
  final SearchTypedLogic? _typed;

  @override
  String get id => 'search';

  @override
  String get route => '/search';

  @override
  NavEntry? get navEntry => const NavEntry('搜索', 'search');

  @override
  bool enabled(LogicFacade logic) => true;

  @override
  WidgetBuilder builder(LogicFacade logic) => (ctx) => _SearchPageBody(
        search: _search,
        player: _player,
        typed: _typed,
      );
}

class _SearchPageBody extends StatefulWidget {
  const _SearchPageBody(
      {required this.search, required this.player, this.typed});

  final SearchLogic search;
  final PlayerController player;

  /// 可选六类分类搜索；为空时 Tab 栏不渲染，行为与旧版一致。
  final SearchTypedLogic? typed;

  @override
  State<_SearchPageBody> createState() => _SearchPageBodyState();
}

class _SearchPageBodyState extends State<_SearchPageBody> {
  final TextEditingController _kwCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  Timer? _debounce;
  List<SearchSuggestItem> _suggests = const <SearchSuggestItem>[];
  List<SearchSuggestItem> _hot = const <SearchSuggestItem>[];
  List<SongTileData> _results = const <SongTileData>[];
  int _page = 1;
  int _total = 0;
  bool _searching = false;
  bool _loadingMore = false;
  String _committedKw = '';

  /// 批6-B 六类 Tab：null=未启用（typed 未注入或 song Tab 退回旧链路）。
  /// 语义：歌曲→SearchType.song（v3），歌单→special，专辑→album，
  /// 歌手→author，MV→mv，歌词→lyric（v1，KUGOU_API.md §3.1）。
  static const List<SearchType> _kTypes = <SearchType>[
    SearchType.song, SearchType.special, SearchType.album,
    SearchType.author, SearchType.mv, SearchType.lyric,
  ];
  static const List<String> _kTypeLabels = <String>[
    '歌曲', '歌单', '专辑', '歌手', 'MV', '歌词',
  ];
  int? _typeIndex;

  @override
  void initState() {
    super.initState();
    try {
      _scrollCtrl.addListener(_onScroll);
      _loadHot();
      Log.d(_tag, 'initState');
    } catch (e, st) {
      Log.e(_tag, 'initState failed', e, st);
    }
  }

  @override
  void dispose() {
    try {
      _debounce?.cancel();
      _kwCtrl.dispose();
      _scrollCtrl.dispose();
      Log.d(_tag, 'dispose');
    } catch (e, st) {
      Log.e(_tag, 'dispose failed', e, st);
    }
    super.dispose();
  }

  Future<void> _loadHot() async {
    try {
      final hot = await widget.search.hotSearch();
      if (!mounted) return;
      setState(() => _hot = hot);
    } catch (e, st) {
      Log.e(_tag, 'loadHot failed', e, st);
    }
  }

  /// 输入防抖 300ms → suggestions。
  void _onChanged(String kw) {
    try {
      _debounce?.cancel();
      if (kw.trim().isEmpty) {
        setState(() => _suggests = const <SearchSuggestItem>[]);
        return;
      }
      // 自定义时长说明：防抖间隔 300ms 非动效时长，不属 TnMotion 三档，保留裸值。
      _debounce = Timer(const Duration(milliseconds: 300), () async {
        try {
          final list = await widget.search.suggestions(kw);
          if (!mounted) return;
          setState(() => _suggests = list);
        } catch (e, st) {
          Log.e(_tag, 'suggestions failed', e, st);
        }
      });
    } catch (e, st) {
      Log.e(_tag, 'onChanged failed', e, st);
    }
  }

  /// 提交搜索：重置到第 1 页（批6-B：typed 注入时按当前 Tab 分类搜）。
  Future<void> _submit(String kw) async {
    try {
      final k = kw.trim();
      if (k.isEmpty || _searching) return;
      setState(() {
        _searching = true;
        _committedKw = k;
        _page = 1;
        _results = const <SongTileData>[];
        _total = 0;
        _suggests = const <SearchSuggestItem>[];
      });
      final typed = widget.typed;
      final res = (typed != null && _typeIndex != null)
          ? await typed.typed(_kTypes[_typeIndex!], k, 1)
          : await widget.search.search(k, 1);
      if (!mounted) return;
      setState(() {
        _results = _toTiles(res);
        _total = res.total;
        _searching = false;
      });
      Log.d(_tag, 'submit kw=$k got=${res.items.length}/${res.total}');
    } catch (e, st) {
      Log.e(_tag, 'submit failed kw=$kw', e, st);
      if (mounted) setState(() => _searching = false);
    }
  }

  /// 滚动到底自动翻页。
  void _onScroll() {
    try {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (pos.pixels < pos.maxScrollExtent - 200) return;
      _loadMore();
    } catch (e, st) {
      Log.e(_tag, 'onScroll failed', e, st);
    }
  }

  Future<void> _loadMore() async {
    try {
      final k = _committedKw;
      if (k.isEmpty || _loadingMore || _searching) return;
      if (_total > 0 && _results.length >= _total) return;
      setState(() => _loadingMore = true);
      final typed = widget.typed;
      final res = (typed != null && _typeIndex != null)
          ? await typed.typed(_kTypes[_typeIndex!], k, _page + 1)
          : await widget.search.search(k, _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _results = <SongTileData>[..._results, ..._toTiles(res)];
        _loadingMore = false;
      });
      Log.d(_tag, 'loadMore kw=$k page=$_page got=${res.items.length}');
    } catch (e, st) {
      Log.e(_tag, 'loadMore failed', e, st);
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<SongTileData> _toTiles(SearchResult res) =>
      <SongTileData>[for (final s in res.items) SongTileData(s)];

  void _play(SongTileData d) {
    try {
      widget.player.playSong(d.song);
      Log.d(_tag, 'play ${d.song.hash}');
    } catch (e, st) {
      Log.e(_tag, 'play failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: TnAppBar(
          title: '搜索',
          bottom: widget.typed == null
              ? null
              : TabBar(
                  isScrollable: true,
                  tabs: <Widget>[
                    for (final label in _kTypeLabels) Tab(text: label),
                  ],
                  onTap: (i) {
                    try {
                      setState(() {
                        _typeIndex = i;
                        _results = const <SongTileData>[];
                        _total = 0;
                        _page = 1;
                      });
                      if (_committedKw.isNotEmpty) _submit(_committedKw);
                      Log.d(_tag, 'tab switch type=${_kTypes[i].name}');
                    } catch (e, st) {
                      Log.e(_tag, 'tab switch failed', e, st);
                    }
                  },
                ),
        ),
        body: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(tnPadM, tnPadS, tnPadM, TnDims.padXS),
            child: TextField(
              controller: _kwCtrl,
              onChanged: _onChanged,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜歌曲 / 歌手 / 专辑',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _kwCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _kwCtrl.clear();
                          _onChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          ..._suggests.map((s) => ListTile(
                dense: true,
                leading: const Icon(Icons.trending_up, size: TnDims.iconS),
                title: Text(s.keyword, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  _kwCtrl.text = s.keyword;
                  _submit(s.keyword);
                },
              )),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ]),
      );
    } catch (e, st) {
      Log.e(_tag, 'build crashed', e, st);
      return const SizedBox.shrink();
    }
  }

  Widget _buildBody() {
    try {
      // 空态：热搜榜
      if (_committedKw.isEmpty) {
        if (_hot.isEmpty) {
          return const Center(child: Text('暂无热搜'));
        }
        return ListView.builder(
          controller: _scrollCtrl,
          itemCount: _hot.length,
          itemBuilder: (ctx, i) {
            final h = _hot[i];
            return ListTile(
              dense: true,
              leading: Text('${i + 1}',
                  style: TextStyle(
                      color: i < 3 ? Colors.red : Theme.of(ctx).hintColor,
                      fontWeight: FontWeight.bold)),
              title: Text(h.keyword, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                _kwCtrl.text = h.keyword;
                _submit(h.keyword);
              },
            );
          },
        );
      }
      // 搜索中首屏
      if (_searching && _results.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      // 无结果
      if (_results.isEmpty) {
        return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.search_off, size: 48),
          const SizedBox(height: tnPadS),
          Text('没有找到「$_committedKw」相关结果'),
        ]));
      }
      // 结果列表 + 分页加载
      final count = _results.length + 1;
      return ListView.builder(
        controller: _scrollCtrl,
        itemCount: count,
        itemBuilder: (ctx, i) {
          if (i == _results.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: tnPadL),
              child: Center(
                child: _loadingMore || _searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('上拉加载更多'),
              ),
            );
          }
          final d = _results[i];
          return SongTile(song: d.song, onPlay: (s) => _play(d), index: i + 1);
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'buildBody crashed', e, st);
      return const SizedBox.shrink();
    }
  }
}

/// 列表项包装（便于 append 分页去重扩展）。
class SongTileData {
  const SongTileData(this.song);
  final SongBrief song;
}
