// L4 core · 数据库开启桥接函数（bootloader await 用，避免 DAO 首访 fail-fast）
// 职责：把 DatabaseService.open 收敛为单入口异步函数，L2 经 bridge_core 调用。
// 铁律：try/catch + Log('core.dbbridge')；失败 rethrow 由 boot 兜底。
import '../database/db.dart';
import '../../kernel/kernel.dart' show Log;

const String _tag = 'core.dbbridge';

/// 打开 Isar 数据库（幂等）。返回是否新开（已开返回 false）。
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
