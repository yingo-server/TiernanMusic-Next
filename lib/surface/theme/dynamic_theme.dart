// L6 surface/theme · 动态主题状态（riverpod StateNotifier）
// GAP #19 封面取色/动态主题的状态容器：持有当前 ThemePalette?，
// 由封面 RGBA 字节经 extractDominant → fromSeed 更新，clear() 回落品牌紫。
//
// ⚠ 接线现状（诚实标注，审计B P2-1）：当前版本本链路未接线——
// 原封面取色桥 cover_color_bridge.dart 已删除，dynamicThemeProvider
// 暂无任何 UI 消费方。能力保留供后续封面字节接入；本文件为纯 L6 内部
// 状态容器（riverpod StateNotifier + 纯 Dart 算法），非死循环、非运行期
// 依赖，未接线不影响应用运行。
//
// 后续接线说明（供装配层参考，本批不改 player_page.dart / app_root.dart）：
//   ref.watch(dynamicThemeProvider) → ThemePalette?（null = 沿用 tnLight/DarkThemeData）
//   ref.read(dynamicThemeProvider.notifier).setDark(mode == 2) ← themeModeProvider
//   封面字节接线由装配层直接调 dynamicThemeProvider.updateFromImageBytes
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show StateNotifier, StateNotifierProvider;

import '../../bridges/bridge_logic.dart' show Log;
import 'color_extract.dart'
    show ColorSeed, ThemePalette, extractDominant, fromSeed;

export 'color_extract.dart'
    show ColorSeed, ThemePalette, extractDominant, fromSeed;

const String _tag = 'surface.dynamic';

/// 当前动态调色板；null 表示未取色（沿用 tnLightThemeData/tnDarkThemeData 常量表）。
class DynamicThemeNotifier extends StateNotifier<ThemePalette?> {
  DynamicThemeNotifier({bool dark = false}) : _dark = dark, super(null);

  bool _dark;
  ColorSeed? _lastSeed;

  /// 与 themeModeProvider（0 系统 / 1 亮 / 2 暗）同步；已取色时即时重算调色板。
  void setDark(bool dark) {
    try {
      if (_dark == dark) {
        Log.d(_tag, 'setDark unchanged=$dark');
        return;
      }
      _dark = dark;
      final ColorSeed? seed = _lastSeed;
      if (seed != null) state = fromSeed(seed, dark: _dark);
      Log.d(_tag, 'setDark -> $dark recomputed=${seed != null}');
    } catch (e, st) {
      Log.e(_tag, 'setDark failed', e, st);
    }
  }

  /// 封面 RGBA8888 字节 → 主色 → 调色板（同步计算，约 4096 样本，勿传超大图）。
  void updateFromImageBytes(List<int> bytes, int w, int h) {
    try {
      final ColorSeed seed = extractDominant(bytes, w, h);
      _lastSeed = seed;
      state = fromSeed(seed, dark: _dark);
      Log.d(_tag, 'updateFromImageBytes seed=$seed dark=$_dark '
          'bytes=${bytes.length} ${w}x$h');
    } catch (e, st) {
      Log.e(_tag, 'updateFromImageBytes failed', e, st);
    }
  }

  /// 清空取色（换回默认主题常量表）。
  void clear() {
    try {
      _lastSeed = null;
      state = null;
      Log.d(_tag, 'clear: dynamic palette dropped');
    } catch (e, st) {
      Log.e(_tag, 'clear failed', e, st);
    }
  }
}

/// 全局动态主题 provider（与 app_root.themeModeProvider 并列，互不覆盖）。
final StateNotifierProvider<DynamicThemeNotifier, ThemePalette?>
    dynamicThemeProvider =
    StateNotifierProvider<DynamicThemeNotifier, ThemePalette?>(
  (ref) => DynamicThemeNotifier(),
);
