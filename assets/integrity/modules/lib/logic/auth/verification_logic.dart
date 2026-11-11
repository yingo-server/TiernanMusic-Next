// L5 logic/auth · 20028 人机验证单一门面（功能对齐批5-A）
// 收敛语义（docs/PARITY_NOTES.md §3、FEATURE_PARITY.md S-2）：
//   旧项目 20028 存在三套平行实现（auth_repository / verification_service /
//   captcha_types），语义不一致。本项目 **唯一可信验证入口是 VerificationLogic**：
//   禁止在 auth_repository / playback_service 再各写一套；auth/surface 只消费
//   本类状态机（VerificationState），不得自行解析 errcode 20028。
// 注入：KugouClient + KeyValueSettings。
// 铁律：禁 surface/flutter 直连；每方法 try/catch + Log('logic.verification')；
//   ssaCode 等验证留痕不进日志明文（只打长度/存在性）。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show KeyValueSettings, KugouClient;

const String _tag = 'logic.verification';

/// 验证状态机（单一语义源）。
enum VerificationState { idle, required, solving, solved, failed }

/// 20028 验证单例门面。
/// errcode==20028 时由各链路（播放/评论/登录）经 onVerificationRequired 进入，
/// state 变为 required；surface 驱动 TCaptcha/验证 UI 后 submitVerification；
/// 全链路只有本类改 state。
class VerificationLogic {
  VerificationLogic({
    required KugouClient client,
    required KeyValueSettings settings,
  })  : _client = client,
        _settings = settings {
    Log.d(_tag, 'init');
  }

  final KugouClient _client;
  final KeyValueSettings _settings;

  VerificationState _state = VerificationState.idle;
  String _ssaCode = '';

  /// 当前验证状态（surface 唯一读取口）。
  VerificationState get state => _state;

  /// 最近一次 20028 留痕的 ssaCode（未设置时为空串）。
  String get ssaCode => _ssaCode;

  /// 20028 进入点：仅 errcode==20028 才置 required 并记录 ssaCode 留痕；
  /// 其他 errcode 不接管（返回 false，调用方自行按各自语义处理）。
  bool onVerificationRequired(int errcode, String ssaCode) {
    try {
      if (errcode != 20028) {
        Log.d(_tag, 'onVerificationRequired ignore errcode=$errcode');
        return false;
      }
      _state = VerificationState.required;
      _ssaCode = ssaCode;
      Log.d(_tag,
          'onVerificationRequired state=required ssaLen=${ssaCode.length}');
      return true;
    } catch (e, st) {
      Log.e(_tag, 'onVerificationRequired failed', e, st);
      return false;
    }
  }

  /// 拉取验证信息（get/verify/info，FEATURE_PARITY.md：v_type 分发回填重试）。
  /// ⚠️ 端点未实测（docs 零留样：路径/参数/响应 v_type 语义均未知）：
  /// 不猜参数结构、不发网络请求，Log.w 标注 needs probe 并返回 false。
  Future<bool> getVerifyInfo() async {
    try {
      if (_state != VerificationState.required &&
          _state != VerificationState.solving) {
        Log.w(_tag, 'getVerifyInfo invalid state=$_state');
        return false;
      }
      Log.w(_tag,
          'getVerifyInfo needs probe: get/verify/info 端点 docs 零留样，'
          '返回 false（不发网络请求、不猜参数结构）');
      return false;
    } catch (e, st) {
      Log.e(_tag, 'getVerifyInfo failed', e, st);
      return false;
    }
  }

  /// 提交验证结果（TCaptcha 桥接捕获 ssaCode 后回填重试）。
  /// ⚠️ 提交端点未实测：预留接口，payload 校验通过即置 solving（UI 可感知），
  /// 但不外发网络请求；实测后在此接提交端点 + 自动重试原请求。
  Future<bool> submitVerification(Map<String, Object?> payload) async {
    try {
      if (_state != VerificationState.required) {
        Log.w(_tag, 'submitVerification invalid state=$_state');
        return false;
      }
      if (payload.isEmpty) {
        Log.w(_tag, 'submitVerification empty payload');
        return false;
      }
      Log.w(_tag,
          'submitVerification needs probe: 提交端点未实测，'
          '预留不提交，置 solving 供 UI 感知');
      _state = VerificationState.solving;
      return false;
    } catch (e, st) {
      Log.e(_tag, 'submitVerification failed', e, st);
      _state = VerificationState.failed;
      return false;
    }
  }

  /// 验证通过（端点闭环后由提交链路调用）：required/solving → solved。
  void markSolved() {
    try {
      _state = VerificationState.solved;
      Log.d(_tag, 'markSolved');
    } catch (e, st) {
      Log.e(_tag, 'markSolved failed', e, st);
    }
  }

  /// 重置回 idle（验证失败或过期后调用），清除 ssaCode 留痕。
  void reset() {
    try {
      _state = VerificationState.idle;
      _ssaCode = '';
      Log.d(_tag, 'reset');
    } catch (e, st) {
      Log.e(_tag, 'reset failed', e, st);
    }
  }
}
