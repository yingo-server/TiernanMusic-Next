// L7 surface/pages · 登录弹层（批2-F2）：扫码 / 验证码 / 密码 三 Tab + YKG 入口 + 账号区。
//
// 76 原则：L7 只画控件；状态与意图全经 bridge_session(bootstrap.appGraph/navState)
// 与 bridge_logic(AuthLogic/AccountLogic) 令牌。
// 铁律：只用官方 Material 3 控件；不手写控件类（弹层本身为唯一页面容器，
// 各 Tab 内容均内联为方法 + 官方控件组合）；颜色只来自语义 token。
// 凭据安全：手机号日志/界面脱敏（138****1234）；token 不回显不进日志。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show AccountRecord;
import '../../bridges/bridge_logic.dart' show Log, QrLoginState, QrLoginStatus;
import '../../bridges/bridge_session.dart' show appGraph, navState, AuthSession;
import '../design/tokens_v2.dart';
import '../l10n/s.dart' show S;
import 'login_account_section.dart'
    show AccountEntry, buildAccountEntries, accountSubtitle;
import 'ykg_sheet.dart' show showYkgExport, showYkgImport;

/// 登录弹层入口：isScrollControlled + 约 70% 高度。
/// [onAuthChanged]：登录成功后回调（在 pop 之前触发）。
Future<void> showLoginSheet(
  BuildContext context, {
  void Function()? onAuthChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => SizedBox(
      height: MediaQuery.sizeOf(c).size.height * 0.7,
      child: LoginSheetPanel(onAuthChanged: onAuthChanged),
    ),
  );
}

/// 手机号脱敏：138****1234；异常输入原样截断尾部 4 位。
String _maskPhone(String phone) {
  final p = phone.trim();
  if (p.length >= 7) {
    return '${p.substring(0, 3)}****${p.substring(p.length - 4)}';
  }
  return p.isEmpty
      ? '-'
      : '****${p.substring(p.length - 2 < 0 ? 0 : p.length - 2)}';
}

/// 弹层面板：TabBar + Tab 内容 + 底部已登录账号区。
class LoginSheetPanel extends StatefulWidget {
  const LoginSheetPanel({super.key, this.onAuthChanged});
  final void Function()? onAuthChanged;
  @override
  State<LoginSheetPanel> createState() => _LoginSheetPanelState();
}

class _LoginSheetPanelState extends State<LoginSheetPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  // 账号区
  List<AccountRecord> _accounts = const <AccountRecord>[];

  // 扫码 Tab
  QrLoginState? _qr;
  Uint8List? _qrImg;
  bool _qrRecreatedOnce = false;
  String _qrHint = '正在获取二维码…';
  Timer? _qrTimer;

  // 验证码 Tab
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  int _countdown = 0;
  Timer? _smsTimer;

  // 密码 Tab
  final TextEditingController _pwdAccount = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  bool _pwdObscure = true;

  @override
  void initState() {
    super.initState();
    _reloadAccounts();
    _createQr();
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _smsTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    _pwdAccount.dispose();
    _pwd.dispose();
    _tabs.dispose();
    super.dispose();
  }

  // 按钮回调内持有 future，不在 build 新建。
  Future<void> _reloadAccounts() async {
    try {
      final account = appGraph.account;
      if (account == null) return;
      final list = await account.listAccounts();
      if (!mounted) return;
      setState(() => _accounts = list);
    } catch (e, st) {
      Log.e('surface.login', 'load accounts failed', e, st);
    }
  }

  Future<void> _switchTo(String accountId) async {
    try {
      final ok = await appGraph.account?.switchTo(accountId) ?? false;
      if (!mounted) return;
      _toast(ok ? '已切换账号 $accountId' : '切换失败');
      if (ok) navState().bumpAuth();
      _reloadAccounts();
    } catch (e, st) {
      Log.e('surface.login', 'switch account failed', e, st);
    }
  }

  Future<void> _removeAccount(String accountId) async {
    try {
      final ok = await appGraph.account?.removeAccount(accountId) ?? false;
      if (!mounted) return;
      _toast(ok ? '已移除账号 $accountId' : '移除失败');
      _reloadAccounts();
    } catch (e, st) {
      Log.e('surface.login', 'remove account failed', e, st);
    }
  }

  /// 登录成功统一收口：落账号档案 → bumpAuth → 广播登录态 → 回调 → 关弹层。
  Future<void> _onLoginSuccess() async {
    try {
      await appGraph.account?.saveCurrent();
    } catch (e, st) {
      Log.e('surface.login', 'save account failed', e, st);
    }
    navState().bumpAuth();
    // 审查修复（阶段B B5）：广播登录态，触发换号重置（收藏镜像/缓存前缀）。
    AuthSession.instance.notifyAuthChanged();
    if (!mounted) return;
    widget.onAuthChanged?.call();
    Navigator.of(context).pop();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────────────────────── 扫码 Tab ─────────────────────────

  /// 出码 + 1.5s 轮询（0/1/2/4 四态）；过期自动重建一次。
  Future<void> _createQr() async {
    final auth = appGraph.auth;
    if (auth == null) {
      if (mounted) setState(() => _qrHint = '登录能力未装配');
      return;
    }
    try {
      final st = await auth.createQrLogin();
      if (!mounted) return;
      setState(() {
        _qr = st;
        _qrHint = '请使用酷狗音乐 App 扫码';
        try {
          _qrImg = st.qrImageB64.isEmpty ? null : base64Decode(st.qrImageB64);
        } catch (_) {
          _qrImg = null; // 官方图解码失败兜底为提示文案
        }
      });
      _qrTimer?.cancel();
      _qrTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _pollQr(st.key),
      );
    } catch (e, st) {
      Log.e('surface.login', 'create qr failed', e, st);
      if (mounted) setState(() => _qrHint = '二维码获取失败，请重试');
    }
  }

  Future<void> _pollQr(String key) async {
    final auth = appGraph.auth;
    if (auth == null || _qr == null) return;
    final QrLoginState st;
    try {
      st = await auth.pollQrLogin(key);
    } catch (e, st2) {
      Log.e('surface.login', 'poll qr failed', e, st2);
      return; // 轮询瞬时失败容错，下个周期继续
    }
    if (!mounted) return;
    switch (st.status) {
      case QrLoginStatus.waitScan:
        break; // 保持「请扫码」文案
      case QrLoginStatus.waitConfirm:
        setState(() => _qrHint = '已在手机上扫码，请在手机端确认登录');
        break;
      case QrLoginStatus.expired:
        _qrTimer?.cancel();
        if (!_qrRecreatedOnce) {
          _qrRecreatedOnce = true;
          setState(() => _qrHint = '二维码已过期，正在自动刷新…');
          _createQr();
        } else {
          setState(() => _qrHint = '二维码已过期，请下拉重试或退出重开');
        }
        break;
      case QrLoginStatus.success:
        _qrTimer?.cancel();
        _onLoginSuccess();
        break;
    }
  }

  Widget _qrBody(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const SizedBox(height: 8),
        Center(
          child: _qrImg != null
              ? Image.memory(
                  _qrImg!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                )
              : Card(
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const CircularProgressIndicator(strokeWidth: 2),
                          const SizedBox(height: 12),
                          Text('二维码加载中', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _qrHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              _qrRecreatedOnce = false; // 手动刷新重置一次性重建标记
              _createQr();
            },
            child: const Text('刷新二维码'),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── 验证码 Tab ─────────────────────────

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
    } catch (e, st) {
      Log.e('surface.login', 'send verify code failed', e, st);
      _toast('验证码发送失败（接口待实测）');
      return;
    }
    _toast(ok ? '验证码已发送至 ${_maskPhone(phone)}' : '发送失败，请稍后重试');
    if (ok) {
      setState(() => _countdown = 60);
      _smsTimer?.cancel();
      _smsTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _countdown = _countdown - 1);
        if (_countdown <= 0) t.cancel();
      });
    }
  }

  Future<void> _smsLogin() async {
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
      _onLoginSuccess();
    } catch (e, st) {
      Log.e('surface.login', 'sms login failed', e, st);
      _toast('验证码登录失败');
    }
  }

  Widget _smsBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: '手机号',
            hintText: '用于登录酷狗账号',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '验证码'),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _countdown > 0 ? null : _sendCode,
              child: Text(_countdown > 0 ? '${_countdown}s' : '发送验证码'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _smsLogin, child: const Text('登录')),
      ],
    );
  }

  // ───────────────────────── 密码 Tab ─────────────────────────

  Future<void> _pwdLogin() async {
    final acc = _pwdAccount.text.trim();
    final pwd = _pwd.text;
    if (acc.isEmpty || pwd.isEmpty) {
      _toast('请输入账号与密码');
      return;
    }
    try {
      final auth = appGraph.auth;
      if (auth == null) {
        _toast('登录能力未装配');
        return;
      }
      await auth.signInByPwd(pwd);
      _onLoginSuccess();
    } catch (e, st) {
      Log.e('surface.login', 'pwd login failed', e, st);
      _toast('密码登录待后端就绪');
    }
  }

  Widget _pwdBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _pwdAccount,
          decoration: const InputDecoration(labelText: '手机号 / 用户名'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pwd,
          obscureText: _pwdObscure,
          decoration: InputDecoration(
            labelText: '密码',
            suffixIcon: IconButton(
              tooltip: _pwdObscure ? '显示密码' : '隐藏密码',
              icon: Icon(_pwdObscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _pwdObscure = !_pwdObscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _pwdLogin, child: const Text('登录')),
      ],
    );
  }

  // ───────────────────────── YKG Tab ─────────────────────────

  Widget _ykgBody(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(Icons.link, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            s.t('ykgRisk'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => showYkgImport(context),
            icon: const Icon(Icons.download_outlined),
            label: Text(s.t('ykgImport')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showYkgExport(context),
            icon: const Icon(Icons.upload_outlined),
            label: Text(s.t('ykgExport')),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 账号区 ─────────────────────────

  Widget _accountArea(BuildContext context) {
    final theme = Theme.of(context);
    final activeUid = appGraph.auth?.session.userid ?? '';
    final List<AccountEntry> entries = buildAccountEntries(
      _accounts,
      activeUid,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('已登录账号', style: theme.textTheme.titleSmall),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('暂无账号，登录后将自动保存到这里', style: theme.textTheme.bodySmall),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final AccountEntry e in entries)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        e.active ? Icons.person : Icons.person_outline,
                        color: e.active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      title: Text(
                        e.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        accountSubtitle(e.accountId),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        tooltip: '移除账号',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _removeAccount(e.accountId),
                      ),
                      onTap: () => _switchTo(e.accountId),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────── 组装 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(s.t('login'), style: theme.textTheme.titleLarge),
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: theme.colorScheme.onSurface,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: context.cs.primary,
          tabs: <Widget>[
            Tab(text: s.t('qrLogin')),
            Tab(text: s.t('smsLogin')),
            Tab(text: s.t('pwdLogin')),
            Tab(text: s.t('ykgTitle')),
          ],
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _tabs,
            builder: (BuildContext c, Widget? _) {
              switch (_tabs.index) {
                case 1:
                  return _smsBody(c);
                case 2:
                  return _pwdBody(c);
                case 3:
                  return _ykgBody(c);
                default:
                  return _qrBody(c);
              }
            },
          ),
        ),
        _accountArea(context),
      ],
    );
  }
}
