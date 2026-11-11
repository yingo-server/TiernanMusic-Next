// 构建期完整性清单生成：
//   1) 扫描 lib/ 下全部 dart 文件，算「加盐 SHA-512」写入 manifest；
//   2) 把这些文件原样复制到 assets/integrity/modules/<原路径>，
//      运行期从 rootBundle 读同一批字节比对（Android APK 内无 lib/ 文件系统路径，
//      故必须随包携带，才能真正校验「APK 内容未被篡改」）；
//   3) salt 与算法写入 manifest，运行期从 manifest 取（Android 无环境变量，
//      构建期/运行期取不同 salt 会导致校验必然失败）。
// 铁律：纯 Dart 实现（复用 kernel.Sha512.saltedHex），不调用外部 shell——
// 避免整文件塞进环境变量导致 "Argument list too long"。
import 'dart:convert';
import 'dart:io';

import '../lib/kernel/sha512.dart' show Sha512;

void main(List<String> args) {
  final env = Platform.environment;
  final saltEnv = env['NEXT_MANIFEST_SALT'];
  final keyEnv = env['NEXT_MANIFEST_KEY'];
  // Secret 未配置时用确定性回退 salt（构建期/运行期自洽，见 manifest['salt']）。
  final effectiveSalt =
      (saltEnv == null || saltEnv.isEmpty) ? 'next-manifest-unsigned' : saltEnv;
  final signed = keyEnv != null && keyEnv.isNotEmpty;

  final libDir = Directory('lib');
  final modules = <String, String>{};
  final outRoot = Directory('assets/integrity/modules');
  if (outRoot.existsSync()) outRoot.deleteSync(recursive: true);

  for (final f in libDir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final rel = f.path.replaceAll('\\', '/');
    modules[rel] = Sha512.saltedHex(f.readAsBytesSync(), effectiveSalt);
    // 复制到 assets，供运行期逐字节校验（保留原目录结构）。
    final dst = File('${outRoot.path}/$rel');
    dst.parent.createSync(recursive: true);
    dst.writeAsBytesSync(f.readAsBytesSync());
  }

  final payload = jsonEncode(modules);
  // 签名：salted_sha512(salt || payload)（占位实现；真 Ed25519 私钥签名待接入）。
  final sig = signed
      ? Sha512.saltedHex(utf8.encode(payload), effectiveSalt)
      : 'unsigned';

  Directory('assets/integrity').createSync(recursive: true);
  File('assets/integrity/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
    'algo': 'salted_sha512+payload_sig',
    'salt': effectiveSalt,
    'signed': signed,
    'signature': sig,
    'modules': modules,
  }));
  stdout.writeln('gen_manifest: ${modules.length} modules, '
      'signed=$signed, salt_set=${effectiveSalt.isNotEmpty}');
  if (!signed) {
    stderr.writeln('gen_manifest: WARN — NEXT_MANIFEST_SALT/KEY not configured; '
        'using deterministic fallback salt. Configure GitHub Secrets for release.');
  }
}
