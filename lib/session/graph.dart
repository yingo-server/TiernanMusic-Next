// L6 session · 装配图（依赖 core/logic 单例；纯数据，无业务逻辑）
// 纯契约（NavEntry/SurfaceModule）在 contracts.dart，本文件只放有依赖的部分。
import '../bridges/bridge_core.dart'
    show
        KugouClient,
        SongDao,
        PlaylistDao,
        HistoryDao,
        DownloadStore,
        KeyValueSettings,
        StoragePaths,
        CacheService,
        NotificationMeta,
        NotificationControls,
        MusicAudioHandler;
import '../bridges/bridge_logic.dart'
    show
        SearchLogic,
        PlaylistLogic,
        RankLogic,
        AuthLogic,
        LyricsLogic,
        PlaybackService,
        HistoryRecorder,
        DownloadManager,
        RecommendLogic,
        ArtistLogic,
        FmLogic,
        SearchTypedLogic,
        PlaylistWriteLogic,
        UserLogic,
        CollectLogic,
        CommentLogic,
        MvLogic,
        AlbumLogic,
        AccountLogic,
        VerificationLogic,
        TranslationLogic,
        YkgLogic;
import 'contracts.dart' show NavEntry, SurfaceModule;

export 'contracts.dart' show NavEntry, SurfaceModule;

/// core 依赖集合（bootloader 装配后交给 session）。
class SessionDeps {
  const SessionDeps({
    required this.client,
    required this.songDao,
    required this.playlistDao,
    required this.historyDao,
    required this.downloadStore,
    required this.settings,
    this.paths,
    this.cache,
    this.notification,
  });

  final KugouClient client;
  final SongDao songDao;
  final PlaylistDao playlistDao;
  final HistoryDao historyDao;
  final DownloadStore downloadStore;
  final KeyValueSettings settings;
  final StoragePaths? paths;

  /// 缓存 ⊃ 预读 统一服务（L4 core/cache；session 消费，L7 不碰）。
  final CacheService? cache;

  /// 通知栏网关（L4 core/audio；session 绑定控制，L7 不碰）。
  final MusicAudioHandler? notification;

  StoragePaths get pathsOrI => paths ?? StoragePaths.I;
}

/// 装配结果：全部 logic 单例 + 已注册模块 id 列表。
class AppGraph {
  const AppGraph({
    this.modules = const <String>[],
    this.search,
    this.playlist,
    this.rank,
    this.auth,
    this.lyrics,
    this.playback,
    this.history,
    this.downloads,
    this.recommend,
    this.artist,
    this.fm,
    this.searchTyped,
    this.playlistWrite,
    this.user,
    this.collect,
    this.comment,
    this.mv,
    this.album,
    this.account,
    this.verification,
    this.translation,
    this.ykg,
    this.cache,
    this.notification,
    this.songDao,
    this.historyDao,
    this.client,
  });

  factory AppGraph.empty() => const AppGraph(
    modules: const <String>[],
    songDao: null,
    historyDao: null,
    client: null,
  );

  final List<String> modules;
  final SearchLogic? search;
  final PlaylistLogic? playlist;
  final RankLogic? rank;
  final AuthLogic? auth;
  final LyricsLogic? lyrics;
  final PlaybackService? playback;
  final HistoryRecorder? history;
  final DownloadManager? downloads;
  final RecommendLogic? recommend;
  final ArtistLogic? artist;
  final FmLogic? fm;
  final SearchTypedLogic? searchTyped;
  final PlaylistWriteLogic? playlistWrite;
  final UserLogic? user;
  final CollectLogic? collect;
  final CommentLogic? comment;
  final MvLogic? mv;
  final AlbumLogic? album;
  final AccountLogic? account;
  final VerificationLogic? verification;
  final TranslationLogic? translation;
  final YkgLogic? ykg;

  /// 缓存 ⊃ 预读 统一服务（L4）。
  final CacheService? cache;

  /// 通知栏网关（L4）。
  final MusicAudioHandler? notification;

  /// 供 L7 取 DAO/Client（可选出口）。
  final SongDao? songDao;
  final HistoryDao? historyDao;
  final KugouClient? client;

  bool get isReady => modules.isNotEmpty;
}
