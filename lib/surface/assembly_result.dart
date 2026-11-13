// L6 surface · 装配结果数据类（从 assembly.dart 拆出，控制文件长度 ≤500）
// 纯数据契约：装配产出的各域 logic/控制器引用 + provider overrides。
// 铁律：不 import flutter 业务组件；类型引用走同层文件与桥。
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;

import '../bridges/bridge_core.dart' show SongDao, HistoryDao;
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
        VerificationLogic,
        UserLogic;
import 'player_controller.dart' show PlayerController;

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
