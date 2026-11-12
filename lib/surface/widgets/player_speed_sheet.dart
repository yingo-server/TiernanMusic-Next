// L6 surface/widgets · 播放页倍速选择 bottom sheet（批R1-B 从 player_page.dart 拆出）
// 仅移动代码：文案/回调/ChoiceChip 行为零改动；每函数 try/catch+Log 留痕。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../player_controller.dart' show playerProvider;
import '../theme/tn_theme.dart' show tnPadL, tnPadS;

const String _tag = 'surface.player_speed_sheet';

/// 弹出倍速选择（0.5/1.0/1.5/2.0，ChoiceChip 选中态）。
Future<void> showPlayerSpeedSheet(BuildContext context) async {
  try {
    const speeds = <double>[0.5, 1.0, 1.5, 2.0];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(tnPadL),
          child: Consumer(builder: (ctx, r, _) => Wrap(
            spacing: tnPadS,
            children: <Widget>[
              for (final s in speeds)
                ChoiceChip(
                  label: Text('${s.toStringAsFixed(1)}x'),
                  selected: s == r.watch(playerProvider).speed,
                  onSelected: (_) {
                    try {
                      r.read(playerProvider.notifier).setSpeed(s);
                    } catch (e, st) {
                      Log.e(_tag, 'setSpeed failed $s', e, st);
                    }
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          )),
        ),
      ),
    );
  } catch (e, st) {
    Log.e(_tag, 'showSpeedSheet failed', e, st);
  }
}
