// L7 surface/pages · 搜索页（Spotify 深色 + M3）
// 只画控件；数据只经 bridge_logic 的 logic 单例取；颜色/字号/间距只用 Sp.*。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show Log, SearchResult, SongBrief, SearchSuggestItem;
import '../../bridges/bridge_session.dart'
    show NavState, PlaybackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens.dart' show Sp;

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
  WidgetBuilder? get builder => (BuildContext ctx) => const SearchPage();
}

/// 结果分段：仅「歌曲」在当前 logic 层有可用端点，其余分段给空态说明。
const List<String> kSearchSegments = <String>['歌曲', '歌单', '专辑', '歌手', '歌词'];

/// 热门分类（前端关键词触发对应歌曲搜索；不臆造服务端分类端点）。
const List<String> kHotCategories = <String>[
  '华语', '流行', '摇滚', '民谣', '电子', '轻音乐', '古风', '情歌',
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
      setState(() {
        _query = q;
        _suggestF = null;
        _resultF = se?.search(q, 1) ?? Future.value(const SearchResult());
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
      backgroundColor: Sp.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[_searchBar(), _suggestBox(), Expanded(child: _body())],
        ),
      ),
    );
  }
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.pagePad, Sp.gapM, Sp.pagePad, Sp.gapS),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: Sp.gapM, right: Sp.gapS),
              decoration: BoxDecoration(
                color: Sp.card,
                borderRadius: BorderRadius.circular(Sp.rFull),
                border: Border.all(color: Sp.divider),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.search, size: 20, color: Sp.textSub),
                  const SizedBox(width: Sp.gapS),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(fontSize: Sp.fItem, color: Sp.text),
                      cursorColor: Sp.green,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索歌曲、歌单、歌手',
                        hintStyle:
                            TextStyle(fontSize: Sp.fItem, color: Sp.textFaint),
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
              color: Sp.green,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _doSearch(_ctrl.text),
                child:
                    const Icon(Icons.arrow_forward, size: 20, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _suggestBox() {
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
                leading:
                    const Icon(Icons.history, size: 18, color: Sp.textFaint),
                title: Text(it.keyword,
                    style:
                        const TextStyle(fontSize: Sp.fItem, color: Sp.text)),
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
      children: <Widget>[_segmentBar(), Expanded(child: _resultBody())],
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
              label: Text(kSearchSegments[i],
                  style: TextStyle(
                      fontSize: Sp.fSub, color: sel ? Colors.black : Sp.text)),
              selected: sel,
              showCheckmark: false,
              backgroundColor: Sp.card,
              selectedColor: Sp.green,
              side: const BorderSide(color: Sp.divider),
              onSelected: (_) => setState(() => _segment = i),
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
          padding: EdgeInsets.fromLTRB(Sp.pagePad, Sp.gapL, Sp.pagePad, Sp.gapM),
          child: Text('热门分类',
              style: TextStyle(
                  fontSize: Sp.fSection,
                  fontWeight: FontWeight.w700,
                  color: Sp.text)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
          child: Wrap(
            spacing: Sp.gapS,
            runSpacing: Sp.gapS,
            children: <Widget>[
              for (final String name in kHotCategories)
                ActionChip(
                  label: Text(name,
                      style: const TextStyle(fontSize: Sp.fSub, color: Sp.text)),
                  backgroundColor: Sp.card,
                  side: const BorderSide(color: Sp.divider),
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
        child: Text('暂无搜索历史',
            style: TextStyle(fontSize: Sp.fSub, color: Sp.textFaint)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Sp.pagePad, Sp.gapXL, Sp.pagePad, Sp.gapM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('历史记录',
                  style: TextStyle(
                      fontSize: Sp.fSection,
                      fontWeight: FontWeight.w700,
                      color: Sp.text)),
              TextButton(
                onPressed: _clearHistory,
                child: const Text('清空',
                    style: TextStyle(fontSize: Sp.fSub, color: Sp.textSub)),
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
                  label: Text(h,
                      style: const TextStyle(fontSize: Sp.fSub, color: Sp.text)),
                  backgroundColor: Sp.card,
                  side: const BorderSide(color: Sp.divider),
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
    if (_segment != 0) {
      return SearchEmptyBox(
          '「${kSearchSegments[_segment]}」分类搜索在当前 logic 层未开放端点，暂不可用');
    }
    final Future<SearchResult>? f = _resultF;
    if (f == null) return const SearchEmptyBox('暂无结果');
    return FutureBuilder<SearchResult>(
      future: f,
      builder: (BuildContext c, AsyncSnapshot<SearchResult> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: Sp.green));
        }
        if (snap.hasError) {
          return SearchErrorRetry(message: '搜索失败', onRetry: () => _doSearch(_query));
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
class SearchSongTile extends StatelessWidget {
  const SearchSongTile({required this.song, required this.onTap, required this.onAlbum});
  final SongBrief song;
  final VoidCallback onTap;
  final VoidCallback onAlbum;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(Sp.rM),
        child: SizedBox(
          width: Sp.tileCover,
          height: Sp.tileCover,
          child: song.cover.isEmpty
              ? Container(color: Sp.cardHigh)
              : Image.network(
                  song.cover,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                      Container(color: Sp.cardHigh),
                ),
        ),
      ),
      title: Text(
        song.name.isEmpty ? '未知歌曲' : song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: Sp.fItem,
          color: Sp.text,
          fontWeight: song.isVip ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        song.singer.isEmpty ? '未知歌手' : song.singer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: Sp.fSub, color: Sp.textSub),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (song.albumId.isNotEmpty)
            IconButton(
              tooltip: '专辑',
              iconSize: 18,
              color: Sp.textFaint,
              onPressed: onAlbum,
              icon: const Icon(Icons.album_outlined),
            ),
          Text(
            song.durationSec > 0 ? '${song.durationSec}s' : '',
            style: const TextStyle(fontSize: Sp.fTiny, color: Sp.textFaint),
          ),
        ],
      ),
    );
  }
}

/// 空态。
class SearchEmptyBox extends StatelessWidget {
  const SearchEmptyBox(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Sp.pagePad, vertical: Sp.gapXL),
      child: Text(message,
          style: const TextStyle(fontSize: Sp.fSub, color: Sp.textFaint)));
}

/// 错误 + 重试。
class SearchErrorRetry extends StatelessWidget {
  const SearchErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Sp.pagePad, vertical: Sp.gapXL),
      child: Row(children: <Widget>[
        Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: Sp.fSub, color: Sp.red))),
        TextButton(
            onPressed: onRetry,
            child: const Text('重试',
                style: TextStyle(fontSize: Sp.fSub, color: Sp.green))),
      ]));
}
