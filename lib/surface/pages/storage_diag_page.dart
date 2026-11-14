// L6 surface/pages · 存储诊断页（我的歌单 / 本地曲库 / 下载任务 / 缓存概况）
// 目的：把「装了哪些数据、各占多少」显式化（截图基线的存储分组），
// 便于用户定位空间占用与清理。所有数据经注入的依赖读取，不直连 IO。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show SongDao, PlaylistBrief, PlaylistDetail, SongBrief;
import '../../bridges/bridge_logic.dart' show DownloadManager, Log;
import '../theme/tn_theme.dart' show TnDims;
import '../widgets/m3/m3_state_views.dart' show M3EmptyState, M3ErrorRetry;
import '../widgets/m3/m3_skeleton.dart' show M3ListSkeleton;
import '../widgets/playlist_tracks_sheet.dart' show showPlaylistTracksSheet;

const String _tag = 'surface.storageDiag';

/// 存储诊断所需数据源。
class StorageDiagDeps {
  const StorageDiagDeps({
    required this.songDao,
    required this.downloads,
    this.myPlaylists,
    this.playlistDetail,
    this.playlistTracks,
    this.onPlay,
    this.onSongAction,
  });

  final SongDao songDao;
  final DownloadManager downloads;

  /// 我的歌单（可选）。
  final Future<List<PlaylistBrief>> Function()? myPlaylists;

  /// 歌单详情（可选；打开弹层前取数字 specialId；入参 brief.id 为 gc_id）。
  final Future<PlaylistDetail> Function(String playlistId)? playlistDetail;

  /// 歌单曲目（可选；入参必须是数字 specialId）。
  final Future<List<SongBrief>> Function(String playlistId)? playlistTracks;

  final void Function(SongBrief)? onPlay;
  final void Function(SongBrief)? onSongAction;
}

/// 存储诊断页。
class StorageDiagPage extends StatefulWidget {
  const StorageDiagPage({super.key, required this.deps});

  final StorageDiagDeps deps;

  @override
  State<StorageDiagPage> createState() => _StorageDiagPageState();
}

class _StorageDiagPageState extends State<StorageDiagPage> {
  int _localCount = -1;
  int _downloadTasks = -1;
  List<PlaylistBrief> _playlists = const <PlaylistBrief>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final songs = await widget.deps.songDao.list();
      final tasks = widget.deps.downloads.listTasks();
      final lists = await widget.deps.myPlaylists?.call() ?? const <PlaylistBrief>[];
      if (!mounted) return;
      setState(() {
        _localCount = songs.length;
        _downloadTasks = tasks.length;
        _playlists = lists;
        _error = null;
      });
    } catch (e, st) {
      Log.e(_tag, 'load failed', e, st);
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      final t = Theme.of(context).textTheme;
      return Scaffold(
        appBar: AppBar(title: const Text('存储诊断')),
        body: _error != null
            ? M3ErrorRetry(
                title: '诊断数据加载失败', detail: _error, onRetry: _load)
            : _localCount < 0
                ? const M3ListSkeleton(rows: 5)
                : ListView(
                    padding: const EdgeInsets.only(bottom: TnDims.padXL),
                    children: <Widget>[
                      _StatTile(
                        icon: Icons.library_music_outlined,
                        label: '本地曲库',
                        value: '$_localCount 首',
                      ),
                      _StatTile(
                        icon: Icons.download_outlined,
                        label: '下载任务',
                        value: '$_downloadTasks 个',
                      ),
                      _StatTile(
                        icon: Icons.queue_music_outlined,
                        label: '我的歌单',
                        value: '${_playlists.length} 个',
                      ),
                      const Divider(height: 1),
                      if (_playlists.isEmpty)
                        const M3EmptyState(
                          icon: Icons.folder_off_outlined,
                          title: '暂无歌单',
                          subtitle: '登录后可在酷狗云端查看「我的歌单」',
                        )
                      else
                        for (final p in _playlists)
                          ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: p.cover.isEmpty
                                    ? ColoredBox(
                                        color: cs.surfaceContainerHigh,
                                        child: Icon(Icons.queue_music,
                                            color: cs.onSurfaceVariant),
                                      )
                                    : Image.network(p.cover,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => ColoredBox(
                                              color: cs.surfaceContainerHigh,
                                              child: Icon(Icons.queue_music,
                                                  color: cs.onSurfaceVariant),
                                            )),
                              ),
                            ),
                            title: Text(p.name.isEmpty ? '歌单' : p.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${p.trackCount} 首'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              try {
                                _openPlaylist(p);
                              } catch (e, st) {
                                Log.e(_tag, 'open playlist failed', e, st);
                              }
                            },
                          ),
                      Padding(
                        padding: const EdgeInsets.all(TnDims.padL),
                        child: Text('提示：歌词缓存可在设置页「播放与存储」中清理。',
                            style: t.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return const SizedBox.shrink();
    }
  }

  Future<void> _openPlaylist(PlaylistBrief brief) async {
    try {
      final loader = widget.deps.playlistTracks;
      final detailOf = widget.deps.playlistDetail;
      if (loader == null || detailOf == null) return;
      // gc_id 先 detail 换数字 specialId；空则 Log.w + 空曲目（不回退 gc_id）。
      final sid = (await detailOf(brief.id)).specialId.trim();
      if (!mounted) return;
      if (sid.isEmpty) {
        Log.w(_tag, 'openPlaylist empty specialId id=${brief.id} → empty tracks');
      }
      await showPlaylistTracksSheet(
        context,
        brief,
        load: () => sid.isEmpty
            ? Future<List<SongBrief>>.value(const <SongBrief>[])
            : loader(sid),
        onPlay: widget.deps.onPlay ?? (_) {},
        onSongAction: widget.deps.onSongAction,
      );
    } catch (e, st) {
      Log.e(_tag, 'openPlaylist failed', e, st);
    }
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      final t = Theme.of(context).textTheme;
      return ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(label),
        trailing: Text(value, style: t.titleMedium?.copyWith(color: cs.primary)),
      );
    } catch (e, st) {
      Log.e(_tag, 'stat tile failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
