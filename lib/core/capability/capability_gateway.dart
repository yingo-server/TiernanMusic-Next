// L4 core/capability · 能力与权限网关（平台无关语义模型）
//
// 契约（docs/UI_REWRITE_PLAN.md §3）：
// - 移动端有运行时权限（Android 13+ 通知等），需「请求→拒绝→永久拒绝→去设置」；
// - 桌面端无运行时权限，但有「文件系统作用域」（用户选目录后才可访问）与网络；
// - Web 有浏览器权限模型（通知需授权、剪贴板需用户手势）。
// 这些分叉**不得**泄漏到 logic/surface：统一经本网关。
//
// 分层：L4 core 定义平台无关的接口与状态；平台实现放在 lib/platform/**，
// 由本目录经条件导入选择。logic/surface 只经 bridge_core 拿门面。
library;

/// 能力授权状态。
enum CapStatus {
  /// 已授权。
  granted,

  /// 未授权（可再次请求）。
  denied,

  /// 永久拒绝（需引导去系统设置）。
  permanentlyDenied,

  /// 受限（策略/系统禁止，无法请求）。
  restricted,

  /// 该平台不支持此能力。
  unsupported,
}

/// 能力标识。
class CapId {
  const CapId._();

  /// 桌面/移动通知。
  static const String notification = 'notification';

  /// 文件读取（桌面为用户选定作用域，移动为系统选择器）。
  static const String fileRead = 'fileRead';

  /// 文件写入（下载目录等）。
  static const String fileWrite = 'fileWrite';

  /// 剪贴板读写（Web 写需用户手势）。
  static const String clipboard = 'clipboard';

  /// 网络访问（各平台均可用；桌面可能受防火墙影响）。
  static const String network = 'network';

  /// 本地存储目录（桌面为用户目录，移动为沙盒）。
  static const String storage = 'storage';

  /// 媒体会话/媒体键（锁屏、耳机按键、桌面全局快捷键）。
  static const String mediaKeys = 'mediaKeys';

  /// 外部链接跳转（浏览器/系统）。
  static const String openExternal = 'openExternal';
}

/// 一次能力查询结果。
class CapState {
  const CapState({
    required this.id,
    required this.status,
    this.reason,
    this.grantedAt,
  });

  final String id;
  final CapStatus status;

  /// 面向用户的原因说明（拒绝/受限时展示；由 L7 做 i18n，core 只给语义键）。
  final String? reason;

  final DateTime? grantedAt;

  bool get isGranted => status == CapStatus.granted;

  /// 是否可再次弹出系统授权流程。
  bool get canRequest =>
      status == CapStatus.denied || status == CapStatus.granted;

  /// 是否需要引导用户去系统设置。
  bool get needsSettings => status == CapStatus.permanentlyDenied;
}

/// 能力网关（平台无关接口）。
abstract class CapabilityGateway {
  /// 查询当前状态（不触发系统弹窗）。
  Future<CapState> status(String capId);

  /// 请求授权（触发系统流程）。
  Future<CapState> request(String capId);

  /// 打开系统设置页（永久拒绝时引导）。不支持的平台返回 false。
  Future<bool> openSettings();

  /// 监听某能力的状态变化（如用户从系统设置里改回来）。
  Stream<CapState> watch(String capId);
}

/// 内存实现（测试与不支持平台的降级）。
class InMemoryCapabilityGateway implements CapabilityGateway {
  InMemoryCapabilityGateway({Map<String, CapStatus>? initial})
    : _states = <String, CapStatus>{...?initial};

  final Map<String, CapStatus> _states;

  @override
  Future<CapState> status(String capId) async => CapState(
    id: capId,
    status: _states[capId] ?? CapStatus.unsupported,
  );

  @override
  Future<CapState> request(String capId) async {
    final s = _states[capId] ?? CapStatus.denied;
    _states[capId] = s == CapStatus.granted ? CapStatus.granted : CapStatus.denied;
    return CapState(id: capId, status: _states[capId]!);
  }

  @override
  Future<bool> openSettings() async => false;

  @override
  Stream<CapState> watch(String capId) => const Stream<CapState>.empty();
}
