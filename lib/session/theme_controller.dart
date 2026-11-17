// L6 session · 主题模式控制器（批1-F1）
// ValueNotifier<int>（flutter foundation，L6 允许）；持久化经 bridge_core 的
// KeyValueSettings.shared(StoragePaths.I)。0 系统 / 1 亮 / 2 暗 / 3 纯黑。
// L7 只经 bridge_session 取 ThemeController，禁直连本文件。
library;

import 'package:flutter/foundation.dart';

import '../bridges/bridge_core.dart'
    show KeyValueSettings, StoragePaths, ColorSeed, fromSeed, ThemePalette;
import '../bridges/bridge_kernel.dart' show Log;

/// 主题控制器：mode（0系统/1亮/2暗/3纯黑）+ seed（动态取色主色 ARGB）。
/// 阶段B B6：接入 L4 fromSeed，让动态取色链（L4→L6→L7）打通。
class ThemeController extends ValueNotifier<int> {
  ThemeController._() : super(2) {
    try {
      final s = KeyValueSettings.shared(StoragePaths.I);
      final v = s.getInt(kThemeModeKey);
      if (v != null && v >= 0 && v <= 3) value = v;
      final seed = s.getInt(kSeedKey);
      if (seed != null) _seedArgb = seed;
    } catch (e, st) {
      Log.e('theme_controller', 'init load failed', e, st);
    }
  }

  /// 持久化键（settings.json）。
  static const String kThemeModeKey = 'ui.themeMode';
  static const String kSeedKey = 'ui.seedArgb';

  /// 全局单例。
  static final ThemeController instance = ThemeController._();

  /// 当前动态取色种子（ARGB int）。L7 Sp.theme 用它派生 ColorScheme。
  int _seedArgb = 0xFF1DB954; // 默认品牌绿
  int get seedArgb => _seedArgb;

  /// 从 L4 ColorSeed 派生调色板并更新种子（封面取色入口）。
  /// 返回派生出的 ThemePalette 供调用方参考；失败保留旧种子。
  ThemePalette? applySeed(ColorSeed seed, {required bool dark}) {
    try {
      final palette = fromSeed(seed, dark: dark);
      _seedArgb = palette.primary;
      KeyValueSettings.shared(StoragePaths.I).setInt(kSeedKey, _seedArgb);
      notifyListeners();
      Log.d('theme_controller', 'applySeed primary=${palette.primary.toRadixString(16)}');
      return palette;
    } catch (e, st) {
      Log.e('theme_controller', 'applySeed failed', e, st);
      return null;
    }
  }

  /// 切换主题模式：写值 + 持久化 + 通知监听者（AppRoot / 设置页）。
  void setMode(int mode) {
    try {
      if (mode < 0 || mode > 3) {
        Log.w('theme_controller', 'setMode invalid: $mode');
        return;
      }
      value = mode;
      final ok = KeyValueSettings.shared(StoragePaths.I)
          .setInt(kThemeModeKey, mode);
      if (!ok) {
        Log.w('theme_controller', 'persist mode failed: $mode');
      }
      notifyListeners();
    } catch (e, st) {
      Log.e('theme_controller', 'setMode($mode) failed', e, st);
    }
  }
}
