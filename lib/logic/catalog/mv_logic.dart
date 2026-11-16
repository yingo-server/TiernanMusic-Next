// L5 logic/catalog · MV 域门面（批1-B · GAP_ANALYSIS #16）
// videoDetail/videoUrl 端点 + LruCache(ns:'mv')。schemaVer v2（顶部常量）。
// 风格照 rank_logic.dart：缓存优先、每方法 try/catch + Log('logic.mv')。
// 清晰度降级策略见 playUrl 文档注释。
// 审查修复（阶段A A3/A5）：/v1/video 需要**数字 video_id**（实测 596344），
// 旧签名用 32 位歌曲 hash 冒充 → 档位恒空。qualities/playUrl 入参改 int。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart'
    as mv
    show
        MvPlayResult,
        MvQuality,
        getMvBySong,
        getVideoQualities,
        getVideoUrl;
import '../../bridges/bridge_core.dart'
    show KugouClient, LruCache, buildKey, prefixOf;

/// MV 域缓存 schema 版本（v2：键改用 videoId，旧 hash 键条目自然失效）。
const int kMvCacheSchemaVer = 2;

const String _tag = 'logic.mv';
const String _ns = 'mv';
const String _pVideoDetail = '/v1/video/detail';

class MvLogic {
  MvLogic({
    required KugouClient client,
    required LruCache<String, dynamic> cache,
  }) : _client = client,
       _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final LruCache<String, dynamic> _cache;

  /// 按歌曲 albumAudioId 解析数字 videoId（两段式第一段）。
  /// 端点 getMvBySong 现已按实测 video_id 返回 MvBrief（A3 P0 修复）；
  /// 返回 0 表示该歌曲无 MV，调用方应给明确空态而不是发错误请求。
  Future<int> videoIdOfSong(int albumAudioId) async {
    try {
      if (albumAudioId <= 0) return 0;
      final brief = await mv.getMvBySong(_client, albumAudioId);
      final id = brief?.videoId ?? 0;
      Log.d(_tag, 'videoIdOfSong aid=$albumAudioId videoId=$id');
      return id;
    } catch (e, st) {
      Log.e(_tag, 'videoIdOfSong failed aid=$albumAudioId', e, st);
      return 0;
    }
  }

  /// MV 清晰度档位（video/detail）。缓存优先，入参为数字 videoId。
  Future<List<mv.MvQuality>> qualities(int videoId) async {
    try {
      if (videoId <= 0) return const <mv.MvQuality>[];
      final key = buildKey(
        ns: _ns,
        userid: _client.session.userid,
        path: _pVideoDetail,
        params: <String, Object?>{'video_id': videoId},
        schemaVer: kMvCacheSchemaVer,
      );
      final hit = _cache.get(key);
      if (hit is List<mv.MvQuality>) {
        Log.d(_tag, 'qualities cache hit videoId=$videoId');
        return hit;
      }
      final items = await mv.getVideoQualities(_client, videoId);
      // 空结果不落缓存——网络抖动一次即永久「不可播」。
      if (items.isNotEmpty) _cache.put(key, items);
      Log.d(_tag, 'qualities videoId=$videoId got=${items.length}');
      return items;
    } catch (e, st) {
      Log.e(_tag, 'qualities failed videoId=$videoId', e, st);
      return const <mv.MvQuality>[];
    }
  }

  /// 取 MV 播放地址（入参数字 videoId）。
  ///
  /// 清晰度降级策略：
  /// 1. 档位按 size 降序排列（size 大 ≈ 画质高），取 requestedId 对应档位；
  /// 2. 请求档位 URL 为空（不可用，含 VIP 档被权限挡下）→ 沿降序自动降档；
  /// 3. 全档皆空 → 返回空 MvPlayResult（调用方提示不可播）。
  Future<mv.MvPlayResult> playUrl(
    int videoId, {
    String? requestedId,
    String title = '',
  }) async {
    try {
      if (videoId <= 0) return const mv.MvPlayResult();
      final quals = await qualities(videoId);
      if (quals.isEmpty) {
        Log.w(_tag, 'playUrl no qualities videoId=$videoId');
        return mv.MvPlayResult(title: title);
      }
      final sorted = quals.toList()..sort((a, b) => b.size.compareTo(a.size));
      var ordered = sorted;
      if (requestedId != null && requestedId.trim().isNotEmpty) {
        final idx = sorted.indexWhere(
          (q) => q.id == requestedId.trim() || q.hash == requestedId.trim(),
        );
        if (idx >= 0) ordered = sorted.sublist(idx);
      }
      for (final q in ordered) {
        final r = await mv.getVideoUrl(
          _client,
          q.hash,
          quality: q.id,
          title: title,
        );
        if (r.playable) {
          Log.d(
            _tag,
            'playUrl videoId=$videoId quality=${q.id} cdn=${r.urls.length} '
            'degraded=${q.id != requestedId}',
          );
          return r;
        }
        Log.w(_tag, 'playUrl quality=${q.id} empty urls, degrade next');
      }
      Log.w(_tag, 'playUrl all qualities unavailable videoId=$videoId');
      return mv.MvPlayResult(title: title);
    } catch (e, st) {
      Log.e(_tag, 'playUrl failed videoId=$videoId', e, st);
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
