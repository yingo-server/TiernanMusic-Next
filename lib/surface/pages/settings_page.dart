// L6 surface/pages · 设置页模块（buildSettingsPageModule）
// 由 modules.dart（批4-B）汇总注册：SurfaceRegistry.install(buildSettingsPageModule(...))。
// 登录区（二维码登录轮询）/ 主题切换（亮/暗/跟随系统，riverpod 状态由批4-B 提供）/ 缓存清理 / 关于。
// 二维码登录对话框 + 多账号管理区已拆至 widgets/settings_qr_dialog.dart（批R1-B）。
// 铁律：只 import flutter/miuix/riverpod/bridge_logic/bridge_core/本层；try/catch + Log('surface.settings')。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart';
import '../l10n/l10n_helper.dart' show TnStrings;
import '../registry.dart';
import '../theme/theme_state.dart' show themeModeProvider;
import '../widgets/m3/m3_section_header.dart' show M3SectionHeader;
import '../theme/tn_theme.dart';
import '../widgets/tn_app_bar.dart' show TnAppBar;
import '../widgets/settings_qr_dialog.dart'
    show QrLoginDialog, AccountSection;

import 'settings_deps.dart' show SettingsDeps;

// 批03-C 环A破除：SettingsDeps 定义迁至 settings_deps.dart；此处继续 export，
// 保持 assembly 从 settings_page.dart 取类型的 import 不变。
export 'settings_deps.dart' show SettingsDeps;

const String _tag = 'surface.settings';
const String kAppVersion = '26.11.10.1';

/// 设置页模块：id='settings'，底部导航入口「设置」。
class SettingsPageModule extends SurfaceModule {
  SettingsPageModule({required this.deps});

  final SettingsDeps deps;

  @override
  String get id => 'settings';

  @override
  String get route => '/settings';

  @override
  NavEntry get navEntry => const NavEntry('设置', 'settings');

  @override
  bool enabled(LogicFacade logic) => true;

  @override
  WidgetBuilder builder(LogicFacade logic) => (_) => SettingsPage(deps: deps);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.deps});

  final SettingsDeps deps;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loggedIn = false;
  String _userid = '';
  // 从持久化读取偏好（'' = 跟随系统；失败降级 ''），重启后保持。
  String _localeCode = TnStrings.loadLocale();

  @override
  void initState() {
    super.initState();
    _refreshLoginState();
  }

  void _refreshLoginState() {
    try {
      _userid = widget.deps.auth.session.userid;
      _loggedIn = _userid.isNotEmpty;
    } catch (e, st) {
      Log.e(_tag, 'refreshLoginState failed', e, st);
      _loggedIn = false;
      _userid = '';
    }
  }

  void _pickLocale(String code) {
    try {
      setState(() => _localeCode = code);
      // 10 语偏好持久化（KeyValueSettings 'ui.locale'），'' = 跟随系统。
      TnStrings.saveLocale(code);
      widget.deps.onLocaleChanged?.call(code);
    } catch (e, st) {
      Log.e(_tag, 'set locale failed', e, st);
    }
  }

  Future<void> _showQrLoginDialog() async {
    try {
      final st = await widget.deps.auth.createQrLogin();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QrLoginDialog(deps: widget.deps, state: st),
      );
      if (!mounted) return;
      setState(_refreshLoginState);
    } catch (e, st) {
      Log.e(_tag, 'createQrLogin failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建二维码失败：$e')));
      }
    }
  }

  Future<void> _logout() async {
    try {
      final ok = widget.deps.auth.logout();
      Log.d(_tag, 'logout ok=$ok');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ok ? '已登出' : '登出失败')));
        setState(_refreshLoginState);
      }
    } catch (e, st) {
      Log.e(_tag, 'logout failed', e, st);
    }
  }

  Future<void> _clearCache() async {
    try {
      for (final h in widget.deps.lyricHashes()) {
        widget.deps.lyrics.clearFileCache(h); // 逐曲内存+文件
      }
      widget.deps.clearLyricCache(); // 兜底 LruCache.clear 等
      Log.d(_tag, 'cache cleared');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('歌词缓存已清理')));
      }
    } catch (e, st) {
      Log.e(_tag, 'clearCache failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清理失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = TnText.of(context);
    return Scaffold(
      appBar: const TnAppBar(title: '设置'),
      body: ListView(
        children: [
          const M3SectionHeader(
            title: '账号',
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          ),
          ListTile(
            leading: Icon(_loggedIn ? Icons.account_circle : Icons.login),
            title: Text(_loggedIn ? '已登录：$_userid' : '未登录（酷狗账号）'),
            subtitle: Text(_loggedIn ? '点击登出' : '扫码登录后可使用会员音质等功能', style: t.aux),
            trailing: _loggedIn
                ? TextButton(onPressed: _logout, child: const Text('登出'))
                : TextButton(
                    onPressed: _showQrLoginDialog,
                    child: const Text('二维码登录')),
          ),
          // ── 多账号管理（批2 收尾接线）──
          if (widget.deps.accounts != null)
            AccountSection(accounts: widget.deps.accounts!),
          if (widget.deps.collect != null)
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('我的收藏'),
              subtitle: Text(
                  '已收藏 ${widget.deps.collect!.count} 首 · '
                  '列表 ${widget.deps.collect!.listFavorites().length} 条',
                  style: t.aux),
            ),
          if (widget.deps.onStartFm != null)
            ListTile(
              leading: const Icon(Icons.radio),
              title: const Text('个人 FM'),
              subtitle: Text('随机连续播放，喜欢/不喜欢随时调整', style: t.aux),
              onTap: () {
                try {
                  widget.deps.onStartFm!();
                } catch (e, st) {
                  Log.e(_tag, 'start fm failed', e, st);
                }
              },
            ),
          if (widget.deps.verificationState != null)
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('验证状态'),
              subtitle: Text(widget.deps.verificationState!(), style: t.aux),
            ),
          const Divider(height: 1),
          const M3SectionHeader(
            title: '外观',
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          ),
          Consumer(builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return ListTile(
              leading: const Icon(Icons.brightness_6),
              title: const Text('主题'),
              subtitle: SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text('系统')),
                  ButtonSegment<int>(value: 1, label: Text('亮')),
                  ButtonSegment<int>(value: 2, label: Text('暗')),
                  ButtonSegment<int>(value: 3, label: Text('纯黑')),
                ],
                selected: {mode},
                onSelectionChanged: (s) {
                  try {
                    ref.read(themeModeProvider.notifier).set(s.first);
                    Log.d(_tag, 'theme mode=${s.first}');
                  } catch (e, st) {
                    Log.e(_tag, 'set theme failed', e, st);
                  }
                },
              ),
            );
          }),
          const Divider(height: 1),
          // ── 语言（State 持有 + 回调注入；''=跟随系统，禁引入新依赖）──
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('语言'),
            trailing: DropdownButton<String>(
              value: _localeCode, onChanged: (v) => _pickLocale(v ?? ''),
              items: const [
                DropdownMenuItem(value: '', child: Text('跟随系统')),
                DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                DropdownMenuItem(value: 'zh_Hant', child: Text('繁體中文')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'ja', child: Text('日本語')),
                DropdownMenuItem(value: 'ko', child: Text('한국어')),
                DropdownMenuItem(value: 'es', child: Text('Español')),
                DropdownMenuItem(value: 'fr', child: Text('Français')),
                DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                DropdownMenuItem(value: 'pt', child: Text('Português')),
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── 缓存 ──
          const M3SectionHeader(
            title: '播放与存储',
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('清理歌词缓存'),
            subtitle: Text('内存缓存 + 本地歌词文件', style: t.aux),
            onTap: _clearCache,
          ),
          const Divider(height: 1),
          // ── 关于 ──
          const M3SectionHeader(
            title: '关于',
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('TiernanMusicNext v$kAppVersion'),
          ),
          // 批6-B：多语言状态行（3/10 语可用，7 语待人工翻译）。
          Builder(builder: (ctx) {
            final s = TnStrings.of(ctx);
            return Padding(
              padding: const EdgeInsets.fromLTRB(tnPadL, 0, tnPadL, tnPadS),
              child: Text(
                '多语言：${TnStrings.supportedCodes.length}/'
                '${TnStrings.plannedCodes.length} 语可用'
                '（${TnStrings.plannedCodes.length - TnStrings.supportedCodes.length}'
                ' 语待人工翻译）',
                style: t.aux,
              ),
            );
          }),
        ],
      ),
    );
  }
}
