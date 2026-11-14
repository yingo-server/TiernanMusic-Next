// L4 core/net/endpoints · 歌单/排行域模型（PlaylistBrief/PlaylistDetail/TrackPage/RankBrief）
// 来源拆分：models.dart（614 行超行拆分，R2-A）；类体逐字搬移，零逻辑改动。
import '../../../bridges/bridge_kernel.dart' show Log;
import 'models_util.dart';
import 'cover_url.dart' show normalizeCoverUrl;
import 'song_models.dart' show SongBrief;


const String _tag = 'net.models.playlist';
class PlaylistBrief {
  const PlaylistBrief({
    this.id = '',
    this.listid = '',
    this.name = '',
    this.cover = '',
    this.playCount = 0,
    this.trackCount = 0,
    this.creator = '',
    this.intro = '',
  });

  final String id; // global_collection_id / specialid / listid
  /// 数字歌单 id（/v7/get_all_list 的 listid，写操作 add_song/delete_songs 专用）。
  final String listid;
  final String name; // specialname
  final String cover; // imgurl（recommend）/ pic（detail）/ img（search special）
  final int playCount;
  final int trackCount; // count / song_count
  final String creator; // username / list_create_username / nickname
  final String intro;

  factory PlaylistBrief.fromMap(Map<String, dynamic> m) {
    try {
      return PlaylistBrief(
        id: safeStr(
            m['global_collection_id'] ?? m['specialid'] ?? m['listid'] ??
                m['id'] ?? ''),
        listid: safeStr(m['listid'] ?? m['id'] ?? ''),
        name: safeStr(m['specialname'] ?? m['name'] ??
            m['collection_name'] ?? ''),
        // 批N1-C 实测（API_FIELDS_TRUTH.md A2-2/A2-3/A2-4）：
        // - recommend special_list[]：cover 键 imgurl（recommend 命中），搜索
        //   special 命中是 img；play_count（下划线）、song_count。
        // - detail 首项：cover 键 pic（无 imgurl）、count、creator 键
        //   list_create_username（无 username）。tags 为逗号分隔字符串。
        cover: normalizeCoverUrl(safeStr(m['imgurl'] ?? m['pic'] ?? m['img'] ?? m['cover'] ?? '')),
        playCount: safeInt(m['playcount'] ?? m['play_count']),
        trackCount: safeInt(m['count'] ?? m['song_count'] ?? m['track_count']),
        creator: safeStr(m['username'] ?? m['list_create_username'] ??
            m['user_name'] ?? m['nickname'] ?? ''),
        intro: safeStr(m['intro'] ?? ''),
      );
    } catch (e, st) {
      Log.e(_tag, 'PlaylistBrief.fromMap failed', e, st);
      return const PlaylistBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'name': name, 'cover': cover, 'playCount': playCount,
        'trackCount': trackCount, 'creator': creator, 'intro': intro,
      };
}

/// 歌单详情（playlist_detail data[] 首项）。
class PlaylistDetail {
  const PlaylistDetail({
    this.id = '',
    this.name = '',
    this.cover = '',
    this.playCount = 0,
    this.trackCount = 0,
    this.intro = '',
    this.creator = '',
    this.tags = const <String>[],
    this.listVer = 0,
    this.specialId = '',
  });

  final String id;
  final String name;
  final String cover;
  final int playCount;
  final int trackCount;
  final String intro;
  final String creator;
  final List<String> tags;
  /// 批N3-B 实测（A2-2）：get_list_info data[0].list_ver 歌单内容版本号，
  /// 写操作请求体 list_ver 须与服务器一致。detail 成功后写入 _listVerCache。
  final int listVer;

  /// 数字 specialid（detail 响应透传；playlistTracks 必须用它，
  /// 传 global_collection_id 实测恒 20010）。为空时上层不得调 tracks。
  final String specialId;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id, 'name': name, 'cover': cover, 'playCount': playCount,
        'trackCount': trackCount, 'intro': intro, 'creator': creator,
        'tags': tags, 'listVer': listVer,
      };
}

/// 歌单曲目分页（playlistTracks：data.info[] + data.count）。
class TrackPage {
  const TrackPage({
    this.total = 0,
    this.beginIdx = 0,
    this.pageSize = 0,
    this.items = const <SongBrief>[],
  });
  final int total; // data.count
  final int beginIdx;
  final int pageSize;
  final List<SongBrief> items;

  bool get hasMore {
    try {
      return beginIdx + items.length < total;
    } catch (e, st) {
      Log.e(_tag, 'TrackPage.hasMore failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'total': total, 'beginIdx': beginIdx, 'pageSize': pageSize,
        'hasMore': hasMore,
        'items': items.map((s) => s.toMap()).toList(growable: false),
      };
}

/// 排行榜条目（rank list data.info[]）。
class RankBrief {
  const RankBrief({
    this.rankId = 0,
    this.name = '',
    this.cover = '',
    this.updateTime = '',
    this.intro = '',
  });

  final int rankId; // rankid
  final String name; // rankname
  final String cover; // imgurl
  final String updateTime;
  final String intro;

  factory RankBrief.fromMap(Map<String, dynamic> m) {
    try {
      // 批N1-B 实测（docs/API_FIELDS_TRUTH.md A2-4）：rank/list info[] 无
      // updatetime 键；更新时间键是 rank_id_publish_date（期号发布时间），
      // 另有 update_frequency（频率描述）/ rank_cid（本期快照 id）/ issue（期号）。
      return RankBrief(
        rankId: safeInt(m['rankid']),
        name: safeStr(m['rankname'] ?? m['name'] ?? ''),
        cover: normalizeCoverUrl(safeStr(m['imgurl'] ?? m['img'] ?? '')),
        // 批N1-C 实测（A2-4 rank/list info[]）：更新时间键是
        // rank_id_publish_date；另有 update_frequency（频率描述）。
        updateTime: safeStr(m['rank_id_publish_date'] ??
            m['updatetime'] ?? m['update_frequency'] ?? ''),
        intro: safeStr(m['intro'] ?? ''),
      );
    } catch (e, st) {
      Log.e(_tag, 'RankBrief.fromMap failed', e, st);
      return const RankBrief();
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'rankId': rankId, 'name': name, 'cover': cover,
        'updateTime': updateTime, 'intro': intro,
      };
}

