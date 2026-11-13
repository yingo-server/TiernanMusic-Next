// L6 surface/theme · 动态主题状态（riverpod StateNotifier）
// GAP #19 封面取色/动态主题的状态容器：持有当前 ThemePalette?，
// 由封面 RGBA 字节经 extractDominant → fromSeed 更新，clear() 回落品牌紫。
//
// ── 收敛期目标（功能批次统一收敛阶段执行，本批不改桥）──
// 本能力当前为 L6 surface 内部状态，仅在 surface 层内被 widgets/pages 消费；
// 待 lib/bridges/bridge_surface.dart 补齐后，dynamicThemeProvider / ThemePalette
// 「经 bridge_surface 暴露给上层」，桥侧逐函数 try/catch + Log 留痕，只做转发
// 与错误翻译；在此之前不新增跨更高层 import，不改 bridge_logic / bridge_core。
//
// 装配契约（主会话执行，本批不改 player_page.dart / app_root.dart）：
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
