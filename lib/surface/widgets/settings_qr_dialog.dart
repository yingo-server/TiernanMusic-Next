// L6 surface/widgets · 二维码登录对话框 + 多账号管理区（批R1-B 从 settings_page.dart 拆出）
// 仅移动代码：文案/回调/轮询逻辑零改动；每函数 try/catch+Log 留痕。
// 铁律：只 import flutter/riverpod/bridge_logic/bridge_core/本层。
import 'dart:async';
import 'dart:convert' show base64Decode;

import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show AccountRecord;
import '../../bridges/bridge_logic.dart';
import '../l10n/l10n_helper.dart' show TnStrings;
import '../pages/settings_page.dart' show SettingsDeps;
import '../theme/tn_theme.dart';
import 'qr_view.dart';

const String _tag = 'surface.settings';

/// 二维码纯白底（M3 语义例外）：二维码扫码对比度要求纯白底，
/// 不改 scheme.surface，显式常量并保留例外说明。
const Color kQrBackgroundColor = Color(0xFFFFFFFF);

/// 二维码登录对话框：渲染 qrcode 文本 + 每 1.5s 轮询 pollQrLogin，status 展示。
class QrLoginDialog extends StatefulWidget {
  const QrLoginDialog({super.key, required this.deps, required this.state});

  final SettingsDeps deps;
  final QrLoginState state;

  @override
  State<QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<QrLoginDialog> {
  late QrLoginState _state = widget.state;
  Timer? _poll;
  String _hint = '等待扫码…';
  @override
  void initState() {
    super.initState();
    _startPolling();
  }
  void _startPolling() {
    _poll?.cancel();
    // 业务轮询节奏（1.5s）：登录接口轮询间隔非动效时长，不属 TnMotion 三档，保留裸值。
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted || _state.status == QrLoginStatus.success) return;
    try {
      final s = await widget.deps.auth.pollQrLogin(_state.key);
      if (!mounted) return;
      setState(() {
        _state = s;
        _hint = switch (s.status) {
          QrLoginStatus.waitScan => '等待扫码…',
          QrLoginStatus.waitConfirm => '已扫码，请在手机上确认',
          QrLoginStatus.success => '登录成功',
          QrLoginStatus.expired => '二维码已过期',
        };
      });
      if (s.status == QrLoginStatus.success) {
        // 即时恢复会话（restoreSession 从持久层回灌，幂等）；提示重启更稳妥。
        final restored = widget.deps.auth.restoreSession();
        Log.d(_tag, 'login success restored=$restored');
        _poll?.cancel();
        // 登录成功后的缓冲等待（400ms）：提示展示节奏非动效时长，保留裸值。
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('登录成功（uid=${widget.deps.auth.session.userid}），'
                  '建议重启 App 以刷新全局会话')));
          Navigator.of(context).pop();
        }
      } else if (s.status == QrLoginStatus.expired) {
        // 过期自动重开一轮。
        final fresh = await widget.deps.auth.createQrLogin();
        if (mounted) setState(() => _state = fresh);
      }
    } catch (e, st) {
      Log.e(_tag, 'pollQrLogin tick failed', e, st);
      // 网络抖动：继续下一轮轮询。
    }
  }
  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('扫码登录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 200,
            height: 200,
            color: kQrBackgroundColor,
            alignment: Alignment.center,
            child: _state.qrImageB64.isNotEmpty
                ? Image.memory(
                    base64Decode(_state.qrImageB64),
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                  )
                : (_state.qrcode.isEmpty
                    ? const Text('生成中…')
                    : QrView(data: _state.qrcode)),
            // QR 真渲染（批1-C）：QrView 纯 Dart 编码 + CustomPainter，无第三方包。
          ),
          const SizedBox(height: 12),
          const Text('请使用酷狗 App 扫码'),
          Text(_hint),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 多账号管理：列出档案、切换、删除；保存当前会话为档案。
class AccountSection extends StatefulWidget {
  const AccountSection({super.key, required this.accounts});

  final AccountLogic accounts;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  List<AccountRecord> _items = const <AccountRecord>[];
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.accounts.listAccounts();
      final active = await widget.accounts.activeAccount();
      if (!mounted) return;
      setState(() {
        _items = list;
        _activeId = active?.accountId;
      });
    } catch (e, st) {
      Log.e(_tag, 'account list failed', e, st);
    }
  }
  Future<void> _switch(AccountRecord r) async {
    try {
      await widget.accounts.switchTo(r.accountId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已切换到 ${r.displayName}')));
      }
    } catch (e, st) {
      Log.e(_tag, 'account switch failed', e, st);
    }
  }

  Future<void> _save() async {
    try {
      final rec = await widget.accounts.saveCurrent();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(rec == null ? '未登录，无法保存账号' : '已保存当前账号')));
      }
    } catch (e, st) {
      Log.e(_tag, 'account save failed', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(tnPadL, tnPadS, tnPadL, TnDims.padXS),
          child: Row(
            children: [
              const Text('账号管理',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.person_add_alt, size: TnDims.iconS),
                label: const Text('保存当前'),
              ),
            ],
          ),
        ),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(tnPadL, TnDims.padXS, tnPadL, tnPadS),
            child: Text('暂无账号档案', style: TextStyle(fontSize: 12)),
          )
        else
          for (final r in _items)
            ListTile(
              dense: true,
              leading: Icon(r.accountId == _activeId
                  ? Icons.check_circle
                  : Icons.account_circle_outlined),
              title:
                  Text(r.displayName.isEmpty ? r.accountId : r.displayName),
              subtitle: Text(r.accountId),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  await widget.accounts.removeAccount(r.accountId);
                  await _load();
                },
              ),
              onTap: () => _switch(r),
            ),
      ],
    );
  }
}
