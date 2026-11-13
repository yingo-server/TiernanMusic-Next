// L2 bootloader 级 · 启动序列装配
// 职责：按序装配 L3 kernel 模块 → core 单例装配 → 会话恢复 → 输出 BootResult。
// init 层是唯一调用方（经 bridge_boot 的 runBoot）。
// 批7-A：L2 只经桥取 kernel/core/logic 能力（kernel 能力后续经 bridge_kernel）。
// 注册机制：运行期完整性校验已删除，防篡改由 CI 构建期（verification.json）承担；
//   Bootstrap.run 不再消费 manifest/moduleBytes，无任何运行期校验逻辑。
//   注册由显式函数 installBootBridge() 完成（见文件底部），由 L1 经
//   lib/bootloader/register.dart 的 registerBootloader() 调用一次。
import 'dart:async';

import '../bridges/bridge_boot.dart' as bb;
import '../bridges/bridge_boot.dart' show KernelContext, Log;
import '../bridges/bridge_core.dart' as core;
import '../bridges/bridge_logic.dart' as lg;

/// init 层拿到的启动结果。
/// 批5-B：成功路径装配的 core 单例随结果上交，由 main（L1 依赖根，白名单）
/// 构造 SurfaceDeps 并调 surface.installServices —— L2 不得 import L6。
/// init 层经 bridge_boot.BootOutcome.fromAny 把本类型归一化为类型化 BootOutcome。
class BootResult {
  const BootResult({
    required this.rejected,
    required this.kernel,
    this.client,
    this.songDao,
    this.playlistDao,
    this.historyDao,
    this.downloadStore,
    this.settings,
    this.paths,
    this.auth,
  });
  final bool rejected;
  final KernelContext? kernel;

  // 批5-B 装配的 core 单例（失败路径为 null）。
  final core.KugouClient? client;
  final core.SongDao? songDao;
  final core.PlaylistDao? playlistDao;
  final core.HistoryDao? historyDao;
  final core.DownloadStore? downloadStore;
  final core.KeyValueSettings? settings;
  final core.StoragePaths? paths;

  /// 已 restoreSession 的 AuthLogic（会话 cookie 落在此 client.session 上）。
  final lg.AuthLogic? auth;
}

class Bootstrap {
  Bootstrap._();

  /// 启动序列：kernel 装配 → core 单例装配 → 会话恢复。
  ///
  /// [rootDir]：存储根目录。TODO(时序说明)：L2 是纯 dart:io 层、禁 flutter，
  /// 无法调 path_provider。约定由 main（L1 特例，允许 import path_provider）
  /// 在 runApp 前先 `getApplicationSupportDirectory()` 拿目录，再传进本参数
  /// （见 init/main.dart）。未传时用 `.` 相对根兜底（仅 debug 可跑通）。
  /// 注：无 manifest/moduleBytes 参数——运行期完整性校验已删除，
  /// 防篡改由 CI 构建期 verification.json（加盐 md5/sha512 + RSA-4096 签名）
  /// 承担；init 层的 runBoot 调用点也不再传这些实参。
  static BootResult run({bool bypassIntegrity = false, String? rootDir}) {
    Log.d('boot', 'bootstrap run (bypass=$bypassIntegrity)');
    // 无运行期完整性校验。防篡改由 CI 构建期承担：tool/gen_verification.dart
    // 生成加盐 md5/sha512 + RSA-4096 签名的 verification.json，
    // 随同版本 release 发布（每版一份）。
    final kernel = bb.BootBridge.assemble();
    try {
      final coreSet = _assembleCore(rootDir: rootDir);
      return BootResult(
        rejected: false,
        kernel: kernel,
        client: coreSet['client'] as core.KugouClient?,
        songDao: coreSet['songDao'] as core.SongDao?,
        playlistDao: coreSet['playlistDao'] as core.PlaylistDao?,
        historyDao: coreSet['historyDao'] as core.HistoryDao?,
        downloadStore: coreSet['downloadStore'] as core.DownloadStore?,
        settings: coreSet['settings'] as core.KeyValueSettings?,
        paths: coreSet['paths'] as core.StoragePaths?,
        auth: coreSet['auth'] as lg.AuthLogic?,
      );
    } catch (e, st) {
      Log.e('boot', 'core assemble failed', e, st);
      return BootResult(rejected: true, kernel: kernel);
    }
  }

  /// 批5-B 成功路径装配：StoragePaths.init → DAO/Store/Settings → AuthLogic
  /// → restoreSession 恢复会话。每步 try/catch + Log('boot')。
  /// 返回字段与 BootResult 装配字段同名的 map（spread 构造 BootResult）。
  static Map<String, Object?> _assembleCore({String? rootDir}) {
    // 1) 存储根注入（真实路径由 main 经 path_provider 拿到后传入，见 run 文档）。
    final paths = core.StoragePaths.init(rootDir ?? '.');
    Log.d('boot', 'storage root=${paths.rootDir.path}');

    // 2) DB 打开（经桥接函数，幂等）——bootloader 是 async 不可行，
    //    改由 main 在 runApp 前 await；此处仅记录意图。
    Log.d('boot', 'db open deferred to main (bridge: openDatabase)');
    unawaited(core
        .openDatabase(paths.db().path)
        .then((opened) => Log.d('boot', 'db opened=$opened'))
        .catchError((Object e, StackTrace st) =>
            Log.e('boot', 'db open failed (async)', e, st)));

    // 3) core 单例 + AuthLogic 单例（每步 try/catch 由 run 外层兜底留痕）。
    // 客户端带 L2 磁盘缓存 + 单飞合并（批R2）：
    // 缓存目录 = StoragePaths.I.cache()；播放地址类端点已在端点表标 cacheable=false。
    final client = core.KugouClient(
      core.KugouSession(),
      cache: core.ResourceCache(
        rootDir: core.StoragePaths.I.cache(),
        namespace: 'net',
      ),
      inflight: core.InFlight<Map<String, dynamic>>(),
    );
    final auth =
        lg.AuthLogic(client: client, settings: core.KeyValueSettings(paths));
    try {
      final ok2 = auth.restoreSession();
      Log.d('boot', 'restoreSession ok=$ok2');
    } catch (e, st) {
      Log.e('boot', 'restoreSession failed', e, st);
    }

    return <String, Object?>{
      'client': client,
      'songDao': core.SongDao(),
      'playlistDao': core.PlaylistDao(),
      'historyDao': core.HistoryDao(),
      'downloadStore': core.DownloadStore(paths),
      'settings': core.KeyValueSettings(paths),
      'paths': paths,
      'auth': auth,
    };
  }
}

// 批7-A：启动序列注册到 bridge_boot（L1 init 只经 runBoot 调本方法）。
// 注册为显式安装函数 installBootBridge()：Dart 顶层变量惰性初始化，顶层
// final 无人读取时永不执行，故弃用「文件加载即注册」方式，由 L1 经
// lib/bootloader/register.dart 的 registerBootloader() 调用一次。
// 注：manifest/moduleBytes 形参仅因 bridge_boot 的注册函数类型要求而保留
// （bridge_boot 不可改），本闭包零消费、不转发给 Bootstrap.run；
// init 调用点已不传这些实参。
void installBootBridge() {
  bb.setRunBootImpl(
      ({bool bypassIntegrity = false,
        String? rootDir,
        dynamic manifest,
        Map<String, List<int>>? moduleBytes}) =>
          Bootstrap.run(bypassIntegrity: bypassIntegrity, rootDir: rootDir));
}
