// L6 surface/pages · 评论页模块（GAP #14，批1-A）
// 无 navEntry——从播放页/歌单页 Navigator.push 进入。
// 装配说明：本模块不由 modules.dart/assembly.dart 默认装配，
// 由装配处执行 SurfaceRegistry.install(buildCommentModule(logic:..., mixSongIdProvider:...))。
// 工厂函数 buildCommentModule 在本文件底部（deps 注入 CommentLogic + mixSongId 提供者）。
// 铁律：surface 只 import flutter/miuix + bridges + 本层；每函数 try/catch + Log。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart'
    show CommentLogic, CommentItem, CommentPage, Log, LogicFacade;
import '../registry.dart';
import '../widgets/tn_app_bar.dart' show TnAppBar, TnPagePadding;

const String _tag = 'surface.comment_page';

/// 评论页模块工厂：由装配处调用并 SurfaceRegistry.install。
/// mixSongIdProvider：从播放页/歌单页取当前 mixSongId。
SurfaceModule buildCommentModule({
  required CommentLogic logic,
  required int Function() mixSongIdProvider,
}) {
  try {
    return _CommentPageModule(logic: logic, mixSongIdProvider: mixSongIdProvider);
  } catch (e, st) {
    Log.e(_tag, 'buildCommentModule failed', e, st);
    return _CommentPageModule(logic: logic, mixSongIdProvider: () => 0);
  }
}

class _CommentPageModule implements SurfaceModule {
  _CommentPageModule({required this.logic, required this.mixSongIdProvider});

  final CommentLogic logic;
  final int Function() mixSongIdProvider;

  @override
  String get id => 'comment';

  @override
  String get route => '/comment';

  @override
  bool enabled(LogicFacade facade) => true;

  @override
  WidgetBuilder builder(LogicFacade facade) =>
      (ctx) => _CommentPageBody(logic: logic, mixSongIdProvider: mixSongIdProvider);
}

/// 评论列表控制器：分页加载 + 刷新。
class _CommentListModel extends ChangeNotifier {
  _CommentListModel(this._logic, this._mixSongId) {
    _load(refresh: true);
  }

  final CommentLogic _logic;
  final int _mixSongId;
  final List<CommentItem> _items = <CommentItem>[];
  List<String> hotWords = const <String>[];
  int _total = 0;
  int _page = 1;
  bool loading = false;
  String? error;

  List<CommentItem> get items => List<CommentItem>.unmodifiable(_items);
  bool get hasMore => _items.length < _total || (_total <= 0 && _items.isNotEmpty);

  Future<void> _load({bool refresh = false}) async {
    try {
      if (loading || _mixSongId <= 0) return;
      loading = true;
      error = null;
      notifyListeners();
      if (refresh) {
        _page = 1;
        _items.clear();
      }
      final page = await _logic.comments(_mixSongId, _page);
      _items.addAll(page.items);
      if (page.hotWords.isNotEmpty) hotWords = page.hotWords;
      if (page.total > 0) _total = page.total;
      _page += 1;
    } catch (e, st) {
      error = '$e';
      Log.e(_tag, 'list load failed mix=$_mixSongId', e, st);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => _load(refresh: true);
  Future<void> loadMore() => _load();

  @override
  void dispose() {
    try {
      super.dispose();
    } catch (e, st) {
      Log.e(_tag, 'dispose failed', e, st);
    }
  }
}

class _CommentPageBody extends StatefulWidget {
  const _CommentPageBody(
      {required this.logic, required this.mixSongIdProvider});
  final CommentLogic logic;
  final int Function() mixSongIdProvider;

  @override
  State<_CommentPageBody> createState() => _CommentPageBodyState();
}

class _CommentPageBodyState extends State<_CommentPageBody> {
  late final _CommentListModel _model =
      _CommentListModel(widget.logic, widget.mixSongIdProvider());
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      try {
        if (_scroll.position.pixels >
            _scroll.position.maxScrollExtent - 400) {
          _model.loadMore();
        }
      } catch (e, st) {
        Log.e(_tag, 'scroll loadMore failed', e, st);
      }
    });
  }

  @override
  void dispose() {
    try {
      _scroll.dispose();
      _model.dispose();
    } catch (e, st) {
      Log.e(_tag, 'dispose failed', e, st);
    }
    super.dispose();
  }

  void _openFloor(CommentItem c) {
    try {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _FloorPage(logic: widget.logic, commentId: c.id),
      ));
    } catch (e, st) {
      Log.e(_tag, 'openFloor failed cid=${c.id}', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return AnimatedBuilder(
        animation: _model,
        builder: (ctx, _) => Scaffold(
          appBar: TnAppBar(
            title: '评论',
            leading: BackButton(onPressed: () => Navigator.of(ctx).maybePop()),
          ),
          body: RefreshIndicator(
            onRefresh: _model.refresh,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (_model.hotWords.isNotEmpty)
                  TnPagePadding(child: _HotWordsChips(words: _model.hotWords)),
                if (_model.error != null)
                  TnPagePadding(child: Text('加载失败：${_model.error}')),
                ..._model.items.map((c) => _CommentTile(
                      item: c,
                      onTapFloor: () => _openFloor(c),
                    )),
                if (_model.loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!_model.hasMore && _model.items.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('没有更多了')),
                  )
                else if (_model.items.isEmpty && !_model.loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('暂无评论')),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return Scaffold(appBar: TnAppBar(title: '评论'), body: const SizedBox());
    }
  }
}

/// 热词 chips。
class _HotWordsChips extends StatelessWidget {
  const _HotWordsChips({required this.words});
  final List<String> words;

  @override
  Widget build(BuildContext context) {
    try {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: words
            .map((w) => Chip(label: Text(w), visualDensity: VisualDensity.compact))
            .toList(growable: false),
      );
    } catch (e, st) {
      Log.e(_tag, 'HotWordsChips build failed', e, st);
      return const SizedBox();
    }
  }
}

/// 单条评论：头像/昵称/内容/点赞/时间/楼层。
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.item, required this.onTapFloor});
  final CommentItem item;
  final VoidCallback onTapFloor;

  String _timeText(int ms) {
    try {
      if (ms <= 0) return '';
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final hasFloor = item.floor > 0 && item.id.isNotEmpty;
      final child = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage:
                item.avatar.isNotEmpty ? NetworkImage(item.avatar) : null,
            child: item.avatar.isEmpty ? const Icon(Icons.person, size: 16) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(item.nickname.isEmpty ? '匿名' : item.nickname,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (item.likeCount > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.thumb_up_outlined, size: 14),
                      const SizedBox(width: 4),
                      Text('${item.likeCount}'),
                    ]),
                ]),
                if (item.replyTo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('回复 @${item.replyTo}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(item.content.isEmpty ? '（空内容）' : item.content),
                ),
                Row(children: [
                  if (hasFloor)
                    Text('${item.floor}楼',
                        style: Theme.of(context).textTheme.bodySmall),
                  if (hasFloor && _timeText(item.timeMs).isNotEmpty)
                    const Text(' · '),
                  Text(_timeText(item.timeMs),
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ],
            ),
          ),
        ],
      );
      return ListTile(
        onTap: hasFloor ? onTapFloor : null,
        title: child,
      );
    } catch (e, st) {
      Log.e(_tag, 'CommentTile build failed', e, st);
      return const SizedBox();
    }
  }
}

/// 楼中楼（热评回复）内嵌页。
class _FloorPage extends StatefulWidget {
  const _FloorPage({required this.logic, required this.commentId});
  final CommentLogic logic;
  final String commentId;

  @override
  State<_FloorPage> createState() => _FloorPageState();
}

class _FloorPageState extends State<_FloorPage> {
  final List<CommentItem> _items = <CommentItem>[];
  int _page = 1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_loading) return;
      _loading = true;
      final res = await widget.logic.floor(widget.commentId, _page);
      if (mounted) setState(() => _items.addAll(res));
      _page += 1;
    } catch (e, st) {
      Log.e(_tag, 'floor load failed cid=${widget.commentId}', e, st);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: TnAppBar(
          title: '楼层回复',
          leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ..._items.map((c) => _CommentTile(item: c, onTapFloor: () {})),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_items.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('暂无回复')),
              ),
          ],
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'FloorPage build failed', e, st);
      return Scaffold(appBar: TnAppBar(title: '楼层回复'), body: const SizedBox());
    }
  }
}
