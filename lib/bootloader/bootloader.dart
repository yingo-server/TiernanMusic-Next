// L2 bootloader 级 · 启动序列与完整性校验触发点
// 职责：按序装配 L3 kernel 模块 → 校验模块清单（加盐 SHA-512 + Ed25519 签名）
// → 输出 BootResult。init 层是唯一调用方（经 bridge_boot 的 runBoot）。
// 批7-A：L2 只经桥取 kernel/core/logic 能力（kernel 能力后续经 bridge_kernel）。
//   _registerRunBoot：文件加载即把 Bootstrap.run 注册进 bridge_boot，
//   init/main.dart 调 runBoot(...) → 转回 Bootstrap.run（桥不反向 import L2）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../bridges/bridge_boot.dart' as bb;
import '../bridges/bridge_boot.dart' show KernelContext, Log;
import '../bridges/bridge_core.dart' as core;
import '../bridges/bridge_logic.dart' as lg;
import '../bridges/bridge_core.dart' as core;
import '../bridges/bridge_logic.dart' as lg;

/// init 层拿到的启动结果。
/// 批5-B：成功路径装配的 core 单例随结果上交，由 main（L1 依赖根，白名单）
/// 构造 SurfaceDeps 并调 surface.installServices —— L2 不得 import L6。
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

  /// 启动序列：签名清单校验 → kernel 装配 → core 单例装配 → 会话恢复。
  ///
  /// [rootDir]：存储根目录。TODO(时序说明)：L2 是纯 dart:io 层、禁 flutter，
  /// 无法调 path_provider。约定由 main（L1 特例，允许 import path_provider）
  /// 在 runApp 前先 `getApplicationSupportDirectory()` 拿目录，再传进本参数
  /// （见 init/main.dart）。未传时用 `.` 相对根兜底（仅 debug 可跑通）。
  static BootResult run(
      {bool bypassIntegrity = false, String? rootDir}) {
    Log.d('boot', 'bootstrap run (bypass=$bypassIntegrity)');
    final manifest = _loadManifest();
    final ok = bb.BootBridge.verifyIntegrity(manifest, bypass: bypassIntegrity);
    if (!ok) {
      // debug bypass 时 rejected=true 但 init 决定继续；release 直接拒绝
      return BootResult(rejected: true, kernel: null);
    }
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
    final client = core.KugouClient(core.KugouSession());
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

  static dynamic _loadManifest() {
    // 构建期由 tool/gen_manifest.dart 生成 assets/integrity/manifest.json
    try {
      return jsonDecode(
          File('assets/integrity/manifest.json').readAsStringSync());
    } catch (e, st) {
      Log.e('boot', 'manifest load failed', e, st);
      return null;
    }
  }
}

/// 由 surface 桥注入根组件构建器；L2 不得直接 import L6。
/// （批7-A 注：此 hook 已无赋值方，保留仅为向后兼容，下批可删。）
typedef WidgetBuilderHook = Object Function(BootResult result);
WidgetBuilderHook bootstrapWidgetHook = (r) =>
    throw UnimplementedError('surface bridge not installed');

// 批7-A：启动序列注册到 bridge_boot（L1 init 只经 runBoot 调本方法）。
final _registerRunBoot = () {
  bb.setRunBootImpl(
      ({bool bypassIntegrity = false, String? rootDir}) =>
          Bootstrap.run(bypassIntegrity: bypassIntegrity, rootDir: rootDir));
  return true;
}();
