// L6 surface/pages · MV 内嵌播放壳（video_player）
// 目的：替换此前的「外部播放器占位」——MV 清晰度与播放地址已在库内就绪，
// 可直接内嵌播放。依赖例外：video_player（见 ARCHITECTURE.md 依赖白名单）。
// 铁律：控制器必须 dispose；每步 try/catch + Log；失败显式提示，不静默。
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.mvShell';

/// MV 内嵌播放器：入参为可直接播放的 URL；自持 VideoPlayerController 生命周期。
class MvPlayerShell extends StatefulWidget {
  const MvPlayerShell({super.key, required this.url});

  final String url;

  @override
  State<MvPlayerShell> createState() => _MvPlayerShellState();
}

class _MvPlayerShellState extends State<MvPlayerShell> {
  VideoPlayerController? _ctl;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(MvPlayerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _init();
  }

  Future<void> _init() async {
    try {
      await _disposeCtl();
      final url = widget.url.trim();
      if (url.isEmpty) {
        setState(() => _error = '播放地址为空');
        return;
      }
      final ctl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctl.initialize();
      await ctl.setLooping(false);
      await ctl.play();
      if (!mounted) {
        await ctl.dispose();
        return;
      }
      setState(() {
        _ctl = ctl;
        _ready = true;
        _error = null;
      });
      Log.d(_tag, 'mv ready url=${_safeHost(url)}');
    } catch (e, st) {
      Log.e(_tag, 'mv init failed', e, st);
      if (!mounted) return;
      setState(() => _error = 'MV 播放失败：$e');
    }
  }

  Future<void> _disposeCtl() async {
    try {
      final c = _ctl;
      _ctl = null;
      if (c != null) await c.dispose();
    } catch (e, st) {
      Log.e(_tag, 'dispose controller failed', e, st);
    }
  }

  String _safeHost(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '?';
    }
  }

  @override
  void dispose() {
    _disposeCtl();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      final ctl = _ctl;
      if (_error != null) {
        return _ErrorBox(message: _error!, onRetry: _init);
      }
      if (ctl == null || !_ready) {
        return const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return AspectRatio(
        aspectRatio: ctl.value.aspectRatio == 0 ? 16 / 9 : ctl.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            VideoPlayer(ctl),
            Positioned(
              right: 8,
              bottom: 8,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                  foregroundColor: cs.onSurface,
                ),
                tooltip: ctl.value.isPlaying ? '暂停' : '播放',
                icon: Icon(
                    ctl.value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  try {
                    setState(() {
                      ctl.value.isPlaying ? ctl.pause() : ctl.play();
                    });
                  } catch (e, st) {
                    Log.e(_tag, 'toggle failed', e, st);
                  }
                },
              ),
            ),
          ],
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    try {
      final cs = Theme.of(context).colorScheme;
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: cs.surfaceContainerHigh,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, color: cs.error),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(message,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'error box build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
