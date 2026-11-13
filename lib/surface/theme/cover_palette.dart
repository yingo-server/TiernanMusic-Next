// L6 surface/theme · 封面取色 → 动态调色板接线
// 职责：取封面字节（core）→ 解码为 RGBA（Flutter 侧）→ extractDominant →
// dynamicThemeProvider。解码必须在本层（dart:ui），IO 在 core，符合分层。
// 铁律：整链路 try/catch + Log；失败静默回落默认主题（不阻断播放）。
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_core.dart' show fetchCoverBytes;
import '../../bridges/bridge_logic.dart' show Log;
import 'dynamic_theme.dart' show dynamicThemeProvider;

const String _tag = 'surface.coverPalette';

/// 载入封面并更新动态调色板（fire-and-forget；失败只留痕）。
Future<void> applyCoverPalette(
  WidgetRef ref,
  String coverUrl, {
  required bool dark,
}) async {
  try {
    if (coverUrl.trim().isEmpty) return;
    final bytes = await fetchCoverBytes(coverUrl);
    if (bytes == null) return;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        Log.w(_tag, 'toByteData returned null');
        return;
      }
      ref.read(dynamicThemeProvider.notifier).updateFromImageBytes(
            data.buffer.asUint8List(),
            image.width,
            image.height,
          );
      Log.d(_tag, 'palette applied ${image.width}x${image.height}');
    } finally {
      image.dispose();
    }
  } catch (e, st) {
    Log.e(_tag, 'applyCoverPalette failed', e, st);
  }
}
