// L6 surface/pages · 设置页模块（buildSettingsPageModule）
// 由 modules.dart（批4-B）汇总注册：SurfaceRegistry.install(buildSettingsPageModule(...))。
// 登录区（二维码登录轮询）/ 主题切换（亮/暗/跟随系统，riverpod 状态由批4-B 提供）/ 缓存清理 / 关于。
// 铁律：只 import flutter/miuix/riverpod/bridge_logic/bridge_core/本层；try/catch + Log('surface.settings')。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridges/bridge_logic.dart';
import '../../bridges/bridge_core.dart' show AccountRecord;
import '../l10n/l10n_helper.dart' show TnStrings;
import '../registry.dart';
import '../theme/tn_theme.dart';
import '../widgets/tn_app_bar.dart' show TnAppBar;
import '../widgets/qr_view.dart';

const String _tag = 'surface.settings';
const String kAppVersion = '26.11.10.1';

/// 主题模式 riverpod 状态（批4-B 的 ThemeController 可替换实现；默认跟随系统）。
/// anyState：0=跟随系统 1=亮 2=暗 3=纯黑。
/// ⚠️ 纯黑消费待 app_root 接线：app_root 的 themeModeProvider 只识别 0/1/2，
/// mode==3 当前按跟随系统渲染（switch 落 default），需 app_root 接 tnPitchBlackThemeData()。
final StateProvider<int> themeModeProvider = StateProvider<int>((_) => 0);

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
}/// 设置页模块：id='settings'，底部导航入口「设置」。
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
          // ── 多账号管理（批2 收尾接线）──
          if (widget.deps.accounts != null)
            _AccountSection(accounts: widget.deps.accounts!),
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
            subtitle: Text('TiernanMusicNext v$kAppVersion'),
          ),
          // 批6-B：多语言状态行（3/10 语可用，7 语待人工翻译）。
          Builder(builder: (ctx) {
            final s = TnStrings.of(ctx);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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

/// 多账号管理：列出档案、切换、删除；保存当前会话为档案。
class _AccountSection extends StatefulWidget {
  const _AccountSection({required this.accounts});
  final AccountLogic accounts;

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  List<AccountRecord> _items = const <AccountRecord>[];
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.accounts.listAccounts();
      final active = await widget.accounts.activeAccount();
      if (!mounted) return;
      setState(() {
        _items = list;
        _activeId = active?.accountId;
      });
    } catch (e, st) {
      Log.e(_tag, 'account list failed', e, st);
    }
  }
  Future<void> _switch(AccountRecord r) async {
    try {
      await widget.accounts.switchTo(r.accountId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已切换到 ${r.displayName}')));
      }
    } catch (e, st) {
      Log.e(_tag, 'account switch failed', e, st);
    }
  }

  Future<void> _save() async {
    try {
      final rec = await widget.accounts.saveCurrent();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(rec == null ? '未登录，无法保存账号' : '已保存当前账号')));
      }
    } catch (e, st) {
      Log.e(_tag, 'account save failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Text('账号管理',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('保存当前'),
              ),
            ],
          ),
        ),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('暂无账号档案', style: TextStyle(fontSize: 12)),
          )
        else
          for (final r in _items)
            ListTile(
              dense: true,
              leading: Icon(r.accountId == _activeId
                  ? Icons.check_circle
                  : Icons.account_circle_outlined),
              title:
                  Text(r.displayName.isEmpty ? r.accountId : r.displayName),
              subtitle: Text(r.accountId),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  await widget.accounts.removeAccount(r.accountId);
                  await _load();
                },
              ),
              onTap: () => _switch(r),
            ),
      ],
    );
  }
}
