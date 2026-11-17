// L6 session · 语言区域控制器（阶段B B7 P0 修复：语言切换完全不可用）
// ValueNotifier<String>（flutter foundation，L6 允许）；持久化经 TnStrings
// （L4 core/l10n，经 bridge_core 门面）。L7 只经 bridge_session 取本控制器。
// 0 跟随系统用空串，否则为 TnStrings 归一化后的语言码（zh/zh_Hant/en/...）。
library;

import 'package:flutter/foundation.dart';

import '../bridges/bridge_core.dart' show TnStrings;
import '../bridges/bridge_kernel.dart' show Log;

class LocaleController extends ValueNotifier<String> {
  LocaleController._() : super(TnStrings.loadLocale()) {
    Log.d(_tag, 'init locale=${value.isEmpty ? "system" : value}');
  }

  static const String _tag = 'session.locale';
  static final LocaleController instance = LocaleController._();

  /// 可选语言（与 TnStrings.supportedCodes 一致）+ 跟随系统（空串）。
  static const List<String> codes = <String>[
    '', 'zh', 'zh_Hant', 'en', 'ja', 'ko', 'es', 'fr', 'de', 'pt', 'ru',
  ];

  /// 切换语言：持久化 + 通知（app_root 监听后重建 MaterialApp）。
  void setLocale(String code) {
    try {
      final s = KeyValueSettings.shared(StoragePaths.I);
      if (code.isEmpty || code == 'system') {
        // 跟随系统：直接存空串（不能走 normalize——normalize('system') 会
        // 落到 defaultCode='zh'，导致"跟随系统"变成强制简体中文）。
        s.setString(_localeKey, '');
        value = '';
        Log.d(_tag, 'setLocale system');
        notifyListeners();
        return;
      }
      final norm = TnStrings.normalize(code);
      TnStrings.saveLocale(norm);
      value = norm;
      Log.d(_tag, 'setLocale $code -> $value');
      notifyListeners();
    } catch (e, st) {
      Log.e(_tag, 'setLocale($code) failed', e, st);
    }
  }

  static const String _localeKey = 'ui.locale';
}
