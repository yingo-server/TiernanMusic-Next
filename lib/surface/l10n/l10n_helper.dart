// L6 surface/l10n · 轻量本地化辅助（10 语 × 20 键，纯 Dart const Map）
// 与 lib/l10n/app_*.arb 严格同集；arb 由 CI gen-l10n 做键校验。
// of(context) 取当前 Locale（缺省 zh）；缺键回退简体中文，再回退键名。
// 失败必 Log('surface.l10n') 留痕，不静默吞。
import 'package:flutter/material.dart' show BuildContext, Localizations, Locale;

import '../../bridges/bridge_logic.dart' show Log;
import '../../bridges/bridge_core.dart' show KeyValueSettings, StoragePaths;

const String _tag = 'surface.l10n';

const Map<String, Map<String, String>> _kCatalog = {
  'zh': {
    'appTitle': 'TiernanMusicNext',
    'search': '搜索',
    'playlist': '歌单',
    'library': '曲库',
    'settings': '设置',
    'player': '播放器',
    'play': '播放',
    'pause': '暂停',
    'next': '下一首',
    'prev': '上一首',
    'login': '登录',
    'logout': '登出',
    'theme': '主题',
    'cache': '缓存',
    'about': '关于',
    'comments': '评论',
    'mv': 'MV',
    'lyrics': '歌词',
    'download': '下载',
    'favorite': '收藏',
  },
  'zh_Hant': {
    'appTitle': 'TiernanMusicNext',
    'search': '搜尋',
    'playlist': '歌單',
    'library': '曲庫',
    'settings': '設定',
    'player': '播放器',
    'play': '播放',
    'pause': '暫停',
    'next': '下一首',
    'prev': '上一首',
    'login': '登入',
    'logout': '登出',
    'theme': '主題',
    'cache': '快取',
    'about': '關於',
    'comments': '評論',
    'mv': 'MV',
    'lyrics': '歌詞',
    'download': '下載',
    'favorite': '收藏',
  },
  'en': {
    'appTitle': 'TiernanMusicNext',
    'search': 'Search',
    'playlist': 'Playlists',
    'library': 'Library',
    'settings': 'Settings',
    'player': 'Player',
    'play': 'Play',
    'pause': 'Pause',
    'next': 'Next',
    'prev': 'Previous',
    'login': 'Sign in',
    'logout': 'Sign out',
    'theme': 'Theme',
    'cache': 'Cache',
    'about': 'About',
    'comments': 'Comments',
    'mv': 'MV',
    'lyrics': 'Lyrics',
    'download': 'Download',
    'favorite': 'Favorite',
  },
  'ja': {
    'appTitle': 'TiernanMusicNext',
    'search': '検索',
    'playlist': 'プレイリスト',
    'library': 'ライブラリ',
    'settings': '設定',
    'player': 'プレーヤー',
    'play': '再生',
    'pause': '一時停止',
    'next': '次の曲',
    'prev': '前の曲',
    'login': 'ログイン',
    'logout': 'ログアウト',
    'theme': 'テーマ',
    'cache': 'キャッシュ',
    'about': 'アプリについて',
    'comments': 'コメント',
    'mv': 'MV',
    'lyrics': '歌詞',
    'download': 'ダウンロード',
    'favorite': 'お気に入り',
  },
  'ko': {
    'appTitle': 'TiernanMusicNext',
    'search': '검색',
    'playlist': '플레이리스트',
    'library': '보관함',
    'settings': '설정',
    'player': '플레이어',
    'play': '재생',
    'pause': '일시정지',
    'next': '다음 곡',
    'prev': '이전 곡',
    'login': '로그인',
    'logout': '로그아웃',
    'theme': '테마',
    'cache': '캐시',
    'about': '앱 정보',
    'comments': '댓글',
    'mv': 'MV',
    'lyrics': '가사',
    'download': '다운로드',
    'favorite': '즐겨찾기',
  },
  'es': {
    'appTitle': 'TiernanMusicNext',
    'search': 'Buscar',
    'playlist': 'Listas de reproducción',
    'library': 'Biblioteca',
    'settings': 'Ajustes',
    'player': 'Reproductor',
    'play': 'Reproducir',
    'pause': 'Pausar',
    'next': 'Siguiente',
    'prev': 'Anterior',
    'login': 'Iniciar sesión',
    'logout': 'Cerrar sesión',
    'theme': 'Tema',
    'cache': 'Caché',
    'about': 'Acerca de',
    'comments': 'Comentarios',
    'mv': 'MV',
    'lyrics': 'Letras',
    'download': 'Descargar',
    'favorite': 'Favoritos',
  },
  'fr': {
    'appTitle': 'TiernanMusicNext',
    'search': 'Rechercher',
    'playlist': 'Playlists',
    'library': 'Bibliothèque',
    'settings': 'Paramètres',
    'player': 'Lecteur',
    'play': 'Lire',
    'pause': 'Pause',
    'next': 'Suivant',
    'prev': 'Précédent',
    'login': 'Se connecter',
    'logout': 'Se déconnecter',
    'theme': 'Thème',
    'cache': 'Cache',
    'about': 'À propos',
    'comments': 'Commentaires',
    'mv': 'MV',
    'lyrics': 'Paroles',
    'download': 'Télécharger',
    'favorite': 'Favoris',
  },
  'de': {
    'appTitle': 'TiernanMusicNext',
    'search': 'Suchen',
    'playlist': 'Wiedergabelisten',
    'library': 'Mediathek',
    'settings': 'Einstellungen',
    'player': 'Player',
    'play': 'Abspielen',
    'pause': 'Pause',
    'next': 'Weiter',
    'prev': 'Zurück',
    'login': 'Anmelden',
    'logout': 'Abmelden',
    'theme': 'Design',
    'cache': 'Cache',
    'about': 'Über',
    'comments': 'Kommentare',
    'mv': 'MV',
    'lyrics': 'Liedtext',
    'download': 'Herunterladen',
    'favorite': 'Favoriten',
  },
  'pt': {
    'appTitle': 'TiernanMusicNext',
    'search': 'Pesquisar',
    'playlist': 'Listas de reprodução',
    'library': 'Biblioteca',
    'settings': 'Definições',
    'player': 'Reprodutor',
    'play': 'Reproduzir',
    'pause': 'Pausar',
    'next': 'Seguinte',
    'prev': 'Anterior',
    'login': 'Entrar',
    'logout': 'Sair',
    'theme': 'Tema',
    'cache': 'Cache',
    'about': 'Sobre',
    'comments': 'Comentários',
    'mv': 'MV',
    'lyrics': 'Letras',
    'download': 'Transferir',
    'favorite': 'Favoritos',
  },
  'ru': {
    'appTitle': 'TiernanMusicNext',
    'search': 'Поиск',
    'playlist': 'Плейлисты',
    'library': 'Медиатека',
    'settings': 'Настройки',
    'player': 'Плеер',
    'play': 'Воспроизвести',
    'pause': 'Пауза',
    'next': 'Следующий',
    'prev': 'Предыдущий',
    'login': 'Войти',
    'logout': 'Выйти',
    'theme': 'Тема',
    'cache': 'Кэш',
    'about': 'О приложении',
    'comments': 'Комментарии',
    'mv': 'MV',
    'lyrics': 'Текст песни',
    'download': 'Скачать',
    'favorite': 'Избранное',
  },
};

/// 轻量取词器：10 语人工级译文，语言码经 normalize 归一化。
class TnStrings {
  TnStrings._(this.code);
  final String code;
  static const String defaultCode = 'zh';
  static const String _localeKey = 'ui.locale';

  /// 已实装语言（10 语全量）。
  static const List<String> supportedCodes = <String>[
    'zh', 'zh_Hant', 'en', 'ja', 'ko', 'es', 'fr', 'de', 'pt', 'ru',
  ];

  /// 目标清单（已全部达成，保留供设置页显示 N/N）。
  static const List<String> plannedCodes = supportedCodes;

  /// 语言偏好持久化：设置页 _pickLocale 调用；重启后由 app_root 读取。
  static void saveLocale(String code) {
    try {
      final s = KeyValueSettings(StoragePaths.I);
      s.setString(_localeKey, normalize(code));
    } catch (e, st) {
      Log.e(_tag, 'saveLocale failed', e, st);
    }
  }

  /// 读取持久化的语言码；空/异常返回 ''（跟随系统）。
  static String loadLocale() {
    try {
      final s = KeyValueSettings(StoragePaths.I);
      final v = s.getString(_localeKey) ?? '';
      return v.isEmpty || v == 'system' ? '' : normalize(v);
    } catch (e, st) {
      Log.e(_tag, 'loadLocale failed', e, st);
      return '';
    }
  }

  /// 生成的 MaterialApp locale（空串 = 跟随系统）。
  static Locale? appLocale() {
    final c = loadLocale();
    if (c.isEmpty) return null;
    if (c == 'zh_Hant') return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    return Locale(c);
  }

  static TnStrings of(BuildContext context) {
    try {
      final saved = loadLocale();
      if (saved.isNotEmpty) return TnStrings._(saved);
      final l = Localizations.localeOf(context);
      return TnStrings._(normalize(l.languageCode, l.scriptCode, l.countryCode));
    } catch (e, st) {
      Log.e(_tag, 'of(context) failed, fallback=$defaultCode', e, st);
      return TnStrings._(defaultCode);
    }
  }

  static TnStrings forCode(String code) => TnStrings._(normalize(code));

  /// 归一化：zh+Hant/TW/HK/MO -> zh_Hant；其余按 supportedCodes 白名单。
  static String normalize([String? language, String? script, String? country]) {
    try {
      final lang = (language ?? '').toLowerCase();
      final sc = (script ?? '').toLowerCase();
      final cc = (country ?? '').toUpperCase();
      if (lang == 'zh_hant' || lang == 'zh' && (sc == 'hant' || cc == 'TW' || cc == 'HK' || cc == 'MO')) {
        return 'zh_Hant';
      }
      for (final c in supportedCodes) {
        if (c.toLowerCase() == lang) return c;
      }
      return defaultCode;
    } catch (e, st) {
      Log.e(_tag, 'normalize failed, fallback=$defaultCode', e, st);
      return defaultCode;
    }
  }

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

  String call(String key) => tr(key);
}
