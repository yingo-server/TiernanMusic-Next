// L6 surface/pages · 曲库模块（buildLibraryModule）· Material Design 3
// 由 modules.dart（批4-B）汇总注册：SurfaceRegistry.install(buildLibraryModule(...))。
// 三个 tab：本地曲库（SongDao.list）/ 最近播放（注入 historyRecent 回调）/ 下载管理（DownloadManager）。
// 铁律：只 import flutter/material/riverpod/bridge_logic/bridge_core/本层；try/catch + Log('surface.library')。
// M3：二级 TabBar 挂 TnAppBar.bottom；颜色取 Theme.of(context).colorScheme；间距/圆角走 TnDims。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart';
import '../../bridges/bridge_logic.dart';
import '../registry.dart';
import '../theme/tn_theme.dart' show TnDims, TnText, tnPadL;
import '../widgets/tn_app_bar.dart' show TnAppBar;

const String _tag = 'surface.library';

/// 曲库模块依赖：全部经工厂注入，页面内不做任何装配。
class LibraryDeps {
  const LibraryDeps({
    required this.songDao,
    required this.historyRecent,
    required this.downloads,
    required this.onPlay,
  });

  /// 本地曲库数据源。
  final SongDao songDao;

  /// 最近播放（HistoryDao.recent 桥接，避免 surface 直连 dao 内部类型）。
  final Future<List<PlayHistoryEntry>> Function({int limit}) historyRecent;

  /// 下载管理器（任务列表 + 控制）。
  final DownloadManager downloads;

  /// 点击歌曲的播放回调（批4-B PlayerController 提供）。
  final void Function(SongBrief song) onPlay;
}

/// 曲库页模块：id='library'，底部导航入口「曲库」。
class LibraryPageModule extends SurfaceModule {
  LibraryPageModule({required this.deps});

  final LibraryDeps deps;

  @override
  String get id => 'library';

  @override
  String get route => '/library';

  @override
  NavEntry get navEntry => const NavEntry('曲库', 'library_music');

  @override
  bool enabled(LogicFacade logic) => true;

  @override
  WidgetBuilder builder(LogicFacade logic) => (_) => LibraryPage(deps: deps);
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.deps});

  final LibraryDeps deps;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this);
  StreamSubscription<DownloadEvent>? _dlSub;

  @override
  void initState() {
    super.initState();
    try {
      // 下载管理 tab：订阅任务事件实时刷新。
      widget.deps.downloads.onTask = _onDownloadEvent;
    } catch (e, st) {
      Log.e(_tag, 'subscribe onTask failed', e, st);
    }
  }

  void _onDownloadEvent(DownloadEvent event) {
    if (!mounted) return;
    try {
      setState(() {}); // 任务快照整体重建，行数少（≤并发任务+历史），可接受
    } catch (e, st) {
      Log.e(_tag, 'onDownloadEvent setState failed', e, st);
    }
  }

  @override
  void dispose() {
    _dlSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TnAppBar(title: '曲库'),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: '本地曲库'),
                Tab(text: '最近播放'),
                Tab(text: '下载管理'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _LocalTab(deps: widget.deps),
                _RecentTab(deps: widget.deps),
                _DownloadsTab(deps: widget.deps),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab 1：本地曲库 ───

class _LocalTab extends StatelessWidget {
  const _LocalTab({required this.deps});

  final LibraryDeps deps;

  Future<List<SongRecord>> _load() async {
    try {
      return await deps.songDao.list();
    } catch (e, st) {
      Log.e(_tag, 'songDao.list failed', e, st);
      return const <SongRecord>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongRecord>>(
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final songs = snap.data ?? const <SongRecord>[];
        if (songs.isEmpty) {
          return const Center(child: Text('曲库还是空的，先去下载几首歌吧'));
        }
        return ListView.builder(
          itemCount: songs.length,
          itemBuilder: (context, i) {
            final s = songs[i];
            return SongTile(
              title: s.fileName.isEmpty ? s.hash : s.fileName,
              subtitle: [
                if (s.singerName.isNotEmpty) s.singerName,
                if (s.albumName.isNotEmpty) s.albumName,
              ].join(' · '),
              trailing: s.localPath != null ? const Icon(Icons.offline_pin) : null,
              onTap: () {
                try {
                  deps.onPlay(SongBrief(
                    hash: s.hash,
                    name: s.fileName,
                    singer: s.singerName,
                    durationSec: s.durationMs ~/ 1000,
                    albumName: s.albumName,
                  ));
                } catch (e, st) {
                  Log.e(_tag, 'onPlay failed hash=${s.hash}', e, st);
                }
              },
            );
          },
        );
      },
    );
  }
}

// ─── Tab 2：最近播放 ───

class _RecentTab extends StatelessWidget {
  const _RecentTab({required this.deps});

  final LibraryDeps deps;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayHistoryEntry>>(
      future: () async {
        try {
          return await deps.historyRecent(limit: 50);
        } catch (e, st) {
          Log.e(_tag, 'historyRecent failed', e, st);
          return const <PlayHistoryEntry>[];
        }
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? const <PlayHistoryEntry>[];
        if (items.isEmpty) {
          return const Center(child: Text('还没有播放记录'));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final h = items[i];
            final dt =
                DateTime.fromMillisecondsSinceEpoch(h.playedAt);
            return SongTile(
              title: h.fileName.isEmpty ? h.hash : h.fileName,
              subtitle:
                  '${h.singerName} · ${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
              onTap: () {
                try {
                  deps.onPlay(SongBrief(
                    hash: h.hash,
                    name: h.fileName,
                    singer: h.singerName,
                  ));
                } catch (e, st) {
                  Log.e(_tag, 'onPlay(history) failed hash=${h.hash}', e, st);
                }
              },
            );
          },
        );
      },
    );
  }
}

// ─── Tab 3：下载管理 ───

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab({required this.deps});

  final LibraryDeps deps;

  @override
  Widget build(BuildContext context) {
    List<DownloadTask> tasks;
    try {
      tasks = deps.downloads.listTasks();
    } catch (e, st) {
      Log.e(_tag, 'listTasks failed', e, st);
      tasks = const <DownloadTask>[];
    }
    if (tasks.isEmpty) {
      return const Center(child: Text('暂无下载任务'));
    }
    return ListView.builder(
      itemCount: tasks.length,
      itemBuilder: (context, i) => _TaskTile(task: tasks[i], deps: deps),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.deps});

  final DownloadTask task;
  final LibraryDeps deps;

  void _act(String action) {
    try {
      final h = task.hash;
      switch (action) {
        case 'pause':
          deps.downloads.pause(h);
        case 'resume':
          deps.downloads.resume(h);
        case 'cancel':
          deps.downloads.cancel(h);
        case 'retry':
          deps.downloads.retry(h);
      }
      Log.d(_tag, 'download $action hash=$h');
    } catch (e, st) {
      Log.e(_tag, 'download ${action} failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = task.progress;
    final known = p >= 0;
    final running = task.status == DownloadStatus.running ||
        task.status == DownloadStatus.pending;
    return ListTile(
      title: Text(task.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${task.quality} · ${task.status.name}'
            '${task.error == null ? '' : ' · ${task.error}'}'
            '${known ? ' · ${(p * 100).toStringAsFixed(0)}%' : ''}',
            style: TnText.of(context).aux,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: known ? p.clamp(0.0, 1.0) : null,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            IconButton(
              tooltip: '暂停',
              icon: const Icon(Icons.pause),
              onPressed: () => _act('pause'),
            ),
          if (task.status == DownloadStatus.paused)
            IconButton(
              tooltip: '继续（从头重下）',
              icon: const Icon(Icons.play_arrow),
              onPressed: () => _act('resume'),
            ),
          if (task.status == DownloadStatus.failed)
            IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh),
              onPressed: () => _act('retry'),
            ),
          if (task.status != DownloadStatus.done)
            IconButton(
              tooltip: '取消',
              icon: const Icon(Icons.close),
              onPressed: () => _act('cancel'),
            ),
        ],
      ),
    );
  }
}

/// 通用歌曲行（曲库/最近播放共用；widgets 抽离前先留在本文件，≤500 行约束内）。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.music_note),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
