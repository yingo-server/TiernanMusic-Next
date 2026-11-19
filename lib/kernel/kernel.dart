// L3 kernel 级 · 生命周期编排、模块注册表、日志

// ─── 日志（桥接层唯一日志出口，所有桥函数经此留痕） ───

class Log {
  Log._();
  static final _buf = <String>[];
  static void d(String tag, String msg) => _emit('D', tag, msg);
  static void w(String tag, String msg) => _emit('W', tag, msg);
  static void e(String tag, String msg, [Object? err, StackTrace? st]) =>
      _emit('E', tag, '$msg ERR=$err ST=$st');

  /// 可选的落盘 sink（由 L1 init 注入真实路径）。
  ///
  /// 背景：release 真机上 print 的 stdout 不可见，"see boot log" 曾经是
  /// 空头支票 —— 启动失败时用户与开发者都拿不到任何真实原因。
  /// L3 不 import dart:io（保持纯 Dart），由上层注入写文件的能力。
  static void Function(String line)? sink;

  /// 最近日志（内存缓冲，供错误页直接展示）。
  static List<String> get recent => List.unmodifiable(_buf);

  static void _emit(String lvl, String tag, String msg) {
    final line = '${DateTime.now().toIso8601String()} $lvl/$tag: $msg';
    _buf.add(line);
    if (_buf.length > 2000) _buf.removeRange(0, 500);
    // ignore: avoid_print
    print(line);
    final s = sink;
    if (s != null) {
      try {
        s(line);
      } catch (_) {
        // 落盘失败不得影响主流程。
      }
    }
  }
}

class KernelContext {
  const KernelContext({required this.modules});
  final Map<Type, Object> modules;
  T get<T extends Object>() => modules[T] as T;
}

class Kernel {
  Kernel._();

  static KernelContext assemble() {
    Log.d('kernel', 'assembling modules');
    return KernelContext(modules: const {});
  }
}
