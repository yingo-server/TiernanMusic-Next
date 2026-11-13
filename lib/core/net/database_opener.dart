// L4 core · 数据库开启函数 DatabaseOpener（bootloader await 用，避免 DAO 首访 fail-fast）
// 命名说明（审计B F-08）：本文件原为 database_bridge.dart，因「bridge」字样冲淡
// 「桥唯一目录 lib/bridges/」认知，且其并非五桥之一，故更名为 database_opener.dart。
// 职责：把 DatabaseService.open 收敛为单入口异步函数，L2 经 bridge_core 调用。
// 铁律：try/catch + Log('core.dbopener')；失败 rethrow 由 boot 兜底。
import '../database/db.dart';
import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'core.dbopener';

/// DatabaseOpener：打开 Isar 数据库（幂等）。返回是否新开（已开返回 false）。
Future<bool> openDatabase(String dir) async {
  try {
    if (DatabaseService.isOpen) {
      Log.d(_tag, 'already open, skip dir=$dir');
      return false;
    }
    await DatabaseService.instance.open(dir);
    return true;
  } catch (e, st) {
    Log.e(_tag, 'openDatabase failed dir=$dir', e, st);
    rethrow;
  }
}
