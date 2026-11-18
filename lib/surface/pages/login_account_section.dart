// L7 surface/pages · 登录弹层的已登录账号区（纯数据装配，零控件）
//
// 铁律：L7 零手写控件。本文件只提供「账号记录 → 展示行」的纯数据映射，
// 账号区 UI 由 login_sheet.dart 内联为官方 ListTile 组合渲染。
// 数据经 bridge_core 的 AccountRecord；不 import 旧 design/tokens.dart。
import '../../bridges/bridge_core.dart' show AccountRecord;

/// 账号展示行（纯数据，非控件）。
class AccountEntry {
  const AccountEntry({
    required this.accountId,
    required this.displayName,
    required this.active,
  });

  /// 账号业务 id。
  final String accountId;

  /// 展示名（昵称）。
  final String displayName;

  /// 是否为当前激活账号。
  final bool active;
}

/// 账号列表 → 展示行（当前账号高亮；展示名为空时回退账号 id）。
List<AccountEntry> buildAccountEntries(
  List<AccountRecord> accounts,
  String activeUid,
) {
  final List<AccountEntry> out = <AccountEntry>[];
  for (final AccountRecord rec in accounts) {
    out.add(
      AccountEntry(
        accountId: rec.accountId,
        displayName: rec.displayName.isEmpty ? rec.accountId : rec.displayName,
        active: rec.accountId == activeUid,
      ),
    );
  }
  return out;
}

/// 账号副标题文案。
String accountSubtitle(String accountId) => '账号 $accountId';
