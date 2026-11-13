// L3 kernel 级 · 生命周期编排、模块注册表、日志

// ─── 日志（桥接层唯一日志出口，所有桥函数经此留痕） ───

class Log {
  Log._();
  static final _buf = <String>[];
  static void d(String tag, String msg) => _emit('D', tag, msg);
  static void w(String tag, String msg) => _emit('W', tag, msg);
  static void e(String tag, String msg, [Object? err, StackTrace? st]) =>
      _emit('E', tag, '$msg ERR=$err ST=$st');

  static void _emit(String lvl, String tag, String msg) {
    final line =
        '${DateTime.now().toIso8601String()} $lvl/$tag: $msg';
    _buf.add(line);
    if (_buf.length > 2000) _buf.removeRange(0, 500);
    // ignore: avoid_print
    print(line);
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
