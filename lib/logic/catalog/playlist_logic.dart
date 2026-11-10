// L5 logic/catalog · 歌单门面（缓存接入 + 本地镜像）
// 注入 KugouClient + PlaylistDao + LruCache<String, dynamic>。
// recommend/detail/tracks 走 core 端点封装（specialid/data.songs 实测修正已封在 L4）。
// 本地镜像：saveLocalMirror(PlaylistDetail + tracks) 写 PlaylistDao；listLocal() 读。
// schemaVer v1（顶部常量）；每方法 try/catch + Log('logic.playlist')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, PlaylistDao, PlaylistMeta, PlaylistBrief, PlaylistDetail, SongBrief, TrackPage, recommendPlaylists, playlistDetail, playlistTracks, addSongsToPlaylist;

/// 歌单域缓存 schema 版本。
const int kPlaylistCacheSchemaVer = 1;

const String _tag = 'logic.playlist';
const String _ns = 'playlist';

class PlaylistLogic {
  PlaylistLogic({
    required KugouClient client,
    required PlaylistDao playlistDao,
    required LruCache<String, dynamic> cache,
  })  : _client = client,
        _dao = playlistDao,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final PlaylistDao _dao;
  final LruCache<String, dynamic> _cache;

  String _uid() => _client.session.userid;

  // ── 在线歌单 ──

  /// 推荐歌单列表。缓存 ns:'playlist' path:/v2/special_recommend。
  Future<List<PlaylistBrief>> recommend(int page, {int pageSize = 30, int categoryId = 0}) async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _uid(),
        path: '/v2/special_recommend',
        params: <String, Object?>{
          'page': page, 'pagesize': pageSize, 'categoryid': categoryId,
        },
        schemaVer: kPlaylistCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<PlaylistBrief>) {
        Log.d(_tag, 'recommend cache hit page=$page');
        return hit;
      }
      final items = await recommendPlaylists(_client,
          page: page, pageSize: pageSize, categoryId: categoryId);
      _cache.put(key, items);
      Log.d(_tag, 'recommend page=$page got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'recommend failed page=$page', e, st);
      return const <PlaylistBrief>[];
    }
  }

  /// 歌单详情。缓存 path:/v3/get_list_info。
  Future<PlaylistDetail> detail(String playlistId) async {
    try {
      final id = playlistId.trim();
      final key = buildKey(
        ns: _ns,
        userid: _uid(),
        path: '/v3/get_list_info',
        params: <String, Object?>{'id': id},
        schemaVer: kPlaylistCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is PlaylistDetail) {
        Log.d(_tag, 'detail cache hit id=$id');
        return hit;
      }
      final d = await playlistDetail(_client, id);
      _cache.put(key, d);
      Log.d(_tag, 'detail id=$id name=${d.name}');
      return d;
    } catch (e, st) {
      Log.e(_tag, 'detail failed id=$playlistId', e, st);
      return const PlaylistDetail();
    }
  }

  /// 歌单曲目分页。走修正后封装（specialid 参数 / data.songs[] / data.count）。
  /// 缓存 path:/pubsongs/v2/get_other_list_file_nofilt。
  Future<TrackPage> tracks(String playlistId, int page, {int pageSize = 30}) async {
    try {
      final id = playlistId.trim();
      final beginIdx = (page < 1 ? 1 : page - 1) * pageSize;
      final key = buildKey(
        ns: _ns,
        userid: _uid(),
        path: '/pubsongs/v2/get_other_list_file_nofilt',
        params: <String, Object?>{
          'specialid': id, 'begin_idx': beginIdx, 'pagesize': pageSize,
        },
        schemaVer: kPlaylistCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is TrackPage) {
        Log.d(_tag, 'tracks cache hit id=$id page=$page');
        return hit;
      }
      final tp = await playlistTracks(_client, id, page, pageSize);
      _cache.put(key, tp);
      Log.d(_tag, 'tracks id=$id page=$page got=${tp.items.length}/${tp.total}');
      return tp;
    } catch (e, st) {
      Log.e(_tag, 'tracks failed id=$playlistId page=$page', e, st);
      return const TrackPage();
    }
  }

  /// 加歌到酷狗在线歌单（经 addSongsToPlaylist）；成功后失效该歌单 tracks 缓存。
  Future<bool> addSongsToKugouPlaylist(
      String playlistId, List<SongBrief> songs) async {
    try {
      final ok = await addSongsToPlaylist(_client, playlistId, songs);
      if (ok) {
        // 歌单内容变更：失效该 id 的 tracks 缓存，下次拉取最新。
        _cache.invalidateWhere((k) {
          final info = parseKey('$k');
          return info.valid &&
              info.namespace == _ns &&
              info.path.contains('get_other_list_file_nofilt') &&
              info.query.contains('${Uri.encodeQueryComponent(playlistId)}');
        });
        Log.d(_tag, 'addSongsToKugouPlaylist ok id=$playlistId n=${songs.length}');
      }
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'addSongsToKugouPlaylist failed id=$playlistId', e, st);
      return false;
    }
  }

  // ── 本地歌单镜像（PlaylistDao） ──

  /// 保存本地镜像：PlaylistDetail + 其曲目 hash 有序列表 → PlaylistMeta。
  Future<bool> saveLocalMirror(PlaylistDetail detail, List<SongBrief> tracks) async {
    try {
      if (detail.id.trim().isEmpty) {
        Log.w(_tag, 'saveLocalMirror empty detail id');
        return false;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final existing = await _dao.getByPlaylistId(detail.id);
      final meta = existing ?? PlaylistMeta()
        ..playlistId = detail.id
        ..createdAt = existing?.createdAt ?? nowMs
        ..source = 'online';
      meta
        ..name = detail.name
        ..coverUrl = detail.cover
        ..songHashes = [for (final s in tracks) if (s.hash.isNotEmpty) s.hash];
      await _dao.put(meta);
      Log.d(_tag, 'saveLocalMirror id=${detail.id} tracks=${meta.songHashes.length}');
      return true;
    } catch (e, st) {
      Log.e(_tag, 'saveLocalMirror failed id=${detail.id}', e, st);
      return false;
    }
  }

  /// 本地镜像列表（updatedAt 倒序）。
  Future<List<PlaylistMeta>> listLocal() async {
    try {
      final out = await _dao.list();
      Log.d(_tag, 'listLocal got=${out.length}');
      return out;
    } catch (e, st) {
      Log.e(_tag, 'listLocal failed', e, st);
      return const <PlaylistMeta>[];
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
