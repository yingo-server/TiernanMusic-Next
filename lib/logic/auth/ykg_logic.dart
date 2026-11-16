// L5 logic/auth · YKG 浏览器链接登录编排
//
// 职责边界（76 原则）：
//  - 密码学/报文：L4 core/net/ykg_codec.dart（本文件只调桥导出的方法）
//  - 凭据编排：本文件（无 Widget、无 IO 直连，全部经桥）
//  - 会话注入：L6 AuthSession（notify + client.session 由 AuthLogic.restoreSession 回填）
//  - UI/文案：L7 surface（导出按钮、密码弹层、风险提示）
//
// 纪律：算法用成熟库，自研仅封装与流程；token/cookie 不进日志（只打长度）。
library;

import '../../bridges/bridge_core.dart'
    show
        KugouClient,
        KeyValueSettings,
        encodeYkgLink,
        decodeYkgLink,
        YkgLinkResult,
        passwordVerifier,
        newYkgVerifier,
        kYkgScheme;
import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'logic.ykg';

// 与 AuthLogic 的 settings 键保持同一字面量（L5 内不 import 私有常量）。
const String _kToken = 'auth.token';
const String _kUserid = 'auth.userid';
const String _kMid = 'auth.mid';
const String _kDfid = 'auth.dfid';
const String _kCookie = 'auth.cookie';
const String _kVipToken = 'auth.vip_token';
const String _kVipType = 'auth.vip_type';
const String _kT1 = 'auth.t1';
const String _kYkgVerifier = 'auth.ykg_verifier';
const String _kYkgSalt = 'auth.ykg_salt';

/// YKG 编排门面（由 session/bootstrap 装配进 AppGraph）。
class YkgLogic {
  YkgLogic({
    required KugouClient client,
    required KeyValueSettings settings,
    required Object auth,
    void Function()? onImported,
  }) : _client = client,
       _settings = settings,
       _auth = auth,
       _onImported = onImported {
    Log.d(_tag, 'init');
  }

  final KugouClient _client;
  final KeyValueSettings _settings;
  // AuthLogic（经桥以 Object 传，避免 L5 内部循环依赖）；只用 restoreSession。
  final Object _auth;
  /// 导入成功后的通知回调（由 L6 注入；L5 不反向依赖 L6 AuthSession）。
  final void Function()? _onImported;

  /// 当前是否可导出（需已登录）。
  bool get canExport {
    try {
      final uid = _client.session.userid;
      return uid.isNotEmpty && uid != '0';
    } catch (e, st) {
      Log.e(_tag, 'canExport failed', e, st);
      return false;
    }
  }

  /// 导出凭据为 YKG 链接。未登录返回 null；口令为空抛 ArgumentError。
  Future<String?> exportLink({
    required String password,
    int ttlSec = 7 * 24 * 3600,
  }) async {
    try {
      if (!canExport) {
        Log.w(_tag, 'exportLink not logged in');
        return null;
      }
      if (password.isEmpty) {
        throw ArgumentError('password must not be empty');
      }
      final s = _client.session;
      final cookie = s.cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      final cred = <String, String>{
        'cookie': cookie,
        'token': s.token,
        'userid': s.userid,
        'mid': s.mid,
        'dfid': s.dfid,
        'vip_token': _settings.getString(_kVipToken) ?? '',
        'vip_type': _settings.getString(_kVipType) ?? '',
      };
      final link = await encodeYkgLink(
        credentials: cred,
        password: password,
        ttlSec: ttlSec,
      );
      // 保存口令校验值（不存明文），供重新导出时验证；salt 由 L4 CSPRNG 生成。
      try {
        final (saltB64, verifier) = await newYkgVerifier(password);
        _settings.setString(_kYkgSalt, saltB64);
        _settings.setString(_kYkgVerifier, verifier);
      } catch (e, st) {
        Log.w(_tag, 'export verifier persist skipped: $e');
      }
      Log.d(_tag, 'exportLink ok uid=${s.userid} len=${link.length}');
      return link;
    } catch (e, st) {
      Log.e(_tag, 'exportLink failed', e, st);
      rethrow;
    }
  }

  /// 校验重新导出时输入的口令是否与上次导出一致（未设置过返回 true）。
  Future<bool> verifyPassword(String password) async {
    try {
      final salt = _settings.getString(_kYkgSalt) ?? '';
      final verifier = _settings.getString(_kYkgVerifier) ?? '';
      if (salt.isEmpty || verifier.isEmpty) return true;
      final got = await passwordVerifier(password, salt);
      return got == verifier;
    } catch (e, st) {
      Log.w(_tag, 'verifyPassword failed: $e');
      return false;
    }
  }

  /// 导入：先验密码再解密，成功后把凭据落 settings 并恢复会话。
  /// 返回 (ok, message)；错误统一为非具体文案（避免 oracle）。
  Future<(bool, String)> importLink(String link, String password) async {
    try {
      final YkgLinkResult r = await decodeYkgLink(
        link,
        password: password,
      );
      if (!r.ok) {
        return (false, r.error ?? '');
      }
      final c = r.credentials!;
      final token = c['token'] ?? '';
      final userid = c['userid'] ?? '';
      if (token.isEmpty || userid.isEmpty) {
        return (false, 'invalid credentials');
      }
      _settings
        ..setString(_kToken, token)
        ..setString(_kUserid, userid)
        ..setString(_kMid, c['mid'] ?? '')
        ..setString(_kDfid, c['dfid'] ?? '')
        ..setString(_kCookie, c['cookie'] ?? '')
        ..setString(_kVipToken, c['vip_token'] ?? '')
        ..setString(_kVipType, c['vip_type'] ?? '');
      // 复用 AuthLogic.restoreSession 回填 client.session（不造第二套写入路径）。
      try {
        (_auth as dynamic).restoreSession();
      } catch (e, st) {
        Log.w(_tag, 'restoreSession after import failed: $e');
      }
      // 通知 L6（由 bootstrap 注入 AuthSession.notifyAuthChanged；L5 不反向依赖）。
      try {
        _onImported?.call();
      } catch (e, st) {
        Log.w(_tag, 'onImported callback failed: $e');
      }
      Log.d(_tag, 'importLink ok uid=$userid tokenLen=${token.length}');
      return (true, '');
    } catch (e, st) {
      Log.e(_tag, 'importLink failed', e, st);
      return (false, '');
    }
  }

  /// 链接是否为本协议（供 UI 粘贴校验）。
  bool isYkgLink(String text) => text.trim().startsWith(kYkgScheme);
}
