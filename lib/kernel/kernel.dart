// L3 kernel 级 · 生命周期编排、模块注册表、盐值校验执行、日志
import 'dart:async';
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

  /// 清单含每模块加盐 SHA-512 与整体签名。
  /// salt 由 tool/gen_manifest.dart 写入 manifest（构建期与运行期必须同源：
  /// Android 运行时没有环境变量，故不得从 Platform.environment 取）。
  /// [moduleBytes] 为 APK 内模块字节（由 L1 从 rootBundle 预加载，见 init/main.dart）；
  /// 为空时退回文件系统（桌面/调试场景）。
  static bool verify(
    dynamic manifest, {
    bool bypass = false,
    Map<String, List<int>>? moduleBytes,
  }) {
    if (bypass) return false; // rejected=true，由 init 决定 debug 继续跑
    if (manifest == null) return false;
    try {
      final modules = (manifest['modules'] as Map).cast<String, String>();
      final salt = (manifest['salt'] as String?) ?? '';
      for (final e in modules.entries) {
        final bytes = moduleBytes?[e.key] ?? _readFromFs(e.key);
        if (bytes == null) {
          Log.w('integrity', 'module bytes unavailable: ${e.key}');
          return false;
        }
        final h = Sha512.saltedHex(bytes, salt);
        if (h != e.value) {
          Log.w('integrity',
              'hash mismatch: ${e.key} expect=${e.value} got=$h bytes=${bytes.length}');
          return false;
        }
      }
      // 整体签名验证：payload 重算 + manifest 内同源 salt 比对。
      return Ed25519Verifier.verify(
          jsonEncode(modules), manifest['signature'],
          salt: salt);
    } catch (e, st) {
      Log.e('integrity', 'verify crashed', e, st);
      return false;
    }
  }

  static List<int>? _readFromFs(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      return f.readAsBytesSync();
    } catch (e, st) {
      Log.e('integrity', 'fs read failed: $path', e, st);
      return null;
    }
  }
}

class Ed25519Verifier {
  Ed25519Verifier._();

  /// 清单签名验证：gen_manifest 对 payload 做 salted_sha512(salt||payload)，
  /// 运行期用同一 salt 重算比对（salt 在 manifest 内，见 kernel.verify）。
  /// 未签名（'unsigned'）的清单一律拒绝——防篡改门不因配置缺失而虚开。
  static bool verify(String payload, String? sigHex, {String salt = ''}) {
    if (sigHex == null || sigHex.isEmpty || sigHex == 'unsigned') {
      Log.w('integrity', 'manifest is unsigned — rejected');
      return false;
    }
    try {
      final expect = Sha512.saltedHex(utf8.encode(payload), salt);
      final ok = expect == sigHex;
      if (!ok) Log.w('integrity', 'signature mismatch');
      return ok;
    } catch (e, st) {
      Log.e('integrity', 'verify crashed', e, st);
      return false;
    }
  }
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
