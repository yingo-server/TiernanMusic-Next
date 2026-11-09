// 五桥 · bridge_logic：L5 logic 暴露给 L6 surface 的能力门面（含 Log）。
// 铁律：本文件只 export（外加一个纯占位 LogicFacade），不写业务逻辑。
// 每个被 export 的 logic 模块自身负责 try/catch + Log 留痕。
library;

import '../kernel/kernel.dart' show Log;

// ── 播放编排器能力（批2-B） ──
export '../logic/player/playback_service.dart'
    show PlaybackService, PlaySource, PlaybackError, PlaybackException;
export '../logic/player/history_recorder.dart' show HistoryRecorder;

// ── 播放队列状态机 / 播放器状态 / reducer（批2-A） ──
export '../logic/player/queue_state.dart' show PlayMode, QueueState;
export '../logic/player/player_state.dart' show PlayerState, PlayerStatus;
export '../logic/player/playback_reducer.dart'
    show
        PlaybackAction,
        StartLoad,
        Playing,
        Paused,
        Progress,
        Completed,
        ErrorAction,
        SeekTo,
        QueueJump,
        SetVolume,
        SetSpeed,
        Resume,
        Stop,
        playbackReducer;

// ── catalog logic 门面（搜索/歌单/榜单，批2-C） ──
export '../logic/catalog/search_logic.dart'
    show SearchLogic, kSearchCacheSchemaVer;
export '../logic/catalog/playlist_logic.dart'
    show PlaylistLogic, kPlaylistCacheSchemaVer;
export '../logic/catalog/rank_logic.dart' show RankLogic, kRankCacheSchemaVer;

// ── auth logic 门面（账号登录域，批3-B） ──
export '../logic/auth/auth_logic.dart'
    show
        AuthLogic,
        QrLoginStatus,
        QrLoginState,
        RefreshResult,
        kSettingToken,
        kSettingUserid,
        kSettingMid,
        kSettingDfid,
        kSettingKugouApiMid;

// ── download logic 门面（并发队列下载管理，批3-C） ──
export '../logic/download/download_models.dart'
    show DownloadTask, DownloadEvent, DownloadStatus;
export '../logic/download/download_manager.dart' show DownloadManager;

// ── lyrics logic 门面（歌词域，批3-A） ──
export '../logic/lyrics/lyrics_logic.dart' show LyricsLogic;
export '../logic/lyrics/lyrics_parser.dart'
    show LyricParseResult, LrcLine, KrcWord, parseLyrics, applyOffset, findLineIndex;

// ── kernel 门面（L6 surface 需要统一 Log；registry.dart 已依赖此导出） ──
export '../kernel/kernel.dart' show Log;

/// logic 能力门面：surface 只拿这个，不 import logic 内部模块。
/// 具体能力类经上方 export 直接可用；此类仅承载跨域摘要与装配状态。
class LogicFacade {
  const LogicFacade();

  /// 查询当前播放状态描述（占位：批3 装配后接 PlaybackService）。
  String playbackSummary() => 'idle';
}
