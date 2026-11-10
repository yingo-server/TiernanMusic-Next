// L5 logic/catalog · 专辑域门面（功能对齐批4-B，主会话实现）
// 契约：缓存优先（ns 'album' / 'similar'，schemaVer 1）；每方法 try/catch+Log。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as ep show AlbumDetail, LruCache, PlaylistBrief, TrackPage, buildKey, getAlbumDetail, getAlbumSongs, getSimilarPlaylists, prefixOf;
import '../../bridges/bridge_core.dart' show KugouClient, SongBrief, TrackPage, PlaylistBrief, AlbumDetail, LruCache;

const String _tag = 'logic.album';
const int kAlbumCacheSchemaVer = 1;

/// 专辑门面：详情 / 曲目 / 相似歌单。
class AlbumLogic {
  AlbumLogic({
    required KugouClient client,
    required LruCache<String, dynamic> cache,
  })  : _client = client,
        _cache = cache;

  final KugouClient _client;
  final LruCache<String, dynamic> _cache;

  String _uid() => _client.session.userid;

  Future<ep.AlbumDetail> detail(String albumId) async {
    try {
      final id = albumId.trim();
      if (id.isEmpty) return const ep.AlbumDetail();
      final key = buildKey(
        ns: 'album',
        userid: _uid(),
        path: '/kmr/v2/albums',
        params: <String, Object?>{'id': id},
        schemaVer: kAlbumCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is ep.AlbumDetail) return hit;
      final d = await ep.getAlbumDetail(_client, id);
      if (!d.isEmpty) _cache.put(key, d);
      return d;
    } catch (e, st) {
      Log.e(_tag, 'detail failed id=$albumId', e, st);
      return const ep.AlbumDetail();
    }
  }

  Future<TrackPage> songs(String albumId, int page, {int pageSize = 30}) async {
    try {
      final id = albumId.trim();
      if (id.isEmpty) return const TrackPage();
      final p = page < 1 ? 1 : page;
      final key = buildKey(
        ns: 'album',
        userid: _uid(),
        path: '/v1/album_audio/lite',
        params: <String, Object?>{'id': id, 'page': p, 'pagesize': pageSize},
        schemaVer: kAlbumCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is TrackPage) return hit;
      final r = await ep.getAlbumSongs(_client, id, p, pageSize);
      if (r.items.isNotEmpty) _cache.put(key, r);
      return r;
    } catch (e, st) {
      Log.e(_tag, 'songs failed id=$albumId page=$page', e, st);
      return const TrackPage();
    }
  }

  Future<List<PlaylistBrief>> similarPlaylists(String playlistId) async {
    try {
      final id = playlistId.trim();
      if (id.isEmpty) return const <PlaylistBrief>[];
      final key = buildKey(
        ns: 'similar',
        userid: _uid(),
        path: '/pubsongs/v1/kmr_get_similar_lists',
        params: <String, Object?>{'id': id},
        schemaVer: kAlbumCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<PlaylistBrief>) return hit;
      final list = await ep.getSimilarPlaylists(_client, id);
      if (list.isNotEmpty) _cache.put(key, list);
      return list;
    } catch (e, st) {
      Log.e(_tag, 'similarPlaylists failed id=$playlistId', e, st);
      return const <PlaylistBrief>[];
    }
  }

  int invalidatePrefix({String? userid}) {
    try {
      final removed = _cache.invalidatePrefix(
          prefixOf('album', userid ?? _uid()));
      final removed2 = _cache.invalidatePrefix(
          prefixOf('similar', userid ?? _uid()));
      Log.d(_tag, 'invalidatePrefix removed=${removed.length + removed2.length}');
      return removed.length + removed2.length;
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
      return 0;
    }
  }
}
