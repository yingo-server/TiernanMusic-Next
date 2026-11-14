// L6 surface/pages · 歌曲操作弹层启动器（首页/音乐库共用）
// 把「取导航 context + 组装回调」收敛为一个函数，避免 assembly 重复内联。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SongBrief;
import '../../bridges/bridge_logic.dart' show Log;
import '../providers.dart' show appNavigatorKey;
import '../widgets/song_actions_sheet.dart' show showSongActionsSheet;

const String _tag = 'surface.songActionLaunch';

/// 打开歌曲操作弹层（context 缺失时仅留痕，不崩）。
void launchSongActions({
  required SongBrief song,
  required void Function(SongBrief) onPlayNext,
  required Future<Object?> Function() onCollect,
  required bool collected,
  required void Function() onDownload,
}) {
  try {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) {
      Log.w(_tag, 'skipped: no navigator context');
      return;
    }
    showSongActionsSheet(
      ctx,
      song,
      onPlayNext: () => onPlayNext(song),
      onCollect: onCollect,
      collected: collected,
      onDownload: onDownload,
    );
  } catch (e, st) {
    Log.e(_tag, 'launch failed', e, st);
  }
}
