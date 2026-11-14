// L6 surface/widgets · 拖动态进度条（从 player_page 拆出，控制文件长度）
// onChanged 只更新本地预览，onChangeEnd 才真正 seek（审查修复拖动 seek 风暴）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.player';

/// 拖动态进度条（本地 StatefulWidget，避免 seek 风暴）。
class SeekSlider extends StatefulWidget {
  const SeekSlider({
    required this.progress,
    required this.enabled,
    required this.durationMs,
    required this.onSeek,
  });

  final double progress;
  final bool enabled;
  final int durationMs;
  final void Function(int ms) onSeek;

  @override
  State<SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<SeekSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _drag ?? widget.progress.clamp(0.0, 1.0),
      onChanged: widget.enabled
          ? (v) {
              try {
                setState(() => _drag = v);
              } catch (e, st) {
                Log.e('surface.player', 'slider drag failed', e, st);
              }
            }
          : null,
      onChangeEnd: widget.enabled
          ? (v) {
              try {
                _drag = null;
                widget.onSeek((v * widget.durationMs).round());
              } catch (e, st) {
                Log.e('surface.player', 'slider seekEnd failed', e, st);
              }
            }
          : null,
    );
  }
}
