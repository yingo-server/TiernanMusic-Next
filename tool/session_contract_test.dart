// tool/session_contract_test.dart · L6 session 契约自检（纯 Dart，无 flutter）
// 目的：钉死 session 层语义（队列/快照/意图/注册表/导航），防止 UI 重写时上层塌陷。
// 运行：dart run tool/session_contract_test.dart
import 'dart:async';

import '../lib/session/contracts.dart' show NavEntry, SurfaceModule;
import '../lib/session/module_registry.dart' show ModuleRegistry;
import '../lib/session/nav_state.dart' show NavState;

int _pass = 0;
int _fail = 0;

void check(String name, bool ok) {
  if (ok) {
    _pass++;
    print('PASS  $name');
  } else {
    _fail++;
    print('FAIL  $name');
  }
}

/// 最小队列样本（不依赖网络）。
List<_Song> _songs(int n) =>
    List<_Song>.generate(n, (i) => _Song('h$i', 's$i'));

class _Song {
  _Song(this.hash, this.name);
  final String hash;
  final String name;
}

/// 测试用模块（验证注册表契约）。
class _Mod extends SurfaceModule {
  _Mod(this.id, this.entry);
  @override
  final String id;
  @override
  final NavEntry? entry;
  @override
  String get route => '/$id';
  @override
  NavEntry? get navEntry => entry;
  @override
  bool get enabled => true;
}

void main() {
  // ② NavEntry 是纯数据
  const e = NavEntry('首页', 'home');
  check('NavEntry 纯数据', e.label == '首页' && e.icon == 'home');

  // ③ SurfaceModule 默认契约：navEntry 可空、enabled 默认 true、builder 可空
  final m = _Mod('x', null);
  check('模块默认 enabled', m.enabled);
  check('模块 navEntry 可空', m.navEntry == null);
  check('模块 route 约定', m.route == '/x');
  check('模块 builder 默认为 null', m.builder == null);

  // ④ 模块注册表：install/active/navEntries/uninstall
  final reg = ModuleRegistry.instance;
  reg.clear();
  reg.install(_Mod('home', const NavEntry('首页', 'home')));
  reg.install(_Mod('search', const NavEntry('搜索', 'search')));
  check('注册表 active 数量', reg.active().length == 2);
  check('注册表按 id 排序', reg.active().first.id == 'home');
  check('注册表 navEntries 只含贡献者', reg.navEntries().length == 2);
  reg.install(_Mod('home', const NavEntry('首页2', 'home')));
  check('重复 id 覆盖而非累积', reg.active().length == 2);
  reg.uninstall('search');
  check('uninstall 生效', reg.active().length == 1);
  check('byId 命中', reg.byId('home') != null);
  reg.clear();

  // ⑤ 导航状态：album/artist/tab 请求 + 通知
  final nav = NavState.instance;
  nav.setAlbum('a1');
  nav.setArtist('r1');
  nav.requestTab('settings');
  check('导航 album', nav.albumId == 'a1');
  check('导航 artist', nav.artistId == 'r1');
  check('导航 tab 请求', nav.tabRequest == 'settings');
  nav.clearTabRequest();
  check('导航 tab 可清空', nav.tabRequest.isEmpty);

  print('---- session contract self-check: $_pass passed, $_fail failed ----');
  if (_fail > 0) throw StateError('session contract FAILED');
}
