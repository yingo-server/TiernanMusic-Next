// L6 surface/pages · 搜索结果歌单/专辑详情页（R3 从 search_page.dart 拆出）。
// 以命中标题检索曲目并整列表播放；业务/回调/文案零改动。M3；每函数 try/catch+Log。
import 'package:flutter/material.dart';
import '../../bridges/bridge_logic.dart' show SearchTypedLogic, Log;
import '../../bridges/bridge_core.dart' show SongBrief, SearchType;
import '../player_controller.dart' show PlayerController;
import '../theme/tn_theme.dart' show tnPadL;
import '../widgets/common_widgets.dart' show SongTile;
import '../widgets/tn_app_bar.dart' show TnAppBar;

const String _tag = 'surface.search';

/// 搜索结果歌单/专辑详情页（走查修复）：以命中标题检索曲目并整列表播放。
/// （R3-C：自 search_page.dart 拆出，原 _SearchDetailPage，业务/回调/文案零改动。）
class SearchDetailPage extends StatefulWidget {
  const SearchDetailPage({
    required this.title, required this.kind, required this.refId,
    required this.player, this.typed,
  });
  final String title;
  final SearchType kind;
  final String refId;
  final PlayerController player;
  final SearchTypedLogic? typed;

  @override
  State<SearchDetailPage> createState() => _SearchDetailPageState();
}

class _SearchDetailPageState extends State<SearchDetailPage> {
  List<SongBrief> _songs = const <SongBrief>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      // 以命中行标题作关键词检索歌曲补曲目（不猜未实测的歌单/专辑曲目端点字段）。
      final typed = widget.typed;
      final List<SongBrief> songs = typed == null
          ? const <SongBrief>[]
          : (await typed.typed(SearchType.song, widget.title, 1)).items;
      if (!mounted) return;
      setState(() { _songs = songs; _loading = false; });
      Log.d(_tag, 'detail loaded kind=${widget.kind.name} n=${songs.length}');
    } catch (e, st) {
      Log.e(_tag, 'detail load failed', e, st);
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: TnAppBar(title: widget.title.isEmpty
            ? (widget.kind == SearchType.special ? '歌单' : '专辑')
            : widget.title),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _msg(context, '加载失败：$_error')
                : _songs.isEmpty
                    ? _msg(context, '暂无曲目')
                    : Column(children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(tnPadL),
                          child: FilledButton.icon(
                            onPressed: () {
                              try {
                                widget.player.playAll(_songs, 0);
                              } catch (e, st) {
                                Log.e(_tag, 'playAll failed', e, st);
                              }
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: Text('播放全部（${_songs.length}首）'),
                          ),
                        ),
                        Expanded(child: ListView.builder(
                          itemCount: _songs.length,
                          itemBuilder: (ctx, i) {
                            try {
                              return SongTile(song: _songs[i], index: i + 1,
                                onPlay: (s) {
                                  try {
                                    widget.player.playAll(_songs, i);
                                  } catch (e, st) {
                                    Log.e(_tag, 'tile play failed', e, st);
                                  }
                                });
                            } catch (e, st) {
                              Log.e(_tag, 'tile build failed', e, st);
                              return const SizedBox.shrink();
                            }
                          })),
                      ]),
      );
    } catch (e, st) {
      Log.e(_tag, 'detail build crashed', e, st);
      return const Scaffold(body: Center(child: Text('页面加载失败')));
    }
  }

  Widget _msg(BuildContext ctx, String text) => Center(
      child: Text(text, style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
          color: Theme.of(ctx).colorScheme.onSurfaceVariant)));
}
