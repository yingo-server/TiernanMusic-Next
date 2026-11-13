// L6 surface/pages · 搜索首页态（截图基线：搜索历史 + 热门分类 + 热词）
// 仅负责展示与回调；历史持久化由 search_page 经 KeyValueSettings 负责。
// 铁律：不 import 下层非桥文件；每渲染分支 try/catch 兜底。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show SearchSuggestItem, Log;
import '../theme/tn_theme.dart' show TnDims;
import '../widgets/m3/m3_section_header.dart' show M3SectionHeader;
import '../widgets/m3/m3_state_views.dart' show M3EmptyState;

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
        padding: const EdgeInsets.only(bottom: TnDims.padXL),
        children: <Widget>[
          if (history.isNotEmpty) ...<Widget>[
            M3SectionHeader(
              title: '搜索历史',
              actionLabel: '清空',
              onAction: () {
                try {
                  onClearHistory();
                } catch (e, st) {
                  Log.e(_tag, 'clear history failed', e, st);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: TnDims.padL),
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
            const M3SectionHeader(
              title: '热门分类',
              padding: EdgeInsets.fromLTRB(
                  TnDims.padL, TnDims.padXL, TnDims.padL, TnDims.padM),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: TnDims.padL),
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
          const M3SectionHeader(title: '热门搜索'),
          if (hot.isEmpty)
            const M3EmptyState(
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
                          color: i < 3 ? cs.primary : cs.onSurfaceVariant,
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
