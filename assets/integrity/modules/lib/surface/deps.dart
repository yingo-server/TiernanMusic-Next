// L6 surface · 装配依赖集（core 门面对象的容器）
// 抽成独立文件避免 app_root.dart ↔ assembly.dart 循环 import：
// installServices 与 assembleAll 都只依赖本文件的 Deps 类型。
// 铁律：surface 层，只 import bridge_core/bridge_logic。
import '../bridges/bridge_core.dart'
    show
        KugouClient,
        SongDao,
        PlaylistDao,
        HistoryDao,
        DownloadStore,
        StoragePaths,
        KeyValueSettings;

/// bootloader 成功路径装配好的 core 单例集合。
class SurfaceDeps {
  const SurfaceDeps({
    required this.client,
    required this.songDao,
    required this.playlistDao,
    required this.historyDao,
    required this.downloadStore,
    required this.settings,
    this.paths,
  });
  final KugouClient client;
  final SongDao songDao;
  final PlaylistDao playlistDao;
  final HistoryDao historyDao;
  final DownloadStore downloadStore;
  final KeyValueSettings settings;
  final StoragePaths? paths;

  /// 兜底路径（未注入时取 StoragePaths.I 装配态）。
  StoragePaths get pathsOrI => paths ?? StoragePaths.I;
}
