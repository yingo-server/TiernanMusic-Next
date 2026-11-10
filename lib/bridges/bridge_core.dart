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
