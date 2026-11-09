// L6 surface/pages · 搜索页模块（SurfaceModule 热插拔）
// 搜索框 onChanged 防抖 300ms 调 suggestions + hotSearch 空态；
// 提交调 search(keyword, page)，列表滚动到底自动翻页；
// 点击结果经注入的 PlayerController 回调 playSong(SongBrief)。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show SearchLogic, SearchSuggestItem, SearchResult, Log;
import '../../bridges/bridge_core.dart' show SongBrief;
import '../player_controller.dart' show PlayerController;
import '../registry.dart';
import '../widgets/common_widgets.dart' show SongTile;

const String _tag = 'surface.search';

/// 搜索页模块。deps 注入 SearchLogic 与 PlayerController 工厂。
class SearchPageModule implements SurfaceModule {
  SearchPageModule({required SearchLogic search, required PlayerController player})
      : _search = search,
        _player = player;

  final SearchLogic _search;
  final PlayerController _player;

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
      );
}

class _SearchPageBody extends StatefulWidget {
  const _SearchPageBody({required this.search, required this.player});

  final SearchLogic search;
  final PlayerController player;

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

  /// 提交搜索：重置到第 1 页。
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
      final res = await widget.search.search(k, 1);
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
      final res = await widget.search.search(k, _page + 1);
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
        appBar: AppBar(title: const Text('搜索')),
        body: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
                leading: const Icon(Icons.trending_up, size: 18),
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
          const SizedBox(height: 8),
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
              padding: const EdgeInsets.symmetric(vertical: 16),
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
          return SongTile(song: d.song, onPlay: _play, index: i + 1);
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
