// L6 surface/pages · 设置页依赖定义（批03-C 环A破除）
// 从 settings_page.dart 抽出为独立类型文件：settings_page.dart 与 widgets/settings_qr_dialog.dart 共同 import，
// 消除 settings_page → settings_qr_dialog → settings_page 循环 import（审计B F-02 环A）。
// 铁律：只 import 桥层 bridge_logic；仅承载数据类型定义，业务/文案/回调零改动。
import '../../bridges/bridge_logic.dart';

/// 设置页依赖：全部经工厂注入（批8-B 追加 collect/onStartFm/verificationState 可选字段）。
class SettingsDeps {
  const SettingsDeps({
    required this.auth,
    required this.lyrics,
    required this.clearLyricCache,
    required this.lyricHashes,
    this.onLocaleChanged,
    this.accounts,
    this.collect,
    this.onStartFm,
    this.verificationState,
  });
  final AuthLogic auth;
  /// 多账号门面（可选；为空时设置页不显示账号管理卡片）。
  final AccountLogic? accounts;
  /// 收藏门面（可选；为空时收藏计数不显示）。
  final CollectLogic? collect;
  /// 歌词域（逐曲 clearFileCache 用）。
  final LyricsLogic lyrics;
  /// 缓存清理：逐曲 clearFileCache(hash) + LruCache.clear（由装配处组合）。
  final void Function() clearLyricCache;
  /// 曲库 hash 列表（用于逐曲清缓存；可直接给空实现退化）。
  final List<String> Function() lyricHashes;
  /// 语言切换回调（State 持有选中码；''=跟随系统，zh / zh_Hant / en）。
  final void Function(String code)? onLocaleChanged;
  /// 个人 FM 入口回调（可选；装配处接 FmLogic.start + controller.playAll）。
  final void Function()? onStartFm;
  /// 验证状态快照（可选；为空时不显示验证状态入口）。
  final String Function()? verificationState;
}
