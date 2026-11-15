// L7 surface/pages · 登录弹层的已登录账号区（从 login_sheet 拆出，≤500 行门禁）。
// 只画控件；数据经 bridge_core 的 AccountRecord / bridge_logic 的 AccountLogic。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show AccountRecord;
import '../design/tokens.dart' show Sp;

/// 已登录账号列表区（当前账号高亮；支持切换/移除）。
class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.accounts,
    required this.activeUid,
    required this.onSwitch,
    required this.onRemove,
  });

  final List<AccountRecord> accounts;
  final String activeUid;
  final void Function(String accountId) onSwitch;
  final void Function(String accountId) onRemove;

  @override
  Widget build(BuildContext context) {
    try {
      return Container(
        decoration: const BoxDecoration(color: Sp.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(Sp.pagePad, Sp.gapM, Sp.pagePad, 4),
              child: Text(
                '已登录账号',
                style: TextStyle(fontSize: Sp.fItem, color: Sp.textSub),
              ),
            ),
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(Sp.pagePad, 0, Sp.pagePad, Sp.gapM),
                child: Text(
                  '暂无账号，登录后将自动保存到这里',
                  style: TextStyle(fontSize: Sp.fSub, color: Sp.textFaint),
                ),
              )
            else
              for (final AccountRecord rec in accounts)
                ListTile(
                  dense: true,
                  leading: Icon(
                    rec.accountId == activeUid
                        ? Icons.person
                        : Icons.person_outline,
                    color: rec.accountId == activeUid ? Sp.green : Sp.textSub,
                    size: 20,
                  ),
                  title: Text(
                    rec.displayName,
                    style: const TextStyle(fontSize: Sp.fItem, color: Sp.text),
                  ),
                  subtitle: Text(
                    '账号 ${rec.accountId}',
                    style: const TextStyle(
                        fontSize: Sp.fSub, color: Sp.textFaint),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Sp.textFaint,
                    ),
                    tooltip: '移除账号',
                    onPressed: () => onRemove(rec.accountId),
                  ),
                  onTap: () => onSwitch(rec.accountId),
                ),
          ],
        ),
      );
    } catch (e, st) {
      debugPrint('surface.login: account section failed: $e\n$st');
      return const SizedBox.shrink();
    }
  }
}
