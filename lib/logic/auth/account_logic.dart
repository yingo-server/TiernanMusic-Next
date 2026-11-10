// L5 logic/auth · 多账号门面（功能对齐批2 收尾，主会话装配补齐）
// 契约：AccountDao 为本地档案事实源；switchTo 直接写 KugouSession（不依赖
// AuthLogic.restoreSession，避免启动时序覆盖）；切换触发 onAccountChanged 让各
// 域缓存失效。零 UI、零网络直连；每方法 try/catch+Log('logic.account')。
import '../../core/database/dao.dart';
import '../../core/database/entities.dart';
import '../../core/net/kugou_client.dart';
import '../../core/storage/settings_store.dart';
import '../../kernel/kernel.dart' show Log;

const String _tag = 'logic.account';

/// 多账号管理门面。
class AccountLogic {
  AccountLogic({
    required AccountDao dao,
    required KugouClient client,
    required KeyValueSettings settings,
    void Function()? onAccountChanged,
  })  : _dao = dao,
        _client = client,
        _settings = settings,
        _onAccountChanged = onAccountChanged;

  final AccountDao _dao;
  final KugouClient _client;
  final KeyValueSettings _settings;
  final void Function()? _onAccountChanged;

  /// 把当前会话凭据保存为账号档案（已存在则覆盖），并置为激活。
  Future<AccountRecord?> saveCurrent({String displayName = ''}) async {
    try {
      final s = _client.session;
      if (s.userid.isEmpty) {
        Log.w(_tag, 'saveCurrent: anonymous session, skip');
        return null;
      }
      final existing = await _dao.getByAccountId(s.userid);
      final now = DateTime.now().millisecondsSinceEpoch;
      final rec = existing ?? AccountRecord()
        ..accountId = s.userid
        ..createdAt = now;
      rec
        ..displayName = displayName.isNotEmpty
            ? displayName
            : (existing?.displayName.isNotEmpty == true
                ? existing!.displayName
                : '酷狗用户 ${s.userid}')
        ..token = s.token
        ..mid = s.mid
        ..dfid = s.dfid
        ..cookieBlob = _settings.getString('auth.cookie') ?? ''
        ..lastUsedAt = now;
      // cookieBlob 兜底：session.cookies 序列化（多参不缺参原则）。
      if (rec.cookieBlob.isEmpty && s.cookies.isNotEmpty) {
        rec.cookieBlob = s.cookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
      }
      await _dao.put(rec);
      await _dao.setActive(rec.id);
      Log.d(_tag, 'saveCurrent uid=${s.userid} id=${rec.id}');
      return rec;
    } catch (e, st) {
      Log.e(_tag, 'saveCurrent failed', e, st);
      return null;
    }
  }

  /// 切换到指定账号：写回 KugouSession → 置激活 → 通知缓存失效。
  Future<bool> switchTo(String accountId) async {
    try {
      final rec = await _dao.getByAccountId(accountId);
      if (rec == null) {
        Log.w(_tag, 'switchTo: unknown accountId=$accountId');
        return false;
      }
      final s = _client.session;
      s
        ..token = rec.token
        ..userid = rec.accountId
        ..mid = rec.mid
        ..dfid = rec.dfid;
      // cookie 串解析回 session.cookies（t1 播放权限依赖）。
      if (rec.cookieBlob.isNotEmpty) {
        s.cookies.clear();
        for (final pair in rec.cookieBlob.split(';')) {
          final i = pair.indexOf('=');
          if (i > 0) {
            s.cookies[pair.substring(0, i).trim()] =
                pair.substring(i + 1).trim();
          }
        }
      }
      await _dao.setActive(rec.id);
      _notify();
      Log.d(_tag, 'switchTo uid=$accountId ok');
      return true;
    } catch (e, st) {
      Log.e(_tag, 'switchTo failed accountId=$accountId', e, st);
      return false;
    }
  }

  Future<List<AccountRecord>> listAccounts() async {
    try {
      return await _dao.listAll();
    } catch (e, st) {
      Log.e(_tag, 'listAccounts failed', e, st);
      return const <AccountRecord>[];
    }
  }

  Future<AccountRecord?> activeAccount() async {
    try {
      return await _dao.getActive();
    } catch (e, st) {
      Log.e(_tag, 'activeAccount failed', e, st);
      return null;
    }
  }

  Future<bool> removeAccount(String accountId) async {
    try {
      final rec = await _dao.getByAccountId(accountId);
      if (rec == null) return false;
      final ok = await _dao.remove(rec.id);
      if (ok) _notify();
      Log.d(_tag, 'removeAccount uid=$accountId ok=$ok');
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'removeAccount failed accountId=$accountId', e, st);
      return false;
    }
  }

  void _notify() {
    try {
      _onAccountChanged?.call();
    } catch (e, st) {
      Log.e(_tag, 'onAccountChanged failed', e, st);
    }
  }
}
