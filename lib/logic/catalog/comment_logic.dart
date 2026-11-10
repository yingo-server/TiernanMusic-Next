// L5 logic/catalog · 评论域门面（GAP #14，风格照 search_logic.dart）
// 注入 KugouClient + LruCache<String, CommentPage>(capacity 128)。
// comments/floor 走缓存（ns:'comment'，schemaVer v1，buildKey/prefixOf）；
// count 直通不缓存（轻量、需实时）。热词由 CommentPage.hotWords 携带。
// 铁律：禁 surface/flutter；每方法 try/catch + Log('logic.comment')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, SongBrief, CommentItem, CommentPage;

/// 评论域缓存 schema 版本：模型变更升版自动失效老键。
const int kCommentCacheSchemaVer = 1;

const String _tag = 'logic.comment';
const String _ns = 'comment';
const String _musicPath = '/mcomment/v1/cmtlist';
const String _floorPath = '/mcomment/v1/hot_replylist';

class CommentLogic {
  CommentLogic({
    required KugouClient client,
    required LruCache<String, CommentPage> cache,
  })  : _client = client,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, CommentPage> _cache;

  /// 歌曲评论分页（page 从 1 起）。缓存优先，未命中调 getMusicComments 后 put。
  Future<CommentPage> comments(int mixSongId, int page,
      {int pageSize = 20}) async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _musicPath,
        params: <String, Object?>{
          'mix': mixSongId, 'page': page, 'pagesize': pageSize,
        },
        schemaVer: kCommentCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit != null) {
        Log.d(_tag, 'comments cache hit mix=$mixSongId p=$page');
        return hit;
      }
      final res = await getMusicComments(_client, mixSongId, page,
          pageSize: pageSize);
      _cache.put(key, res);
      Log.d(_tag, 'comments miss→network mix=$mixSongId p=$page '
          'got=${res.items.length} cacheSize=${_cache.length}');
      return res;
    } catch (e, st) {
      Log.e(_tag, 'comments failed mix=$mixSongId page=$page', e, st);
      return const CommentPage();
    }
  }

  /// 楼中楼/热评回复分页。缓存优先。
  Future<List<CommentItem>> floor(String commentId, int page,
      {int pageSize = 20}) async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _floorPath,
        params: <String, Object?>{
          'cid': commentId, 'page': page, 'pagesize': pageSize,
        },
        schemaVer: kCommentCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit != null) {
        Log.d(_tag, 'floor cache hit cid=$commentId p=$page');
        return hit.items;
      }
      final res =
          await getCommentFloor(_client, commentId, page, pageSize: pageSize);
      _cache.put(key, CommentPage(items: res));
      Log.d(_tag, 'floor miss→network cid=$commentId p=$page got=${res.length}');
      return res;
    } catch (e, st) {
      Log.e(_tag, 'floor failed cid=$commentId page=$page', e, st);
      return const <CommentItem>[];
    }
  }

  /// 评论总数：直通不缓存（轻量、需实时）。
  Future<int> count(int mixSongId) async {
    try {
      final n = await getCommentCount(_client, mixSongId);
      Log.d(_tag, 'count mix=$mixSongId got=$n');
      return n;
    } catch (e, st) {
      Log.e(_tag, 'count failed mix=$mixSongId', e, st);
      return 0;
    }
  }

  /// 最近一次取到的热词 chips（由 comments 结果携带；无请求时返回空）。
  Future<List<String>> hotWords(int mixSongId, int page) async {
    try {
      final p = await comments(mixSongId, page);
      Log.d(_tag, 'hotWords mix=$mixSongId got=${p.hotWords.length}');
      return p.hotWords;
    } catch (e, st) {
      Log.e(_tag, 'hotWords failed mix=$mixSongId', e, st);
      return const <String>[];
    }
  }

  /// 按命名空间+用户前缀失效（登出清缓存用）。
  int invalidatePrefix({String userid = ''}) {
    try {
      final removed = _cache.invalidatePrefix(prefixOf(_ns, userid));
      Log.d(_tag, 'invalidatePrefix ns=$_ns uid=$userid removed=${removed.length}');
      return removed.length;
    } catch (e, st) {
      Log.e(_tag, 'invalidatePrefix failed', e, st);
      return 0;
    }
  }
}
