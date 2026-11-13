// L6 surface/pages · 音乐库头部（账号卡 + 快捷入口）
// 截图基线：账号卡（头像/昵称/ID/更多）+ 我的歌单快捷入口。
// 只展示，不持有业务状态；数据由 library_page 注入。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show UserProfile;
import '../../bridges/bridge_logic.dart' show Log;
import '../theme/tn_theme.dart' show TnDims;

const String _tag = 'surface.libraryHeader';

/// 账号卡：未登录显示登录提示；已登录显示头像/昵称/ID。
class LibraryAccountCard extends StatelessWidget {
  const LibraryAccountCard({
    super.key,
    this.profile,
    this.favoriteCount,
    this.onOpenSettings,
  });

  final Future<UserProfile>? profile;
  final Future<int>? favoriteCount;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    try {
      final ColorScheme cs = Theme.of(context).colorScheme;
      final TextTheme t = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            TnDims.padL, TnDims.padL, TnDims.padL, TnDims.padS),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TnDims.rL)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(TnDims.padM),
            child: FutureBuilder<UserProfile>(
              future: profile,
              builder: (ctx, snap) {
                final p = snap.data;
                final bool loggedIn = p != null && !p.isEmpty;
                return Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: cs.surfaceContainerHighest,
                      foregroundImage: (p != null && p.avatar.isNotEmpty)
                          ? NetworkImage(p.avatar)
                          : null,
                      child: Icon(Icons.person_outline,
                          color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            loggedIn
                                ? (p.nickname.isEmpty ? '已登录' : p.nickname)
                                : '未登录',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface),
                          ),
                          const SizedBox(height: 2),
                          if (loggedIn)
                            Text('ID: ${p.userid}',
                                style: t.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (favoriteCount != null)
                      FutureBuilder<int>(
                        future: favoriteCount,
                        builder: (ctx2, s2) {
                          final n = s2.data ?? 0;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text('$n',
                                  style: t.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: cs.primary)),
                              Text('我喜欢',
                                  style: t.labelSmall
                                      ?.copyWith(color: cs.onSurfaceVariant)),
                            ],
                          );
                        },
                      ),
                    if (onOpenSettings != null)
                      IconButton(
                        tooltip: '设置',
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {
                          try {
                            onOpenSettings!();
                          } catch (e, st) {
                            Log.e(_tag, 'open settings failed', e, st);
                          }
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'account card build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
