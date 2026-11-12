import json, re, os

ROOT = '/var/minis/workspace/NextWorkspace/TiernanMusic-Next'
ARB = os.path.join(ROOT, 'lib/l10n')
CODES = ['zh', 'zh_Hant', 'en', 'ja', 'ko', 'es', 'fr', 'de', 'pt', 'ru']

def dart_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"

data = {}
for code in CODES:
    with open(os.path.join(ARB, f'app_{code}.arb'), encoding='utf-8') as f:
        raw = json.load(f)
    pairs = [(k, v) for k, v in raw.items()
             if not k.startswith('@') and isinstance(v, str)]
    data[code] = pairs
    print(f'{code}: {len(pairs)} keys')

keys = [k for k, _ in data['zh']]
assert all([k for k, _ in data[c]] == keys for c in CODES), 'key mismatch'

lines = ["// L6 surface/l10n · 轻量本地化辅助（10 语 × 20 键，纯 Dart const Map）",
         "// 与 lib/l10n/app_*.arb 严格同集；arb 由 CI gen-l10n 做键校验。",
         "// of(context) 取当前 Locale（缺省 zh）；缺键回退简体中文，再回退键名。",
         "// 失败必 Log('surface.l10n') 留痕，不静默吞。",
         "import 'package:flutter/material.dart' show BuildContext, Localizations, Locale;",
         "",
         "import '../../bridges/bridge_logic.dart' show Log;",
         "import '../../bridges/bridge_core.dart' show KeyValueSettings, StoragePaths;",
         "",
         "const String _tag = 'surface.l10n';",
         "",
         "const Map<String, Map<String, String>> _kCatalog = {"]
for code in CODES:
    lines.append(f"  {dart_str(code)}: {{")
    for k, v in data[code]:
        lines.append(f"    {dart_str(k)}: {dart_str(v)},")
    lines.append("  },")
lines += ["};", "",
"/// 轻量取词器：10 语人工级译文，语言码经 normalize 归一化。",
"class TnStrings {",
"  TnStrings._(this.code);",
"  final String code;",
"  static const String defaultCode = 'zh';",
"  static const String _localeKey = 'ui.locale';",
"",
"  /// 已实装语言（10 语全量）。",
"  static const List<String> supportedCodes = <String>[",
"    'zh', 'zh_Hant', 'en', 'ja', 'ko', 'es', 'fr', 'de', 'pt', 'ru',",
"  ];",
"",
"  /// 目标清单（已全部达成，保留供设置页显示 N/N）。",
"  static const List<String> plannedCodes = supportedCodes;",
"",
"  /// 语言偏好持久化：设置页 _pickLocale 调用；重启后由 app_root 读取。",
"  static void saveLocale(String code) {",
"    try {",
"      final s = KeyValueSettings(StoragePaths.I);",
"      s.setString(_localeKey, normalize(code));",
"    } catch (e, st) {",
"      Log.e(_tag, 'saveLocale failed', e, st);",
"    }",
"  }",
"",
"  /// 读取持久化的语言码；空/异常返回 ''（跟随系统）。",
"  static String loadLocale() {",
"    try {",
"      final s = KeyValueSettings(StoragePaths.I);",
"      final v = s.getString(_localeKey) ?? '';",
"      return v.isEmpty || v == 'system' ? '' : normalize(v);",
"    } catch (e, st) {",
"      Log.e(_tag, 'loadLocale failed', e, st);",
"      return '';",
"    }",
"  }",
"",
"  /// 生成的 MaterialApp locale（空串 = 跟随系统）。",
"  static Locale? appLocale() {",
"    final c = loadLocale();",
"    if (c.isEmpty) return null;",
"    if (c == 'zh_Hant') return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');",
"    return Locale(c);",
"  }",
"",
"  static TnStrings of(BuildContext context) {",
"    try {",
"      final saved = loadLocale();",
"      if (saved.isNotEmpty) return TnStrings._(saved);",
"      final l = Localizations.localeOf(context);",
"      return TnStrings._(normalize(l.languageCode, l.scriptCode, l.countryCode));",
"    } catch (e, st) {",
"      Log.e(_tag, 'of(context) failed, fallback=$defaultCode', e, st);",
"      return TnStrings._(defaultCode);",
"    }",
"  }",
"",
"  static TnStrings forCode(String code) => TnStrings._(normalize(code));",
"",
"  /// 归一化：zh+Hant/TW/HK/MO -> zh_Hant；其余按 supportedCodes 白名单。",
"  static String normalize([String? language, String? script, String? country]) {",
"    try {",
"      final lang = (language ?? '').toLowerCase();",
"      final sc = (script ?? '').toLowerCase();",
"      final cc = (country ?? '').toUpperCase();",
"      if (lang == 'zh_hant' || lang == 'zh' && (sc == 'hant' || cc == 'TW' || cc == 'HK' || cc == 'MO')) {",
"        return 'zh_Hant';",
"      }",
"      for (final c in supportedCodes) {",
"        if (c.toLowerCase() == lang) return c;",
"      }",
"      return defaultCode;",
"    } catch (e, st) {",
"      Log.e(_tag, 'normalize failed, fallback=$defaultCode', e, st);",
"      return defaultCode;",
"    }",
"  }",
"",
"  String tr(String key) {",
"    try {",
"      final hit = _kCatalog[code]?[key];",
"      if (hit != null && hit.isNotEmpty) return hit;",
"      final fallback = _kCatalog[defaultCode]?[key];",
"      if (fallback != null && fallback.isNotEmpty) {",
"        Log.d(_tag, 'missing key=$key code=$code, fallback=$defaultCode');",
"        return fallback;",
"      }",
"      Log.d(_tag, 'missing key=$key code=$code, fallback=keyName');",
"      return key;",
"    } catch (e, st) {",
"      Log.e(_tag, 'tr($key) failed', e, st);",
"      return key;",
"    }",
"  }",
"",
"  String call(String key) => tr(key);",
"}",
""]
out = os.path.join(ROOT, 'lib/surface/l10n/l10n_helper.dart')
with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('helper lines:', len(lines))
