import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;

import 'deps.dart' show SurfaceDeps;
import 'registry.dart' show SurfaceRegistry;
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
        LyricResult,
        CommentPage,
        AccountDao,
        toPref;
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
        DownloadManager,
        CommentLogic,
        MvLogic,
        CollectLogic,
        AccountLogic,
        TranslationLogic,
        RecommendLogic,
        ArtistLogic,
        AlbumLogic,
        FmLogic,
        VerificationLogic,
        SearchTypedLogic,
        PlaylistWriteLogic,
        UserLogic,
        SongBrief;
import 'modules.dart' as mod;
import 'pages/library_page.dart' show LibraryPageModule, LibraryDeps;
import 'pages/lyrics_page.dart' show LyricsPageModule, LyricsDeps;
import 'pages/settings_page.dart' show SettingsPageModule, SettingsDeps;
import 'pages/comment_page.dart' show buildCommentModule;
import 'pages/mv_page.dart' show buildMvModule;
import 'app_root.dart' show appNavigatorKey, homeTabRequest, localeRevision;
import 'pages/artist_page.dart' show buildArtistModule;
import 'pages/album_page.dart' show buildAlbumModule, AlbumPage;
import 'nav_state.dart' show SurfaceNavState;
import 'pages/home_page.dart' show buildHomeModule;
import 'player_controller.dart'
    show PlayerController, AudioEngine, NullAudioEngine;
import 'theme/tn_motion.dart' show TnPageRoute;

const String _tag = 'surface.assembly';

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
    required this.recommend,
    required this.artist,
    required this.fm,
    required this.searchTyped,
    required this.playlistWrite,
    required this.verification,
    required this.user,
    required this.controller,
    required this.providerOverrides,
    required this.moduleIds,
    required this.clearLyricCache,
  });

  final SearchLogic search;
  final PlaylistLogic playlist;
  final RankLogic rank;
  final AuthLogic auth;
  final LyricsLogic lyrics;
  final PlaybackService playback;
  final HistoryRecorder history;
  final DownloadManager downloads;
  final RecommendLogic recommend;
  final ArtistLogic artist;
  final FmLogic fm;

  final SearchTypedLogic searchTyped;
  final PlaylistWriteLogic playlistWrite;
  final VerificationLogic verification;
  final UserLogic user;

  final PlayerController controller;

  final List<Override> providerOverrides;

  final List<String> moduleIds;

  final void Function() clearLyricCache;
}

Future<AssemblyResult> assembleAll(SurfaceDeps deps,
    {AudioEngine? engine, String quality = '128'}) async {
  final searchCache = _newCache<String, SearchResult>(128, 'search');
  final playlistCache = _newCache<String, dynamic>(64, 'playlist');
  final navState = SurfaceNavState();
  final rankCache = _newCache<String, dynamic>(64, 'rank');
  final lyricCache = _newCache<String, LyricResult>(32, 'lyrics');

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

  final commentCache = _newCache<String, CommentPage>(64, 'comment');
  final commentLogic = _step('CommentLogic', () => CommentLogic(
        client: deps.client, cache: commentCache,
      ))!;
  final mvCache = _newCache<String, dynamic>(64, 'mv');
  final mvLogic = _step('MvLogic', () => MvLogic(
        client: deps.client, cache: mvCache,
      ))!;
  final collectLogic = _step('CollectLogic', () => CollectLogic(
        client: deps.client,
        settings: deps.settings,
        isLoggedIn: () => auth.session.userid.isNotEmpty,
      ))!;
  final translationLogic = _step('TranslationLogic',
      () => TranslationLogic())!;
  // 多账号切换时的缓存失效器收集器：先声明空列表，各 logic 声明后逐个 add，
  // 避免闭包前向引用未声明的 final 局部变量（Dart 编译期禁止）。
  final accountInvalidators = <void Function()>[];
  accountInvalidators.add(
      () => search.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators.add(
      () => playlist.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators.add(
      () => rank.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators.add(
      () => commentLogic.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators
      .add(() => mvLogic.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators.add(() => collectLogic.resetLocalMirror());
  accountInvalidators.add(() => translationLogic.invalidatePrefix(
      userid: deps.client.session.userid));
  final accountLogic = _step('AccountLogic', () => AccountLogic(
        dao: AccountDao(),
        client: deps.client,
        settings: deps.settings,
        onAccountChanged: () {
          try {
            for (final invalidate in accountInvalidators) {
              invalidate();
            }
            Log.d(_tag, 'account caches invalidated');
          } catch (e, st) {
            Log.e(_tag, 'account cache invalidation failed', e, st);
          }
        },
      ))!;
  final recommendLogic = _step('RecommendLogic', () => RecommendLogic(
        client: deps.client,
        cache: _newCache<String, dynamic>(64, 'recommend'),
      ))!;
  final artistLogic = _step('ArtistLogic', () => ArtistLogic(
        client: deps.client,
        cache: _newCache<String, dynamic>(64, 'artist'),
      ))!;
  final albumLogic = _step('AlbumLogic', () => AlbumLogic(
        client: deps.client,
        cache: _newCache<String, dynamic>(64, 'album'),
      ))!;
  final fmLogic = _step('FmLogic', () => FmLogic(
        client: deps.client,
        cache: _newCache<String, dynamic>(32, 'fm'),
      ))!;
  final userLogic = _step('UserLogic', () => UserLogic(
        client: deps.client,
        cache: _newCache<String, dynamic>(32, 'user'),
      ))!;
  final searchTypedLogic = _step('SearchTypedLogic', () => SearchTypedLogic(
        client: deps.client,
        cache: _newCache<String, SearchResult>(64, 'search_typed'),
      ))!;
  // 后声明的 7 个域补进多账号失效清单（按声明顺序，无前向引用）。
  accountInvalidators.add(() => recommendLogic.invalidatePrefix(
      userid: deps.client.session.userid));
  accountInvalidators
      .add(() => artistLogic.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators
      .add(() => albumLogic.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators
      .add(() => fmLogic.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators
      .add(() => userLogic.invalidatePrefix(userid: deps.client.session.userid));
  accountInvalidators.add(() => searchTypedLogic.invalidatePrefix(
      userid: deps.client.session.userid));
  final playlistWriteLogic = _step('PlaylistWriteLogic', () => PlaylistWriteLogic(
        client: deps.client,
        playlistDao: deps.playlistDao,
        onChanged: () {
          try {
            playlist.invalidatePrefix(userid: deps.client.session.userid);
          } catch (e, st) {
            Log.e(_tag, 'playlist cache invalidation failed', e, st);
          }
        },
      ))!;
  final verificationLogic = _step('VerificationLogic', () => VerificationLogic(
        client: deps.client,
        settings: deps.settings,
      ))!;

  final controller = _step('PlayerController', () => PlayerController(
        resolver: playback.resolvePlaySource,
        engine: engine ?? NullAudioEngine(),
        quality: quality,
      ))!;

  final modules = <dynamic>[];
  final built = _step('defaultModules', () => mod.defaultModules(
        mod.SurfaceDeps(
          search: search,
          playlist: playlist,
          resolver: playback.resolvePlaySource,
          quality: quality,
          collect: collectLogic,
          searchTyped: searchTypedLogic,
          onQualitySelected: (q) {
            try {
              deps.settings.setString('preferred_quality', toPref(q));
              Log.d(_tag, 'quality pref saved=${toPref(q)}');
            } catch (e, st) {
              Log.e(_tag, 'save quality pref failed', e, st);
            }
          },
          onOpenComments: () {
            try {
              final nav = appNavigatorKey.currentState;
              if (nav == null) {
                Log.w(_tag, 'open comments skipped: navigator not ready');
                return;
              }
              final m = SurfaceRegistry.active(const LogicFacade())
                  .where((x) => x.id == 'comment')
                  .toList();
              if (m.isEmpty) {
                Log.w(_tag, 'comment module not installed');
                return;
              }
              nav.push(TnPageRoute<void>(
                Builder(builder: (ctx) =>
                    m.first.builder(const LogicFacade())(ctx)),
              ));
              Log.d(_tag, 'open comments ok');
            } catch (e, st) {
              Log.e(_tag, 'open comments failed', e, st);
            }
          },
          onStartFm: () {
            // 播放页 FM 入口：同 SettingsDeps 组合语义。
            try {
              fmLogic.start().then((batch) {
                if (batch.isNotEmpty) controller.playAll(batch, 0);
              });
            } catch (e, st) {
              Log.e(_tag, 'onStartFm failed', e, st);
            }
          },
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
        translation: translationLogic,
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
        lyricHashes: () => collectLogic.listFavorites(),
        accounts: accountLogic,
        collect: collectLogic,
        onStartFm: () {
          // 个人 FM：FmLogic.start() 取首批 → 非空批次整体入队从 0 播放。
          fmLogic.start().then((batch) {
            if (batch.isNotEmpty) controller.playAll(batch, 0);
          });
        },
        verificationState: () => verificationLogic.state.name,
        onLocaleChanged: (code) {
          try {
            // 语言持久化已在 settings 页 saveLocale 落盘；此处通知 AppRoot 重建。
            localeRevision.value = localeRevision.value + 1;
            Log.d(_tag, 'locale changed → rebuild code=$code');
          } catch (e, st) {
            Log.e(_tag, 'onLocaleChanged failed', e, st);
          }
        },
      )));
    return true;
  });

  _step('CommentModule', () {
    modules.add(buildCommentModule(
      logic: commentLogic,
      mixSongIdProvider: () =>
          controller.state.queue.current?.mixSongId ?? 0,
    ));
    return true;
  });
  _step('MvModule', () {
    modules.add(buildMvModule(
      logic: mvLogic,
      currentMvHash: () => null, // 封面/MV hash 由播放页解析后回填（待接线）
      isFavorite: (hash) => collectLogic.isCollected(hash),
      onToggleFavorite: (hash) async {
        final r = await collectLogic.toggle(hash, 0);
        return collectLogic.isCollected(hash) && !r.needsLogin;
      },
    ));
    return true;
  });

  _step('ArtistModule', () {
    modules.add(buildArtistModule(
      logic: artistLogic,
      currentArtistId: () => navState.artistId,
      onPlay: controller.playSong,
      // 装配层同层接线：写 navState 后用 Navigator 打开专辑页（模块间零 import）。
      onOpenAlbum: (album) {
        try {
          navState.setAlbum(album.id);
          final nav = appNavigatorKey.currentState;
          if (nav == null) {
            Log.w('surface.assembly', 'open album skipped: navigator not ready');
            return;
          }
          nav.push(TnPageRoute<void>(AlbumPage(
              logic: albumLogic,
              albumId: album.id,
              onPlay: controller.playSong,
            )));
        } catch (e, st) {
          Log.e('surface.assembly', 'open album failed', e, st);
        }
      },
    ));
    return true;
  });
  _step('AlbumModule', () {
    modules.add(buildAlbumModule(
      logic: albumLogic,
      currentAlbumId: () => navState.albumId,
      onPlay: controller.playSong,
    ));
    return true;
  });

  // 批6-C 首页模块（工厂签名已核对：recommend/rank/search/playlist + onPlay(SongBrief) + onOpenSearch）。
  _step('HomeModule', () {
    modules.add(buildHomeModule(
      recommend: recommendLogic,
      rank: rank,
      search: search,
      playlist: playlist,
      onPlay: controller.playSong,
      onOpenSearch: () {
        try {
          // 首页搜索入口 → 请求切到搜索 tab（app_root.homeTabRequest 消费）。
          homeTabRequest.value = 'search';
          Log.d(_tag, 'open search → tab search');
        } catch (e, st) {
          Log.e(_tag, 'onOpenSearch failed', e, st);
        }
      },
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
    recommend: recommendLogic,
    artist: artistLogic,
    fm: fmLogic,
    user: userLogic,
    searchTyped: searchTypedLogic,
    playlistWrite: playlistWriteLogic,
    verification: verificationLogic,
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
