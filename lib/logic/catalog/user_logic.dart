// L5 logic/catalog · 用户域门面（批6-A，缓存接入）
// UserLogic：profile
// + LruCache(ns:'user') schemaVer v1。未实测端点返回空并留痕。
// 铁律：禁 surface/flutter；每方法 try/catch + Log('logic.user')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as user show UserProfile, getUserDetail;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, buildKey, prefixOf;

/// 用户域缓存 schema 版本。
const int kUserCacheSchemaVer = 1;

const String _tag = 'logic.user';
const String _ns = 'user';
const String _profilePath = '/v3/get_my_info';

class UserLogic {
  UserLogic({
    required KugouClient client,
    required LruCache<String, dynamic> cache,
  })  : _client = client,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, dynamic> _cache;

  /// 用户档案（缓存 path:/v3/get_my_info）。端点未实测 → UserProfile 空值留痕。
  Future<user.UserProfile> profile() async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _profilePath,
        params: const <String, Object?>{},
        schemaVer: kUserCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is user.UserProfile) {
        Log.d(_tag, 'profile cache hit');
        return hit;
      }
      final p = await user.getUserDetail(_client);
      _cache.put(key, p);
      Log.d(_tag, 'profile got empty=${p.isEmpty}');
      return p;
    } catch (e, st) {
      Log.e(_tag, 'profile failed', e, st);
      return const user.UserProfile();
    }
  }

  /// 按 (ns, userid) 前缀失效（登出清缓存）。
  int invalidatePrefix({String userid = ''}) {
    try {
      final removed = _cache.invalidatePrefix(prefixOf(_ns, userid));
      Log.d(_tag, 'invalidatePrefix removed=${removed.length}');
      return removed.length;
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
      return 0;
    }
  }
}
