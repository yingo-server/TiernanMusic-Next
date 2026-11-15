// L6 session · 启动装配（纯 Dart，无 Widget）
// 职责：把 L4 core / L5 logic 单例装配成 AppGraph，注册模块 id，接上播放会话。
// L1/bridge_surface 调 [bootstrapSession]；L7 surface 只经 bridge_session 消费结果。
library;

import '../bridges/bridge_core.dart'
    show KugouClient, SongDao, PlaylistDao, HistoryDao, DownloadStore,
        KeyValueSettings, StoragePaths, LruCache, SearchResult, LyricResult,
        CommentPage, AccountDao, PlaylistMeta, AudioEngine, CacheService,
        CacheOrigin, Endpoint, EndpointRegistry;
import '../bridges/bridge_logic.dart'
    show SearchLogic, PlaylistLogic, RankLogic, AuthLogic, LyricsLogic,
        PlaybackService, HistoryRecorder, DownloadManager, RecommendLogic,
        ArtistLogic, FmLogic, SearchTypedLogic, PlaylistWriteLogic, UserLogic,
        CollectLogic, CommentLogic, MvLogic, AlbumLogic, AccountLogic,
        VerificationLogic, TranslationLogic, Log;
import 'graph.dart' show AppGraph, SessionDeps, SurfaceModule;
import 'module_registry.dart' show ModuleRegistry;
import 'playback_session.dart' show PlaybackSession;

const String _tag = 'session.bootstrap';

AppGraph? _graph;
AppGraph get appGraph => _graph ?? const AppGraph();

/// 唯一装配入口。每个 _step 失败必抛出（禁止静默少依赖）。
Future<AppGraph> bootstrapSession({
  required KugouClient client,
  required SongDao songDao,
  required PlaylistDao playlistDao,
  required HistoryDao historyDao,
  required DownloadStore downloadStore,
  required KeyValueSettings settings,
  StoragePaths? paths,
  Object? engine,
}) async {
  try {
    T step<T>(String name, T Function() build) {
      try {
        final v = build();
        Log.d(_tag, 'assembled $name');
        return v;
      } catch (e, st) {
        Log.e(_tag, '$name failed', e, st);
        rethrow;
      }
    }

    LruCache<K, V> cache<K, V>(int cap) =>
        LruCache<K, V>(capacity: cap);

    final search = step('SearchLogic',
        () => SearchLogic(client: client, cache: cache<String, SearchResult>(128)));
    final playlist = step('PlaylistLogic',
        () => PlaylistLogic(client: client, playlistDao: playlistDao,
            cache: cache<String, dynamic>(64)));
    final rank = step('RankLogic',
        () => RankLogic(client: client, cache: cache<String, dynamic>(64)));
    final auth = step('AuthLogic',
        () => AuthLogic(client: client, settings: settings));
    final lyrics = step('LyricsLogic',
        () => LyricsLogic(client: client, paths: paths ?? StoragePaths.I,
            cache: cache<String, LyricResult>(32)));
    final playback = step('PlaybackService',
        () => PlaybackService(client: client, songDao: songDao,
            downloadStore: downloadStore));
    final history = step('HistoryRecorder',
        () => HistoryRecorder(historyDao: historyDao, songDao: songDao));
    final downloads = step('DownloadManager',
        () => DownloadManager(playbackService: playback, songDao: songDao,
            downloadStore: downloadStore));
    final comment = step('CommentLogic',
        () => CommentLogic(client: client, cache: cache<String, CommentPage>(64)));
    final mv = step('MvLogic',
        () => MvLogic(client: client, cache: cache<String, dynamic>(64)));
    final collect = step('CollectLogic',
        () => CollectLogic(client: client, settings: settings,
            isLoggedIn: () => auth.session.userid.isNotEmpty));
    final translation = step('TranslationLogic', () => TranslationLogic());
    final recommend = step('RecommendLogic',
        () => RecommendLogic(client: client, cache: cache<String, dynamic>(64)));
    final artist = step('ArtistLogic',
        () => ArtistLogic(client: client, cache: cache<String, dynamic>(64)));
    final album = step('AlbumLogic',
        () => AlbumLogic(client: client, cache: cache<String, dynamic>(64)));
    final fm = step('FmLogic',
        () => FmLogic(client: client, cache: cache<String, dynamic>(32)));
    final user = step('UserLogic',
        () => UserLogic(client: client, cache: cache<String, dynamic>(32)));
    final searchTyped = step('SearchTypedLogic',
        () => SearchTypedLogic(client: client,
            cache: cache<String, SearchResult>(64)));
    final playlistWrite = step('PlaylistWriteLogic',
        () => PlaylistWriteLogic(client: client, playlistDao: playlistDao));
    final account = step('AccountLogic',
        () => AccountLogic(dao: AccountDao(), client: client, settings: settings));
    final verification = step('VerificationLogic',
        () => VerificationLogic(client: client, settings: settings));

    // 缓存 ⊃ 预读 统一服务：启动预热稳定入口数据（热搜/榜单）。
    // 单曲 play_url 端点 cacheable=false，不纳入预读（避免伪造 URL 缓存/风控）；
    // 队列变化只通知缓存服务做 LRU 保活，不臆造按 hash 的预热端点。
    final cacheService = CacheService(client);
    PlaybackSession.instance.onQueueChanged = (hashes) {
      Log.d(_tag, 'queue changed n=${hashes.length} (cache keeps LRU warm)');
    };
    cacheService.prefetch(<({Endpoint ep, Map<String, Object?> params})>[
      (ep: EndpointRegistry.searchHot, params: <String, Object?>{'navid': 1, 'plat': 2}),
      (ep: EndpointRegistry.rankList, params: <String, Object?>{}),
    ]);

    // 播放会话：成熟库 just_audio 引擎由 PlaybackSession.attach 内部构造。
    PlaybackSession.instance.attach(
      service: playback,
      history: history,
      quality: settings.getString('preferred_quality') ?? '128',
    );

    // 默认模块 id（L7 独立模型按这些 id 注册真实页面）。
    const moduleIds = <String>[
      'home', 'search', 'playlist', 'library', 'settings',
      'player', 'lyrics', 'comment', 'mv', 'album', 'artist',
    ];
    for (final id in moduleIds) {
      ModuleRegistry.instance.install(_PlaceholderModule(id));
    }

    _graph = AppGraph(
      modules: moduleIds,
      search: search,
      playlist: playlist,
      rank: rank,
      auth: auth,
      lyrics: lyrics,
      playback: playback,
      history: history,
      downloads: downloads,
      recommend: recommend,
      artist: artist,
      fm: fm,
      searchTyped: searchTyped,
      playlistWrite: playlistWrite,
      user: user,
      collect: collect,
      comment: comment,
      mv: mv,
      album: album,
      account: account,
      verification: verification,
      translation: translation,
      cache: cacheService,
      songDao: songDao,
      historyDao: historyDao,
      client: client,
    );
    Log.d(_tag, 'session ready modules=${moduleIds.length}');
    return _graph!;
  } catch (e, st) {
    Log.e(_tag, 'bootstrapSession failed', e, st);
    rethrow;
  }
}

/// 占位模块：独立 UI 模型注册真实模块时按 id 覆盖。
class _PlaceholderModule extends SurfaceModule {
  _PlaceholderModule(this.id);
  @override
  final String id;
  @override
  String get route => '/$id';
  @override
  bool get enabled => false; // 未接 UI 前不出现在导航
}
