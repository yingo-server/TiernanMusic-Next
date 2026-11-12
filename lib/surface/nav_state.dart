// L6 surface 级 · 导航参数共享状态（模块间零直接 import 的路由参数载体）
// 用途：artist/album/comment/mv 等二级页需要上��页传入的 id，
//       通过本 holder 传递（模块间不互相 import，符合热插拔纪律）。
// 纪律：同层文件；try/catch + Log 留痕；不依赖任何其他层。
import '../bridges/bridge_logic.dart' show Log;

const String _tag = 'surface.nav_state';

/// 导航参数 holder：记录当前二级页参数（歌手 id / 专辑 id / MV hash …）。
/// 由装配层创建并注入各模块工厂；页面进入前写入，页面 build 时读取。
class SurfaceNavState {
  SurfaceNavState();

  String? _artistId;
  String? _albumId;
  String? _mvHash;

  /// 当前歌手 id（歌手页参数）。
  String? get artistId => _artistId;

  /// 当前专辑 id（专辑页参数）。
  String? get albumId => _albumId;

  /// 当前 MV hash（MV 页参数）。
  String? get mvHash => _mvHash;

  /// 写入歌手 id（进入歌手页前调用）。
  void setArtist(String? id) {
    try {
      _artistId = (id == null || id.trim().isEmpty) ? null : id.trim();
    } catch (e, st) {
      Log.e(_tag, 'setArtist failed', e, st);
    }
  }

  /// 写入专辑 id（进入专辑页前调用）。
  void setAlbum(String? id) {
    try {
      _albumId = (id == null || id.trim().isEmpty) ? null : id.trim();
    } catch (e, st) {
      Log.e(_tag, 'setAlbum failed', e, st);
    }
  }

  /// 写入 MV hash。
  void setMv(String? hash) {
    try {
      _mvHash = (hash == null || hash.trim().isEmpty) ? null : hash.trim();
    } catch (e, st) {
      Log.e(_tag, 'setMv failed', e, st);
    }
  }
}
