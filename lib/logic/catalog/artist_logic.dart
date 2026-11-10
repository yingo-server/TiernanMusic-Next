// L5 logic/catalog · 歌手域门面（功能对齐批4-A · GAP #22，风格照 rank_logic.dart）
// 装配注入方式：boot 构造 ArtistLogic(client: KugouClient, cache: LruCache)
//   后经 bridge_logic 暴露给 L6；由 buildArtistModule(logic: ...) 注入页面模块。
// 依赖纪律：禁 surface/flutter、禁 IO 直连；沿用现有 import 惯例（过渡口径，
//   收敛批次统一改桥），不新增跨更高层 import。
// 缓存优先：ns:'artist' schemaVer 1，buildKey/prefixOf；空结果也落缓存；
//   每方法 try/catch + Log('logic.artist')，失败留痕不静默吞。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as ep show AlbumBrief, ArtistBrief, ArtistDetail, SongBrief, getArtistAlbums, getArtistAudios, getArtistDetail, getArtistList, kArtistAlbumsPath, kArtistAudiosPath, kArtistDetailPath, kArtistListPath;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, SongBrief, AlbumBrief, ArtistBrief, ArtistDetail;

/// 歌手域缓存 schema 版本（模型变更升版自动失效老键）。
const int kArtistCacheSchemaVer = 1;
const String _tag = 'logic.artist';
const String _ns = 'artist';
const int _defaultPageSize = 30;

class ArtistLogic {
  ArtistLogic({
    required KugouClient client,
    required LruCache<String, dynamic> cache,
  })  : _client = client, _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }
  final KugouClient _client;
  final LruCache<String, dynamic> _cache;

  /// 统一缓存读取：命中且类型匹配才返回，否则打网并落缓存；
  /// 缓存路径异常直接返回显式 fallback（不二次打网、不静默吞）。
  Future<T> _cached<T>(String path, Map<String, Object?> params,
      T fallback, Future<T> Function() fetch) async {
    try {
      final key = buildKey(ns: _ns, userid: _client.session.userid,
          path: path, params: params, schemaVer: kArtistCacheSchemaVer);
      final hit = _cache.get(key);
      if (hit is T) {
        Log.d(_tag, 'cache hit path=$path');
        return hit;
      }
      final value = await fetch();
      _cache.put(key, value);
      return value;
    } catch (e, st) {
      Log.e(_tag, '_cached failed path=$path', e, st);
      return fallback;
    }
  }

  /// 歌手详情。缓存 path:/kmr/v3/author。
  Future<ep.ArtistDetail> detail(String id) async {
    try {
      final aid = id.trim();
      if (aid.isEmpty) {
        Log.w(_tag, 'detail empty id');
        return const ep.ArtistDetail();
      }
      final d = await _cached<ep.ArtistDetail>(ep.kArtistDetailPath,
          <String, Object?>{'author_id': aid}, const ep.ArtistDetail(),
          () => ep.getArtistDetail(_client, aid));
      Log.d(_tag, 'detail id=$aid name=${d.name}');
      return d;
    } catch (e, st) {
      Log.e(_tag, 'detail failed id=$id', e, st);
      return const ep.ArtistDetail();
    }
  }

  /// 热门歌曲分页（page 从 1 起）。缓存 path:/kmr/v1/author/audios。
  /// ⚠️ 端点层 audios 签名需 defaultParams+body 合并（clearDefaultParams 会
  ///    20006）；本层只管缓存编排，不触碰签名参数。
  Future<List<SongBrief>> audios(String id, int page,
      {int pageSize = _defaultPageSize}) async {
    try {
      final aid = id.trim();
      final p = page < 1 ? 1 : page;
      final ps = pageSize < 1 ? _defaultPageSize : pageSize;
      if (aid.isEmpty) {
        Log.w(_tag, 'audios empty id');
        return const <SongBrief>[];
      }
      final items = await _cached<List<SongBrief>>(ep.kArtistAudiosPath,
          <String, Object?>{'author_id': aid, 'page': p, 'pagesize': ps},
          const <SongBrief>[],
          () => ep.getArtistAudios(_client, aid, p, pageSize: ps));
      Log.d(_tag, 'audios id=$aid page=$p got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'audios failed id=$id page=$page', e, st);
      return const <SongBrief>[];
    }
  }

  /// 专辑分页（page 从 1 起）。缓存 path:/v1/author/albums。
  Future<List<ep.AlbumBrief>> albums(String id, int page,
      {int pageSize = _defaultPageSize}) async {
    try {
      final aid = id.trim();
      final p = page < 1 ? 1 : page;
      final ps = pageSize < 1 ? _defaultPageSize : pageSize;
      if (aid.isEmpty) {
        Log.w(_tag, 'albums empty id');
        return const <ep.AlbumBrief>[];
      }
      final items = await _cached<List<ep.AlbumBrief>>(ep.kArtistAlbumsPath,
          <String, Object?>{'author_id': aid, 'page': p, 'pagesize': ps},
          const <ep.AlbumBrief>[],
          () => ep.getArtistAlbums(_client, aid, p, pageSize: ps));
      Log.d(_tag, 'albums id=$aid page=$p got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'albums failed id=$id page=$page', e, st);
      return const <ep.AlbumBrief>[];
    }
  }

  /// 歌手列表（榜单式全量）。缓存 path:/ocean/v6/singer/list。
  Future<List<ep.ArtistBrief>> list() async {
    try {
      final items = await _cached<List<ep.ArtistBrief>>(ep.kArtistListPath,
          const <String, Object?>{'hotsize': 200},
          const <ep.ArtistBrief>[], () => ep.getArtistList(_client));
      Log.d(_tag, 'list got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'list failed', e, st);
      return const <ep.ArtistBrief>[];
    }
  }

  /// 按 (ns, userid) 前缀失效（登出/换号清缓存；默认当前会话用户）。
  int invalidatePrefix({String? userid}) {
    try {
      final uid = userid ?? _client.session.userid;
      final removed = _cache.invalidatePrefix(prefixOf(_ns, uid));
      Log.d(_tag, 'invalidatePrefix uid=$uid removed=${removed.length}');
      return removed.length;
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
      return 0;
    }
  }
}
