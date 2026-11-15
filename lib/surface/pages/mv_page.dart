// L7 surface/pages · MV 页（内嵌 video_player；非底栏模块）
// 铁律：只画控件；数据只经 bridge_session.appGraph.mv 取；样式一律 Sp.*。
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../bridges/bridge_session.dart'
    show appGraph, ModuleRegistry, NavEntry, SurfaceModule;
import '../design/components.dart' show SpStateView;
import '../design/tokens.dart';

/// 幂等安装 MV 模块到 L6 注册表（id 已存在则不重复覆盖）。
void registerMvModule() {
  try {
    final reg = ModuleRegistry.instance;
    if (reg.byId('mv') != null) return;
    reg.install(MvPageModule());
  } catch (e, st) {
    debugPrint('surface.mv: registerMvModule failed: $e\n$st');
  }
}

/// MV 模块：navEntry=null，不进底部导航；由播放页 ⋮ 菜单直达。
class MvPageModule extends SurfaceModule {
  @override
  String get id => 'mv';
  @override
  String get route => '/mv';
  @override
  NavEntry? get navEntry => null;
  @override
  WidgetBuilder? get builder =>
      (_) => const MvPage(songHash: '');
}

/// MV 内嵌播放页：qualities(hash) → 最低档（ld/sd 优先）→ playUrl。
class MvPage extends StatefulWidget {
  const MvPage({super.key, required this.songHash});
  final String songHash; // 当前曲 hash（兼作 MV 查询键）
  @override
  State<MvPage> createState() => _MvPageState();
}

enum _Phase { loading, empty, error, ready }

class _MvPageState extends State<MvPage> {
  _Phase _phase = _Phase.loading;
  String _message = '', _note = '', _quality = '';
  VideoPlayerController? _ctrl;
  bool? _playing;
  late final VoidCallback _listener = _onCtrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MvPage old) {
    super.didUpdateWidget(old);
    if (old.songHash == widget.songHash) return;
    _release();
    _phase = _Phase.loading;
    _message = _note = _quality = '';
    _load();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    final c = _ctrl;
    _ctrl = null;
    _playing = null;
    c?.removeListener(_listener);
    c?.dispose(); // 释放解码器与网络连接
  }

  void _onCtrl() {
    final p = _ctrl?.value.isPlaying;
    if (!mounted || p == null || p == _playing) return;
    _playing = p;
    setState(() {});
  }

  Future<void> _load() async {
    final hash = widget.songHash.trim().toLowerCase();
    if (hash.isEmpty) {
      _fail(_Phase.empty, '缺少歌曲 hash，无法查询 MV');
      return;
    }
    final logic = appGraph?.mv;
    if (logic == null) {
      _fail(_Phase.error, '装配图未就绪（MV 门面不可用）');
      return;
    }
    try {
      final quals = await logic.qualities(hash);
      if (!mounted) return;
      if (quals.isEmpty) {
        _fail(_Phase.empty, '这首歌暂无可播 MV');
        return;
      }
      // 最低档优先：ld → sd → 按 size 取最小（避开 VIP 高画质档）。
      var low = quals.first;
      for (final q in quals) {
        if (q.id == 'ld') {
          low = q;
          break;
        }
      }
      if (low.id != 'ld') {
        for (final q in quals) {
          if (q.id == 'sd') {
            low = q;
            break;
          }
        }
      }
      if (low.id != 'ld' && low.id != 'sd') {
        for (final q in quals) {
          if (q.size > 0 && (low.size <= 0 || q.size < low.size)) low = q;
        }
      }
      final requested = low.id.isNotEmpty ? low.id : low.hash;
      final r = await logic.playUrl(hash, requestedId: requested);
      if (!mounted) return;
      if (!r.playable) {
        _fail(_Phase.empty, 'MV 地址不可用（可能被权限拦截）');
        return;
      }
      final raw = r.urls
          .firstWhere((u) => u.trim().isNotEmpty, orElse: () => '')
          .trim();
      if (raw.isEmpty) {
        _fail(_Phase.empty, 'MV 地址为空');
        return;
      }
      // http 明文显式处理：Android 默认禁明文，统一升级为 https 并留可见提示。
      var url = raw, note = '';
      if (url.startsWith('http://')) {
        url = 'https://${url.substring(7)}';
        note = 'http 明文链接已升级为 https';
      }
      if (!url.startsWith('https://')) {
        _fail(_Phase.error, '不支持的 MV 链接协议：$url');
        return;
      }
      final c = VideoPlayerController.network(url);
      try {
        await c.initialize();
        await c.setLooping(true);
        await c.play();
      } catch (e) {
        await c.dispose();
        rethrow;
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      _release();
      c.addListener(_listener);
      setState(() {
        _ctrl = c;
        _phase = _Phase.ready;
        _note = note;
        _quality = r.quality;
        _message = '';
        _playing = c.value.isPlaying;
      });
    } catch (e, st) {
      debugPrint('surface.mv: load failed: $e\n$st');
      _fail(_Phase.error, 'MV 加载失败：$e');
    }
  }

  void _fail(_Phase p, String m) {
    if (!mounted) return;
    setState(() {
      _phase = p;
      _message = m;
    });
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) return;
    try {
      if (c.value.isPlaying)
        c.pause();
      else
        c.play();
    } catch (e, st) {
      debugPrint('surface.mv: toggle failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Sp.bg,
    appBar: AppBar(
      backgroundColor: Sp.bg,
      iconTheme: const IconThemeData(color: Sp.text),
      title: const Text(
        'MV',
        style: TextStyle(fontSize: Sp.fSection, color: Sp.text),
      ),
    ),
    body: SafeArea(child: _view()),
  );

  Widget _view() {
    switch (_phase) {
      case _Phase.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(color: Sp.green),
              const SizedBox(height: Sp.gapM),
              const Text(
                '正在加载 MV…',
                style: TextStyle(fontSize: Sp.fSub, color: Sp.textSub),
              ),
            ],
          ),
        );
      case _Phase.empty:
        return SpStateView(
          icon: Icons.movie,
          title: '暂无 MV',
          subtitle: _message,
          actionLabel: '重试',
          onAction: _load,
        );
      case _Phase.error:
        return SpStateView(
          icon: Icons.error_outline,
          title: 'MV 不可用',
          subtitle: _message,
          actionLabel: '重试',
          onAction: _load,
        );
      case _Phase.ready:
        final c = _ctrl;
        if (c == null) {
          return SpStateView(
            icon: Icons.error_outline,
            title: 'MV 不可用',
            subtitle: '播放器已释放',
            actionLabel: '重试',
            onAction: _load,
          );
        }
        final ar = c.value.aspectRatio > 0 ? c.value.aspectRatio : 1.0;
        return Padding(
          padding: const EdgeInsets.all(Sp.gapM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(Sp.rCard),
                child: ColoredBox(
                  color: Sp.bgElevated,
                  child: AspectRatio(aspectRatio: ar, child: VideoPlayer(c)),
                ),
              ),
              const SizedBox(height: Sp.gapM),
              VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Sp.green,
                  bufferedColor: Sp.textFaint,
                  backgroundColor: Sp.divider,
                ),
              ),
              const SizedBox(height: Sp.gapS),
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: _toggle,
                    icon: Icon(
                      c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    color: Sp.green,
                    tooltip: c.value.isPlaying ? '暂停' : '播放',
                  ),
                  const SizedBox(width: Sp.gapS),
                  Expanded(
                    child: Text(
                      _note.isNotEmpty
                          ? _note
                          : (_quality.isEmpty ? 'MV 内嵌播放' : '档位 $_quality'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: Sp.fTiny,
                        color: Sp.textSub,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}
