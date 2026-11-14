// L6 surface/pages · 搜索首页态（截图基线：搜索历史 + 热门分类 + 热词）
// 仅负责展示与回调；历史持久化由 search_page 经 KeyValueSettings 负责。
// 铁律：不 import 下层非桥文件；每渲染分支 try/catch 兜底。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show SearchSuggestItem, Log;
import '../ui/spotify_ui.dart' as sp;

const String _tag = 'surface.searchHome';

/// 搜索首页：历史 chips（可单删/清空）+ 热门分类 chips + 热词列表。
class SearchHomeView extends StatelessWidget {
  const SearchHomeView({
    super.key,
    required this.history,
    required this.hot,
    required this.onPick,
    required this.onRemoveHistory,
    required this.onClearHistory,
  });

  final List<String> history;
  final List<SearchSuggestItem> hot;
  final void Function(String keyword) onPick;
  final void Function(String keyword) onRemoveHistory;
  final void Function() onClearHistory;

  @override
  Widget build(BuildContext context) {
    try {
      final ColorScheme cs = Theme.of(context).colorScheme;
      // 分类去重（SearchSuggestItem.type = 热搜分组名）。
      final List<String> categories = <String>[];
      for (final h in hot) {
        final g = h.type.trim();
        if (g.isNotEmpty && !categories.contains(g)) categories.add(g);
      }
      return ListView(
        padding: const EdgeInsets.only(bottom: sp.Sp.gapXL),
        children: <Widget>[
          if (history.isNotEmpty) ...<Widget>[
            sp.SpSectionHeader(
              '搜索历史',
              action: '清空',
              onAction: () {
                try {
                  onClearHistory();
                } catch (e, st) {
                  Log.e(_tag, 'clear history failed', e, st);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: sp.Sp.pagePad),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final kw in history)
                    InputChip(
                      label: Text(kw, overflow: TextOverflow.ellipsis),
                      onPressed: () => onPick(kw),
                      onDeleted: () => onRemoveHistory(kw),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      backgroundColor: cs.surfaceContainer,
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                ],
              ),
            ),
          ],
          if (categories.isNotEmpty) ...<Widget>[
            const sp.SpSectionHeader('热门分类'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: sp.Sp.pagePad),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final c in categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: false,
                      onSelected: (_) => onPick(c),
                    ),
                ],
              ),
            ),
          ],
          const sp.SpSectionHeader('热门搜索'),
          if (hot.isEmpty)
            const sp.SpStateView(
              icon: Icons.local_fire_department_outlined,
              title: '暂无热搜',
              subtitle: '网络恢复后重试',
            )
          else
            for (var i = 0; i < hot.length && i < 50; i++)
              ListTile(
                leading: SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: i < 3 ? sp.Sp.green : sp.Sp.textSub,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                title: Text(
                  hot[i].keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: hot[i].type.isEmpty ? null : Text(hot[i].type),
                onTap: () => onPick(hot[i].keyword),
              ),
        ],
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return const SizedBox.shrink();
    }
  }
}
