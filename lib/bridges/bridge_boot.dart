// 五桥 · 每桥只暴露其下层的门面；桥函数统一 try/catch + Log 留痕。
// L2 可用：bridge_boot.dart（暴露 kernel 门面）
library;

import '../kernel/kernel.dart' as k;

export '../kernel/kernel.dart' show Kernel, KernelContext, Log;

class BootBridge {
  BootBridge._();

  /// bootloader 暴露给 init 的唯一入口。
  static k.KernelContext assemble() {
    try {
      return k.Kernel.assemble();
    } catch (e, st) {
      k.Log.e('bridge_boot', 'assemble failed', e, st);
      rethrow;
    }
  }
  // verifyIntegrity 已删除（运行期完整性校验移除，见 bootloader.dart 头注释）。
}

/// 启动结果的类型化契约（公开导出给 init 层；消除审计 B F-04 的 duck typing）。
/// 桥不能反向 import L2，故由 [BootOutcome.fromAny] 在唯一收口处把 L2 的
/// BootResult 或失败 Map 归一化为本类型；init 层只依赖本类型与 [deps] 的具名键。
class BootOutcome {
  BootOutcome._(this.rejected, this.error, this.detail, this.deps);

  /// true = 启动被拒/异常；[error] / [detail] 携带可见原因。
  final bool rejected;
  final String error;
  final String detail;

  /// 具名依赖：client / songDao / playlistDao / historyDao /
  /// downloadStore / settings / paths；另含保留键 '__raw'（归一化前的原始
  /// L2 结果，供既有桥函数 bootstrapApp 原样消费，不改桥业务逻辑）。
  final Map<String, Object?> deps;

  /// init 取依赖的唯一出口：Map 取值，返回 dynamic 以兼容既有桥构造参数类型。
  dynamic dep(String key) => deps[key];

  /// 把 L2 的 BootResult 或失败 Map 归一化。桥无法 import L2 类型，成功路径的
  /// 动态字段探测只发生在此处，并由 try/catch + Log 兜底（失败即 rejected）。
  static BootOutcome fromAny(Object? any) {
    try {
      if (any is BootOutcome) return any;
      if (any is Map) {
        final deps = <String, Object?>{};
        any.forEach((key, value) {
          if (key is String) deps[key] = value;
        });
        final rejected = any['rejected'] == true;
        deps['__raw'] = any;
        return BootOutcome._(
          rejected,
          (any['error'] ?? (rejected ? 'boot failed' : '')).toString(),
          (any['detail'] ?? '').toString(),
          deps,
        );
      }
      // 成功路径：L2 BootResult。逐字段动态读取（唯一允许的收口点）。
      final d = any as dynamic;
      return BootOutcome._(false, '', '', <String, Object?>{
        'client': d.client,
        'songDao': d.songDao,
        'playlistDao': d.playlistDao,
        'historyDao': d.historyDao,
        'downloadStore': d.downloadStore,
        'settings': d.settings,
        'paths': d.paths,
        '__raw': any,
      });
    } catch (e, st) {
      k.Log.e('bridge_boot', 'BootOutcome.fromAny failed', e, st);
      return BootOutcome._(
        true,
        'BootOutcome.fromAny failed',
        e.toString(),
        <String, Object?>{'rejected': true},
      );
    }
  }
}

/// init 层拿到的启动失败结果（仅失败路径）：桥无法反向 import L2，
/// 故用 Map 传递失败原因，由 init 层渲染错误页（真实异常不被吞）。
Map<String, Object?> bootFailure(String reason, Object? error) => <String, Object?>{
      'rejected': true,
      'kernel': null,
      'error': reason,
      'detail': error?.toString() ?? '',
    };

/// init 层唯一启动入口包装：转调 bootloader.Bootstrap.run（L1 禁直连 L2）。
/// try/catch + Log 留痕；任何返回值都经 [BootOutcome.fromAny] 归一化，
/// 使 init 层不再面对 dynamic 的 BootResult（见审计 B F-04）。
BootOutcome runBoot(
  {bool bypassIntegrity = false,
  String? rootDir,
  dynamic manifest,
  Map<String, List<int>>? moduleBytes}) {
  try {
    return BootOutcome.fromAny(runBootImpl(
        bypassIntegrity: bypassIntegrity,
        rootDir: rootDir,
        manifest: manifest,
        moduleBytes: moduleBytes));
  } catch (e, st) {
    k.Log.e('bridge_boot', 'runBoot failed', e, st);
    return BootOutcome.fromAny(bootFailure('runBoot failed', e));
  }
}

/// 由 bootloader 在装配时经桥注册的实现（避免桥反向 import L2）。
dynamic Function({
  bool bypassIntegrity,
  String? rootDir,
  dynamic manifest,
  Map<String, List<int>>? moduleBytes
})? _runBootImpl;
void setRunBootImpl(
    dynamic Function({
      bool bypassIntegrity,
      String? rootDir,
      dynamic manifest,
      Map<String, List<int>>? moduleBytes
    }) impl) {
  try {
    _runBootImpl = impl;
    k.Log.d('bridge_boot', 'runBoot impl installed');
  } catch (e, st) {
    k.Log.e('bridge_boot', 'setRunBootImpl failed', e, st);
  }
}

/// 零副作用安装自检（register.dart 用）：桥已持有真实 impl 则为 true。
bool get bootBridgeReady => _runBootImpl != null;

dynamic runBootImpl(
    {bool bypassIntegrity = false,
    String? rootDir,
    dynamic manifest,
    Map<String, List<int>>? moduleBytes}) {
  try {
    final impl = _runBootImpl;
    if (impl == null) {
      throw StateError('runBoot impl not installed (bootloader must register)');
    }
    return impl(
        bypassIntegrity: bypassIntegrity,
        rootDir: rootDir,
        manifest: manifest,
        moduleBytes: moduleBytes);
  } catch (e, st) {
    k.Log.e('bridge_boot', 'runBootImpl failed', e, st);
    return bootFailure('runBootImpl failed', e);
  }
}
