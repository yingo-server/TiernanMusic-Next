// L6 session · 导航状态（纯 Dart，零 flutter 依赖 → 可本地单测）
// 监听：L7 用 addListener/removeListener 订阅（与 flutter ChangeNotifier 同形）。
import '../bridges/bridge_kernel.dart' show Log;

const String _tag = 'session.nav';

/// 跨页面导航意图：albumId / artistId / 首页 tab 请求。
class NavState {
  NavState._();
  static final NavState instance = NavState._();

  final List<void Function()> _listeners = <void Function()>[];

  String _albumId = '';
  String _artistId = '';
  String _tabRequest = '';

  String get albumId => _albumId;
  String get artistId => _artistId;
  String get tabRequest => _tabRequest;

  /// 订阅变更（返回一个便于移除的句柄）。
  void addListener(void Function() listener) {
    try {
      _listeners.add(listener);
    } catch (e, st) {
      Log.e(_tag, 'addListener failed', e, st);
    }
  }

  void removeListener(void Function() listener) {
    try {
      _listeners.remove(listener);
    } catch (e, st) {
      Log.e(_tag, 'removeListener failed', e, st);
    }
  }

  void _notify() {
    try {
      for (final l in List<void Function()>.of(_listeners)) {
        try {
          l();
        } catch (e, st) {
          Log.e(_tag, 'listener failed', e, st);
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'notify failed', e, st);
    }
  }

  void setAlbum(String id) {
    try {
      _albumId = id;
      _notify();
      Log.d(_tag, 'album=$id');
    } catch (e, st) {
      Log.e(_tag, 'setAlbum failed', e, st);
    }
  }

  void setArtist(String id) {
    try {
      _artistId = id;
      _notify();
      Log.d(_tag, 'artist=$id');
    } catch (e, st) {
      Log.e(_tag, 'setArtist failed', e, st);
    }
  }

  void requestTab(String moduleId) {
    try {
      _tabRequest = moduleId;
      _notify();
      Log.d(_tag, 'tab request=$moduleId');
    } catch (e, st) {
      Log.e(_tag, 'requestTab failed', e, st);
    }
  }

  void clearTabRequest() {
    try {
      _tabRequest = '';
    } catch (e, st) {
      Log.e(_tag, 'clearTabRequest failed', e, st);
    }
  }
}
