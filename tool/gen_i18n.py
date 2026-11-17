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

lines = ["// L4 core/l10n · 轻量本地化常量表（V2：由 surface 下沉，零 UI SDK）",
         "// 与 lib/l10n/app_*.arb 严格同集；arb 由 CI gen-l10n 做键校验。",
         "// L7 自行把 appLocaleCode() 包成 Locale；core 不依赖 flutter。",
         "// 失败必 Log('core.l10n') 留痕，不静默吞。",
         "",
         "import '../../bridges/bridge_kernel.dart' show Log;",
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
"  /// 语言偏好持久化：L7 设置页调用；重启后由 L7 读取。",
"  /// [code] 空/'system' = 跟随系统（存空串，不经 normalize 避免落到 zh）。",
"  static void saveLocale(String code) {",
"    try {",
"      final s = KeyValueSettings.shared(StoragePaths.I);",
"      if (code.isEmpty || code == 'system') {",
"        s.setString(_localeKey, '');",
"        return;",
"      }",
"      s.setString(_localeKey, normalize(code));",
"    } catch (e, st) {",
"      Log.e(_tag, 'saveLocale failed', e, st);",
"    }",
"  }",
"",
"  /// 读取持久化的语言码；空/异常返回 ''（跟随系统）。",
"  static String loadLocale() {",
"    try {",
"      final s = KeyValueSettings.shared(StoragePaths.I);",
"      final v = s.getString(_localeKey) ?? '';",
"      return v.isEmpty || v == 'system' ? '' : normalize(v);",
"    } catch (e, st) {",
"      Log.e(_tag, 'loadLocale failed', e, st);",
"      return '';",
"    }",
"  }",
"",
"  /// L7 自行把该码包成 Locale（core 零 flutter 依赖）。",
"  static String? appLocaleCode() {",
"    final c = loadLocale();",
"    return c.isEmpty ? null : c;",
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
out = os.path.join(ROOT, 'lib/core/l10n/strings.dart')
with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('helper lines:', len(lines))
