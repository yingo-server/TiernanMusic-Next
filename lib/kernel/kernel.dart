// L3 kernel 级 · 生命周期编排、模块注册表、盐值校验执行、日志
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'sha512.dart' show Sha512;
export 'sha512.dart' show Sha512;

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

  static List<String> snapshot() => List.unmodifiable(_buf);
}

void debugWarn(String msg) => Log.w('boot', msg);

// ─── 完整性校验 ───

class IntegrityVerifier {
  IntegrityVerifier._();

  /// 清单含每模块加盐 SHA-512 与整体 Ed25519 签名。
  /// salt 在构建期由 tool/gen_manifest.dart 从 GitHub Secret 注入。
  static bool verify(dynamic manifest, {bool bypass = false}) {
    if (bypass) return false; // rejected=true，由 init 决定 debug 继续跑
    if (manifest == null) return false;
    try {
      final modules = (manifest['modules'] as Map).cast<String, String>();
      final salt = Platform.environment['NEXT_MANIFEST_SALT'] ?? '';
      for (final e in modules.entries) {
        final f = File(e.key);
        if (!f.existsSync()) return false;
        final h = Sha512.saltedHex(f.readAsBytesSync(), salt);
        if (h != e.value) return false;
      }
      // Ed25519 整体签名验证：公钥编译期内置（私钥仅在 CI Secret）
      return Ed25519Verifier.verify(jsonEncode(modules), manifest['signature']);
    } catch (e, st) {
      Log.e('integrity', 'verify crashed', e, st);
      return false;
    }
  }
}

class Ed25519Verifier {
  Ed25519Verifier._();
  /// 占位：接入公钥后实现（CI 构建期注入 PEM）。
  static bool verify(String payload, String? sigHex) =>
      sigHex != null && sigHex.isNotEmpty;
}

/// 加盐 SHA-512：sha512(salt || bytes)。
/// 自实现 SHA-512（独立文件 sha512.dart，kernel 与 tool 共用）。

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
