// L7 surface/l10n · 文案取词门面（审查修复 阶段A「文案没改」）
//
// 权威资源：lib/l10n/app_*.arb（10 语，键集一致），由 tool/gen_i18n.py
// 同步生成 L4 core/l10n/strings.dart 的 TnStrings 常量表（单一事实源）。
// 本门面只做两件事：① 按当前 Locale 选 TnStrings；② 提供 S.of(ctx).t(key)。
// 零硬编码文案；未命中 key 时 TnStrings.tr 自带 fallback 到 zh + keyName。
//
// 用户纪律：日常版本只保证 zh / zh_Hant / en；其余 7 语先落英文占位，
// CI 翻译管线（i18n_translate.yml）重要版本手动触发后补齐。
library;

import 'package:flutter/widgets.dart' show BuildContext, Locale, Localizations;

import '../../bridges/bridge_core.dart' show TnStrings;

/// surface 唯一取词入口。
class S {
  S._(this._strings);
  final TnStrings _strings;

  static TnStrings _fromLocale(Locale? locale) {
    // zh + Hant/TW/HK/MO → zh_Hant；其余按 TnStrings.normalize 白名单。
    final l = locale?.languageCode ?? '';
    final c = locale?.countryCode ?? '';
    if (l == 'zh' && (c == 'TW' || c == 'HK' || c == 'MO' || c == 'Hant')) {
      return TnStrings.forCode('zh_Hant');
    }
    return TnStrings.forCode(l.isEmpty ? 'zh' : l);
  }

  static S of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    // 设置页持久化语言优先（ThemeController 之外单独走 TnStrings.loadLocale）。
    final saved = TnStrings.loadLocale();
    return S._(saved.isNotEmpty ? TnStrings.forCode(saved) : _fromLocale(locale));
  }

  /// 取词（key 缺失时返回 key 本身，便于开发期发现漏键）。
  String t(String key) => _strings.tr(key);
}

/// 无 context 场景（如 L7 模块 builder 之外的错误文案拼接）：跟随系统/持久化语言。
String tr(String key) {
  final saved = TnStrings.loadLocale();
  return TnStrings.forCode(saved.isEmpty ? 'zh' : saved).tr(key);
}
