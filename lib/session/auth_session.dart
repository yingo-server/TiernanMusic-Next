// L6 session · 登录态会话（批2-F3）。
// 职责：向消费页暴露 isLoggedIn / userid 快照 + onAuthChanged 订阅。
// 数据源：经 bridge_core 门面取 KugouClient（构造注入；bootloader 装配）。
// ⚠️ 批2-F2 的 NavState.bumpAuth 未落盘（2026-11-15 检查无此 API）——
//    本类不臆造监听机制，仅维护回调注册表；F2 落盘后在此接 NavState 订阅。
import '../bridges/bridge_core.dart' show KugouClient;
import '../bridges/bridge_kernel.dart' show Log;

const String _tag = 'session.auth';

class AuthSession {
  AuthSession._();
  static final AuthSession instance = AuthSession._();

  KugouClient? _client;
  final List<void Function()> _listeners = <void Function()>[];

  /// bootloader 装配时注入（client 由 L4 core 构造，session 只持有引用）。
  void attach(KugouClient? client) {
    try {
      _client = client;
      Log.d(_tag, 'attached=${client != null}');
    } catch (e, st) {
      Log.e(_tag, 'attach failed', e, st);
    }
  }

  /// 登录态快照：userid 非空且非 '0' 视为已登录（对齐旧版判定）。
  bool get isLoggedIn {
    try {
      final String uid = userid;
      return uid.isNotEmpty && uid != '0';
    } catch (e, st) {
      Log.e(_tag, 'isLoggedIn read failed', e, st);
      return false;
    }
  }

  /// 当前 userid（client 未注入或 session 异常时返回空串，不抛）。
  String get userid {
    try {
      return _client?.session.userid ?? '';
    } catch (e, st) {
      Log.e(_tag, 'userid read failed', e, st);
      return '';
    }
  }

  /// 订阅登录态变化（回调在通知方线程同步执行，消费方自行调度 UI）。
  void onAuthChanged(void Function() cb) {
    try {
      // TODO(批2-F2): NavState.bumpAuth 落盘后改为监听 NavState.instance
      // 的 bumpAuth 通知；当前仅本地注册，无触发源（不臆造现有 API 之外的通知）。
      _listeners.add(cb);
      Log.d(_tag, 'onAuthChanged add, total=${_listeners.length}');
    } catch (e, st) {
      Log.e(_tag, 'onAuthChanged failed', e, st);
    }
  }

  void offAuthChanged(void Function() cb) {
    try {
      _listeners.remove(cb);
      Log.d(_tag, 'onAuthChanged remove, total=${_listeners.length}');
    } catch (e, st) {
      Log.e(_tag, 'offAuthChanged failed', e, st);
    }
  }

  /// 内部通知入口（F2 落盘前仅供 login/logout 流程手动调用，供测试与
  /// AuthLogic 后续接线；外部勿在未变更时乱调）。
  void notifyAuthChanged() {
    try {
      for (final l in List<void Function()>.of(_listeners)) {
        try {
          l();
        } catch (e, st) {
          Log.e(_tag, 'auth listener failed', e, st);
        }
      }
    } catch (e, st) {
      Log.e(_tag, 'notifyAuthChanged failed', e, st);
    }
  }
}
