// tool/field_truth_test.dart — 批N1-C/N2/N3 全量字段实证回归锚点（纯 Dart，无 flutter 依赖）
// 数据源：docs/API_FIELDS_TRUTH.md（2026-11-12 probe 实测样例，gateway.kugou.com 三态）。
// 断言 core/net/endpoints/models.dart 及各端点模型对真实响应逐字段正确。
// CI：.github/workflows/ci.yml「field truth (pure Dart anchors)」步 + verdict 门禁。
// 运行：/opt/dart/bin/dart run tool/field_truth_test.dart → 全过输出 FIELD-TRUTH-OK，失败退出码 1。
import 'dart:convert';
import 'dart:io' show exitCode, ZLibCodec;
import '../lib/core/net/endpoints/models.dart';
import '../lib/core/net/endpoints/mv_endpoints.dart'
    show MvBrief, MvQuality;
import '../lib/core/net/endpoints/artist_endpoints.dart'
    show ArtistDetail, ArtistBrief, AlbumBrief;
import '../lib/core/net/endpoints/search_typed_endpoints.dart';
import '../lib/core/net/endpoints/misc_endpoints.dart'
    show krcDecode, kKrcXorKey;
// 批3-F2 新契约断言（纯 Dart，无 flutter）：CommentPage.blockedReason 与
// 每日推荐显式分态；旧锚点一行不动。
import '../lib/core/net/endpoints/comment_endpoints.dart'
    show CommentPage, commentBlockedReason;
import '../lib/core/net/endpoints/recommend_endpoints.dart'
    show DailyRecommendState, DailyRecommendResult;
import '../lib/core/net/kugou_client.dart' show KugouApiException;
import '../lib/core/net/signing.dart' show KugouSign, Md5;

/// 测试锚点用 MD5（复用 signing.dart 纯 Dart 实现，小写 hex）。
String _md5(String s) => Md5.hex(s);

/// 批N3-B 锚点辅助：动态 Map 规范化 + 布尔断言（失败计入 _fail）。
Map<String, dynamic> castMap(Object? v) => v is Map
    ? v.map((k, val) => MapEntry('$k', val))
    : <String, dynamic>{};
void _check(String name, bool ok) {
  if (ok) {
    _pass++;
  } else {
    _fail++;
    print('FAIL $name');
  }
}

int _pass = 0, _fail = 0;
void eq(String name, Object? got, Object? want) {
  if ('$got' == '$want') {
    _pass++;
  } else {
    _fail++;
    print('FAIL $name: got=$got want=$want');
  }
}

void group(String name) => print('-- $name');

void main() {
  // 封面契约更新（R2）：{size} 模板在模型层归一化为 240（cover_url.dart）。
// ══ A5/A6 · 批N3-A 评论/收藏/FM 实测锚点（2026-11-12）══
  group('N3-A comment/collect/FM field truth');

  final cmt = <String, dynamic>{
    'id': 123456,
    'content': '好听',
    'addtime': '2025-12-26 19:46:04',
    'reply_num': 7,
    'like': {'count': 42, 'haslike': 0, 'likenum': 42},
    'user_name': '听友',
    'user_pic': 'http://imge.kugou.com/a.jpg',
    'user_id': 88,
  };
  eq('A5-1 like 是对象，取 like.count',
      safeInt(cmt['like'] is Map ? cmt['like']['count'] : cmt['like']), 42);
  eq('A5-1 addtime 是字符串非时间戳',
      cmt['addtime'] is String, true);
  eq('A5-1 用户名键 user_name', safeStr(cmt['user_name']), '听友');

  final cmtRes = <String, dynamic>{
    'count': 711210,
    'list': [cmt],
    'hot_word_list': [
      {'content': '晴天', 'count': 23593},
      {'content': '青春', 'count': 1000},
    ],
    'classify_list': [
      {'id': 13, 'label': '歌曲相关', 'cnt': 55400},
    ],
    'maxPage': 5000,
  };
  eq('A5-1 评论在顶层 list[]（无 data 包层）',
      listOf(cmtRes['list']).length, 1);
  eq('A5-1 热词 hot_word_list[].content',
      safeStr(listOf(cmtRes['hot_word_list']).first['content']), '晴天');
  eq('A5-1 count 顶层', safeInt(cmtRes['count']), 711210);

  final favRes = <String, dynamic>{
    'errcode': 0,
    'data': {
      'list': [
        {'mixsongid': 32100650, 'count': 47876938, 'count_text': '4787w'},
        {'mixsongid': 32100651, 'count': 100, 'count_text': '100'},
      ],
    },
  };
  final favList = listOf((favRes['data'] as Map)['list']);
  var favSum = 0;
  for (final it in favList) {
    if (it is Map) favSum += safeInt(it['count']);
  }
  eq('A5-5 favorite_count 是 data.list[] 数组', favList.length, 2);
  eq('A5-5 批量计数求和', favSum, 47877038);

  final fmRes = <String, dynamic>{
    'status': 1,
    'data': {
      'song_list': [
        {
          'hash': 'B3A52A7A958BF0AED0EBFBA2E9A818B7',
          'songname': '晴天',
          'mixsongid': '32100650',
          'time_length': 269,
          'singerinfo': [
            {'name': '周杰伦'}
          ],
        }
      ],
    },
  };
  eq('A5-6 FM 列表键是 data.song_list（非 data.songs）',
      listOf((fmRes['data'] as Map)['song_list']).length, 1);
  eq('A5-6 FM mixsongid 是字符串',
      listOf((fmRes['data'] as Map)['song_list']).first['mixsongid'] is String,
      true);

  eq('A5-3 评论数必须传 hash（mixsongid 恒 0）',
      safeInt(<String, dynamic>{'HASH': 711210}['HASH']), 711210);

  // ══ A1 · search /v3/search/song（data.lists[]，实测留样 2026-11-12）══
  group('A1 search song');
  const songItem = <String, dynamic>{
    'FileName': '周杰伦 - 发如雪',
    'SingerName': '周杰伦',
    'OriSongName': '发如雪',
    'FileHash': '1F7E7659B9FFF4FB6F71562A61BBC25F',
    'FileSize': 4789176,
    'ExtName': 'mp3',
    'Duration': 299,
    'Bitrate': 128,
    'PublishAge': 255,
    'AlbumID': '958909',
    'AlbumName': '十一月的萧邦',
    'MixSongID': '32029513', // 实测为字符串
    'Audioid': 339589, // 实测：无 AlbumAudioId 键，音频 id 在 Audioid（=Scid）
    'AlbumPrivilege': 10,
    'trans_param': {'musicpack_advance': 1},
  };
  final s = SongBrief.fromSearchList(songItem);
  eq('song.hash(lower)', s.hash, '1f7e7659b9fff4fb6f71562a61bbc25f');
  eq('song.name', s.name, '周杰伦 - 发如雪');
  eq('song.singer', s.singer, '周杰伦');
  eq('song.mixSongId(str→int)', s.mixSongId, 32029513);
  eq('song.albumAudioId(Audioid 兜底)', s.albumAudioId, 339589);
  eq('song.durationSec', s.durationSec, 299);
  eq('song.bitrate', s.bitrate, 128);
  eq('song.fileSize', s.fileSize, 4789176);
  eq('song.albumId', s.albumId, '958909');
  eq('song.albumName', s.albumName, '十一月的萧邦');
  eq('song.isVip(trans_param.musicpack_advance)', s.isVip, true);

  final res1 = parseSearchItems(<String, dynamic>{
    'status': 1,
    'data': {'total': 590, 'lists': [songItem, {'FileHash': '', 'FileName': ''}]},
  });
  eq('parseSearchItems data.lists(空项滤除)', res1.length, 1);
  final res2 = parseSearchItems(<String, dynamic>{
    'status': 1,
    'data': {'info': [songItem]},
  });
  eq('parseSearchItems info 兜底', res2.length, 1);

  // ══ A1 · 五类分类搜索 data.lists[] 字段树锚点（真实留样键集）══
  group('A1 typed search field trees');
  const specialItem = <String, dynamic>{
    'specialid': 2255477,
    'specialname': '跑步必听｜超燃英文歌',
    'img': 'http://imge.kugou.com/soft/collection/280/20200324/x.jpg',
    'intro': '适合跑步时听的英文歌',
    'play_count': 999999,
    'song_count': 23,
    'collect_count': 4321,
    'nickname': '薛予安',
    'suid': 486950678,
    'publish_time': '2020-03-24',
    'isvip': 0,
  };
  final pb1 = PlaylistBrief.fromMap(specialItem);
  eq('special.id(specialid)', pb1.id, '2255477');
  eq('special.name', pb1.name, '跑步必听｜超燃英文歌');
  eq('special.cover(img 键，N1-C 修复)', pb1.cover,
      'http://imge.kugou.com/soft/collection/280/20200324/x.jpg');
  eq('special.trackCount(song_count，N1-C 修复)', pb1.trackCount, 23);
  eq('special.playCount(play_count，N1-C 修复)', pb1.playCount, 999999);
  eq('special.creator(nickname)', pb1.creator, '薛予安');

  // album / author / mv 分类项无强类型模型（AlbumBrief/AuthorBrief/MvBrief 缺失），
  // 实测键集固化于 API_FIELDS_TRUTH.md §A1，批N2 补模型时以此为准。
  const albumKeys = [
    'albumid', 'albumname', 'singer', 'singerid', 'img', 'publish_time',
    'songcount', 'play_count', 'collect_count', 'company', 'intro', 'grade',
    'privilege', 'language', 'singers', 'title', 'category',
  ];
  const authorKeys = [
    'AuthorId', 'AuthorName', 'Avatar', 'AlbumCount', 'AudioCount', 'FansNum',
    'Heat', 'Identity', 'IsReal', 'IsSettledAuthor', 'UserId', 'VideoCount',
    'ComplexSongName', 'FirstFrameImage',
  ];
  const mvKeys = [
    'MvID', 'MvName', 'MvHash', 'FileName', 'FileHash', 'FileSize', 'Bitrate',
    'Duration', 'Pic', 'SingerName', 'SingerID', 'MixSongID', 'AlbumID',
    'AudioID', 'IsOfficial', 'PublishDate', 'Remark', 'Description',
  ];
  eq('album keys fixed', albumKeys.length, 17);
  eq('author keys fixed', authorKeys.length, 14);
  eq('mv keys fixed', mvKeys.length, 18);

  // ══ A2-1 · playlist recommend（data.special_list[]）══
  group('A2-1 playlist recommend');
  const recItem = <String, dynamic>{
    'global_collection_id': 'collection_1_486950678_2255477_0',
    'specialid': 2255477,
    'specialname': '跑步必听｜超燃英文歌，助你轻松奔跑',
    'imgurl': 'http://imge.kugou.com/soft/collection/240/20200324/20200324024507285054.jpg',
    'pic': 'http://imge.kugou.com/soft/collection/{size}/20200324/pic.jpg',
    'intro': '适合跑步时听的英文歌',
    'play_count': 888888,
    'nickname': '薛予安',
    'singername': '',
    'tags': ['英语', '兴奋', '运动'],
  };
  final pb2 = PlaylistBrief.fromMap(recItem);
  eq('rec.id(global_collection_id 优先)', pb2.id, 'collection_1_486950678_2255477_0');
  eq('rec.name', pb2.name, '跑步必听｜超燃英文歌，助你轻松奔跑');
  eq('rec.cover(imgurl 优先)', pb2.cover,
      'http://imge.kugou.com/soft/collection/240/20200324/20200324024507285054.jpg');
  eq('rec.playCount(play_count，N1-C 修复)', pb2.playCount, 888888);
  eq('rec.creator(nickname)', pb2.creator, '薛予安');

  // ══ A2-2 · playlist detail（data[] 首项，实测 name/pic/list_create_username）══
  group('A2-2 playlist detail');
  const detailItem = <String, dynamic>{
    'global_collection_id': 'collection_1_486950678_2255477_0',
    'specialid': 2255477,
    'name': '跑步必听｜超燃英文歌，助你轻松奔跑',
    'pic': 'http://imge.kugou.com/soft/collection/240/20200324/20200324024507285054.jpg',
    'intro': '适合跑步时听的英文歌',
    'count': 23,
    'tags': '英语,兴奋,运动', // 实测为逗号分隔字符串
    'list_create_username': '薛予安',
    'list_create_userid': 486950678,
    'status': 1,
    'list_ver': 9,
    'publish_date': '2020-03-24',
    'collect_total': 0,
    'heat': 0,
    'musiclib_tags': [
      {'tag_id': 20, 'tag_name': '英语'},
    ],
  };
  eq('detail.name(实测 name)', detailItem['name'],
      '跑步必听｜超燃英文歌，助你轻松奔跑');
  eq('detail.cover(实测 pic)', detailItem['pic'],
      'http://imge.kugou.com/soft/collection/240/20200324/20200324024507285054.jpg');
  eq('detail.creator(实测 list_create_username)', detailItem['list_create_username'], '薛予安');
  eq('detail.trackCount(count)', detailItem['count'], 23);
  eq('detail.tags(逗号字符串拆分)', (detailItem['tags'] as String).split(',').length, 3);

  // ══ A2-3 · playlist tracks（data.songs[] + data.count）══
  group('A2-3 playlist tracks');
  const trackItem = <String, dynamic>{
    'hash': '48A4E22027AC783E4682B05543B75DDC',
    'name': 'Hawk Nelson、Jonathan Steingard - Sold Out',
    'singerinfo': [
      {'name': 'Hawk Nelson', 'id': 119093, 'type': 3},
      {'name': 'Jonathan Steingard', 'id': 93770, 'type': 1},
    ],
    'album_id': '981208',
    'albuminfo': {'name': 'Diamonds', 'id': 981208, 'publish': 1},
    'mixsongid': 32230859,
    'audio_id': 11672407,
    'timelen': 213133, // 毫秒
    'bitrate': 128,
    'size': 3410777,
    'extname': 'mp3',
    'fileid': 2,
    'cover': 'http://imge.kugou.com/stdmusic/{size}/20210606/x.jpg',
    'privilege': 10,
  };
  final t = SongBrief.fromTrackInfo(trackItem);
  eq('track.hash', t.hash, '48a4e22027ac783e4682b05543b75ddc');
  eq('track.name', t.name, 'Hawk Nelson、Jonathan Steingard - Sold Out');
  eq('track.singer(singerinfo[] 聚合「、」，N1-C 修复)', t.singer,
      'Hawk Nelson、Jonathan Steingard');
  eq('track.mixSongId', t.mixSongId, 32230859);
  eq('track.albumAudioId(audio_id 兜底)', t.albumAudioId, 11672407);
  eq('track.albumId(str)', t.albumId, '981208');
  eq('track.albumName(albuminfo.name，N1-C 修复)', t.albumName, 'Diamonds');
  eq('track.fileSize(size 键)', t.fileSize, 3410777);
  eq('track.bitrate', t.bitrate, 128);
  eq('track.durationSec(timelen ms→s)', t.durationSec, 213);

  final tp = TrackPage(total: 23, beginIdx: 0, pageSize: 30, items: [t]);
  eq('trackPage.total(data.count)', tp.total, 23);
  eq('trackPage.hasMore', tp.hasMore, true);

  // ══ A2-4 · rank list / rank info ══
  group('A2-4 rank');
  const rankItem = <String, dynamic>{
    'rankid': 8888,
    'rankname': 'TOP500',
    'imgurl': 'http://imge.kugou.com/rank/240/top500.jpg',
    'intro': '酷狗TOP500',
    'update_frequency': '每天更新',
    'rank_cid': 12345,
  };
  final rb = RankBrief.fromMap(rankItem);
  eq('rank.rankid', rb.rankId, 8888);
  eq('rank.name', rb.name, 'TOP500');
  eq('rank.cover', rb.cover, 'http://imge.kugou.com/rank/240/top500.jpg');
  eq('rank.intro', rb.intro, '酷狗TOP500');
  eq('rank.updateTime(update_frequency 兜底，无 updatetime)', rb.updateTime, '每天更新');
  // rank_info 实测：data.songinfo[] 仅 {album_audio_id, album_cover, songname} 三字段
  const rankSong = <String, dynamic>{
    'album_audio_id': 968734427,
    'album_cover': 'http://imge.kugou.com/stdmusic/{size}/20261111/x.jpg',
    'songname': '村口吴老二 - 慌啥子嘛',
  };
  final rs = SongBrief.fromTrackInfo(rankSong);
  eq('rankInfo song.name(songname 兜底，N1-C 修复)', rs.name, '村口吴老二 - 慌啥子嘛');
  eq('rankInfo song.albumAudioId(album_audio_id)', rs.albumAudioId, 968734427);

  // ══ A3 · 播放/歌词域（批N2-A 实测 2026-11-12）══

  // ── A3-3 · lyrics.kugou.com/v1/search candidates[0]（晴天，实测留样）──
  group('A3-3 lyric search');
  const lyricCand = <String, dynamic>{
    'id': '274944371', // 实测字符串
    'product_from': '官方推荐歌词',
    'accesskey': '2A7B35884B3C20E9D3281686BA59A3F8',
    'singer': '周杰伦',
    'song': '晴天',
    'duration': 269792, // 毫秒
    'language': '国语',
    'krctype': 1,
    'contenttype': 0, // 0=krc
    'content_format': 1,
    'download_id': '274944371',
    'score': 60,
    'adjust': 30,
  };
  eq('lyricCand.id(safeInt 容错字符串)', safeInt(lyricCand['id']), 274944371);
  eq('lyricCand.accesskey', safeStr(lyricCand['accesskey']),
      '2A7B35884B3C20E9D3281686BA59A3F8');
  eq('lyricCand.durationMs(毫秒)', safeInt(lyricCand['duration']), 269792);
  eq('lyricCand.contenttype(0=krc)', safeInt(lyricCand['contenttype']), 0);

  // ── A3-4/5 · /download 响应形态 + krc 本地解密（实测逐字节验证）──
  group('A3-5 krc decode');
  // 实测：晴天 krc 密文 b64 解码 4192B，魔数 "krc1"(6b726331)，异或+zlib → 8405 字符明文。
  // 用确定性样例复现算法链：构造 "krc1" 魔数 + 已知明文 zlib 压缩后异或。
  final plainSample = '[ti:晴天]\n[0,2250]<0,160,0>晴<160,160,0>天\n';
  final zlibBody = ZLibCodec().encode(utf8.encode(plainSample));
  final withMagic = <int>[0x6b, 0x72, 0x63, 0x31, ...zlibBody];
  final xored = List<int>.from(withMagic);
  for (var i = 4; i < xored.length; i++) {
    xored[i] ^= kKrcXorKey[(i - 4) % 16];
  }
  final decoded = krcDecode(base64.encode(xored));
  eq('krcDecode roundtrip(魔数+异或+inflate)', decoded, plainSample);
  eq('krcDecode invalid → 空串不抛', krcDecode('not_base64!!'), '');
  // contenttype==0 判定：krc；非 0 → lrc 仅 b64 解
  const dlResp = <String, dynamic>{
    'status': 200,
    'info': 'OK',
    'error_code': 0,
    'fmt': 'krc',
    'contenttype': 0,
    '_source': 'bss',
    'charset': '',
    'id': '274944371',
    'content': '',
  };
  eq('dlResp.status(成功语义 200)', safeInt(dlResp['status']), 200);
  eq('dlResp.contenttype(krc)', safeInt(dlResp['contenttype']), 0);

  // ══ A3 · 批N2-C 收口实测（2026-11-12，探针 n2c_probe.py / n2c_playurl_final.json）══

  // ── N2-C · play_url key 盐负对照锚点 ──
  // 实测：key 盐 = 57ae12eb6890223e355ccfcb74edf70d（signing.dart signKeySalt）；
  // 错盐 57ae12ebac930836ebac6f064f95b046 → status=0 error="illegal key"(31833)。
  // 公式：md5(hash + 盐 + '1005' + mid + userid||0)。
  group('N2-C play_url key salt');
  eq('signKeySalt 定稿', KugouSign.signKeySalt, '57ae12eb6890223e355ccfcb74edf70d');
  eq('playKey 拼接顺序(hash+盐+appid+mid+userid)',
      KugouSign.playKey('b3a52a7a958bf0aed0ebfba2e9a818b7', '281949768489412648962353822266799178366', ''),
      _md5('b3a52a7a958bf0aed0ebfba2e9a818b7'
          '57ae12eb6890223e355ccfcb74edf70d'
          '1005'
          '281949768489412648962353822266799178366'
          '0'));
  // 成功响应顶层 22 键形态（VIP 实测留样）：flac 档 bitRate 恒 0（不可用 bitrate 判档）。
  const playOk = <String, dynamic>{
    'status': 1, 'priv_status': 1, 'bitRate': 0, 'extName': 'flac',
    'timeLength': 269, 'q': 'flac',
  };
  eq('playOk flac bitRate=0(实测不判档)', safeInt(playOk['bitRate']), 0);
  eq('playOk priv_status=1 权限位', safeInt(playOk['priv_status']), 1);
  // 匿名 20028 形态：顶层仅 errcode/error/fail_process/status，无 priv_status。
  const playAnon = <String, dynamic>{
    'errcode': 20028, 'status': 2, 'error': '本次请求需要验证',
    'fail_process': ['pkg'],
  };
  eq('playAnon 匿名 20028', safeInt(playAnon['errcode']), 20028);
  eq('playAnon 无 priv_status 键', playAnon.containsKey('priv_status'), false);

  // ── N2-C · similar 双层解析锚点（data[].collection_list[]）──
  group('N2-C similar collection_list');
  const similarResp = <String, dynamic>{
    'status': 1,
    'error_code': 0,
    'data': [
      {
        'collection_list': [
          {
            'collection_id': '9443893',
            'cloudlist_id': '15',
            'global_collection_id': 'collection_3_1210326444_15_0',
            'collection_name': '给身体来点电——燥起来吧',
            'cover': 'http://c1.kgimg.com/custom/150/20260330/x.jpg',
            'flexible_cover': 'http://c1.kgimg.com/custom/{size}/20260330/x.jpg',
            'intro': '为运动和旅途准备的活力满满的歌单',
            'heat': '286', // 实测字符串
            'song_count': 52,
            'percount': '0',
            'publish_date': '2023-10-05',
            'type': '0',
            'is_publish': '1',
            'user_id': '1210326444',
            'user_name': '貔貅',
            'user_avatar': 'http://imge.kugou.com/kugouicon/165/x.jpg',
            'songs': [
              {
                'hash': 'D6C78FBD24B64FEE6CE6DA8A229BC8CF',
                'name': 'Imagine Dragons、JID - ENEMY (宿敌).mp3',
                'mixsongid': 345871732,
                'cover': 'http://imge.kugou.com/stdmusic/{size}/20211028/x.jpg',
                'privilege': 10,
                'level': 1,
                'sort': 0,
              },
            ],
          },
        ],
        'tag_info': [
          {'tag_id': '20', 'tag_name': '英语'},
          {'tag_id': '50', 'tag_name': '兴奋'},
        ],
      },
    ],
  };
  final simGroups = listOf((similarResp['data'] as List));
  // 双层平铺：data[] → item.collection_list[] → PlaylistBrief
  final simItems = <PlaylistBrief>[];
  for (final g in simGroups) {
    for (final m in listOf(g['collection_list'])) {
      final p = PlaylistBrief.fromMap(m);
      if (p.id.isNotEmpty) simItems.add(p);
    }
  }
  eq('similar.data 是数组', simGroups.length, 1);
  eq('similar 平铺 collection_list 双层', simItems.length, 1);
  eq('similar.id(global_collection_id)', simItems.first.id,
      'collection_3_1210326444_15_0');
  eq('similar.name(collection_name)', simItems.first.name, '给身体来点电——燥起来吧');
  eq('similar.cover(cover 完整URL)', simItems.first.cover,
      'http://c1.kgimg.com/custom/150/20260330/x.jpg');
  eq('similar.trackCount(song_count)', simItems.first.trackCount, 52);
  eq('similar.creator(user_name)', simItems.first.creator, '貔貅');
  // 内嵌 songs[] 无 duration/album_audio_id——fromTrackInfo 容错取 0，不猜。
  final simSong = SongBrief.fromTrackInfo(
      (similarResp['data'] as List)[0]['collection_list'][0]['songs'][0]
          as Map<String, dynamic>);
  eq('similar song.hash(小写化)', simSong.hash,
      'd6c78fbd24b64fee6ce6da8a229bc8cf');
  eq('similar song.mixSongId', simSong.mixSongId, 345871732);
  eq('similar song.durationSec(无键如实 0)', simSong.durationSec, 0);

  // ══ A4 · 歌手/专辑域（批N2-B 实测 2026-11-12，n2b_raw.json）══

  // ── A4-2 · /v1/album_audio/lite data.songs[]（夜曲实测留样）──
  group('A4-2 album lite');
  const liteItem = <String, dynamic>{
    'base': {
      'is_publish': 1,
      'album_id': 958909,
      'author_name': '周杰伦',
      'audio_name': '夜曲',
      'album_audio_id': 32029511,
    },
    'audio_info': {
      'hash': '16C8AB298231370293D16BCF9E5FF9B6',
      'hash_128': '16C8AB298231370293D16BCF9E5FF9B6',
      'bitrate': 128,
      'duration': 226873, // 实测毫秒
      'filesize': 3630591,
      'filesize_128': 3630591,
      'extname': 'mp3',
    },
    'album_info': {
      'album_name': '十一月的萧邦',
      'cover': 'http://imge.kugou.com/stdmusic/240/20250125/x.jpg',
    },
    'authors': [
      {'author_name': '周杰伦', 'author_id': 3520},
    ],
    'mvdata': [
      {'typ': 0, 'trk': '3', 'hash': '14F783AB3068B2CFB40B64F7A79763C8',
       'id': '596344'},
    ],
    'trans_param': {'musicpack_advance': 1},
  };
  final lite = SongBrief.fromAlbumLite(liteItem);
  eq('lite.hash(audio_info.hash 小写)', lite.hash,
      '16c8ab298231370293d16bcf9e5ff9b6');
  eq('lite.name(base.audio_name)', lite.name, '夜曲');
  eq('lite.singer(base.author_name)', lite.singer, '周杰伦');
  eq('lite.albumAudioId(base.album_audio_id)', lite.albumAudioId, 32029511);
  eq('lite.albumId(int→str)', lite.albumId, '958909');
  eq('lite.albumName(album_info.album_name)', lite.albumName, '十一月的萧邦');
  eq('lite.durationSec(ms→s)', lite.durationSec, 226);
  eq('lite.fileSize(audio_info.filesize)', lite.fileSize, 3630591);
  eq('lite.isVip(trans_param.musicpack_advance)', lite.isVip, true);
  // authors[] 聚合兜底（base.author_name 缺失时）
  final lite2 = SongBrief.fromAlbumLite(<String, dynamic>{
    'base': {'audio_name': '夜曲'},
    'audio_info': {'hash': '16C8AB298231370293D16BCF9E5FF9B6'},
    'authors': [
      {'author_name': '周杰伦', 'author_id': 3520},
      {'author_name': '费玉清', 'author_id': 6638},
    ],
  });
  eq('lite2.singer(authors[] 聚合「、」)', lite2.singer, '周杰伦、费玉清');

  // ── A4-3 · /kmr/v2/albums data[0]（十一月的萧邦实测留样）──
  group('A4-3 album detail');
  const albumItem = <String, dynamic>{
    'album_id': '958909',
    'album_name': '十一月的萧邦',
    'author_name': '周杰伦',
    'sizable_cover': 'http://imge.kugou.com/stdmusic/240/20250125/x.jpg',
    'cover': '20250125121901851911.jpg', // 实测裸文件名，非 URL
    'intro': '周杰伦2005最新国语专辑',
    'publish_date': '2005-11-01',
    'publish_company': '杰威尔音乐有限公司',
    'grade': '8.7',
    'heat': '2329975',
    'language': '国语',
    'type': '录音室专辑',
    // 实测无 count/song_count/songnum —— songCount 如实 0
  };
  final ab = AlbumBrief.fromMap(albumItem);
  eq('album.id(str)', ab.id, '958909');
  eq('album.name', ab.name, '十一月的萧邦');
  eq('album.cover(sizable_cover 优先)', ab.cover,
      'http://imge.kugou.com/stdmusic/240/20250125/x.jpg');
  eq('album.publishDate', ab.publishDate, '2005-11-01');
  eq('album.songCount(实测无键如实 0)', ab.songCount, 0);

  // ── A4-1 · /kmr/v3/author data 平铺（周杰伦实测 14 键）──
  group('A4-1 artist detail');
  const authorItem = <String, dynamic>{
    'author_id': 3520,
    'author_name': '周杰伦',
    'sizable_avatar': 'http://singerimg.kugou.com/uploadpic/softhead/{size}/x.jpg',
    'intro': '',
    'long_intro': '周杰伦（Jay Chou），1979年1月18日出生于台湾省新北市…',
    'album_count': 40,
    'song_count': 515,
    'mv_count': 78,
    'fansnums': 5810243, // 实测键 fansnums
    'area_id': 15,
    'is_publish': 1,
    'pinyin_initial': 'zjl',
    'user_status': 0,
  };
  final ad = ArtistDetail.fromMap(authorItem);
  eq('artist.id', ad.id, '3520');
  eq('artist.name', ad.name, '周杰伦');
  eq('artist.avatar', ad.avatar,
      'http://singerimg.kugou.com/uploadpic/softhead/{size}/x.jpg');
  eq('artist.intro(空→long_intro 兜底)', ad.intro,
      '周杰伦（Jay Chou），1979年1月18日出生于台湾省新北市…');
  eq('artist.albumCount', ad.albumCount, 40);
  eq('artist.songCount', ad.songCount, 515);
  eq('artist.mvCount', ad.mvCount, 78);
  eq('artist.fans(fansnums)', ad.fans, 5810243);
  // 搜索域驼峰键兜底（A1-4 /v1/search/author）
  final abr = ArtistBrief.fromMap(<String, dynamic>{
    'AuthorId': 3520, 'AuthorName': '周杰伦', 'FansNum': 5810243,
    'Avatar': 'http://singerimg.kugou.com/x.jpg',
  });
  eq('artistSearch.id(AuthorId)', abr.id, '3520');
  eq('artistSearch.name(AuthorName)', abr.name, '周杰伦');
  eq('artistSearch.fans(FansNum)', abr.fans, 5810243);

  // ── A5-1 · /kmr/v1/audio/mv data[0][0]（夜曲 MV 实测留样）──
  group('A5-1 mv brief');
  const mvItem = <String, dynamic>{
    'video_id': 596344,
    'mv_name': '夜曲',
    'singer': '周杰伦',
    'duration': 231732, // 实测毫秒 3:51
    'hdpic': 'http://imge.kugou.com/mvhdpic/240/20201126/x.jpg',
    'thumb': 'http://imge.kugou.com/mvthumb/{size}/3e/d4/x.jpg',
    'hit': 33229711,
    'have_mp4': 1,
    'audio_id': 338638,
    'album_audio_id': 32029511,
  };
  final mv = MvBrief.fromMap(mvItem);
  eq('mv.name(mv_name 实测键)', mv.name, '夜曲');
  eq('mv.singer', mv.singer, '周杰伦');
  eq('mv.durationMs', mv.durationMs, 231732);
  eq('mv.coverUrl(hdpic 优先)', mv.coverUrl,
      'http://imge.kugou.com/mvhdpic/240/20201126/x.jpg');

  // ── A5-2 · /v1/video data[0] 平铺档位（夜曲 MV 实测留样）──
  group('A5-2 mv qualities flat');
  const videoDetail = <String, dynamic>{
    'video_id': '596344',
    'video_name': '夜曲',
    'ld_hash': '8AA3FFCD89B2D644CD3499F920632D5C', 'ld_filesize': '15747489',
    'ld_width': '480', 'ld_height': '270',
    'sd_hash': 'E219A9287D08F632BCF96CE5DA74D7A0', 'sd_filesize': '18451967',
    'hd_hash': '6F3AB816859A9F2F4ADEC162A74C5FC4', 'hd_filesize': '61979881',
    'hd_height': '720',
    'fhd_hash': 'EA6A48A677EFB989655F258D061BB5FD',
    'fhd_filesize': '120093770', 'fhd_height': '1080',
    'qhd_hash': '14F783AB3068B2CFB40B64F7A79763C8', // 实测留样（videourl_qhd）
    'qhd_filesize': '32952294',
    'qhd_hash_265': '2659D5F2E8017E537B56F2E08CDA420C',
    'qhd_filesize_265': 15567229,
    'mkv_qhd_hash': '5FA9DA04AFD3317DCAE55A5D73664596',
    'mkv_qhd_filesize': '32684171',
  };
  final qs = MvQuality.fromFlat(videoDetail);
  eq('mvQ.fromFlat 档位数(ld/sd/hd/fhd/qhd 主+qhd265+mkv)', qs.length, 7);
  eq('mvQ ld.hash', qs[0].hash, '8aa3ffcd89b2d644cd3499f920632d5c');
  eq('mvQ ld.size', qs[0].size, 15747489);
  eq('mvQ fhd.hash', qs[3].hash, 'ea6a48a677efb989655f258d061bb5fd');
  eq('mvQ qhd.hash(实测留样)', qs[4].hash, '14f783ab3068b2cfb40b64f7a79763c8');
  eq('mvQ qhd_265.hash', qs[5].hash, '2659d5f2e8017e537b56f2e08cda420c');
  eq('mvQ qhd_265.size', qs[5].size, 15567229);
  eq('mvQ mkv.hash', qs[6].hash, '5fa9da04afd3317dcae55a5d73664596');

  // ── A5-3 · /v2/interface/index data[hash].downurl（实测留样）──
  group('A5-3 mv play url');
  const urlResp = <String, dynamic>{
    'status': 1,
    'privileges': {'14f783ab3068b2cfb40b64f7a79763c8': 0},
    'data': {
      '14f783ab3068b2cfb40b64f7a79763c8': {
        'backupdownurl': [
          'http://fsmvpc.kugou.com/202611120720/b/KGTX/CLTX002/x.mp4',
        ],
        'filesize': '32952294',
        'downurl':
            'http://fsmvpc.tx.kugou.com/202611120720/a/v2/x/KGTX/CLTX002/x.mp4',
      },
    },
  };
  final d0 = dataOf(urlResp);
  final bucket0 = d0['14f783ab3068b2cfb40b64f7a79763c8'] as Map;
  final urls0 = <String>[
    ...(bucket0['downurl'] is List
        ? (bucket0['downurl'] as List).map((u) => '$u')
        : ['${bucket0['downurl']}']),
    ...(bucket0['backupdownurl'] as List).map((u) => '$u'),
  ];
  eq('mvUrl.downurl 单串主链', urls0[0],
      'http://fsmvpc.tx.kugou.com/202611120720/a/v2/x/KGTX/CLTX002/x.mp4');
  eq('mvUrl.backupdownurl 备链数组', urls0.length, 2);
  eq('mvUrl.filesize(str)', safeInt(
      (bucket0 as Map)['filesize']), 32952294);
  // key 盐负对照锚点（批N2-B 实测）：缺 key/错 cmd → 40003 Empty key/Bad cmd；
  // key 公式 = md5(hash + signKeySalt + appid + mid + userid||0)（同 play_url 盐）。
  eq('mvKey.signKeySalt 与 play_url 同盐',
      KugouSign.signKeySalt, '57ae12eb6890223e355ccfcb74edf70d');
  eq('mvKey.playKey 拼接顺序', KugouSign.playKey(
      '14f783ab3068b2cfb40b64f7a79763c8',
      '281949768489412648962353822266799178366', ''),
      _md5('14f783ab3068b2cfb40b64f7a79763c8'
          '57ae12eb6890223e355ccfcb74edf70d'
          '1005'
          '281949768489412648962353822266799178366'
          '0'));

  // ── A4-5 · /kmr/v1/audio_group/author data[] 平铺（批N3-C 实测留样）──
  group('N3-C artist audios field truth');
  const audiosItem = <String, dynamic>{
    'audio_name': '发如雪',
    'author_name': '周杰伦',
    'album_name': '十一月的萧邦',
    'album_id': 958909,
    'album_audio_id': 32029513,
    'audio_id': 339589,
    'hash': '1F7E7659B9FFF4FB6F71562A61BBC25F',
    'hash_320': 'CE2F056CA8CDC1027942C6067C532D87',
    'filesize': 4789176,
    'timelength': 299284, // 实测毫秒（299s）
    'bitrate': 128,
    'playcount': 0,
    'publish_date': '2005-11-01',
    'privilege': 10,
    'video_hash': '7AE3E2309AE6DE1871FC04261EBAC0A6',
    'video_id': 2761,
    'trans_param': {'musicpack_advance': 1},
  };
  final au = SongBrief.fromTrackInfo(audiosItem);
  eq('artistAudios.hash(小写化)', au.hash,
      '1f7e7659b9fff4fb6f71562a61bbc25f');
  eq('artistAudios.name(audio_name)', au.name, '发如雪');
  eq('artistAudios.singer(author_name 兜底)', au.singer, '周杰伦');
  eq('artistAudios.mixSongId(实测无 mixsongid，songid 不映射如实 0)',
      au.mixSongId, 0);
  eq('artistAudios.albumAudioId(album_audio_id)', au.albumAudioId, 32029513);
  eq('artistAudios.durationSec(timelength ms→s)', au.durationSec, 299);
  eq('artistAudios.albumId(int→str)', au.albumId, '958909');
  eq('artistAudios.albumName(album_name)', au.albumName, '十一月的萧邦');
  eq('artistAudios.fileSize', au.fileSize, 4789176);
  eq('artistAudios.isVip(trans_param.musicpack_advance)', au.isVip, true);
  // 平铺数组取数锚点：data 即列表（非 songs[] 包裹），dataOf 返回空 Map、
  // listOf(res['data']) 命中（_pickList 平铺分支语义）。
  final flatData = {'status': 1, 'data': [audiosItem]};
  eq('artistAudios data 平铺取数', listOf(flatData['data']).length, 1);
  eq('artistAudios dataOf 平铺回空 Map(设计语义)',
      dataOf(flatData).isEmpty, true);

  // ══ 批2-C · 端点声明/取数路径窄复核锚点（2026-11-13）══
  group('batch2-C endpoint narrow recheck');
  // §A2-2：/v3/get_list_info 的 data 是数组；dataOf() 只收 Map（旧详情恒空根因）。
  final detailArr = <String, dynamic>{
    'status': 1,
    'data': [
      <String, dynamic>{
        'global_collection_id': 'collection_1_486950678_2255477_0',
        'name': '跑步必听｜超燃英文歌',
        'pic': 'http://imge.kugou.com/x.jpg',
        'count': 23,
        'tags': '英语,兴奋,运动',
        'list_create_username': '薛予安',
        'list_ver': 9,
      },
    ],
  };
  eq('A2-2 data[] 数组取首项', listOf(detailArr['data']).length, 1);
  eq('A2-2 dataOf 对数组 data 回空 Map(旧 bug 根因)',
      dataOf(detailArr).isEmpty, true);
  eq('A2-2 name(实测键 name)',
      safeStr(listOf(detailArr['data']).first['name']), '跑步必听｜超燃英文歌');
  eq('A2-2 无 playcount 键(playCount 如实 0)',
      listOf(detailArr['data']).first.containsKey('playcount'), false);
  // §R1-A-8：searchSuggest 的 data 是数组分组，data['records'] 恒 null。
  final suggestArr = <String, dynamic>{
    'status': 1,
    'data': [
      <String, dynamic>{
        'LableName': '',
        'RecordCount': 1,
        'RecordDatas': [
          <String, dynamic>{'HintInfo': '晴天', 'MatchCount': 10},
        ],
      },
    ],
  };
  final sugGroups = listOf(suggestArr['data']);
  eq('R1-A-8 data[] 数组分组', sugGroups.length, 1);
  eq('R1-A-8 词条在 RecordDatas[].HintInfo',
      safeStr(listOf(sugGroups.first['RecordDatas']).first['HintInfo']), '晴天');
  eq('R1-A-8 dataOf 对数组 data 回空 Map',
      dataOf(suggestArr).isEmpty, true);
  // §A3-1（批N2-A）：非 VIP 带 key 的失败形态顶层 error_code=35104。
  final play35104 = <String, dynamic>{
    'status': 0, 'error_code': 35104, 'error': 'Hash not found',
  };
  eq('A3-1 35104 失败形态取 error_code',
      safeInt(play35104['errcode'] ?? play35104['error_code']), 35104);

  // ══ 批3-F2 · 网络层诚实化新契约（旧锚点全部保留，仅追加）══
  group('F2 network honesty contract');
  const plainPage = CommentPage();
  eq('F2 CommentPage 旧构造 blockedReason 默认 null',
      plainPage.blockedReason, null);
  eq('F2 CommentPage toMap 含 blockedReason 键',
      plainPage.toMap().containsKey('blockedReason'), true);
  final blocked = CommentPage(blockedReason: '接口返回非 JSON');
  eq('F2 受限页 blockedReason 透传', blocked.blockedReason,
      '接口返回非 JSON');
  eq('F2 受限页 toMap 保留原因',
      blocked.toMap()['blockedReason'], '接口返回非 JSON');
  final waf = commentBlockedReason(
      KugouApiException(-3, 'invalid json from commentMusic: Access Deny !!!'));
  eq('F2 WAF 非 JSON(-3) 原因含「非 JSON」',
      waf.contains('非 JSON'), true);
  eq('F2 WAF 原因含「安全策略拦截」',
      waf.contains('安全策略拦截'), true);
  eq('F2 WAF 原因含原始 WAF 文案',
      waf.contains('Access Deny !!!'), true);
  eq('F2 其他异常原因不冒充 WAF',
      commentBlockedReason(KugouApiException(403, 'http 403: blocked'))
          .contains('接口响应异常'),
      true);
  final okState = DailyRecommendResult.ok(const <SongBrief>[]);
  eq('F2 每日推荐空列表 → empty 态', okState.state,
      DailyRecommendState.empty);
  eq('F2 每日推荐 200103 → loginRequired 态',
      DailyRecommendResult.loginRequired().state,
      DailyRecommendState.loginRequired);
  eq('F2 loginRequired 不可写缓存',
      DailyRecommendResult.loginRequired().cacheable, false);
  eq('F2 error 不可写缓存',
      DailyRecommendResult.error().cacheable, false);
  eq('F2 empty 可写缓存',
      DailyRecommendResult.ok(const <SongBrief>[]).cacheable, true);
  eq('F2 结果仍是 List<SongBrief>（home_page 零改动）',
      okState is List<Object>, true);

  // ══ 批N3-B · A6 用户域歌单写锚点（原 main 收尾后独立函数）══
  n3b_playlist_write_truth();

  print('');
  print('pass=$_pass fail=$_fail');
  if (_fail > 0) {
    print('FIELD-TRUTH-FAIL');
    exitCode = 1;
  } else {
    print('FIELD-TRUTH-OK');
  }
}

// ── 批N3-B · A6 用户域歌单写锚点（docs/API_FIELDS_TRUTH.md A6 节）──
Map<String, dynamic> _cm(Object? v) =>
    v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};

void n3b_playlist_write_truth() {
  // A6-2 建歌单：listid 路径 = data.info.listid（data.listid 不存在，旧假设证伪）。
  final addList = {
    'status': 1, 'error_code': 0,
    'data': {'info': {'listid': 41, 'list_create_listid': 41,
      'global_collection_id': 'collection_3_1666835066_41_0',
      'name': 'N3B实测vip40241', 'status': 1, 'code': 1, 'count': 0,
      'list_ver': 0, 'type': 0, 'source': 1},
      'list_count': 1, 'total_ver': 1, 'userid': 1666835066},
  };
  final al = dataOf(_cm(addList));
  final info = _cm(al['info']);
  eq('A6-2 info.listid==41', safeInt(info['listid']), 41);
  eq('A6-2 info.list_create_listid==41', safeInt(info['list_create_listid']), 41);
  eq('A6-2 data.listid 不存在', al['listid'], null);

  // A6-3 加歌回执 data.info[] 逐曲（fileid/audio_id/hash 大写回显）。
  final addSong = {
    'status': 1, 'error_code': 0,
    'data': {'listid': 41, 'cursor': '202611|131071', 'status': 1,
      'pre_list_ver': 0, 'list_ver': 1, 'del_fileids': null,
      'info': [{'fileid': 1, 'number': 1,
        'hash': 'FAB30A43449D8C12528DD9D83A7693E7',
        'name': '贝瓦儿歌 - 一只哈巴狗.mp3', 'audio_id': 1049676742,
        'language': '国语', 'csong': 0}]},
  };
  final asd = dataOf(_cm(addSong));
  final items = listOf(asd['info']);
  eq('A6-3 回执1条', items.length, 1);
  eq('A6-3 audio_id', safeInt(_cm(items[0])['audio_id']), 1049676742);
  eq('A6-3 fileid', safeInt(_cm(items[0])['fileid']), 1);

  // A6-4 删歌 data.list_ver 递增 + count。
  final delSongs = {'status': 1, 'error_code': 0,
    'data': {'listid': 41, 'pre_list_ver': 1, 'list_ver': 1, 'count': 1,
      'status': 1, 'cursor': '202611|131071'}};
  final ds = dataOf(_cm(delSongs));
  eq('A6-4 count==1', safeInt(ds['count']), 1);
  eq('A6-4 list_ver==1', safeInt(ds['list_ver']), 1);

  // A6-6 删歌单明文兜底失败形态：error_code 20010（诚实失败锚点，不猜加密）。
  final delList = {'status': 0, 'error_code': 20010, 'data': ''};
  eq('A6-6 明文兜底 20010', safeInt(delList['error_code']), 20010);

  // A6-1 user_playlist item 41 键锚点子集（无 specialname/imgurl 旧口径）。
  final upItem = <String, dynamic>{
    'listid': 1, 'global_collection_id': 'collection_3_1666835066_1_0',
    'name': '我喜欢', 'pic': 'http://imge.kugou.com/x.jpg', 'count': 25,
    'type': 0, 'status': 1, 'is_def': 1, 'is_mine': 1, 'is_pri': 0,
    'is_publish': 1, 'incr_sync': 1, 'list_ver': 7,
    'list_create_userid': 1666835066, 'list_create_listid': 1,
    'list_create_username': '云淡风清', 'create_time': 1700000000,
    'update_time': 1794440000, 'tags': '', 'musiclib_tags': <dynamic>[],
    'trans_param': <String, dynamic>{}, 'per_num': 0, 'pub_new': 0,
    'pub_type': 0, 'source': 0, 'sort': 0, 'sound_quality': 0,
    'radio_id': 0, 'kq_talent': 0, 'm_count': 0, 'per_count': 0,
    'pub_time': 0, 'is_del': 0, 'is_drop': 0, 'is_edit': 1,
    'is_per': 0, 'is_featured': 0, 'is_custom_pic': 1, 'intro': '',
    'create_user_pic': 'http://imge.kugou.com/y.jpg', 'list_create_gid': 0,
  };
  eq('A6-1 listid', safeInt(upItem['listid']), 1);
  eq('A6-1 无 specialname 旧口径', upItem.containsKey('specialname'), false);
  eq('A6-1 无 imgurl 旧口径（是 pic）', upItem.containsKey('imgurl'), false);
  eq('A6-1 41键全（实测键数）', upItem.length, 41);
  eq('A6-1 global_collection_id 前缀',
      (upItem['global_collection_id'] as String).startsWith('collection_'), true);
}
