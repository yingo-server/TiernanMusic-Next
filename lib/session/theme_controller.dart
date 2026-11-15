// L6 session · 主题模式控制器（批1-F1）
// ValueNotifier<int>（flutter foundation，L6 允许）；持久化经 bridge_core 的
// KeyValueSettings.shared(StoragePaths.I)。0 系统 / 1 亮 / 2 暗 / 3 纯黑。
// L7 只经 bridge_session 取 ThemeController，禁直连本文件。
library;

import 'package:flutter/foundation.dart';

import '../bridges/bridge_core.dart' show KeyValueSettings, StoragePaths;
import '../bridges/bridge_kernel.dart' show Log;

class ThemeController extends ValueNotifier<int> {
  ThemeController._() : super(2) {
    try {
      final v = KeyValueSettings.shared(StoragePaths.I).getInt(kThemeModeKey);
      if (v != null && v >= 0 && v <= 3) value = v;
    } catch (e, st) {
      Log.e('theme_controller', 'init load mode failed', e, st);
    }
  }

  /// 持久化键（settings.json）。
  static const String kThemeModeKey = 'ui.themeMode';

  /// 全局单例。
  static final ThemeController instance = ThemeController._();

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
