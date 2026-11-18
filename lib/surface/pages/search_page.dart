// L7 surface/pages · 搜索页（官方 M3 + 语义 token 森林翡翠）。
//
// 契约：只用官方 Material 3 控件 + get 包现成能力；不手写控件类（页面容器除外）；
// 颜色只来自 context.cs.*（design/tokens_v2.dart 的 ColorScheme 扩展）；
// 数据只经 bridge_logic/logic 单例取；异步 future 一律在交互回调中持有，build 内不新建。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SearchType;
import '../../bridges/bridge_logic.dart'
    show Log, SearchResult, SongBrief, SearchSuggestItem;
import '../../bridges/bridge_session.dart'
    show NavState, PlaybackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens_v2.dart';

const String _tag = 'surface.search';

// 语义间距/圆角（纯数值，非色值；语义色一律走 context.cs.*）。
const double _pad = 16;
const double _gapS = 8;
const double _gapM = 12;
const double _gapL = 16;
const double _gapXL = 24;
const double _radiusS = 8;

/// 页面模块注册（L7 注入 builder，宿主按 id 覆盖 session 占位模块）。
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

/// 搜索页：搜索栏 + 联想 + 分段结果 + 热门/历史（官方控件组合）。
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
      appBar: AppBar(title: Text('搜索', style: Theme.of(context).textTheme.headlineSmall)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _searchBar(context),
            _suggestBox(context),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  /// 搜索栏：官方 SearchBar + FilledIconButton（原手写胶囊 Material/InkWell）。
  Widget _searchBar(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, _gapS, _pad, _gapS),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SearchBar(
              controller: _ctrl,
              hintText: '搜索歌曲、歌单、歌手',
              leading: const Icon(Icons.search),
              onChanged: _onChanged,
              onSubmitted: _doSearch,
              elevation: WidgetStateProperty.all(0),
              backgroundColor: WidgetStateProperty.all(c.cs.surfaceContainer),
              side: WidgetStateProperty.all(BorderSide(color: c.cs.outlineVariant)),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: _gapL),
              ),
            ),
          ),
          const SizedBox(width: _gapS),
          IconButton.filled(
            tooltip: '搜索',
            onPressed: () => _doSearch(_ctrl.text),
            icon: const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    );
  }

  /// 联想词：官方 ListTile（原 ListTile 保留，仅换语义色）。
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
            padding: const EdgeInsets.symmetric(horizontal: _pad),
            itemCount: items.length,
            itemBuilder: (BuildContext c, int i) {
              final SearchSuggestItem it = items[i];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history, color: c.cs.onSurfaceVariant),
                title: Text(it.keyword, style: Theme.of(c).textTheme.bodyMedium),
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

  Widget _body(BuildContext c) {
    if (_resultF == null) return _idleBody(c);
    return Column(
      children: <Widget>[
        _segmentBar(c),
        Expanded(child: _resultBody(c)),
      ],
    );
  }

  /// 分段：官方 ChoiceChip （颜色用语义 token，选中文字用 onPrimary）。
  Widget _segmentBar(BuildContext c) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _pad),
        itemCount: kSearchSegments.length,
        itemBuilder: (BuildContext c, int i) {
          final bool sel = i == _segment;
          return Padding(
            padding: const EdgeInsets.only(right: _gapS, top: _gapS),
            child: ChoiceChip(
              label: Text(
                kSearchSegments[i],
                style: Theme.of(c).textTheme.labelLarge?.copyWith(
                      color: sel ? c.cs.onPrimary : c.cs.onSurface,
                    ),
              ),
              selected: sel,
              showCheckmark: false,
              selectedColor: c.cs.primary,
              side: BorderSide(color: c.cs.outlineVariant),
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

  Widget _idleBody(BuildContext c) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: _gapXL),
      itemCount: 2,
      itemBuilder: (BuildContext c, int i) {
        if (i == 0) return _hotCategories(c);
        return _historySection(c);
      },
    );
  }

  Widget _hotCategories(BuildContext c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, _gapL, _pad, _gapM),
          child: Text('热门分类', style: Theme.of(c).textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pad),
          child: Wrap(
            spacing: _gapS,
            runSpacing: _gapS,
            children: <Widget>[
              for (final String name in kHotCategories)
                ActionChip(
                  label: Text(name, style: Theme.of(c).textTheme.labelLarge),
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

  Widget _historySection(BuildContext c) {
    if (_history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(_pad, _gapXL, _pad, 0),
        child: Text(
          '暂无搜索历史',
          style: Theme.of(c).textTheme.bodySmall,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, _gapXL, _pad, _gapM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('历史记录', style: Theme.of(c).textTheme.titleLarge),
              TextButton(
                onPressed: _clearHistory,
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pad),
          child: Wrap(
            spacing: _gapS,
            runSpacing: _gapS,
            children: <Widget>[
              for (final String h in _history)
                ActionChip(
                  label: Text(h, style: Theme.of(c).textTheme.labelLarge),
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

  Widget _resultBody(BuildContext c) {
    final Future<SearchResult>? f = _resultF;
    if (f == null) return _empty(c, '暂无结果');
    return FutureBuilder<SearchResult>(
      future: f,
      builder: (BuildContext c, AsyncSnapshot<SearchResult> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: c.cs.primary),
          );
        }
        if (snap.hasError) {
          return _error(c, '搜索失败', () => _doSearch(_query));
        }
        final SearchResult r = snap.data ?? const SearchResult();
        final List<SongBrief> items = r.items;
        if (items.isEmpty) {
          return _empty(c, '没有找到与「$_query」相关的内容');
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: _gapXL),
          itemCount: items.length,
          itemBuilder: (BuildContext c, int i) =>
              _songTile(c, items[i], () => _play(items, i),
                  () => _openAlbum(items[i].albumId)),
        );
      },
    );
  }

  /// 歌曲行：官方 ListTile（原 SearchSongTile / SpSongTile 的等价物）。
  Widget _songTile(BuildContext c, SongBrief song, VoidCallback onTap,
      VoidCallback onAlbum) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: _pad),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(_radiusS),
        child: SizedBox(
          width: 48,
          height: 48,
          child: song.cover.isEmpty
              ? Container(color: c.cs.surfaceContainerHigh)
              : Image.network(
                  song.cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: c.cs.surfaceContainerHigh),
                ),
        ),
      ),
      title: Text(
        song.name.isEmpty ? '未知歌曲' : song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(c).textTheme.bodyMedium?.copyWith(
              fontWeight: song.isVip ? FontWeight.w600 : FontWeight.w400,
            ),
      ),
      subtitle: Text(
        song.singer.isEmpty ? '未知歌手' : song.singer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(c).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (song.albumId.isNotEmpty)
            IconButton(
              tooltip: '专辑',
              iconSize: 18,
              onPressed: onAlbum,
              icon: const Icon(Icons.album_outlined),
            ),
          Text(
            song.durationSec > 0 ? '${song.durationSec}s' : '',
            style: Theme.of(c).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  /// 空态：官方 Icon + Text（原 SearchEmptyBox）。
  Widget _empty(BuildContext c, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: _gapXL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_off, color: c.cs.onSurfaceVariant),
          const SizedBox(height: _gapS),
          Text(message, style: Theme.of(c).textTheme.bodySmall),
        ],
      ),
    );
  }

  /// 错误 + 重试：官方 Icon + Text + TextButton（原 SearchErrorRetry）。
  Widget _error(BuildContext c, String message, VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: _gapXL),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: c.cs.error),
          const SizedBox(width: _gapS),
          Expanded(
            child: Text(message, style: Theme.of(c).textTheme.bodySmall),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
