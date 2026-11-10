// L5 logic/catalog · 用户域门面（批6-A，缓存接入）
// UserLogic：profile / cloud / climax / uploadPlayed / reportListen
// + LruCache(ns:'user') schemaVer v1。未实测端点返回空并留痕。
// 铁律：禁 surface/flutter；每方法 try/catch + Log('logic.user')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as user show UserProfile, getSongClimax, getUserCloud, getUserDetail, reportListen, uploadPlayHistory;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, SongBrief;

/// 用户域缓存 schema 版本。
const int kUserCacheSchemaVer = 1;

const String _tag = 'logic.user';
const String _ns = 'user';
const String _profilePath = '/v3/get_my_info';
const String _cloudPath = '/v1/user_cloud';
const String _climaxPath = '/v1/song_climax';

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

  /// 云盘歌曲（缓存 path:/v1/user_cloud）。端点未实测 → 空列表留痕。
  Future<List<SongBrief>> cloud() async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _cloudPath,
        params: const <String, Object?>{},
        schemaVer: kUserCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<SongBrief>) {
        Log.d(_tag, 'cloud cache hit');
        return hit;
      }
      final items = await user.getUserCloud(_client);
      _cache.put(key, items);
      Log.d(_tag, 'cloud got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'cloud failed', e, st);
      return const <SongBrief>[];
    }
  }

  /// 高潮片段（缓存 path:/v1/song_climax，键含 hash）。
  /// 端点未实测 → null 留痕。
  Future<String?> climax(String hash) async {
    try {
      final h = hash.trim().toLowerCase();
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _climaxPath,
        params: <String, Object?>{'hash': h},
        schemaVer: kUserCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is String) {
        Log.d(_tag, 'climax cache hit hash=$h');
        return hit;
      }
      final r = await user.getSongClimax(_client, h);
      if (r != null && r.isNotEmpty) _cache.put(key, r);
      Log.d(_tag, 'climax hash=$h got=${r != null}');
      return r;
    } catch (e, st) {
      Log.e(_tag, 'climax failed hash=$hash', e, st);
      return null;
    }
  }

  /// 批量听歌上报（写操作，不走缓存）。端点未实测 → false 留痕。
  Future<bool> uploadPlayed(List<int> mixSongIds) async {
    try {
      final ok = await user.uploadPlayHistory(_client, mixSongIds);
      Log.d(_tag, 'uploadPlayed n=${mixSongIds.length} ok=$ok');
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'uploadPlayed failed', e, st);
      return false;
    }
  }

  /// 单曲试听上报（写操作，不走缓存）。端点未实测 → false 留痕。
  Future<bool> reportListen(String hash) async {
    try {
      final ok = await user.reportListen(_client, hash);
      Log.d(_tag, 'reportListen hash=$hash ok=$ok');
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'reportListen failed hash=$hash', e, st);
      return false;
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
