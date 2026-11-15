// L7 surface/pages · 设置页（分组：账号 / 外观 / 播放 / 存储 / 关于）
// 数据经桥：AuthLogic / AccountLogic（bridge_logic）、CacheService（bridge_core）、
// 播放偏好经 PlaybackSession 意图方法。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show AudioQuality, qualityParam, vipQualities;
import '../../bridges/bridge_logic.dart' show AuthLogic, AccountLogic;
import '../../bridges/bridge_session.dart'
    show playbackSession, SurfaceModule, NavEntry;
import '../../bridges/bridge_session.dart' show appGraph, ThemeController;
import '../design/tokens.dart';
import '../design/components.dart';

/// 应用版本号（与 pubspec.yaml version 同步）。
const String kAppVersion = '26.11.10+1';

/// 设置页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<double> _speeds = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 2.0,
  ];

  // 主题模式已上移 L6 ThemeController（批1-F1），本页不再持本地 state。
  String _nickname = '';
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadAccount();
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
    setState(() {
      _loggedIn = false;
      _nickname = '';
    });
    _loadAccount();
  }

  void _openQualitySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Sp.bgElevated,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const SpSectionHeader(title: '音质档位'),
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
      backgroundColor: Sp.bgElevated,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const SpSectionHeader(title: '播放倍速'),
            for (final s in _speeds)
              ListTile(
                title: Text('${s}x'),
                trailing: (s - current).abs() < 0.001
                    ? const Icon(Icons.check, color: Sp.green)
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
  /// 说明：磁盘级缓存目录清理能力尚未经桥暴露（见 GAP 注释），此处只做
  /// 已暴露能力的调用，不臆造磁盘删除。
  void _clearCache() {
    final cache = appGraph.cache;
    if (cache == null) {
      _toast('缓存能力未装配');
      return;
    }
    cache.invalidateSession();
    _toast('已清理会话缓存');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final session = playbackSession();
    return Scaffold(
      backgroundColor: Sp.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: session,
          builder: (context, _) {
            final speed = session.snapshot.speed;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: Sp.gapM),
              children: <Widget>[
                const SpSectionHeader(title: '账号'),
                _group(<Widget>[
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: Sp.textSub),
                    title: Text(_loggedIn ? '已登录' : '未登录'),
                    subtitle: Text(
                      _loggedIn
                          ? (_nickname.isEmpty ? '酷狗用户' : _nickname)
                          : '扫码登录后同步收藏与历史',
                      style: const TextStyle(
                          fontSize: Sp.fSub, color: Sp.textSub),
                    ),
                    trailing: _loggedIn
                        ? TextButton(
                            onPressed: _logout,
                            child: const Text('登出'),
                          )
                        : FilledButton(
                            onPressed: () => _toast('扫码登录入口待接入'),
                            child: const Text('扫码登录'),
                          ),
                  ),
                ]),
                const SpSectionHeader(title: '外观'),
                _group(<Widget>[
                  Padding(
                    padding: const EdgeInsets.all(Sp.pagePad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('主题模式',
                            style: TextStyle(fontSize: Sp.fItem, color: Sp.text)),
                        const SizedBox(height: Sp.gapM),
                        ValueListenableBuilder<int>(
                          valueListenable: ThemeController.instance,
                          builder: (context, mode, _) =>
                              SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedButton<int>(
                              showSelectedIcon: false,
                              segments: const <ButtonSegment<int>>[
                                ButtonSegment<int>(value: 0, label: Text('跟随系统')),
                                ButtonSegment<int>(value: 1, label: Text('亮')),
                                ButtonSegment<int>(value: 2, label: Text('暗')),
                                ButtonSegment<int>(value: 3, label: Text('纯黑')),
                              ],
                              selected: <int>{mode},
                              onSelectionChanged: (s) =>
                                  ThemeController.instance.setMode(s.first),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SpSectionHeader(title: '播放'),
                _group(<Widget>[
                  ListTile(
                    leading: const Icon(Icons.graphic_eq, color: Sp.textSub),
                    title: const Text('音质'),
                    subtitle: const Text('128（标准）',
                        style: TextStyle(
                            fontSize: Sp.fSub, color: Sp.textSub)),
                    trailing: const Icon(Icons.chevron_right, color: Sp.textFaint),
                    onTap: _openQualitySheet,
                  ),
                  ListTile(
                    leading: const Icon(Icons.speed, color: Sp.textSub),
                    title: const Text('倍速'),
                    subtitle: Text('${speed}x',
                        style: const TextStyle(
                            fontSize: Sp.fSub, color: Sp.textSub)),
                    trailing: const Icon(Icons.chevron_right, color: Sp.textFaint),
                    onTap: () => _openSpeedSheet(speed),
                  ),
                ]),
                const SpSectionHeader(title: '存储'),
                _group(<Widget>[
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined,
                        color: Sp.textSub),
                    title: const Text('清理缓存'),
                    subtitle: const Text('清理会话缓存与请求合并表',
                        style: TextStyle(
                            fontSize: Sp.fSub, color: Sp.textSub)),
                    trailing: FilledButton(
                      onPressed: _clearCache,
                      child: const Text('清理'),
                    ),
                  ),
                ]),
                const SpSectionHeader(title: '关于'),
                _group(<Widget>[
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Sp.textSub),
                    title: const Text('版本'),
                    trailing: Text(kAppVersion,
                        style: const TextStyle(
                            fontSize: Sp.fSub, color: Sp.textSub)),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _group(List<Widget> children) => Container(
        margin: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
        decoration: BoxDecoration(
          color: Sp.card,
          borderRadius: BorderRadius.circular(Sp.rCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
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
  WidgetBuilder? get builder => (_) => const SettingsPage();
}
