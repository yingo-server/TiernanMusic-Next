// L5 logic/auth · 账号登录域状态机（二维码登录 / 会话恢复 / 登出）
// 知识来源：docs/KUGOU_API.md §3.8（login_qr_key / login_qr_check）。
// 注入：KugouClient（session 落点）+ KeyValueSettings（持久化）。
// 登录状态机（login_qr_check status 语义）：
//   0 expired（二维码过期，需重新 createQrLogin）
//   1 waitScan（已出码未扫码）
//   2 waitConfirm（已扫码，等待手机端确认）
//   4 success（data.token/data.userid 下发 → 落 session + 持久化）
//   （status 3 及其他未知值归为 waitScan 继续轮询，容错）
// 铁律：禁 surface/flutter；每方法 try/catch + Log('logic.auth')；
//   token 等敏感值不进日志（只打存在性与长度）。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart'
    as auth_ep
    show
        LoginResult,
        SmsLoginResult,
        loginByPwd,
        loginByToken,
        smsLogin,
        sendSmsCode,
        devLogout;
import '../../bridges/bridge_core.dart'
    show
        EndpointRegistry,
        KeyValueSettings,
        KugouApiException,
        KugouClient,
        KugouSession,
        KugouSign,
        Md5;

const String _tag = 'logic.auth';

/// 二维码轮询状态语义枚举（docs/KUGOU_API.md §3.8）。
enum QrLoginStatus { expired, waitScan, waitConfirm, success }

class QrLoginState {
  const QrLoginState({
    required this.status,
    this.qrcode = '',
    this.key = '',
    this.qrImageB64 = '',
  });
  final QrLoginStatus status;

  /// createQrLogin 返回的二维码内容（备用：官方扫码 URL 前缀，UI 可编码成 QR）。
  final String qrcode;

  /// 轮询 key（pollQrLogin 入参）。
  final String key;

  /// 实测 2026-11-13：/v2/qrcode 返回 data.qrcode_img（PNG base64，已含 key），
  /// UI 优先直接显示该官方图，避免自编码 QR 内容错误导致扫码失败。
  final String qrImageB64;
}

/// 持久化键（settings.json）。
const String kSettingToken = 'auth.token';
const String kSettingUserid = 'auth.userid';
const String kSettingMid = 'auth.mid';
const String kSettingDfid = 'auth.dfid';
// KUGOU_API_MID：§1.1 mid = cookie 中的 KUGOU_API_MID。
const String kSettingKugouApiMid = 'KUGOU_API_MID';
// C1 缺项：登录回写 vip_token/vip_type/t1（旧版 _afterLogin 对照）。
const String kSettingVipToken = 'auth.vip_token';
const String kSettingVipType = 'auth.vip_type';
const String kSettingT1 = 'auth.t1';

class AuthLogic {
  AuthLogic({required KugouClient client, required KeyValueSettings settings})
    : _client = client,
      _settings = settings {
    Log.d(_tag, 'init');
  }

  final KugouClient _client;
  final KeyValueSettings _settings;
  KugouSession get session => _client.session;

  // ── 1. 二维码登录 ──

  /// 申请二维码：loginQrKey（web 签名，§3.8 login_qr_key.js）。
  /// 参数 appid=1014(web)/1001(移动)、type=1、plat=4、qrcode_txt、srcappid=2919。
  /// 返回 {qrcode, key}；qrcode 供 UI 渲染，key 供 pollQrLogin 轮询。
  Future<QrLoginState> createQrLogin({String appid = '1001'}) async {
    try {
      // 上游 login_qr_key.js：qrcode_txt 是 h5 扫码页 URL（appid 与 check 一致），
      // 后端返回的 data.qrcode 是轮询 key；二维码内容须含该 key 才可扫码。
      final qrcodeTxt =
          'https://h5.kugou.com/apps/loginQRCode/html/index.html'
          '?appid=${Uri.encodeComponent(appid)}&';
      final res = await _client.request(
        EndpointRegistry.loginQrKey,
        <String, Object?>{
          'appid': appid,
          'type': '1',
          'plat': '4',
          'qrcode_txt': qrcodeTxt,
          'srcappid': KugouSign.srcappid,
        },
      );
      final data = res['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final key = '${map['qrcode'] ?? ''}';
      if (key.isEmpty) {
        Log.w(_tag, 'createQrLogin empty key status=${res['status']}');
        throw KugouApiException(0, 'empty qrcode key');
      }
      // 官方返回 qrcode_img（"data:image/png;base64,..."）：去掉 scheme 前缀留纯 base64。
      final img = '${map['qrcode_img'] ?? ''}';
      final b64 = img.contains('base64,') ? img.split('base64,').last : img;
      Log.d(_tag, 'createQrLogin ok keyLen=${key.length} imgLen=${b64.length}');
      return QrLoginState(
        status: QrLoginStatus.waitScan,
        qrcode: qrcodeTxt + key,
        key: key,
        qrImageB64: b64,
      );
    } catch (e, st) {
      Log.e(_tag, 'createQrLogin failed', e, st);
      rethrow;
    }
  }

  /// 轮询二维码：loginQrCheck（§3.8 login_qr_check.js）。
  /// status 0/1/2/4 → expired/waitScan/waitConfirm/success；
  /// success 时取 data.token/data.userid 落 session 并持久化。
  Future<QrLoginState> pollQrLogin(String key) async {
    try {
      if (key.isEmpty) {
        throw KugouApiException(0, 'pollQrLogin empty key');
      }
      final res = await _client.request(
        EndpointRegistry.loginQrCheck,
        <String, Object?>{'plat': '4', 'appid': '1001', 'qrcode': key},
      );
      // 实测 2026-11-13：顶层 status=1 是业务成功码；登录状态在 data.status。
      final data = res['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final status = int.tryParse('${map['status'] ?? 1}') ?? 1;
      switch (status) {
        case 0:
          Log.d(_tag, 'pollQrLogin expired keyLen=${key.length}');
          return const QrLoginState(status: QrLoginStatus.expired);
        case 2:
          Log.d(_tag, 'pollQrLogin waitConfirm');
          return const QrLoginState(status: QrLoginStatus.waitConfirm);
        case 4:
          final token = '${map['token'] ?? ''}';
          final userid = '${map['userid'] ?? ''}';
          if (token.isEmpty || userid.isEmpty) {
            Log.e(_tag, 'pollQrLogin success but empty token/userid');
            throw KugouApiException(0, 'success payload missing token/userid');
          }
          await _applyCredentials(token, userid, source: 'qr');
          Log.d(
            _tag,
            'pollQrLogin success tokenLen=${token.length} uid=$userid',
          );
          return QrLoginState(
            status: QrLoginStatus.success,
            qrcode: '',
            key: key,
          );
        default: // 1 及未知值 → 继续等
          Log.d(_tag, 'pollQrLogin status=$status (wait)');
          return const QrLoginState(status: QrLoginStatus.waitScan);
      }
    } catch (e, st) {
      Log.e(_tag, 'pollQrLogin failed', e, st);
      rethrow;
    }
  }

  // ── 2. 会话恢复 / 登出 ──

  /// 启动时从 KeyValueSettings 恢复 KugouSession（token/userid/mid/dfid/cookie）。
  /// 返回是否恢复出非空凭据。
  bool restoreSession() {
    try {
      final token = _settings.getString(kSettingToken) ?? '';
      final userid = _settings.getString(kSettingUserid) ?? '';
      final mid =
          _settings.getString(kSettingMid) ??
          _settings.getString(kSettingKugouApiMid) ??
          '';
      final dfid = _settings.getString(kSettingDfid) ?? '-';
      if (token.isEmpty || userid.isEmpty) {
        Log.d(_tag, 'restoreSession none (anonymous)');
        return false;
      }
      session
        ..token = token
        ..userid = userid
        ..mid = mid
        ..dfid = dfid;
      // cookie：t1 参与播放权限判定（FINDINGS.md），恢复存的原始 cookie 串。
      final cookieRaw = _settings.getString('auth.cookie');
      if (cookieRaw != null && cookieRaw.isNotEmpty) {
        for (final part in cookieRaw.split('; ')) {
          final i = part.indexOf('=');
          if (i > 0) {
            session.cookies[part.substring(0, i)] = part.substring(i + 1);
          }
        }
      }
      Log.d(
        _tag,
        'restoreSession ok uid=$userid tokenLen=${token.length} mid=${mid.isEmpty ? '-' : 'set'}',
      );
      _restoreVipExtras();
      // 自动续期钩子：存有 t1/t2/t3（此处以 t1 为哨兵）时先调 loginByToken
      // 刷新 token；失败静默降级继续用旧凭据（Log.w，不抛）。
      _tryRefreshToken();
      return true;
    } catch (e, st) {
      Log.e(_tag, 'restoreSession failed', e, st);
      return false;
    }
  }

  void _restoreVipExtras() {
    try {
      final vipToken = _settings.getString(kSettingVipToken) ?? '';
      final vipType = _settings.getString(kSettingVipType) ?? '';
      final t1 = _settings.getString(kSettingT1) ?? '';
      if (t1.isNotEmpty) {
        session.cookies['t1'] = t1;
      }
      Log.d(
        _tag,
        'restoreVipExtras vipTokenLen=${vipToken.length} '
        'vipType=$vipType t1Len=${t1.length}',
      );
    } catch (e, st) {
      Log.e(_tag, 'restoreVipExtras failed', e, st);
    }
  }

  void _tryRefreshToken() {
    try {
      final hasT1 = (session.cookies['t1'] ?? '').isNotEmpty;
      if (!hasT1) {
        Log.d(_tag, 'refresh skip (no t1)');
        return;
      }
      auth_ep
          .loginByToken(_client)
          .then((r) async {
            try {
              if (r.ok && r.token.isNotEmpty) {
                await _applyCredentials(
                  r.token,
                  r.userid,
                  source: 'tokenRenew',
                  vipToken: r.vipToken,
                  vipType: r.vipType,
                  t1: r.t1,
                );
                Log.d(_tag, 'refresh ok tokenLen=${r.token.length}');
              } else {
                // 失败静默降级：继续用旧凭据，仅 Log.w。
                Log.w(
                  _tag,
                  'refresh degraded err=${r.error} '
                  'needsProbe=${r.needsProbe}',
                );
              }
            } catch (e, st) {
              Log.e(_tag, 'refresh apply failed (degraded)', e, st);
            }
          })
          .catchError((e, st) {
            Log.w(_tag, 'refresh degraded (exception)');
          });
    } catch (e, st) {
      Log.e(_tag, '_tryRefreshToken failed (degraded)', e, st);
    }
  }

  // ── 3. 密码登录 / token 续期 / 设备登出门面 ──

  /// 密码登录门面（bridge_core → ep.auth.loginByPwd，端点待实测）。
  /// 参数校验 + 失败不静默吞（rethrow 语义失败给调用方 UI 提示）+ 脱敏 Log。
  Future<auth_ep.LoginResult> signInByPwd(
    String pwd, {
    String code = '',
  }) async {
    try {
      if (pwd.isEmpty) {
        throw KugouApiException(0, 'empty pwd');
      }
      final r = await auth_ep.loginByPwd(_client, pwd, code: code);
      if (r.ok) {
        await _applyCredentials(
          r.token,
          r.userid,
          source: 'pwd',
          vipToken: r.vipToken,
          vipType: r.vipType,
          t1: r.t1,
        );
      } else {
        // 失败不静默吞：把错误抛给调用方（needsProbe 也显式上报）。
        throw KugouApiException(0, r.error.isEmpty ? 'login failed' : r.error);
      }
      return r;
    } catch (e, st) {
      Log.e(_tag, 'signInByPwd failed', e, st);
      rethrow;
    }
  }

  /// 短信验证码登录门面（批2 收口：login_sheet 直接消费；端点待实测）。
  Future<auth_ep.SmsLoginResult> signInByVerifyCode(
    String mobile,
    String code,
  ) async {
    try {
      final r = await auth_ep.smsLogin(_client, mobile, code);
      if (r.ok) {
        await _applyCredentials(
          r.token,
          r.userid,
          source: 'sms',
          vipToken: r.vipToken,
          vipType: r.vipType,
          t1: r.t1,
        );
      }
      return r;
    } catch (e, st) {
      Log.e(_tag, 'signInByVerifyCode failed', e, st);
      rethrow;
    }
  }

  /// 发送短信验证码门面（60s 防重发由 UI 负责；端点待实测）。
  Future<bool> sendVerifyCode(String mobile) async {
    try {
      return await auth_ep.sendSmsCode(_client, mobile);
    } catch (e, st) {
      Log.e(_tag, 'sendVerifyCode failed', e, st);
      rethrow;
    }
  }

  /// token 续期门面（ep.auth.loginByToken，端点待实测）。
  Future<auth_ep.LoginResult> renewByToken() async {
    try {
      final r = await auth_ep.loginByToken(_client);
      if (r.ok) {
        await _applyCredentials(
          r.token,
          r.userid,
          source: 'token',
          vipToken: r.vipToken,
          vipType: r.vipType,
          t1: r.t1,
        );
      } else {
        throw KugouApiException(0, r.error.isEmpty ? 'renew failed' : r.error);
      }
      return r;
    } catch (e, st) {
      Log.e(_tag, 'renewByToken failed', e, st);
      rethrow;
    }
  }

  /// 设备登出门面：先调服务端 devLogout（失败不阻断本地登出，Log.w），
  /// 再清本地凭据（原 logout 语义不变）。
  Future<bool> signOut() async {
    try {
      final remote = await auth_ep.devLogout(_client);
      if (!remote) {
        Log.w(_tag, 'signOut remote devLogout failed (degraded to local)');
      }
    } catch (e, st) {
      Log.e(_tag, 'signOut devLogout failed (degraded)', e, st);
    }
    return logout();
  }

  /// 登出：清 session + settings。缓存失效由调用方执行，这里只清凭据。
  bool logout() {
    try {
      final uid = session.userid;
      session
        ..token = ''
        ..userid = ''
        ..cookies.clear();
      // mid/dfid/KUGOU_API_MID 也必须删：残留会让下次登录/restoreSession
      // 复用旧账号设备标识，且与 switchTo 的全量回写不一致。
      final ok =
          _settings.remove(kSettingToken) &
          _settings.remove(kSettingUserid) &
          _settings.remove(kSettingMid) &
          _settings.remove(kSettingDfid) &
          _settings.remove(kSettingKugouApiMid) &
          _settings.remove('auth.cookie') &
          _settings.remove(kSettingVipToken) &
          _settings.remove(kSettingVipType) &
          _settings.remove(kSettingT1);
      Log.d(_tag, 'logout uid=$uid settingsCleared=$ok');
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'logout failed', e, st);
      return false;
    }
  }

  // ── 内部：凭据落 session + 持久化 ──

  Future<void> _applyCredentials(
    String token,
    String userid, {
    required String source,
    String vipToken = '',
    String vipType = '',
    String t1 = '',
  }) async {
    // mid 若空，生成一次并持久化（KUGOU_API_MID，§1.1）。
    if (session.mid.isEmpty) {
      final stored =
          _settings.getString(kSettingMid) ??
          _settings.getString(kSettingKugouApiMid) ??
          '';
      session.mid = stored.isEmpty ? _generateMid() : stored;
    }
    session.token = token;
    session.userid = userid;
    // C1 必修#2：回写 vip_token/vip_type/t1（旧版 _afterLogin 缺项）——
    // /v6/priv_url 的 viptoken 参与与播放权限判定均依赖这三个值。
    if (t1.isNotEmpty) session.cookies['t1'] = t1;
    _settings
      ..setString(kSettingToken, token)
      ..setString(kSettingUserid, userid)
      ..setString(kSettingMid, session.mid)
      ..setString(kSettingKugouApiMid, session.mid)
      ..setString(kSettingDfid, session.dfid)
      ..setString(
        'auth.cookie',
        session.cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      )
      ..setString(kSettingVipToken, vipToken)
      ..setString(kSettingVipType, vipType)
      ..setString(kSettingT1, t1);
    Log.d(
      _tag,
      'credentials applied src=$source uid=$userid tokenLen=${token.length} '
      'mid=${session.mid.length} vipTokenLen=${vipToken.length} '
      'vipType=$vipType t1Len=${t1.length}',
    );
  }

  /// calculateMid（§1.1）：md5(随机源) hex。
  String _generateMid() {
    final src = 'tmn-${DateTime.now().microsecondsSinceEpoch}-${session.dfid}';
    return Md5.hex(src);
  }
}
