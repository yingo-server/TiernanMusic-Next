// L7 surface/pages · 设置页（官方 M3 分组：账号 / 外观 / 播放 / 存储 / 关于）
//
// 契约：只用官方 Material 3 控件；不手写控件类；颜色只来自语义 token。
// 数据经桥：AuthLogic / AccountLogic（bridge_logic）、CacheService（bridge_core）、
// 播放偏好经 PlaybackSession 意图方法；主题/语言经 L6 控制器。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show AudioQuality, qualityParam, vipQualities;
import '../../bridges/bridge_logic.dart' show Log, AuthLogic, AccountLogic;
import '../../bridges/bridge_session.dart'
    show
        playbackSession,
        SurfaceModule,
        NavEntry,
        appGraph,
        navState,
        ThemeController,
        LocaleController,
        AuthSession;
import '../design/tokens_v2.dart';
import '../l10n/s.dart' show S;
import 'login_sheet.dart' show showLoginSheet;

/// 应用版本号（与 pubspec.yaml version 同步）。
const String kAppVersion = '26.11.10+1';

/// 设置页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<double> _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // 主题模式已上移 L6 ThemeController（批1-F1），本页不再持本地 state。
  String _nickname = '';
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadAccount();
    navState().addListener(_onAuthChanged);
  }

  /// 登录态广播（NavState.authVersion）：登录/登出/切号后重读账号卡。
  void _onAuthChanged() {
    _loadAccount();
  }

  @override
  void dispose() {
    navState().removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _loadAccount() async {
    final AuthLogic? auth = appGraph.auth;
    final AccountLogic? account = appGraph.account;
    if (auth == null && account == null) return;
    var name = '';
    if (account != null) {
      final rec = await account.activeAccount();
      if (rec != null) name = rec.displayName;
    }
    final uid = auth?.session.userid ?? '';
    if (!mounted) return;
    setState(() {
      _nickname = name.isEmpty ? (uid.isEmpty ? '' : '酷狗用户 $uid') : name;
      _loggedIn = uid.isNotEmpty;
    });
  }

  void _logout() {
    final AuthLogic? auth = appGraph.auth;
    if (auth == null) return;
    auth.logout();
    // 登出即失效会话缓存/等待表（批6 网络专项：换号不复用旧 token 条目）。
    appGraph.cache?.invalidateSession();
    setState(() {
      _loggedIn = false;
      _nickname = '';
    });
    _loadAccount();
    navState().bumpAuth();
    // 审查修复（阶段B B5）：登出同样广播登录态，触发收藏镜像/缓存前缀重置。
    AuthSession.instance.notifyAuthChanged();
  }

  void _openQualitySheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('音质档位', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final AudioQuality q in vipQualities())
              ListTile(
                title: Text(qualityParam(q)),
                onTap: () {
                  playbackSession().setQuality(qualityParam(q));
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openSpeedSheet(double current) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('播放倍速', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final s in _speeds)
              ListTile(
                title: Text('${s}x'),
                trailing: (s - current).abs() < 0.001
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  playbackSession().setSpeed(s);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 清缓存：经 bridge_core 的 CacheService 清理会话缓存。
  /// 说明：磁盘级缓存目录清理能力尚未经桥暴露，此处只做已暴露能力的调用。
  void _clearCache() {
    final cache = appGraph.cache;
    if (cache == null) {
      _toast('缓存能力未装配');
      return;
    }
    try {
      cache.invalidateSession();
      _toast('已清理会话缓存');
    } catch (e, st) {
      Log.e('surface.settings', 'clear cache failed', e, st);
      _toast('缓存清理失败');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = playbackSession();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('settings'), style: theme.textTheme.headlineSmall),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: session,
          builder: (BuildContext context, Widget? _) {
            final speed = session.snapshot.speed;
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                _sectionHeader(context, '账号'),
                _group(<Widget>[
                  ListTile(
                    leading: Icon(
                      Icons.person_outline,
                      color: context.cs.onSurfaceVariant,
                    ),
                    title: Text(_loggedIn ? '已登录' : '未登录'),
                    subtitle: Text(
                      _loggedIn
                          ? (_nickname.isEmpty ? '酷狗用户' : _nickname)
                          : '扫码登录后同步收藏与历史',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: _loggedIn
                        ? TextButton(
                            onPressed: _logout,
                            child: Text(s.t('logout')),
                          )
                        : FilledButton(
                            onPressed: () => showLoginSheet(context),
                            child: Text(s.t('login')),
                          ),
                  ),
                ]),
                _sectionHeader(context, s.t('theme')),
                _group(<Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('主题模式', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<int>(
                          valueListenable: ThemeController.instance,
                          builder: (BuildContext c, int mode, Widget? _) =>
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SegmentedButton<int>(
                                  showSelectedIcon: false,
                                  segments: const <ButtonSegment<int>>[
                                    // 档位：0=跟随系统 / 1=浅色 / 2=深色 / 3=纯黑。
                                    ButtonSegment<int>(
                                      value: 0,
                                      label: Text('跟随系统'),
                                    ),
                                    ButtonSegment<int>(
                                      value: 1,
                                      label: Text('浅色'),
                                    ),
                                    ButtonSegment<int>(
                                      value: 2,
                                      label: Text('深色'),
                                    ),
                                    ButtonSegment<int>(
                                      value: 3,
                                      label: Text('纯黑'),
                                    ),
                                  ],
                                  selected: <int>{mode},
                                  onSelectionChanged: (Set<int> sel) =>
                                      ThemeController.instance.setMode(
                                        sel.first,
                                      ),
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  // 阶段B B7 P0：语言选择入口（切语言实时生效）。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('界面语言', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<String>(
                          valueListenable: LocaleController.instance,
                          builder: (BuildContext c, String code, Widget? _) =>
                              DropdownButtonFormField<String>(
                                value: code,
                                decoration: const InputDecoration(
                                  isDense: true,
                                ),
                                items: const <DropdownMenuItem<String>>[
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text('跟随系统'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'zh',
                                    child: Text('简体中文'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'zh_Hant',
                                    child: Text('繁體中文'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'en',
                                    child: Text('English'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ja',
                                    child: Text('日本語'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ko',
                                    child: Text('한국어'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'es',
                                    child: Text('Español'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'fr',
                                    child: Text('Français'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'de',
                                    child: Text('Deutsch'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pt',
                                    child: Text('Português'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ru',
                                    child: Text('Русский'),
                                  ),
                                ],
                                onChanged: (String? v) => LocaleController
                                    .instance
                                    .setLocale(v ?? ''),
                              ),
                        ),
                      ],
                    ),
                  ),
                ]),
                _sectionHeader(context, '播放'),
                _group(<Widget>[
                  ListTile(
                    leading: Icon(
                      Icons.graphic_eq,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('音质'),
                    subtitle: Text('128（标准）', style: theme.textTheme.bodySmall),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: _openQualitySheet,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.speed,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('倍速'),
                    subtitle: Text(
                      '${speed}x',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => _openSpeedSheet(speed),
                  ),
                ]),
                _sectionHeader(context, s.t('cache')),
                _group(<Widget>[
                  ListTile(
                    leading: Icon(
                      Icons.cleaning_services_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('清理缓存'),
                    subtitle: Text(
                      '清理会话缓存与请求合并表',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: FilledButton(
                      onPressed: _clearCache,
                      child: const Text('清理'),
                    ),
                  ),
                ]),
                _sectionHeader(context, s.t('about')),
                _group(<Widget>[
                  ListTile(
                    leading: Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('版本'),
                    trailing: Text(
                      kAppVersion,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 区块标题（官方 Text）。
  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  /// 分组容器（官方 Card）。
  Widget _group(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

/// 设置模块（进底部导航）。
class SettingsPageModule extends SurfaceModule {
  @override
  String get id => 'settings';

  @override
  String get route => '/settings';

  @override
  NavEntry? get navEntry => const NavEntry('设置', 'settings', navOrder: 4);

  @override
  WidgetBuilder? get builder =>
      (_) => const SettingsPage();
}
