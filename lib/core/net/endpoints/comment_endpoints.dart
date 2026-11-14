// L4 core/net/endpoints · 评论域端点封装（GAP #14，docs/KUGOU_API.md §3.9）
// PARITY_NOTES.md 实测纪律：
// - comment/music：参数走 QUERY 不是 body；顶层即 list（无 data 包层容错）
// - comment/floor：mcomment/v1/hot_replylist（楼层/热评回复）
// - comment/count：web 签名（WEB_SALT）+ sum.comment.service x-router
// ⚠ docs/API_FIELDS_TRUTH.md **无评论域实测章节**（该文档 A5 编号属 MV 域）。
//   本文件字段锚点 = 批N3-A 探针留样（tool/field_truth_test.dart
//   'N3-A comment/collect/FM field truth' 组）；待 API_FIELDS_TRUTH.md 补章节。
//   凡未在锚点留样中的键一律按容错读取，不作成功门槛。
import '../../../bridges/bridge_kernel.dart' show Log;
import '../kugou_client.dart';
import 'models.dart';

const String _tag = 'ep.comment';
const String kCommentCode = 'fc4be23b4e972707f36b8a828a93ba8a';

/// 单条评论。
class CommentItem {
  const CommentItem({
    this.id = '',
    this.content = '',
    this.nickname = '',
    this.avatar = '',
    this.likeCount = 0,
    this.timeMs = 0,
    this.floor = 0,
    this.replyTo = '',
  });

  final String id; // comment_id / cid
  final String content; // content / text
  final String nickname; // nickname / uname
  final String avatar; // avatar / uheadurl
  final int likeCount; // like / praisecount
  final int timeMs; // time / createtime（毫秒）
  final int floor; // 楼层号（floo / floor，缺失 0）
  final String replyTo; // 被回复者昵称（reply_name，空=顶层）

  /// 批N3-A 实测锚点（A5-1）：评论项键 = id/content/addtime/reply_num/
  /// like{count,haslike,likenum}/user_name/user_pic/user_id；
  /// **无 nickname/avatar/floo/time 键** → 下述多键仅容错兜底（缺失即 0/空），
  /// 不作成功门槛；楼层号/被回复者键在 API_FIELDS_TRUTH.md 无实测章节（待实测）。
  factory CommentItem.fromMap(Map<String, dynamic> m) {
    try {
      return CommentItem(
        id: safeStr(m['comment_id'] ?? m['cid'] ?? m['id'] ?? ''),
        content: safeStr(m['content'] ?? m['text'] ?? ''),
        nickname: safeStr(m['nickname'] ?? m['uname'] ?? m['username'] ??
            m['user_name'] ?? ''),
        avatar: safeStr(m['avatar'] ?? m['uheadurl'] ?? m['headurl'] ??
            m['user_pic'] ?? ''),
        // 实测：like 是对象 {count,haslike,...}，无顶层标量 → 取 like.count。
        likeCount: safeInt(m['like'] is Map
            ? (m['like']['count'] ?? m['like']['likenum'])
            : (m['like'] ?? m['praisecount'] ?? m['like_count'])),
        // addtime 是格式化字符串（非时间戳），timeMs 保留兼容，字符串不猜解析。
        timeMs: safeInt(m['time'] ?? m['createtime'] ?? m['create_time']),
        // ⚠ 待实测：楼层号/被回复者键在 API_FIELDS_TRUTH.md 无实测章节，
        // 仅容错读取（缺失即 0/空），不作成功门槛。
        floor: safeInt(m['floo'] ?? m['floor'] ?? m['floor_num']),
        replyTo: safeStr(m['reply_name'] ?? m['toname'] ?? ''),
      );
    } catch (e, st) {
      Log.e(_tag, 'CommentItem.fromMap failed', e, st);
      return const CommentItem();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'content': content, 'nickname': nickname,
        'avatar': avatar, 'likeCount': likeCount, 'timeMs': timeMs,
        'floor': floor, 'replyTo': replyTo,
      };
}

/// 评论分页：顶层 list / data.list[] 双容错 + 热词 chips。
/// 批3-F2：blockedReason 非空表示「加载受限」（WAF `Access Deny !!!` 等非 JSON
/// 响应被 KugouClient 归一为 KugouApiException(-3)），UI 据此显示受限提示，
/// 不再把解析失败误报成「暂无评论」。可选命名参数，旧 const 构造零破坏。
class CommentPage {
  const CommentPage({
    this.total = 0,
    this.items = const <CommentItem>[],
    this.hotWords = const <String>[],
    this.blockedReason,
  });

  final int total; // count / total
  final List<CommentItem> items;
  final List<String> hotWords; // data.hot_words 之类提取，空=无
  final String? blockedReason; // 非 null：加载受限原因（解析失败/WAF/异常）

  bool get hasMore {
    try {
      return items.isNotEmpty && (total <= 0 || items.length < total);
    } catch (e, st) {
      Log.e(_tag, 'CommentPage.hasMore failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'total': total, 'hotWords': hotWords, 'hasMore': hasMore,
        'blockedReason': blockedReason,
        'items': items.map((c) => c.toMap()).toList(growable: false),
      };
}

/// 顶层 list / data.list[] / data.listinfos[] 三态容错提取评论列表。
List<Map<String, dynamic>> _commentListOf(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    if (data.isEmpty) {
      // 顶层即 list（PARITY_NOTES：comment/music 顶层 list ✅）
      // 注意：listOf 只吃 List；顶层键 list/listinfos/info 必须单独取，
      // 直接传 Map 恒空列表（列表恒空 → 评论页空白）。
      return listOf(res['list'] ?? res['listinfos'] ?? res['info']);
    }
    return listOf(data['list'] ?? data['listinfos'] ?? data['info']);
  } catch (e, st) {
    Log.e(_tag, '_commentListOf failed', e, st);
    return const <Map<String, dynamic>>[];
  }
}

/// 热词提取：data.hot_words / hotwords / hot_chips。
List<String> _hotWordsOf(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    // 批N3-A 实测（A5-1）：热词 chips 直接内嵌于 cmtlist 顶层
    // hot_word_list[]{content,count}；分类在 classify_list[]（不单独调端点）。
    final raw = res['hot_word_list'] ?? data['hot_word_list'] ??
        data['hot_words'] ?? data['hotwords'] ?? res['hot_words'];
    if (raw is List) {
      return raw.map((w) => safeStr(w is Map
              ? (w['content'] ?? w['word'] ?? w['name'])
              : w))
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  } catch (e, st) {
    Log.e(_tag, '_hotWordsOf failed', e, st);
    return const <String>[];
  }
}

/// 批3-F2：把受限原因归一化（端点 catch 与 tool/field_truth_test.dart 共用同一实现，
/// 避免测试复制逻辑）；生产调用与断言都走此函数。
/// 只保留可读短因，绝不把原始响应/凭据写进 UI 文案。
String commentBlockedReason(Object e) {
  try {
    final msg = '$e'.trim();
    if (e is KugouApiException && e.code == -3) {
      // 实测：WAF 拦截返回非 JSON（Access Deny !!!），jsonDecode 失败归一为 -3。
      return '接口返回非 JSON（可能被安全策略拦截，$msg）';
    }
    return '接口响应异常（$msg）';
  } catch (_) {
    return '接口响应异常';
  }
}

/// 歌曲评论列表（commentMusic：GET，参数走 query；android 签名）。
/// 批3-F2：catch 中把失败原因写入 CommentPage.blockedReason，端点层不静默吞，
/// 调用方（logic → surface）据此区分「受限」与「真的没有评论」。
Future<CommentPage> getMusicComments(
    KugouClient client, int mixSongId, int page,
    {int pageSize = 20}) async {
  try {
    if (mixSongId <= 0) {
      Log.w(_tag, 'getMusicComments invalid mixSongId=$mixSongId');
      return const CommentPage(
          blockedReason: '歌曲标识无效，无法加载评论');
    }
    final res = await client.request(EndpointRegistry.commentMusic,
        <String, Object?>{
      'mixsongid': mixSongId,
      'p': page,
      'pagesize': pageSize,
      'code': kCommentCode,
    });
    final data = dataOf(res);
    final items = _commentListOf(res).map(CommentItem.fromMap).toList();
    final total = safeInt(
        data['count'] ?? data['total'] ?? res['count'] ?? res['total']);
    final page_ = CommentPage(
      total: total,
      items: items,
      hotWords: _hotWordsOf(res),
    );
    Log.d(_tag, 'getMusicComments mix=$mixSongId p=$page got=${items.length} '
        'total=$total hot=${page_.hotWords.length}');
    return page_;
  } catch (e, st) {
    final reason = commentBlockedReason(e);
    Log.e(_tag, 'getMusicComments failed mix=$mixSongId p=$page '
        'reason=$reason', e, st);
    // 诚实化：受限不是「暂无评论」，把原因随空页透传给 UI，且不落缓存。
    return CommentPage(blockedReason: reason);
  }
}

/// 楼中楼/热评回复列表（commentFloor：GET hot_replylist）。
/// 批N3-A 实测锚点（A5-2）：**楼层键是 `tid`**（不是 commentid）。
/// ⚠ 待实测：childrenid/mixsongid 的正确口径（歌曲 id vs 评论 id）在
///   API_FIELDS_TRUTH.md 无实测章节，按最小参数集随传，不作成功门槛。
Future<List<CommentItem>> getCommentFloor(
    KugouClient client, String commentId, int page,
    {int pageSize = 20}) async {
  try {
    if (commentId.trim().isEmpty) {
      Log.w(_tag, 'getCommentFloor empty commentId');
      return const <CommentItem>[];
    }
    final res = await client.request(EndpointRegistry.commentFloor,
        <String, Object?>{
      'tid': commentId,
      'childrenid': commentId,
      'mixsongid': commentId,
      'p': page,
      'pagesize': pageSize,
      'code': kCommentCode,
    });
    final items = _commentListOf(res).map(CommentItem.fromMap).toList();
    Log.d(_tag, 'getCommentFloor cid=$commentId p=$page got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'getCommentFloor failed cid=$commentId p=$page', e, st);
    return const <CommentItem>[];
  }
}

/// 评论总数（commentCount：GET，web 签名，x-router sum.comment.service）。
/// 批N3-A 实测锚点（A5-3）：**必须传 FileHash**，响应以 hash 键取值；
/// 传 mixsongid/childrenid 恒 0（实测），故无 fileHash 时直接返回 0，
/// 不发无锚点请求、不臆造响应层级（键名大小写两路容错）。
/// mixSongId 形参保留兼容旧调用（不参与取值）。
Future<int> getCommentCount(KugouClient client, int mixSongId,
    {String fileHash = ''}) async {
  try {
    final hash = fileHash.trim();
    if (hash.isEmpty) {
      // 实测：mixsongid 恒 0 → 无 FileHash 即无有效总数，如实返回 0。
      Log.w(_tag, 'getCommentCount no fileHash (mixsongid 实测恒 0) '
          'mix=$mixSongId');
      return 0;
    }
    final res = await client.request(EndpointRegistry.commentCount,
        <String, Object?>{
      'code': kCommentCode,
      'hash': hash,
    });
    // 实测：响应顶层以 hash 键取值（大小写两路容错）。
    final n = safeInt(res[hash] ?? res[hash.toUpperCase()] ??
        res[hash.toLowerCase()] ?? 0);
    Log.d(_tag, 'getCommentCount hash=$hash count=$n');
    return n;
  } catch (e, st) {
    Log.e(_tag, 'getCommentCount failed mix=$mixSongId', e, st);
    return 0;
  }
}
