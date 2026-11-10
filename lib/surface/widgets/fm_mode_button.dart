// L6 surface/widgets · 个人 FM「随便听听」入口按钮（功能对齐批4-C · GAP #21）
// 本组件只负责发光按钮 + 回调，不含 AppBar / Scaffold / 页面；由装配处嵌入
// 曲库 tab / 首页模块 / 播放页控制区（SurfaceRegistry 热插拔模块内部使用）。
// 装配方式（装配处，非本文件）：
//   FmModeButton(onStart: () async {
//     final batch = await fmLogic.start();           // FmLogic 经 bridge_logic 暴露
//     if (batch.isEmpty) { /* 空态提示：FM 端点 needs probe，不切队列 */ return; }
//     await controller.playAll(batch, 0);           // PlayerController.playAll
//   })
//   后续「跳过」按钮接 fmLogic.next() → controller.playAll(fmLogic.currentBatch(), 0)；
//   「喜欢/不喜欢」接 fmLogic.like(hash) / dislike(hash)（本地记录，不上报）。
// ⚠️ 端点状态：personalFm / fmSongs 未实测（needs probe），当前 start() 恒空批次，
//    装配处必须按空态降级，不要循环重试或伪造歌曲。
// 铁律：只 import flutter + 桥（模块间零直接 import）；try/catch + Log('surface.fm')。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.fm_button';

/// FM 入口按钮：点击回调 onStart()（无参；装配处负责装配逻辑）。
class FmModeButton extends StatelessWidget {
  const FmModeButton({
    super.key,
    required this.onStart,
    this.label = '随便听听',
    this.enabled = true,
    this.compact = false,
  });

  final VoidCallback onStart;
  final String label;
  final bool enabled;
  /// compact=true 用紧凑圆角按钮（嵌入播放页控制区）；false 用带图标的抬升按钮。
  final bool compact;

  void _tap() {
    try {
      if (!enabled) {
        Log.d(_tag, 'tap ignored (disabled)');
        return;
      }
      Log.d(_tag, 'tap → onStart');
      onStart();
    } catch (e, st) {
      Log.e(_tag, 'onStart callback failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final icon = const Icon(Icons.radio);
      final text = Text(label);
      if (compact) {
        return OutlinedButton.icon(
          onPressed: enabled ? _tap : null,
          icon: icon,
          label: text,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            shape: const StadiumBorder(),
          ),
        );
      }
      return ElevatedButton.icon(
        onPressed: enabled ? _tap : null,
        icon: icon,
        label: text,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: const StadiumBorder(),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
