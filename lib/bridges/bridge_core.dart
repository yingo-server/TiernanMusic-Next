// 桥文件 bridge_core · L4 core ⇅ 上层（logic/surface 经此访问 core 门面）
// 铁律：本文件只 export，不写任何逻辑；上层禁直接 import core 内部模块。
export '../core/storage/paths.dart' show StoragePaths;
export '../core/storage/download_store.dart' show DownloadRecord, DownloadStore;
export '../core/database/dao.dart'
    show SongDao, PlaylistDao, HistoryDao, SortKey, SortOrder;
export '../core/database/entities.dart'
    show SongRecord, PlaylistMeta, PlayHistoryEntry;
export '../core/net/endpoints/models.dart'
    show SongBrief, SearchResult, PlaylistBrief, PlaylistDetail, TrackPage, LyricResult;
// MV 域模型（批1-B · GAP #16）：ep.mv 端点强类型结果经 core 桥转出。
export '../core/net/endpoints/mv_endpoints.dart'
    show MvBrief, MvQuality, MvPlayResult;
export '../core/memory/lru_cache.dart' show LruCache, CacheStats, LruEvictCallback;
export '../core/memory/cache_keys.dart'
    show buildKey, prefixOf, namespacePrefixOf, parseKey, CacheKeyInfo, sortedQuery;
// L6 surface 装配所需（app_root 组装 logic 单例时的构造参数类型）
export '../core/net/kugou_client.dart' show KugouClient, KugouSession;
export '../core/storage/settings_store.dart' show KeyValueSettings;
export '../core/net/database_bridge.dart' show openDatabase;
export '../core/net/endpoints/models.dart' show SearchResult, LyricResult;
// ── 评论域端点模型（批1-A：logic/surface 经此引用 CommentItem/CommentPage） ──
export '../core/net/endpoints/comment_endpoints.dart'
    show CommentItem, CommentPage;
// ── 多账号（批2-A）：AccountRecord 实体与 AccountDao 经 core 桥转出 ──
export '../core/database/entities.dart' show AccountRecord;
export '../core/database/dao.dart' show AccountDao;
// ── 翻译歌词数据层（批2-B）：模型与对齐/抽取/预留端点经 core 桥转出 ──
export '../core/net/endpoints/translation_models.dart'
    show TranslatedLine, TranslationResult, LyricsDisplayMode;
export '../core/net/endpoints/translation_endpoints.dart'
    show alignTranslation, extractOriginalLines, fetchTranslation;
// ── 收藏域数据层（批2-C）：写操作结果模型经 core 桥转出 ──
export '../core/net/endpoints/collect_endpoints.dart' show CollectResult;
// ── 音质档位 + 每日推荐（功能对齐批3-C · GAP #30 / #20）──
// quality_endpoints：纯数据枚举与映射函数（无 IO、无模型类）。
export '../core/net/endpoints/quality_endpoints.dart'
    show
        AudioQuality,
        qualityParam,
        toPlayUrlQuality,
        vipQualities,
        magicQualities,
        fromPref,
        toPref;
// recommend_endpoints：无模型函数（结果模型 SongBrief 已由 models.dart 转出）。
export '../core/net/endpoints/recommend_endpoints.dart'
    show getDailyRecommend, kDailyRecommendPath;
// ── 歌手域数据层（功能对齐批4-A · GAP #22）：三个结果模型经 core 桥转出 ──
// ── 专辑 + 相似推荐（功能对齐批4-B，主会话实现）──
export '../core/net/endpoints/album_endpoints.dart' show AlbumDetail;
export '../core/net/endpoints/artist_endpoints.dart'
    show ArtistBrief, ArtistDetail, AlbumBrief;
// ── 认证域（功能对齐批5-A · GAP #31）：短信登录结果模型经 core 桥转出 ──
export '../core/net/endpoints/auth_endpoints.dart' show SmsLoginResult;
// ── 六类分类搜索类型枚举（功能对齐批5-C）：SearchType 经 core 桥转出 ──
export '../core/net/endpoints/search_typed_endpoints.dart' show SearchType;
// ── 歌单写操作端点封装（功能对齐批5-B）：无新模型，仅函数集，经此转出 ──
export '../core/net/endpoints/playlist_write_endpoints.dart'
    show
        createPlaylist,
        deletePlaylist,
        removeSongsFromPlaylist,
        getPlaylistTags,
        getUserPlaylists;
