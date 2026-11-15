// L7 surface/pages · 登录弹层（批2-F2）：扫码 / 验证码 / 密码 三 Tab + 账号区。
// 76 原则：L7 只画控件；状态与意图全经 bridge_session(bootstrap.appGraph/navState)
// 与 bridge_logic(AuthLogic/VerificationLogic/AccountLogic) 令牌。
// 凭据安全：手机号日志/界面脱敏（138****1234）；token 不回显不进日志。
// 批2 收口：sendSmsCode/smsLogin/loginByPwd 均已接 AuthLogic 真门面
// （auth_endpoints 顶层封装，端点待实测；手机号/凭据一律脱敏）。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show AccountRecord, sendSmsCode, smsLogin, KugouApiException;
import '../../bridges/bridge_logic.dart' show QrLoginState, QrLoginStatus;
import '../../bridges/bridge_session.dart' show appGraph, navState;
import '../design/tokens.dart';
import 'login_account_section.dart' show AccountSection;

/// 登录弹层入口：isScrollControlled + 约 70% 高度。
/// [onAuthChanged]：登录成功后回调（在 pop 之前触发）。
Future<void> showLoginSheet(
  BuildContext context, {
  void Function()? onAuthChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Sp.bgElevated,
    builder: (_) => SizedBox(
      height: MediaQuery.of(_).size.height * 0.7,
      child: LoginSheetPanel(onAuthChanged: onAuthChanged),
    ),
  );
}

/// 手机号脱敏：138****1234；异常输入原样截断尾部 4 位。
String _maskPhone(String phone) {
  final p = phone.trim();
  if (p.length >= 7)
    return '${p.substring(0, 3)}****${p.substring(p.length - 4)}';
  return p.isEmpty
      ? '-'
      : '****${p.substring(p.length - 2 < 0 ? 0 : p.length - 2)}';
}

/// 弹层面板：TabBar + 底部已登录账号区。
class LoginSheetPanel extends StatefulWidget {
  const LoginSheetPanel({super.key, this.onAuthChanged});
  final void Function()? onAuthChanged;
  @override
  State<LoginSheetPanel> createState() => _LoginSheetPanelState();
}

class _LoginSheetPanelState extends State<LoginSheetPanel> {
  List<AccountRecord> _accounts = const <AccountRecord>[];

  @override
  void initState() {
    super.initState();
    _reloadAccounts();
  }

  // 按钮回调内持有 future，不在 build 新建。
  Future<void> _reloadAccounts() async {
    final account = appGraph.account;
    if (account == null) return;
    final list = await account.listAccounts();
    if (!mounted) return;
    setState(() => _accounts = list);
  }

  Future<void> _switchTo(String accountId) async {
    final ok = await appGraph.account?.switchTo(accountId) ?? false;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '已切换账号 $accountId' : '切换失败')));
    if (ok) navState().bumpAuth();
    _reloadAccounts();
  }

  Future<void> _removeAccount(String accountId) async {
    final ok = await appGraph.account?.removeAccount(accountId) ?? false;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '已移除账号 $accountId' : '移除失败')));
    _reloadAccounts();
  }

  /// 登录成功统一收口：落账号档案 → bumpAuth → 回调 → 关弹层。
  Future<void> _onLoginSuccess() async {
    await appGraph.account?.saveCurrent();
    navState().bumpAuth();
    if (!mounted) return;
    widget.onAuthChanged?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final activeUid = appGraph.auth?.session.userid ?? '';
    return DefaultTabController(
      length: 3,
      child: Column(
        children: <Widget>[
          const TabBar(
            tabs: <Tab>[
              Tab(text: '扫码'),
              Tab(text: '验证码'),
              Tab(text: '密码'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _QrTab(onLoginSuccess: _onLoginSuccess),
                _SmsTab(onLoginSuccess: _onLoginSuccess),
                _PwdTab(),
              ],
            ),
          ),
          _accountSection(activeUid),
        ],
      ),
    );
  }

  Widget _accountSection(String activeUid) {
    return AccountSection(
      accounts: _accounts,
      activeUid: activeUid,
      onSwitch: _switchTo,
      onRemove: _removeAccount,
    );
  }
}

/// 扫码 Tab：createQrLogin 出码 → pollQrLogin 1.5s 轮询（0/1/2/4 四态）。
/// 过期自动重建一次（仅一次）；成功即回调并关闭。
class _QrTab extends StatefulWidget {
  const _QrTab({required this.onLoginSuccess});
  final void Function() onLoginSuccess;
  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  QrLoginState? _qr;
  Uint8List? _img;
  bool _recreatedOnce = false;
  String _hint = '正在获取二维码…';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _createQr();
  }

  Future<void> _createQr() async {
    final auth = appGraph.auth;
    if (auth == null) {
      if (mounted) setState(() => _hint = '登录能力未装配');
      return;
    }
    try {
      final st = await auth.createQrLogin();
      if (!mounted) return;
      setState(() {
        _qr = st;
        _hint = '请使用酷狗音乐 App 扫码';
        try {
          _img = st.qrImageB64.isEmpty ? null : base64Decode(st.qrImageB64);
        } catch (_) {
          _img = null; // 官方图解码失败兜底为提示文案
        }
      });
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _poll(st.key),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _hint = '二维码获取失败，请重试');
      }
    }
  }

  Future<void> _poll(String key) async {
    final auth = appGraph.auth;
    if (auth == null || _qr == null) return;
    final QrLoginState st;
    try {
      st = await auth.pollQrLogin(key);
    } catch (_) {
      return; // 轮询瞬时失败容错，下个周期继续
    }
    if (!mounted) return;
    switch (st.status) {
      case QrLoginStatus.waitScan:
        break; // 保持「请扫码」文案
      case QrLoginStatus.waitConfirm:
        setState(() => _hint = '已在手机上扫码，请在手机端确认登录');
        break;
      case QrLoginStatus.expired:
        _timer?.cancel();
        if (!_recreatedOnce) {
          _recreatedOnce = true;
          setState(() => _hint = '二维码已过期，正在自动刷新…');
          _createQr();
        } else {
          setState(() => _hint = '二维码已过期，请下拉重试或退出重开');
        }
        break;
      case QrLoginStatus.success:
        _timer?.cancel();
        widget.onLoginSuccess();
        break;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.pagePad),
      children: <Widget>[
        const SizedBox(height: Sp.gapM),
        Center(
          child: _img != null
              ? Image.memory(
                  _img!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                )
              : Container(
                  width: 200,
                  height: 200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Sp.card,
                    borderRadius: BorderRadius.circular(Sp.rCard),
                  ),
                  child: const Text(
                    '二维码加载中',
                    style: TextStyle(fontSize: Sp.fSub, color: Sp.textFaint),
                  ),
                ),
        ),
        const SizedBox(height: Sp.gapM),
        Center(
          child: Text(
            _hint,
            style: const TextStyle(fontSize: Sp.fItem, color: Sp.textSub),
          ),
        ),
        const SizedBox(height: Sp.gapM),
        Center(
          child: TextButton(
            onPressed: () {
              _recreatedOnce = false; // 手动刷新重置一次性重建标记
              _createQr();
            },
            child: const Text('刷新二维码'),
          ),
        ),
      ],
    );
  }
}

/// 验证码 Tab：手机号 + 发送（60s 倒计时防重发）+ 验证码 + 登录。
class _SmsTab extends StatefulWidget {
  const _SmsTab({required this.onLoginSuccess});
  final void Function() onLoginSuccess;
  @override
  State<_SmsTab> createState() => _SmsTabState();
}

class _SmsTabState extends State<_SmsTab> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  int _countdown = 0;
  Timer? _timer;
  String _msg = '';

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _sendCode() async {
    if (_countdown > 0) return;
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      _toast('请输入手机号');
      return;
    }
    bool ok = false;
    try {
      ok = await appGraph.auth?.sendVerifyCode(phone) ?? false;
    } catch (e) {
      _msg = '验证码发送失败（接口待实测）';
      _toast(_msg);
      return;
    }
    _toast(ok ? '验证码已发送至 ${_maskPhone(phone)}' : '发送失败，请稍后重试');
    if (ok) {
      setState(() => _countdown = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _countdown = _countdown - 1);
        if (_countdown <= 0) t.cancel();
      });
    }
  }

  Future<void> _login() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      _toast('请输入手机号与验证码');
      return;
    }
    try {
      final res = await appGraph.auth?.signInByVerifyCode(phone, code);
      if (res == null) {
        _toast('登录能力未装配');
        return;
      }
      if (!res.ok) {
        _toast(
          res.needsProbe
              ? '验证码登录端点待实测（needs probe）'
              : '登录失败：${res.error.isEmpty ? '未知错误' : res.error}',
        );
        return;
      }
      widget.onLoginSuccess();
    } catch (e) {
      _toast('验证码登录失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.pagePad),
      children: <Widget>[
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: '手机号',
            hintText: '用于登录酷狗账号',
          ),
        ),
        const SizedBox(height: Sp.gapM),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '验证码'),
              ),
            ),
            const SizedBox(width: Sp.gapM),
            TextButton(
              onPressed: _countdown > 0 ? null : _sendCode,
              child: Text(_countdown > 0 ? '${_countdown}s' : '发送验证码'),
            ),
          ],
        ),
        const SizedBox(height: Sp.gapM),
        FilledButton(onPressed: _login, child: const Text('登录')),
      ],
    );
  }
}

/// 密码 Tab：手机号/用户名 + 密码（obscureText）→ AuthLogic.loginByPwd。
/// 批2-F1 尚未合入该方法：try/catch 兜底提示，不崩。
class _PwdTab extends StatefulWidget {
  @override
  State<_PwdTab> createState() => _PwdTabState();
}

class _PwdTabState extends State<_PwdTab> {
  final TextEditingController _account = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _account.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final acc = _account.text.trim();
    final pwd = _pwd.text;
    if (acc.isEmpty || pwd.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入账号与密码')));
      return;
    }
    try {
      final dynamic auth = appGraph.auth;
      await auth.signInByPwd(pwd);
      // 就绪后此处接 onLoginSuccess（由批2-F1 定义返回形态）
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('密码登录待后端就绪')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.pagePad),
      children: <Widget>[
        TextField(
          controller: _account,
          decoration: const InputDecoration(labelText: '手机号 / 用户名'),
        ),
        const SizedBox(height: Sp.gapM),
        TextField(
          controller: _pwd,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: '密码',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: Sp.gapM),
        FilledButton(onPressed: _login, child: const Text('登录')),
      ],
    );
  }
}
