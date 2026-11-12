// L6 surface/theme · 主题模式唯一状态源（0=跟随系统 1=亮 2=暗 3=纯黑）
// 背景：此前 app_root 与 settings_page 各自声明同名 themeModeProvider 且互不 import，
//       导致设置页切换主题对实际渲染零影响（split-brain）。本文件是唯一真身，
//       两处均 import 此处；持久化经 KeyValueSettings（'ui.themeMode'）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_core.dart' show KeyValueSettings;
import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.theme_state';

/// 主题模式：0=跟随系统 1=亮 2=暗 3=纯黑。
class ThemeModeNotifier extends StateNotifier<int> {
  ThemeModeNotifier(this._settings) : super(_read(_settings));
  final KeyValueSettings? _settings;

  /// 设置主题模式并持久化（失败仅留痕，不阻断 UI）。
  void set(int mode) {
    try {
      final v = mode < 0 ? 0 : (mode > 3 ? 3 : mode);
      state = v;
      _settings?.setInt('ui.themeMode', v);
      Log.d(_tag, 'theme mode -> $v');
    } catch (e, st) {
      Log.e(_tag, 'set theme mode failed', e, st);
    }
  }

  /// 循环切换（跟随系统 → 亮 → 暗 → 纯黑 → 跟随系统）。
  void cycle() => set((state + 1) % 4);

  static int _read(KeyValueSettings? s) {
    try {
      final v = s?.getInt('ui.themeMode') ?? 0;
      return v < 0 ? 0 : (v > 3 ? 3 : v);
    } catch (e, st) {
      Log.e(_tag, 'read theme mode failed', e, st);
      return 0;
    }
  }
}

/// 唯一主题模式 provider（app_root 与 settings_page 共用）。
final StateNotifierProvider<ThemeModeNotifier, int> themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, int>(
        (ref) => ThemeModeNotifier(ref.read(settingsProvider)));

/// 设置存储 provider（bootstrap 装配后由 surface 注入）。
final Provider<KeyValueSettings?> settingsProvider =
    Provider<KeyValueSettings?>((_) => null);
