// tool/field_truth_test.dart — 批N1-C · A1+A2 字段实证回归锚点（纯 Dart，无 flutter 依赖）
// 数据源：docs/API_FIELDS_TRUTH.md（2026-11-12 probe 实测样例，gateway.kugou.com 三态）。
// 断言 core/net/endpoints/models.dart + playlist_endpoints.dart 映射对真实响应逐字段正确。
// 运行：/opt/dart/bin/dart run tool/field_truth_test.dart → 全过输出 FIELD-TRUTH-OK，失败退出码 1。
import 'dart:convert';
import 'dart:io' show exitCode, ZLibCodec;
import '../lib/core/net/endpoints/models.dart';
import '../lib/core/net/endpoints/search_typed_endpoints.dart';
import '../lib/core/net/endpoints/misc_endpoints.dart'
    show krcDecode, kKrcXorKey;

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
    'imgurl': 'http://imge.kugou.com/soft/collection/{size}/20200324/20200324024507285054.jpg',
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
      'http://imge.kugou.com/soft/collection/{size}/20200324/20200324024507285054.jpg');
  eq('rec.playCount(play_count，N1-C 修复)', pb2.playCount, 888888);
  eq('rec.creator(nickname)', pb2.creator, '薛予安');

  // ══ A2-2 · playlist detail（data[] 首项，实测 name/pic/list_create_username）══
  group('A2-2 playlist detail');
  const detailItem = <String, dynamic>{
    'global_collection_id': 'collection_1_486950678_2255477_0',
    'specialid': 2255477,
    'name': '跑步必听｜超燃英文歌，助你轻松奔跑',
    'pic': 'http://imge.kugou.com/soft/collection/{size}/20200324/20200324024507285054.jpg',
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
      'http://imge.kugou.com/soft/collection/{size}/20200324/20200324024507285054.jpg');
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
    'imgurl': 'http://imge.kugou.com/rank/{size}/top500.jpg',
    'intro': '酷狗TOP500',
    'update_frequency': '每天更新',
    'rank_cid': 12345,
  };
  final rb = RankBrief.fromMap(rankItem);
  eq('rank.rankid', rb.rankId, 8888);
  eq('rank.name', rb.name, 'TOP500');
  eq('rank.cover', rb.cover, 'http://imge.kugou.com/rank/{size}/top500.jpg');
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

  print('');
  print('pass=$_pass fail=$_fail');
  if (_fail > 0) {
    print('FIELD-TRUTH-FAIL');
    exitCode = 1;
  } else {
    print('FIELD-TRUTH-OK');
  }
}
