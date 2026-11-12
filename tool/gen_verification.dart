// 构建期校验清单生成器（随 release 发布，每版一份，不重复）：
// 对 lib/ 全部 dart 模块计算 加盐MD5 + 加盐SHA-512，
// 整份清单用 RSA-4096 私钥做 SHA-512 签名（openssl 子进程）。
// 输出 assets/integrity/verification.json，CI 上传到同版本 release assets。
// Secrets：NEXT_MANIFEST_SALT（盐）+ RSA4096_PRIVATE_PEM（私钥 PEM，base64 可选）。
// 公钥入库：docs/VERIFICATION_PUBLIC_KEY.pem（任何人可验，私钥只在 CI）。
// 运行期校验已删除（Flutter 对深层子目录 asset 不可靠）。
import 'dart:convert';
import 'dart:io';

const String fallbackSalt = 'next-manifest-unsigned';

Future<void> main() async {
  final saltEnv = Platform.environment['NEXT_MANIFEST_SALT'];
  final salt = (saltEnv == null || saltEnv.isEmpty) ? fallbackSalt : saltEnv;
  var pem = Platform.environment['RSA4096_PRIVATE_PEM'] ?? '';
  // 兼容 base64 单行 PEM（Secret 换行易丢）。
  if (pem.isNotEmpty && !pem.contains('-----BEGIN')) {
    pem = utf8.decode(base64.decode(pem.replaceAll('\n', '')));
  }
  final pemFile = File('docs/VERIFICATION_PRIVATE_KEY.pem');
  if (pem.isEmpty && pemFile.existsSync()) pem = pemFile.readAsStringSync();
  final canSign = pem.contains('-----BEGIN');
  if (!canSign) {
    // 用户原则：无法验证时警报即可，不阻塞——降级为仅哈希清单继续构建。
    stderr.writeln('gen_verification: WARN — RSA4096_PRIVATE_PEM missing; '
        'emitting hash-only manifest (signed:false), NOT blocking the build.');
  }

  // ① 逐模块加盐 md5/sha512（openssl 子进程，流式避免大文件进参数）。
  final libDir = Directory('lib');
  final modules = <String, Map<String, String>>{};
  for (final f in libDir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final rel = f.path.replaceAll('\\', '/');
    modules[rel] = {
      'md5': await _digest('MD5', f, salt),
      'sha512': await _digest('SHA512', f, salt),
    };
  }

  // ② 清单 payload（稳定键序）。
  final sortedKeys = modules.keys.toList()..sort();
  final payload = jsonEncode({
    'algo': 'salted_md5+salted_sha512+rsa4096_sig',
    'salt': salt,
    'version': Platform.environment['VER'] ?? '',
    'modules': {
      for (final k in sortedKeys) k: modules[k],
    },
  });

  // ③ RSA-4096 签名（私钥写临时文件 → openssl dgst -sha512 -sign）；不可用时跳过。
  String sigB64 = '';
  if (canSign) {
    final keyFile = File('/tmp/rsa4096_priv.pem');
    keyFile.writeAsStringSync(pem, flush: true);
    final payloadFile = File('/tmp/verification_payload.json');
    payloadFile.writeAsStringSync(payload, flush: true);
    sigB64 = await _run(
        ['openssl', 'dgst', '-sha512', '-sign', keyFile.path, payloadFile.path],
        binary: true);
  }

  // ④ 输出。
  final out = const JsonEncoder.withIndent('  ').convert({
    'algo': 'salted_md5+salted_sha512+rsa4096_sig',
    'salt': salt,
    'signed': canSign,
    if (canSign) 'signature': sigB64,
    'signature_algo': canSign ? 'RSA-4096/SHA-512' : 'none (warn only)',
    'version': Platform.environment['VER'] ?? '',
    'modules': {
      for (final k in sortedKeys) k: modules[k],
    },
  });
  Directory('assets/integrity').createSync(recursive: true);
  File('assets/integrity/verification.json').writeAsStringSync(out);
  // 纯发布用副本（CI 上传 release assets）。
  File('verification.json').writeAsStringSync(out);
  stdout.writeln('gen_verification: ${modules.length} modules, '
      'rsa4096 signed, salt_set=${salt != fallbackSalt}');
}

Future<String> _digest(String algo, File f, String salt) async {
  // 盐前缀到临时文件，与目标文件拼接摘要（等效 salted digest，避免命令行长度限制）。
  final tmp = File('/tmp/_digest_input.bin');
  tmp.writeAsBytesSync([...utf8.encode(salt), ...f.readAsBytesSync()],
      flush: true);
  final out = await _run(['openssl', 'dgst', '-$algo', tmp.path]);
  // openssl 输出 "ALGO(path)= hex"
  final line = out.trim();
  final eq = line.lastIndexOf('= ');
  return eq >= 0 ? line.substring(eq + 2).trim() : line;
}

Future<String> _run(List<String> args, {bool binary = false}) async {
  final r = await Process.run(args.first, args.sublist(1),
      stdoutEncoding: binary ? null : systemEncoding);
  if (r.exitCode != 0) {
    throw StateError('openssl failed (${r.exitCode}): ${r.stderr}');
  }
  if (binary) {
    final bytes = (r.stdout as List<int>);
    return base64.encode(bytes);
  }
  return r.stdout as String;
}
