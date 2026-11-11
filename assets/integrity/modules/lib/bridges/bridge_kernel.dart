// 五桥 · bridge_kernel：L3 kernel 暴露给 L2 bootloader（及上层）的能力门面。
// 铁律：每个桥函数 try/catch + Log 留痕（留痕自身用 print 兜底，避免桥内
// 调 kernel.Log 失败时递归）；失败返回语义默认值，不静默吞、不上抛业务异常。
// 本文件是 kernel 的上层出口：import '../kernel/kernel.dart' 合法。
library;

import '../kernel/kernel.dart'
    show Ed25519Verifier, IntegrityVerifier, Kernel, KernelContext, Log;
import '../kernel/sha512.dart' show Sha512;

// 日志系统载体：转出 kernel.Log 供下层经桥留痕（桥自身留痕用 _bridgeLog 兜底）。
export '../kernel/kernel.dart' show Log;

/// 桥内留痕：print 兜底（kernel.Log 若自身异常不致递归爆栈）。
void _bridgeLog(String level, String fn, Object err, StackTrace st) {
  try {
    // ignore: avoid_print
    print('${DateTime.now().toIso8601String()} $level/bridge_kernel: '
        '$fn failed ERR=$err ST=$st');
  } catch (e) {
    // 日志兜底失败：不再递归，静默终止（已尽力留痕）
  }
}

/// 桥级日志出口：L2 只经此写日志，不直接 import kernel。
void logD(String tag, String msg) {
  try {
    Log.d(tag, msg);
  } catch (e, st) {
    _bridgeLog('D', 'logD($tag)', e, st);
  }
}

void logW(String tag, String msg) {
  try {
    Log.w(tag, msg);
  } catch (e, st) {
    _bridgeLog('W', 'logW($tag)', e, st);
  }
}

void logE(String tag, String msg, [Object? err, StackTrace? st]) {
  try {
    Log.e(tag, msg, err, st);
  } catch (e, s2) {
    _bridgeLog('E', 'logE($tag)', e, s2);
  }
}

/// 完整性校验（加盐 SHA-512 + Ed25519 整体签名）。
/// 失败/异常一律返回 false（rejected 语义），由 init 决定 debug 续跑。
bool verifyIntegrity(dynamic manifest, {bool bypass = false}) {
  try {
    return IntegrityVerifier.verify(manifest, bypass: bypass);
  } catch (e, st) {
    _bridgeLog('E', 'verifyIntegrity', e, st);
    return false;
  }
}

/// kernel 装配：返回 KernelContext；失败返回空上下文（不 null，调用方可安全 get）。
KernelContext assembleKernel() {
  try {
    return Kernel.assemble();
  } catch (e, st) {
    _bridgeLog('E', 'assembleKernel', e, st);
    return const KernelContext(modules: {});
  }
}

/// 加盐 SHA-512：sha512(salt || data)。失败返回空串。
String sha512Hex(List<int> data, String salt) {
  try {
    return Sha512.saltedHex(data, salt);
  } catch (e, st) {
    _bridgeLog('E', 'sha512Hex', e, st);
    return '';
  }
}

/// Ed25519 整体签名验证（占位实现：sigHex 非空即过）。
/// 失败/异常返回 false。
bool verifySignature(String payload, String? sig) {
  try {
    return Ed25519Verifier.verify(payload, sig);
  } catch (e, st) {
    _bridgeLog('E', 'verifySignature', e, st);
    return false;
  }
}
