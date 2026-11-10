// L5 logic/catalog · MV 域门面（批1-B · GAP_ANALYSIS #16）
// mvDetail/videoDetail/videoUrl 端点 + LruCache(ns:'mv')。schemaVer v1（顶部常量）。
// 风格照 rank_logic.dart：缓存优先、每方法 try/catch + Log('logic.mv')。
// 清晰度降级策略见 playUrl 文档注释。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' as mv show MvBrief, MvPlayResult, MvQuality, getMvBySong, getVideoQualities, getVideoUrl;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, buildKey, prefixOf;

/// MV 域缓存 schema 版本。
const int kMvCacheSchemaVer = 1;

const String _tag = 'logic.mv';
const String _ns = 'mv';
const String _pMvDetail = '/kmr/audio/mv';
const String _pVideoDetail = '/v1/video/detail';
const String _pVideoUrl = '/v2/interface/index';

class MvLogic {
  MvLogic({
    required KugouClient client,
    required LruCache<String, dynamic> cache,
  })  : _client = client,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, dynamic> _cache;

  /// 按歌查 MV（kmr/audio/mv data.list[0]）。缓存优先（ns:'mv'）。
  /// 查不到返回 null（无 MV 与失败共用，调用方不区分）。
  Future<mv.MvBrief?> resolveBySong(int albumAudioId) async {
    try {
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _pMvDetail,
        params: <String, Object?>{'album_audio_id': albumAudioId},
        schemaVer: kMvCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is mv.MvBrief?) {
        Log.d(_tag, 'resolveBySong cache hit aid=$albumAudioId');
        return hit;
      }
      final brief = await mv.getMvBySong(_client, albumAudioId);
      _cache.put(key, brief);
      Log.d(_tag, 'resolveBySong aid=$albumAudioId got=${brief != null}');
      return brief;
    } catch (e, st) {
      Log.e(_tag, 'resolveBySong failed aid=$albumAudioId', e, st);
      return null;
    }
  }

  /// MV 清晰度档位（video/detail）。缓存优先。
  Future<List<mv.MvQuality>> qualities(String mvHash) async {
    try {
      final h = mvHash.trim().toLowerCase();
      if (h.isEmpty) return const <mv.MvQuality>[];
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _pVideoDetail,
        params: <String, Object?>{'hash': h},
        schemaVer: kMvCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<mv.MvQuality>) {
        Log.d(_tag, 'qualities cache hit hash=$h');
        return hit;
      }
      final items = await mv.getVideoQualities(_client, h);
      _cache.put(key, items);
      Log.d(_tag, 'qualities hash=$h got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'qualities failed hash=$mvHash', e, st);
      return const <mv.MvQuality>[];
    }
  }

  /// 取 MV 播放地址。
  ///
  /// 清晰度降级策略：
  /// 1. 档位按 size 降序排列（size 大 ≈ 画质高），取 requestedId 对应档位；
  /// 2. 请求档位 URL 为空（不可用，含 VIP 档被权限挡下）→ 沿降序自动降档，
  ///    直到命中首个可出 URL 的档位（VIP 不可用自动降档语义）；
  /// 3. 全档皆空 → 返回空 MvPlayResult（调用方提示不可播）。
  /// downurl 多 CDN 全量收集，调用方逐链容错。
  Future<mv.MvPlayResult> playUrl(
    String mvHash, {
    String? requestedId,
    String title = '',
  }) async {
    try {
      final h = mvHash.trim().toLowerCase();
      if (h.isEmpty) return const mv.MvPlayResult();
      final quals = await qualities(h);
      if (quals.isEmpty) {
        Log.w(_tag, 'playUrl no qualities hash=$h');
        return mv.MvPlayResult(title: title);
      }
      // size 降序 = 画质从高到低；requestedId 未命中或未指定 → 取最高档。
      final sorted = quals.toList()
        ..sort((a, b) => b.size.compareTo(a.size));
      var ordered = sorted;
      if (requestedId != null && requestedId.trim().isNotEmpty) {
        final idx = sorted.indexWhere(
            (q) => q.id == requestedId.trim() || q.hash == requestedId.trim());
        if (idx >= 0) ordered = sorted.sublist(idx);
      }
      for (final q in ordered) {
        final r = await mv.getVideoUrl(_client, q.hash,
            quality: q.id, title: title);
        if (r.playable) {
          Log.d(_tag,
              'playUrl hash=$h quality=${q.id} cdn=${r.urls.length} '
              'degraded=${q.id != requestedId}');
          return r;
        }
        Log.w(_tag, 'playUrl quality=${q.id} empty urls, degrade next');
      }
      Log.w(_tag, 'playUrl all qualities unavailable hash=$h');
      return mv.MvPlayResult(title: title);
    } catch (e, st) {
      Log.e(_tag, 'playUrl failed hash=$mvHash', e, st);
      return mv.MvPlayResult(title: title);
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
