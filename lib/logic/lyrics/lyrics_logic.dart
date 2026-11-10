// L5 logic/lyrics · 歌词域门面
// lyricSearch(hash,keyword,durationMs) → candidates[0] → lyricDownload →
// LruCache(ns:'lyrics', key=hash) + 文件缓存 <root>/lyrics/<hash>.lrc。
// 三级加载：内存 → 文件 → 网络。铁律：禁 surface/flutter；每方法 try/catch + Log('logic.lyrics')。
import 'dart:convert';
import 'dart:io' show File;

import '../../bridges/bridge_kernel.dart' show Log;
import 'lyrics_parser.dart';
import '../../bridges/bridge_core.dart' as misc show lyricDownload, lyricSearch;
import '../../bridges/bridge_core.dart' show KugouClient, LruCache, LyricResult, SongBrief, StoragePaths;

const String _tag = 'logic.lyrics';
const String _ns = 'lyrics';

/// 歌词域逻辑：注入 KugouClient + StoragePaths + LruCache<String,LyricResult>。
class LyricsLogic {
  LyricsLogic({
    required KugouClient client,
    required StoragePaths paths,
    required LruCache<String, LyricResult> cache,
  })  : _client = client,
        _paths = paths,
        _cache = cache {
    Log.d(_tag, 'init capacity=${cache.capacity}');
  }

  final KugouClient _client;
  final StoragePaths _paths;
  final LruCache<String, LyricResult> _cache;

  File _lyricFile(String hash) => _paths.fileIn('lyrics', '$hash.lrc');

  /// 文件缓存写入（纯文本覆盖写）。
  bool _writeFile(String hash, String text) {
    try {
      final f = _lyricFile(hash);
      if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
      f.writeAsStringSync(text, flush: true);
      Log.d(_tag, 'file cached hash=$hash len=${text.length}');
      return true;
    } catch (e, st) {
      Log.e(_tag, '_writeFile failed hash=$hash', e, st);
      return false;
    }
  }

  /// 文件缓存读取；无/损坏返回 null。
  LyricResult? _readFile(String hash) {
    try {
      final f = _lyricFile(hash);
      if (!f.existsSync()) return null;
      final text = f.readAsStringSync();
      if (text.trim().isEmpty) return null;
      final parsed = parseLyrics(text);
      Log.d(_tag, 'file hit hash=$hash lines=${parsed.lines.length}');
      return LyricResult(
        fmt: parsed.isKrc ? 'krc' : 'lrc',
        content: text,
        isKrc: parsed.isKrc,
      );
    } catch (e, st) {
      Log.e(_tag, '_readFile failed hash=$hash', e, st);
      return null;
    }
  }

  /// 网络拉取：search → candidates[0] → download（krc 优先，失败退 lrc）。
  Future<LyricResult> _fetch(String hash, String keyword, int durationMs) async {
    final candidates = await misc.lyricSearch(_client,
        hash: hash, keyword: keyword, durationMs: durationMs);
    if (candidates.isEmpty) {
      Log.w(_tag, 'no candidates hash=$hash');
      return const LyricResult();
    }
    final c = candidates.first;
    final dl = await misc.lyricDownload(_client, c.id, c.accessKey, fmt: c.fmt);
    if (dl.content.isEmpty) {
      // krc 失败退回 lrc。
      final dl2 =
          await misc.lyricDownload(_client, c.id, c.accessKey, fmt: 'lrc');
      if (dl2.content.isNotEmpty) return dl2;
    }
    return dl;
  }

  /// 歌词主入口：内存 → 文件 → 网络三级。解析成功后写文件缓存。
  Future<LyricResult> lyricsFor(SongBrief song) async {
    try {
      final hash = song.hash.trim().toLowerCase();
      if (hash.isEmpty) {
        Log.w(_tag, 'lyricsFor empty hash');
        return const LyricResult();
      }
      // 1. 内存。
      final mem = _cache.get(hash);
      if (mem != null && mem.content.isNotEmpty) {
        Log.d(_tag, 'mem hit hash=$hash');
        return mem;
      }
      // 2. 文件。
      final file = _readFile(hash);
      if (file != null) {
        _cache.put(hash, file);
        return file;
      }
      // 3. 网络。
      final dl = await _fetch(hash, '${song.name} ${song.singer}'.trim(),
          song.durationSec * 1000);
      if (dl.content.isNotEmpty) {
        _cache.put(hash, dl);
        final parsed = parseLyrics(dl.content);
        if (parsed.lines.isNotEmpty) {
          _writeFile(hash, dl.content);
        }
        Log.d(_tag,
            'lyricsFor net hash=$hash lines=${parsed.lines.length} krc=${dl.isKrc}');
        return dl;
      }
      return const LyricResult();
    } catch (e, st) {
      Log.e(_tag, 'lyricsFor failed', e, st);
      return const LyricResult();
    }
  }

  /// 解析并应用 offset 后的行级结果（UI 直接消费）。
  LyricParseResult parsedFor(LyricResult r) {
    try {
      return applyOffset(parseLyrics(r.content));
    } catch (e, st) {
      Log.e(_tag, 'parsedFor failed', e, st);
      return const LyricParseResult();
    }
  }

  /// 清除指定歌曲的内存 + 文件缓存。
  void clearFileCache(String hash) {
    try {
      final h = hash.trim().toLowerCase();
      _cache.remove(h);
      final f = _lyricFile(h);
      if (f.existsSync()) {
        f.deleteSync();
      }
      Log.d(_tag, 'clearFileCache hash=$h');
    } catch (e, st) {
      Log.e(_tag, 'clearFileCache failed hash=$hash', e, st);
    }
  }

  /// 缓存统计摘要（诊断用）。
  Map<String, Object?> stats() {
    try {
      return <String, Object?>{'ns': _ns, 'cache': _cache.stats.toMap()};
    } catch (e, st) {
      Log.e(_tag, 'stats failed', e, st);
      return const <String, Object?>{};
    }
  }
}
