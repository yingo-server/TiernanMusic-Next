// L6 surface/widgets · 音质档位弹层内容（功能对齐批3-C · GAP #30）
// 15 档分组：普通 5 / 蝰蛇 3 / 多轨 1 / 魔法 6（docs/PARITY_NOTES.md §2）。
// 这是 bottom sheet 的**内容**，不要 AppBar、不要 Scaffold；由装配处用
// showQualitySheet() 或自行 showModalBottomSheet 弹出。
// 铁律：只 import flutter + 桥 + 本层；try/catch + Log('surface.quality')。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show AudioQuality, magicQualities, toPref, vipQualities;
import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.quality';

/// 档位分组（UI 私有数据；档次顺序与 vipQualities()/magicQualities() 一致）。
class _QualityGroup {
  const _QualityGroup(this.title, this.items);
  final String title;
  final List<AudioQuality> items;
}

/// 中文展示名（与 toPref 的协议值分开展示，便于排障）。
/// Dart 3 穷尽 switch 表达式（新增档位编译期报错，不漏标签）。
String _label(AudioQuality q) => switch (q) {
      AudioQuality.q128 => '标准 128',
      AudioQuality.q320 => '高品质 320',
      AudioQuality.flac => '无损 FLAC',
      AudioQuality.high => '高解析 Hi-Res',
      AudioQuality.qSuper => '臻品 Super',
      AudioQuality.viperAtmos => '蝰蛇·全景声',
      AudioQuality.viperTape => '蝰蛇·母带',
      AudioQuality.viperClear => '蝰蛇·清澈',
      AudioQuality.multitrack => '多轨分轨',
      AudioQuality.magicPiano => '魔法·钢琴',
      AudioQuality.magicAcappella => '魔法·清唱',
      AudioQuality.magicDj => '魔法·DJ',
      AudioQuality.magicSurnay => '魔法·唢呐',
      AudioQuality.magicSubwoofer => '魔法·低音炮',
      AudioQuality.magicAncient => '魔法·古风',
    };

/// 弹层内容：ChoiceChip 列表，当前档位高亮；点选回调 onSelected(AudioQuality)。
class QualitySheet extends StatelessWidget {
  const QualitySheet({
    super.key,
    this.selected = AudioQuality.q128,
    required this.onSelected,
  });

  final AudioQuality selected;
  final void Function(AudioQuality quality) onSelected;

  List<_QualityGroup> _groups() {
    try {
      final vip = vipQualities();
      return <_QualityGroup>[
        _QualityGroup('普通（5）', vip.sublist(0, 5)),
        _QualityGroup('蝰蛇音效（3）', vip.sublist(5, 8)),
        _QualityGroup('多轨（1）', vip.sublist(8, 9)),
        _QualityGroup('魔法音效（6 · 三态全通）', magicQualities()),
      ];
    } catch (e, st) {
      Log.e(_tag, 'groups failed', e, st);
      return <_QualityGroup>[
        _QualityGroup('普通（5）', vipQualities().sublist(0, 5)),
        _QualityGroup('魔法音效（6）', magicQualities()),
      ];
    }
  }

  void _pick(AudioQuality q) {
    try {
      Log.d(_tag, 'pick ${toPref(q)}');
      onSelected(q);
    } catch (e, st) {
      Log.e(_tag, 'onSelected failed q=${toPref(q)}', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final groups = _groups();
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).hintColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('音质档位（15 档）',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...groups.map((g) => _group(context, g)),
            ],
          ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build failed', e, st);
      return const SafeArea(child: SizedBox(height: 120));
    }
  }

  Widget _group(BuildContext context, _QualityGroup g) {
    try {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(g.title,
                style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: g.items.map((q) {
                try {
                  return ChoiceChip(
                    label: Text('${_label(q)} · ${toPref(q)}'),
                    selected: selected == q,
                    onSelected: (_) => _pick(q),
                  );
                } catch (e, st) {
                  Log.e(_tag, 'chip build failed q=$q', e, st);
                  return const SizedBox.shrink();
                }
              }).toList(growable: false),
            ),
          ],
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'group build failed title=${g.title}', e, st);
      return const SizedBox.shrink();
    }
  }
}

/// 便捷弹出：返回选中的档位（外部负责写偏好）；取消/异常返回 null。
Future<AudioQuality?> showQualitySheet(
  BuildContext context, {
  required AudioQuality selected,
}) async {
  try {
    return await showModalBottomSheet<AudioQuality>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => QualitySheet(
        selected: selected,
        onSelected: (q) => Navigator.of(ctx).pop(q),
      ),
    );
  } catch (e, st) {
    Log.e(_tag, 'showQualitySheet failed', e, st);
    return null;
  }
}
