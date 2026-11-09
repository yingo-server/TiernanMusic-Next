// L4 core/net/endpoints · 其他端点封装（rank / lyric / krc 解码）
// krc 解密（docs/KUGOU_API.md §2.3）：base64 → 跳过 4 字节魔数 →
// 异或 16 字节密钥表 [64,71,97,119,94,50,116,71,81,54,49,45,206,210,110,105] →
// zlib inflate（dart:convert 自带 zlib）→ utf8 文本。
import 'dart:convert';
import 'dart:io';

import '../../../kernel/kernel.dart' show Log;
import '../kugou_client.dart';
import '../signing.dart' show KugouSign;
import 'models.dart';

const String _tag = 'ep.misc';

const List<int> kKrcXorKey = <int>[
  64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105,
];

/// krc 解码：输入 base64 内容；contenttype!=0（lrc）时仅 base64 解码。
/// 失败返回 ''，不抛出。
String krcDecode(String base64Content, {bool isKrc = true}) {
  try {
    final raw = base64.decode(base64Content.trim());
    if (!isKrc) {
      return utf8.decode(raw, allowMalformed: true);
    }
    if (raw.length <= 4) {
      Log.w(_tag, 'krcDecode too short len=${raw.length}');
      return '';
    }
    final body = raw.sublist(4); // 跳过前 4 字节魔数
    for (var i = 0; i < body.length; i++) {
      body[i] ^= kKrcXorKey[i % 16];
    }
    // dart:convert 自带 zlib inflate（含 zlib 头）。
    final plain = ZLibCodec().decoder.convert(body);
    return utf8.decode(plain, allowMalformed: true);
  } catch (e, st) {
    Log.e(_tag, 'krcDecode failed len=${base64Content.length}', e, st);
    return '';
  }
}

/// 排行榜列表（/ocean/v6/rank/list）：data.info[]。
Future<List<RankBrief>> rankList(KugouClient client) async {
  try {
    final res = await client.request(EndpointRegistry.rankList,
        <String, Object?>{'plat': 2, 'withsong': 1, 'parentid': 0});
    final data = dataOf(res);
    final items = listOf(data['info'] ?? data['list'])
        .map(RankBrief.fromMap)
        .toList(growable: false);
    Log.d(_tag, 'rankList got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'rankList failed', e, st);
    return const <RankBrief>[];
  }
}

/// 排行榜详情（/ocean/v6/rank/info）：data.songs[]/data.list[]。
Future<List<SongBrief>> rankInfo(KugouClient client, int rankId) async {
  try {
    final res = await client.request(EndpointRegistry.rankInfo,
        <String, Object?>{
      'rankid': rankId,
      'rank_cid': 0,
      'with_album_img': 1,
      'zone': '',
    });
    final data = dataOf(res);
    final items = listOf(data['songs'] ?? data['list'] ?? data['info'])
        .map(SongBrief.fromTrackInfo)
        .toList(growable: false);
    Log.d(_tag, 'rankInfo rankId=$rankId got=${items.length}');
    return items;
  } catch (e, st) {
    Log.e(_tag, 'rankInfo failed rankId=$rankId', e, st);
    return const <SongBrief>[];
  }
}

/// 歌词搜索（lyrics.kugou.com/v1/search，不签名）：candidates[]。
/// duration 为毫秒；返回候选项（id+accesskey 供 /download 使用）。
Future<List<LyricResult>> lyricSearch(
  KugouClient client, {
  required String hash,
  String keyword = '',
  int durationMs = 0,
  int albumAudioId = 0,
}) async {
  try {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      Log.w(_tag, 'lyricSearch empty hash');
      return const <LyricResult>[];
    }
    final res = await client.request(EndpointRegistry.lyricSearch,
        <String, Object?>{
      'hash': h,
      'keyword': keyword,
      'duration': durationMs,
      'album_audio_id': albumAudioId,
      'lrctxt': 1,
      'man': 'no',
      'appid': KugouSign.appid,
      'clientver': KugouSign.clientver,
    });
    final out = <LyricResult>[];
    for (final c in listOf(res['candidates'] ?? dataOf(res)['candidates'])) {
      out.add(LyricResult(
        id: safeInt(c['id']),
        accessKey: safeStr(c['accesskey']),
        fmt: safeStr(c['fmt'], 'krc'),
        durationMs: safeInt(c['duration']),
      ));
    }
    Log.d(_tag, 'lyricSearch hash=$h got=${out.length}');
    return out;
  } catch (e, st) {
    Log.e(_tag, 'lyricSearch failed hash=$hash', e, st);
    return const <LyricResult>[];
  }
}

/// 歌词下载（lyrics.kugou.com/download）：content(base64) + contenttype。
/// contenttype==0 → krc 加密内容，自动走 krcDecode；非 0 → 直接 base64 解码。
/// 返回的 LyricResult.content 为解密后的纯文本。
Future<LyricResult> lyricDownload(
  KugouClient client,
  int id,
  String accessKey, {
  String fmt = 'krc',
}) async {
  try {
    if (id == 0 || accessKey.trim().isEmpty) {
      Log.w(_tag, 'lyricDownload missing id/accesskey');
      return const LyricResult();
    }
    final res = await client.request(EndpointRegistry.lyricDownload,
        <String, Object?>{
      'id': id,
      'accesskey': accessKey.trim(),
      'fmt': fmt,
      'client': 'android',
      'ver': 1,
      'charset': 'utf8',
    });
    final ct = safeInt(res['contenttype']);
    final isKrc = ct == 0;
    final content = krcDecode(safeStr(res['content']), isKrc: isKrc);
    final r = LyricResult(
      id: id,
      accessKey: accessKey.trim(),
      fmt: safeStr(res['fmt'], fmt),
      content: content,
      durationMs: safeInt(res['duration']),
      isKrc: isKrc,
    );
    Log.d(_tag, 'lyricDownload id=$id fmt=$fmt len=${content.length}');
    return r;
  } catch (e, st) {
    Log.e(_tag, 'lyricDownload failed id=$id', e, st);
    return const LyricResult();
  }
}
