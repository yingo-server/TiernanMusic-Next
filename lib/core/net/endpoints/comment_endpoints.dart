// L4 core/net/endpoints · 评论域端点封装（GAP #14，docs/KUGOU_API.md §3.9）
// PARITY_NOTES.md 实测纪律：
// - comment/music：参数走 QUERY 不是 body；顶层即 list（无 data 包层容错）
// - comment/floor：mcomment/v1/hot_replylist（楼层/热评回复）
// - comment/count：web 签名（WEB_SALT）+ sum.comment.service x-router
import '../../../kernel/kernel.dart' show Log;
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

  factory CommentItem.fromMap(Map<String, dynamic> m) {
    try {
      return CommentItem(
        id: safeStr(m['comment_id'] ?? m['cid'] ?? m['id'] ?? ''),
        content: safeStr(m['content'] ?? m['text'] ?? ''),
        nickname: safeStr(m['nickname'] ?? m['uname'] ?? m['username'] ?? ''),
        avatar: safeStr(m['avatar'] ?? m['uheadurl'] ?? m['headurl'] ?? ''),
        likeCount: safeInt(m['like'] ?? m['praisecount'] ?? m['like_count']),
        timeMs: safeInt(m['time'] ?? m['createtime'] ?? m['create_time']),
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
class CommentPage {
  const CommentPage({
    this.total = 0,
    this.items = const <CommentItem>[],
    this.hotWords = const <String>[],
  });

  final int total; // count / total
  final List<CommentItem> items;
  final List<String> hotWords; // data.hot_words 之类提取，空=无

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
        'items': items.map((c) => c.toMap()).toList(growable: false),
      };
}

/// 顶层 list / data.list[] / data.listinfos[] 三态容错提取评论列表。
List<Map<String, dynamic>> _commentListOf(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    if (data.isEmpty) {
      // 顶层即 list（PARITY_NOTES：comment/music 顶层 list ✅）
      return listOf(res);
    }
    return listOf(data['list'] ?? data['listinfos'] ?? data['info'] ?? res);
  } catch (e, st) {
    Log.e(_tag, '_commentListOf failed', e, st);
    return const <Map<String, dynamic>>[];
  }
}

/// 热词提取：data.hot_words / hotwords / hot_chips。
List<String> _hotWordsOf(Map<String, dynamic> res) {
  try {
    final data = dataOf(res);
    final raw = data['hot_words'] ?? data['hotwords'] ??
        data['hot_chips'] ?? res['hot_words'];
    if (raw is List) {
      return raw.map((w) => safeStr(w is Map ? (w['word'] ?? w['name']) : w))
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  } catch (e, st) {
    Log.e(_tag, '_hotWordsOf failed', e, st);
    return const <String>[];
  }
}

/// 歌曲评论列表（commentMusic：GET，参数走 query；android 签名）。
Future<CommentPage> getMusicComments(
    KugouClient client, int mixSongId, int page,
    {int pageSize = 20}) async {
  try {
    if (mixSongId <= 0) {
      Log.w(_tag, 'getMusicComments invalid mixSongId=$mixSongId');
      return const CommentPage();
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
    Log.e(_tag, 'getMusicComments failed mix=$mixSongId p=$page', e, st);
    return const CommentPage();
  }
}

/// 楼中楼/热评回复列表（commentFloor：GET hot_replylist）。
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
      'commentid': commentId,
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
Future<int> getCommentCount(KugouClient client, int mixSongId) async {
  try {
    if (mixSongId <= 0) {
      Log.w(_tag, 'getCommentCount invalid mixSongId=$mixSongId');
      return 0;
    }
    final res = await client.request(EndpointRegistry.commentCount,
        <String, Object?>{'mixsongid': mixSongId, 'code': kCommentCode});
    final data = dataOf(res);
    final n = safeInt(
        data['count'] ?? data['total'] ?? res['count'] ?? res['total']);
    Log.d(_tag, 'getCommentCount mix=$mixSongId count=$n');
    return n;
  } catch (e, st) {
    Log.e(_tag, 'getCommentCount failed mix=$mixSongId', e, st);
    return 0;
  }
}
