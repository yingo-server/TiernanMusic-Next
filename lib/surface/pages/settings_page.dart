// L6 surface/pages · 设置页模块（buildSettingsPageModule）
// 由 modules.dart（批4-B）汇总注册：SurfaceRegistry.install(buildSettingsPageModule(...))。
// 登录区（二维码登录轮询）/ 主题切换（亮/暗/跟随系统，riverpod 状态由批4-B 提供）/ 缓存清理 / 关于。
// 铁律：只 import flutter/miuix/riverpod/bridge_logic/bridge_core/本层；try/catch + Log('surface.settings')。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart';
import '../registry.dart';
import '../theme/tn_theme.dart';
import '../widgets/tn_app_bar.dart' show TnAppBar;
import '../widgets/qr_view.dart';

const String _tag = 'surface.settings';
const String kAppVersion = '26.11.10.1';

/// 主题模式 riverpod 状态（批4-B 的 ThemeController 可替换实现；默认跟随系统）。
/// anyState：0=跟随系统 1=亮 2=暗。
final StateProvider<int> themeModeProvider = StateProvider<int>((_) => 0);

/// 设置页依赖：全部经工厂注入。
class SettingsDeps {
  const SettingsDeps({
    required this.auth,
    required this.lyrics,
    required this.clearLyricCache,
    required this.lyricHashes,
    this.onLocaleChanged,
  });

  final AuthLogic auth;

  /// 歌词域（逐曲 clearFileCache 用）。
  final LyricsLogic lyrics;

  /// 缓存清理：逐曲 clearFileCache(hash) + LruCache.clear（由装配处组合）。
  final void Function() clearLyricCache;

  /// 曲库 hash 列表（用于逐曲清缓存；可直接给空实现退化）。
  final List<String> Function() lyricHashes;

  /// 语言切换回调（State 持有选中码；''=跟随系统，zh / zh_Hant / en）。
  final void Function(String code)? onLocaleChanged;
}

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
  String _localeCode = '';

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
        builder: (_) => _QrLoginDialog(deps: widget.deps, state: st),
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
          // ── 账号 ──
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
          const Divider(height: 1),
          // ── 主题 ──
          Consumer(builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return ListTile(
              leading: const Icon(Icons.brightness_6),
              title: const Text('主题'),
              subtitle: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('系统')),
                  ButtonSegment(value: 1, label: Text('亮')),
                  ButtonSegment(value: 2, label: Text('暗')),
                ],
                selected: {mode},
                onSelectionChanged: (s) {
                  try {
                    ref.read(themeModeProvider.notifier).state = s.first;
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
                DropdownMenuItem(value: 'zh', child: Text('简体')),
                DropdownMenuItem(value: 'zh_Hant', child: Text('繁中')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── 缓存 ──
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('清理歌词缓存'),
            subtitle: Text('内存缓存 + 本地歌词文件', style: t.aux),
            onTap: _clearCache,
          ),
          const Divider(height: 1),
          // ── 关于 ──
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('TiernanMusic-Next v$kAppVersion'),
          ),
        ],
      ),
    );
  }
}

/// 二维码登录对话框：渲染 qrcode 文本 + 每 1.5s 轮询 pollQrLogin，status 展示。
class _QrLoginDialog extends StatefulWidget {
  const _QrLoginDialog({required this.deps, required this.state});

  final SettingsDeps deps;
  final QrLoginState state;

  @override
  State<_QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<_QrLoginDialog> {
  late QrLoginState _state = widget.state;
  Timer? _poll;
  String _hint = '等待扫码…';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted || _state.status == QrLoginStatus.success) return;
    try {
      final s = await widget.deps.auth.pollQrLogin(_state.key);
      if (!mounted) return;
      setState(() {
        _state = s;
        _hint = switch (s.status) {
          QrLoginStatus.waitScan => '等待扫码…',
          QrLoginStatus.waitConfirm => '已扫码，请在手机上确认',
          QrLoginStatus.success => '登录成功',
          QrLoginStatus.expired => '二维码已过期',
        };
      });
      if (s.status == QrLoginStatus.success) {
        // 即时恢复会话（restoreSession 从持久层回灌，幂等）；提示重启更稳妥。
        final restored = widget.deps.auth.restoreSession();
        Log.d(_tag, 'login success restored=$restored');
        _poll?.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('登录成功（uid=${widget.deps.auth.session.userid}），'
                  '建议重启 App 以刷新全局会话')));
          Navigator.of(context).pop();
        }
      } else if (s.status == QrLoginStatus.expired) {
        // 过期自动重开一轮。
        final fresh = await widget.deps.auth.createQrLogin();
        if (mounted) setState(() => _state = fresh);
      }
    } catch (e, st) {
      Log.e(_tag, 'pollQrLogin tick failed', e, st);
      // 网络抖动：继续下一轮轮询。
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('扫码登录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 200,
            height: 200,
            color: Colors.white,
            alignment: Alignment.center,
            child: _state.qrcode.isEmpty
                ? const Text('生成中…')
                : QrView(data: _state.qrcode),
            // QR 真渲染（批1-C）：QrView 纯 Dart 编码 + CustomPainter，无第三方包。
          ),
          const SizedBox(height: 12),
          const Text('请使用酷狗 App 扫码'),
          Text(_hint),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
