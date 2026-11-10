// L6 surface/l10n · 轻量本地化辅助（功能对齐批3-A · 国际化骨架）
// 与 lib/l10n/app_*.arb 一一对应：3 语 × 20 键硬编码为 Dart const Map，
// 不引 flutter_gen / intl 生成链（arb 仅作资源与后续 CI 键校验来源）。
// of(context) 取当前 Locale（缺省 zh）；缺键回退简体中文，再回退键名。
// 失败必 Log('surface.l10n') 留痕，不静默吞。
import 'package:flutter/material.dart' show BuildContext, Localizations;

import '../../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.l10n';

/// 运行时字典：语言码 -> (键 -> 文案)。与 arb 三语 20 键严格同集。
const Map<String, Map<String, String>> _kCatalog = {
  'zh': {
    'appTitle': 'TiernanMusic', 'search': '搜索',
    'playlist': '歌单', 'library': '曲库',
    'settings': '设置', 'player': '播放器',
    'play': '播放', 'pause': '暂停',
    'next': '下一首', 'prev': '上一首',
    'login': '登录', 'logout': '登出',
    'theme': '主题', 'cache': '缓存',
    'about': '关于', 'comments': '评论',
    'mv': 'MV', 'lyrics': '歌词',
    'download': '下载', 'favorite': '收藏',
  },
  'en': {
    'appTitle': 'TiernanMusic', 'search': 'Search',
    'playlist': 'Playlists', 'library': 'Library',
    'settings': 'Settings', 'player': 'Player',
    'play': 'Play', 'pause': 'Pause',
    'next': 'Next', 'prev': 'Previous',
    'login': 'Sign in', 'logout': 'Sign out',
    'theme': 'Theme', 'cache': 'Cache',
    'about': 'About', 'comments': 'Comments',
    'mv': 'MV', 'lyrics': 'Lyrics',
    'download': 'Download', 'favorite': 'Favorite',
  },
  'zh_Hant': {
    'appTitle': 'TiernanMusic', 'search': '搜尋',
    'playlist': '歌單', 'library': '曲庫',
    'settings': '設定', 'player': '播放器',
    'play': '播放', 'pause': '暫停',
    'next': '下一首', 'prev': '上一首',
    'login': '登入', 'logout': '登出',
    'theme': '主題', 'cache': '快取',
    'about': '關於', 'comments': '評論',
    'mv': 'MV', 'lyrics': '歌詞',
    'download': '下載', 'favorite': '收藏',
  },
};

/// 轻量取词器：`final s = TnStrings.of(context); Text(s.tr('settings'));`
class TnStrings {
  TnStrings._(this.code);

  /// 归一化后的语言码：zh / zh_Hant / en。
  final String code;
  static const String defaultCode = 'zh';

  /// 已实装语言；其余 7 语见 lib/l10n/README.md（禁止机器臆造译文）。
  static const List<String> supportedCodes = <String>['zh', 'zh_Hant', 'en'];

  /// 依 Locale 选语言；缺失 Localizations / 异常时回退 zh。
  static TnStrings of(BuildContext context) {
    try {
      final l = Localizations.localeOf(context);
      return TnStrings._(
          normalize(l.languageCode, l.scriptCode, l.countryCode));
    } catch (e, st) {
      Log.e(_tag, 'of(context) failed, fallback=$defaultCode', e, st);
      return TnStrings._(defaultCode);
    }
  }

  /// 显式语言码构造（设置页 State / 预览用）；未知码回退 zh。
  static TnStrings forCode(String code) => TnStrings._(normalize(code));

  /// 归一化：zh+Hant/TW/HK/MO -> zh_Hant；en -> en；其余回退 zh。
  static String normalize([String? language, String? script, String? country]) {
    try {
      final lang = (language ?? '').toLowerCase();
      final sc = (script ?? '').toLowerCase();
      final cc = (country ?? '').toUpperCase();
      if (lang == 'zh_hant') return 'zh_Hant';
      if (lang != 'zh') return lang == 'en' ? 'en' : defaultCode;
      if (sc == 'hant' || cc == 'TW' || cc == 'HK' || cc == 'MO') {
        return 'zh_Hant';
      }
      return defaultCode;
    } catch (e, st) {
      Log.e(_tag, 'normalize failed, fallback=$defaultCode', e, st);
      return defaultCode;
    }
  }

  /// 取词：当前语 -> 简体中文 -> 键名；每次回退留 Log 痕迹。
  String tr(String key) {
    try {
      final hit = _kCatalog[code]?[key];
      if (hit != null && hit.isNotEmpty) return hit;
      final fallback = _kCatalog[defaultCode]?[key];
      if (fallback != null && fallback.isNotEmpty) {
        Log.d(_tag, 'missing key=$key code=$code, fallback=$defaultCode');
        return fallback;
      }
      Log.d(_tag, 'missing key=$key code=$code, fallback=keyName');
      return key;
    } catch (e, st) {
      Log.e(_tag, 'tr($key) failed', e, st);
      return key;
    }
  }

  /// callable 简写：s('play') == s.tr('play')。
  String call(String key) => tr(key);
}
