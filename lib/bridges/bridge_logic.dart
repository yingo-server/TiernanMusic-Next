// 五桥 · bridge_logic：L5 logic 暴露给 L6 surface 的能力门面（export 通道）。
// 铁律：本文件只 export（外加类型标记 LogicFacade），不写业务逻辑。
// 本桥本身不承担日志职责：它以 export 为唯一通道，跨层调用的
// try/catch + Log 留痕由调用方（surface 层）负责。
library;

import '../kernel/kernel.dart' show Log;

// ── 播放编排器能力（批2-B） ──
export '../logic/player/playback_service.dart'
    show PlaybackService, PlaySource, PlaybackError, PlaybackException;
export '../logic/player/history_recorder.dart' show HistoryRecorder;
export '../logic/player/prefetch_engine.dart' show PrefetchEngine;

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
// ── 每日推荐 logic 门面（功能对齐批3-C · GAP #20）──
export '../logic/catalog/recommend_logic.dart'
    show RecommendLogic, kRecommendCacheSchemaVer;
// MV logic 门面（批1-B · GAP #16）
export '../logic/catalog/mv_logic.dart' show MvLogic, kMvCacheSchemaVer;
// MV 模型经 bridge_core 转出（mv_endpoints.dart 在 core/net/endpoints）
// catalog 模型类型经 bridge_core 转出（models.dart 在 core/net/endpoints）
export '../core/net/endpoints/models.dart'
    show SongBrief, SearchResult, SearchSuggestItem, PlaylistBrief, PlaylistDetail, TrackPage, RankBrief, LyricResult;
// ── comment logic 门面（评论域，批1-A） ──
export '../logic/catalog/comment_logic.dart'
    show CommentLogic, kCommentCacheSchemaVer;
export '../core/net/endpoints/comment_endpoints.dart'
    show CommentItem, CommentPage, getMusicComments, getCommentFloor, getCommentCount;

// ── 收藏体系 logic 门面（功能对齐批2-C：登录守卫 + 本地镜像 + 防重锁） ──
export '../logic/catalog/collect_logic.dart' show CollectLogic;

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
// ── 功能对齐批2 收尾：多账号 / 翻译显示门面 ──
export '../logic/auth/account_logic.dart' show AccountLogic;
export '../logic/lyrics/translation_logic.dart'
    show TranslationLogic, DisplayLine;
// ── 个人 FM logic 门面（功能对齐批4-C · GAP #21；端点 needs probe） ──
export '../logic/catalog/fm_logic.dart' show FmLogic, kFmCacheSchemaVer;
// ── 歌手域 logic 门面（功能对齐批4-A · GAP #22）──
// ── 专辑 + 相似推荐 logic 门面（功能对齐批4-B，主会话实现）──
export '../logic/catalog/album_logic.dart'
    show AlbumLogic, kAlbumCacheSchemaVer;
export '../logic/catalog/artist_logic.dart'
    show ArtistLogic, kArtistCacheSchemaVer;
// ── 20028 验证收敛 + 短信登录（功能对齐批5-A · GAP #31）：
//    VerificationLogic 是唯一可信验证门面（收敛旧项目三套平行实现，
//    禁止 auth_repository / playback_service 再各写一套）；
//    SmsLoginResult 经 bridge_core 转出（本桥同步转出，surface 双入口合法）。──
export '../logic/auth/verification_logic.dart'
    show VerificationLogic, VerificationState;
export '../core/net/endpoints/auth_endpoints.dart' show SmsLoginResult;
// ── 六类分类搜索 + 综合搜索 v6 logic 门面（功能对齐批5-C）──
export '../logic/catalog/search_typed_logic.dart'
    show SearchTypedLogic, kSearchTypedCacheSchemaVer;
// ── 歌单写操作 logic 门面（功能对齐批5-B）──
export '../logic/catalog/playlist_write_logic.dart' show PlaylistWriteLogic;
// ── 用户域 logic 门面（批6-A）──
export '../logic/catalog/user_logic.dart' show UserLogic, kUserCacheSchemaVer;

/// logic 能力门面：surface 只拿这个，不 import logic 内部模块。
/// 具体能力类经上方 export 直接可用；此类仅承载跨域摘要与装配状态。
/// 审计B P2-2：本类仅作类型标记（surface 装配/SurfaceModule.enabled、
/// builder 依赖此类型存在），不可当业务门面调用——
/// playbackSummary 零调用、恒返回占位 'idle'，不承载任何业务逻辑。
class LogicFacade {
  const LogicFacade();

  /// 占位方法，禁止作为业务门面调用（见类注释）。
  String playbackSummary() {
    try {
      return 'idle';
    } catch (e, st) {
      Log.e('bridge_logic', 'playbackSummary failed', e, st);
      return 'error';
    }
  }
}

