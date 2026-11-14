// L5 logic/catalog · 歌单门面（缓存接入 + 本地镜像）
// 注入 KugouClient + PlaylistDao + LruCache<String, dynamic>。
// recommend/detail/tracks 走 core 端点封装（specialid/data.songs 实测修正已封在 L4）。
// 本地镜像：saveLocalMirror(PlaylistDetail + tracks) 写 PlaylistDao；listLocal() 读。
// schemaVer v1（顶部常量）；每方法 try/catch + Log('logic.playlist')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, PlaylistBrief, PlaylistDao, PlaylistDetail, PlaylistMeta, SongBrief, TrackPage, addSongsToPlaylist, buildKey, parseKey, playlistDetail, playlistTracks, prefixOf, recommendPlaylists;

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

  /// R3-C #3：Listid → list_ver 缓存。detail 成功后写入（get_list_info
  /// data[0].list_ver 实测存在），写操作（add/removeSongs）作为请求体
  /// list_ver 携带（端点默认 0 兼容旧调用）。
  final Map<String, int> _listVerCache = <String, int>{};

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
      // R3-C #3：detail 成功后记录 list_ver（实测字段，写操作回传）。
      if (d.listVer > 0) { _listVerCache[id] = d.listVer; }
      Log.d(_tag, 'detail id=$id name=${d.name} listVer=${d.listVer}');
      return d;
    } catch (e, st) {
      Log.e(_tag, 'detail failed id=$playlistId', e, st);
      return const PlaylistDetail();
    }
  }

  /// 歌单曲目分页。走修正后封装（specialid 参数 / data.songs[] / data.count）。
  /// 缓存 path:/pubsongs/v2/get_other_list_file_nofilt。
  /// [specialIdOverride]：detail 响应透传的数字 specialid（必须）。
/// 传 global_collection_id 实测恒 20010 —— 上层先 detail 后 tracks。
Future<TrackPage> tracks(String playlistId, int page,
      {int pageSize = 30, String? specialIdOverride}) async {
    final effective = (specialIdOverride ?? playlistId).trim();
    try {
      final id = playlistId.trim();
      final beginIdx = (page < 1 ? 1 : page - 1) * pageSize;
      final key = buildKey(
        ns: _ns,
        userid: _uid(),
        path: '/pubsongs/v2/get_other_list_file_nofilt',
        params: <String, Object?>{
          'specialid': effective, 'begin_idx': beginIdx, 'pagesize': pageSize,
        },
        schemaVer: kPlaylistCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is TrackPage) {
        Log.d(_tag, 'tracks cache hit id=$id page=$page');
        return hit;
      }
      final tp = await playlistTracks(_client, effective, page, pageSize);
      _cache.put(key, tp);
      Log.d(_tag, 'tracks id=$id page=$page got=${tp.items.length}/${tp.total}');
      return tp;
    } catch (e, st) {
      Log.e(_tag, 'tracks failed id=$playlistId page=$page', e, st);
      return const TrackPage();
    }
  }

  /// 加歌到酷狗在线歌单（经 addSongsToPlaylist）；成功后失效该歌单 tracks 缓存。
  /// list_ver：优先用 detail 缓存值，写成功后本地 +1（实测响应回执含递增
  /// list_ver 时以回执为准——此处保守本地递增）。
  Future<bool> addSongsToKugouPlaylist(
      String playlistId, List<SongBrief> songs) async {
    try {
      final id = playlistId.trim();
      final lv = _listVerCache[id] ?? 0;
      final ok = await addSongsToPlaylist(_client, id, songs, listVer: lv);
      if (ok) {
        _listVerCache[id] = lv + 1;
        // 歌单内容变更：失效该 id 的 tracks 分页缓存 + detail 缓存（detail
        // 内含歌曲总数 count，不失效则 UI 首页显示旧总数）。按精确特殊 id
        // 匹配（数字 id 编码后与原文一致；同时匹配 detail 的 'id' 参数）。
        final encId = Uri.encodeQueryComponent(playlistId.trim());        _cache.invalidateWhere((k) {
          final info = parseKey('$k');
          return info.valid &&
              info.namespace == _ns &&
              (info.path.contains('get_other_list_file_nofilt') ||
                  info.path.contains('get_list_info')) &&
              (info.query.contains('specialid=$encId') ||
                  info.query.contains('id=$encId'));
        });
        Log.d(_tag, 'addSongsToKugouPlaylist ok id=$id n=${songs.length} '
            'listVer=${_listVerCache[id]}');
      }
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'addSongsToKugouPlaylist failed id=$playlistId', e, st);
      return false;
    }
  }

  /// R3-C #3：外部读取某歌单当前 list_ver（无缓存返回 0）。
  int listVerOf(String listid) {
    try {
      final v = _listVerCache[listid.trim()] ?? 0;
      Log.d(_tag, 'listVerOf id=$listid ver=$v');
      return v;
    } catch (e, st) {
      Log.e(_tag, 'listVerOf failed id=$listid', e, st);
      return 0;
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
