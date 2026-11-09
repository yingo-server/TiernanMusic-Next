// L6 surface · 全局装配总入口（批5-B）
// 把批4 散装模块（批4-A logic 单例 / 批4-B PlayerController / 批4-C 三页面模块）
// 接成完整 App。app_root.installServices 内部改调本文件 assembleAll，
// 自装配兜底路径已删除（强制走本装配）。
//
// 层纪律：只 import flutter_riverpod / ../bridges/* / 本层文件。
// 铁律：每个装配步骤 try/catch + Log('surface.assembly')。
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;

import 'deps.dart' show SurfaceDeps;
import '../bridges/bridge_core.dart'
    show
        KugouClient,
        SongDao,
        PlaylistDao,
        HistoryDao,
        DownloadStore,
        KeyValueSettings,
        LruCache,
        SearchResult,
        LyricResult;
import '../bridges/bridge_logic.dart'
    show
        Log,
        SearchLogic,
        PlaylistLogic,
        RankLogic,
        AuthLogic,
        LyricsLogic,
        PlaybackService,
        HistoryRecorder,
        DownloadManager;
import 'modules.dart' as mod;
import 'pages/library_page.dart' show LibraryPageModule, LibraryDeps;
import 'pages/lyrics_page.dart' show LyricsPageModule, LyricsDeps;
import 'pages/settings_page.dart' show SettingsPageModule, SettingsDeps;
import 'player_controller.dart'
    show PlayerController, AudioEngine, NullAudioEngine;
import 'registry.dart' show SurfaceRegistry;

const String _tag = 'surface.assembly';

// ───────────────────────── 装配清单 ─────────────────────────

/// assembleAll 的返回值（app_root 消费）：
/// logic 单例 + PlayerController + provider overrides + 清缓存钩子。
class AssemblyResult {
  AssemblyResult({
    required this.search,
    required this.playlist,
    required this.rank,
    required this.auth,
    required this.lyrics,
    required this.playback,
    required this.history,
    required this.downloads,
    required this.controller,
    required this.providerOverrides,
    required this.moduleIds,
    required this.clearLyricCache,
  });

  // logic 单例（全 App 唯一实例，经 provider 或本对象获取）。
  final SearchLogic search;
  final PlaylistLogic playlist;
  final RankLogic rank;
  final AuthLogic auth;
  final LyricsLogic lyrics;
  final PlaybackService playback;
  final HistoryRecorder history;
  final DownloadManager downloads;

  /// 批4-B 播放控制器（engine 可替换，批5-A 传 JustAudioEngine）。
  final PlayerController controller;

  /// 注入 ProviderScope 的 overrides（playerProvider 等 overrideWithValue）。
  final List<Override> providerOverrides;

  /// 已 install 的模块 id（装配清单留痕）。
  final List<String> moduleIds;

  /// 组合清缓存钩子：歌词 LruCache.clear + PlaybackService 内存缓存兜底。
  final void Function() clearLyricCache;
}

// ───────────────────────── 装配总入口 ─────────────────────────

/// 装配全部 surface 依赖。
/// [engine]：批5-A 完成后传 JustAudioEngine；缺省 NullAudioEngine（占位可跑通）。
/// [quality]：默认目标音质。
Future<AssemblyResult> assembleAll(SurfaceDeps deps,
    {AudioEngine? engine, String quality = '128'}) async {
  // 步骤 1：缓存实例集中创建（各域独立 LruCache，不复用同一实例）。
  final searchCache = _newCache<String, SearchResult>(128, 'search');
  final playlistCache = _newCache<String, dynamic>(64, 'playlist');
  final rankCache = _newCache<String, dynamic>(64, 'rank');
  final lyricCache = _newCache<String, LyricResult>(32, 'lyrics');

  // 步骤 2：logic 单例（每步独立 try/catch，失败留痕后 rethrow 由外层兜底）。
  final search = _step('SearchLogic', () => SearchLogic(
        client: deps.client, cache: searchCache,
      ))!;
  final playlist = _step('PlaylistLogic', () => PlaylistLogic(
        client: deps.client, playlistDao: deps.playlistDao, cache: playlistCache,
      ))!;
  final rank = _step('RankLogic', () => RankLogic(
        client: deps.client, cache: rankCache,
      ))!;
  final auth = _step('AuthLogic', () => AuthLogic(
        client: deps.client, settings: deps.settings,
      ))!;
  final lyrics = _step('LyricsLogic', () => LyricsLogic(
        client: deps.client, paths: deps.pathsOrI, cache: lyricCache,
      ))!;
  final playback = _step('PlaybackService', () => PlaybackService(
        client: deps.client,
        songDao: deps.songDao,
        downloadStore: deps.downloadStore,
      ))!;
  final history = _step('HistoryRecorder', () => HistoryRecorder(
        historyDao: deps.historyDao, songDao: deps.songDao,
      ))!;
  final downloads = _step('DownloadManager', () => DownloadManager(
        playbackService: playback,
        songDao: deps.songDao,
        downloadStore: deps.downloadStore,
      ))!;

  // 步骤 3：PlayerController（批4-B）。
  // engine 参数类型为批4-B AudioEngine 抽象：批5-A 未完成时传 NullAudioEngine，
  // 完成后 app_root/installServices 调用处替换为 JustAudioEngine 即可（可替换点）。
  final controller = _step('PlayerController', () => PlayerController(
        resolver: playback.resolvePlaySource,
        engine: engine ?? NullAudioEngine(),
        quality: quality,
      ))!;

  // 步骤 4：批4-C 三模块 Deps 组装 + 全部 6 模块 install。
  final modules = <dynamic>[];
  final built = _step('defaultModules', () => mod.defaultModules(
        mod.SurfaceDeps(
          search: search,
          playlist: playlist,
          resolver: playback.resolvePlaySource,
          quality: quality,
        ),
      ))!;
  modules.addAll(await built);

  _step('LibraryDeps', () {
    modules.add(LibraryPageModule(
      deps: LibraryDeps(
        songDao: deps.songDao,
        historyRecent: ({int limit = 50}) => deps.historyDao.recent(limit: limit),
        downloads: downloads,
        onPlay: controller.playSong,
      ),
    ));
    return true;
  });
  _step('LyricsDeps', () {
    modules.add(LyricsPageModule(
      deps: LyricsDeps(
        lyrics: lyrics,
        currentSong: () => controller.state.queue.current,
        positionMsProvider: () => controller.state.player.positionMs,
      ),
    ));
    return true;
  });
  _step('SettingsDeps', () {
    modules.add(SettingsPageModule(
      deps: SettingsDeps(
        auth: auth,
        lyrics: lyrics,
        // 组合清缓存：歌词域 LruCache.clear（逐曲文件清理由 settings 页逐 hash 调）。
        clearLyricCache: () {
          try {
            lyricCache.clear();
            Log.d(_tag, 'lyricCache cleared');
          } catch (e, st) {
            Log.e(_tag, 'clearLyricCache failed', e, st);
          }
        },
        // TODO(批5-A)：songDao.list 是异步接口，settings 页要求同步清单；
        // 这里退化给空实现（settings 页允许空退化），批5-A 接 Isar 同步查询后替换。
        lyricHashes: () => const <String>[],
      ),
    ));
    return true;
  });

  // 步骤 5：SurfaceRegistry.install 全部模块（重复 id 热替换语义）。
  final ids = <String>[];
  for (final m in modules) {
    try {
      SurfaceRegistry.install(m as dynamic);
      ids.add((m as dynamic).id as String);
    } catch (e, st) {
      Log.e(_tag, 'install module failed', e, st);
    }
  }

  return AssemblyResult(
    search: search,
    playlist: playlist,
    rank: rank,
    auth: auth,
    lyrics: lyrics,
    playback: playback,
    history: history,
    downloads: downloads,
    controller: controller,
    providerOverrides: SurfaceRegistry.providerOverrides,
    moduleIds: ids,
    clearLyricCache: () {
      try {
        lyricCache.clear();
      } catch (e, st) {
        Log.e(_tag, 'assembly clearLyricCache failed', e, st);
      }
    },
  );
}

// ───────────────────────── 内部工具 ─────────────────────────

LruCache<K, V> _newCache<K, V>(int capacity, String domain) {
  try {
    final c = LruCache<K, V>(capacity: capacity);
    Log.d(_tag, 'cache[$domain] capacity=$capacity');
    return c;
  } catch (e, st) {
    Log.e(_tag, 'cache[$domain] create failed', e, st);
    rethrow;
  }
}

/// 单步装配包装：每步 try/catch + Log，失败 rethrow（装配失败必须显式暴露）。
T? _step<T>(String name, T Function() build) {
  try {
    final r = build();
    Log.d(_tag, 'assembled $name');
    return r;
  } catch (e, st) {
    Log.e(_tag, 'assemble $name failed', e, st);
    rethrow;
  }
}
