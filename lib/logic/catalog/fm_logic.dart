// L5 logic/catalog · 个人 FM 门面（批4-C · GAP #21，风格照 rank_logic.dart）
// 装配：boot 处 FmLogic(client:kugouClient, cache:lruCache) 单例，经 bridge_logic
//   `export FmLogic` 供 L6；FM 入口由装配层 onStartFm 回调接 fmLogic.start() +
//   controller.playAll(batch, 0)（空批次降级不切队列）；跳过接 next()，
//   喜欢/不喜欢接 like/dislike。surface 不 import core 端点、不持有 client。
// 端点状态：personalFm/fmSongs 均 needs probe（PARITY_NOTES.md §3）→ 恒空批次，
//   空批次不写缓存，探针实测翻转 ep flag 后无需清缓存。
// 跳过语义：next() 丢弃批次头曲（本地跳过，不调未实测服务端接口），耗尽才按
//   offset 取下一批并过滤 disliked；喜欢语义：like/dislike 只写内存 Set + Log
//   留痕、不上报（不引 KeyValueSettings），dislike 同时移出当前批次。
// 铁律：禁 surface/flutter、禁 IO 直连；每方法 try/catch + Log('logic.fm')；
//   缓存 ns:'fm' schemaVer 1；失败返空/原值不静默吞。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as ep show SongBrief, getFmPlay, getFmSongs;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, SongBrief, buildKey, prefixOf;
/// FM 域缓存 schema 版本。
const int kFmCacheSchemaVer = 1;
const String _tag = 'logic.fm', _ns = 'fm';
const String _playPath = '/v1/fm/play', _songsPath = '/v1/fm/songs';
const int _batchSize = 20;
class FmLogic {
  FmLogic({required KugouClient client,
      required LruCache<String, dynamic> cache})
      : _client = client, _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }
  final KugouClient _client;
  final LruCache<String, dynamic> _cache;
  List<SongBrief> _batch = const <SongBrief>[];
  int _batchNo = 0;
  final Set<String> _liked = <String>{}, _disliked = <String>{};
  /// 首批 FM 歌曲：重置批次号 → getFmPlay（needs probe 时返回空）。供「随便听听」入口。
  Future<List<SongBrief>> start() async {
    try {
      _batchNo = 0;
      _batch = const <SongBrief>[];
      final key = _key(_playPath, const <String, Object?>{
        'mode': 'normal', 'action': 'play', 'batch': 0});
      final hit = _cache.get(key);
      if (hit is List<SongBrief>) {
        _batch = _filter(hit);
        Log.d(_tag, 'start cache hit got=${_batch.length}');
        return currentBatch();
      }
      _batch = _filter(await _load(key, ep.getFmPlay(_client), 'start'));
      Log.d(_tag, 'start got=${_batch.length}');
      return currentBatch();
    } catch (e, st) {
      Log.e(_tag, 'start failed', e, st);
      return const <SongBrief>[];
    }
  }
  /// 下一批/跳过：批次 >1 首则丢头曲（不打网）；余 0/1 首按 offset 取下一批。
  Future<List<SongBrief>> next() async {
    try {
      if (_batch.length > 1) {
        _batch = List<SongBrief>.unmodifiable(_batch.sublist(1));
        Log.d(_tag, 'next local skip left=${_batch.length}');
        return currentBatch();
      }
      _batchNo++;
      final offset = _batchNo * _batchSize;
      final key = _key(_songsPath, <String, Object?>{
        'offset': offset, 'size': _batchSize, 'batch': _batchNo});
      final hit = _cache.get(key);
      if (hit is List<SongBrief>) {
        _batch = _filter(hit);
        Log.d(_tag, 'next cache hit batch=$_batchNo got=${_batch.length}');
        return currentBatch();
      }
      // fmid/fmtype 未实测：留空、不猜枚举；端点层按 needs probe 留痕。
      final where = 'next batch=$_batchNo';
      _batch = _filter(await _load(key,
          ep.getFmSongs(_client, offset: offset, size: _batchSize), where));
      Log.d(_tag, '$where got=${_batch.length}');
      return currentBatch();
    } catch (e, st) {
      Log.e(_tag, 'next failed', e, st);
      return currentBatch();
    }
  }
  /// 喜欢：只记本地 Set + Log；保留当前曲（无服务端上报端点）。
  bool like(String hash) => _record(hash, liked: true);
  /// 不喜欢：记本地 Set + Log，并从当前批次移除该曲（等价于本地跳过）。
  bool dislike(String hash) {
    final ok = _record(hash, liked: false);
    if (!ok) return false;
    try {
      final h = hash.trim().toLowerCase();
      final n = _batch.length;
      _batch = List<SongBrief>.unmodifiable(
          _batch.where((s) => s.hash.toLowerCase() != h));
      Log.d(_tag, 'dislike removed from batch n=${n - _batch.length}');
    } catch (e, st) {
      Log.e(_tag, 'dislike remove failed hash=$hash', e, st);
    }
    return true;
  }

  /// 当前批次快照（不可变）；空批次 = needs probe / 无更多 FM 歌曲。
  List<SongBrief> currentBatch() {
    try {
      return _batch;
    } catch (e, st) {
      Log.e(_tag, 'currentBatch failed', e, st);
      return const <SongBrief>[];
    }
  }
  Set<String> get likedHashes => Set<String>.unmodifiable(_liked);
  Set<String> get dislikedHashes => Set<String>.unmodifiable(_disliked);

  /// 按 (ns, userid) 前缀失效（登出/换号清 FM 缓存）。
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
  String _key(String path, Map<String, Object?> params) => buildKey(
      ns: _ns, userid: _client.session.userid, path: path,
      params: params, schemaVer: kFmCacheSchemaVer);

  /// 空结果不落缓存：needs probe 恒空，避免实测后仍命中空缓存。
  Future<List<SongBrief>> _load(
      String key, Future<List<SongBrief>> future, String where) async {
    try {
      final items = await future;
      if (items.isEmpty) {
        Log.w(_tag, '$where empty batch (needs probe?) → not cached');
        return const <SongBrief>[];
      }
      _cache.put(key, List<SongBrief>.unmodifiable(items));
      Log.d(_tag, '$where cached n=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'load failed $where', e, st);
      return const <SongBrief>[];
    }
  }
  bool _record(String hash, {required bool liked}) {
    try {
      final h = hash.trim().toLowerCase();
      if (h.isEmpty) {
        Log.w(_tag, '${liked ? 'like' : 'dislike'} empty hash');
        return false;
      }
      if (liked) {
        _disliked.remove(h);
        _liked.add(h);
      } else {
        _liked.remove(h);
        _disliked.add(h);
      }
      Log.d(_tag, '${liked ? 'like' : 'dislike'} hash=$h '
          'liked=${_liked.length} disliked=${_disliked.length}');
      return true;
    } catch (e, st) {
      Log.e(_tag, '${liked ? 'like' : 'dislike'} failed hash=$hash', e, st);
      return false;
    }
  }
  List<SongBrief> _filter(List<SongBrief> items) {
    try {
      return List<SongBrief>.unmodifiable(items.where((s) =>
          s.hash.isNotEmpty && !_disliked.contains(s.hash.toLowerCase())));
    } catch (e, st) {
      Log.e(_tag, 'filter failed', e, st);
      return const <SongBrief>[];
    }
  }
}
