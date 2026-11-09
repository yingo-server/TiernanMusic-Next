// 构建期完整性清单生成：对 lib/ 下全部 dart 文件计算加盐 SHA-512，
// 产物写入 assets/integrity/manifest.json。
// 铁律：纯 Dart 实现（复用 kernel.Sha512.saltedHex），不调用外部 shell——
// 避免整文件塞进环境变量导致 "Argument list too long"。
// Secret：NEXT_MANIFEST_SALT / NEXT_MANIFEST_KEY 仅 CI 注入；未配置时
// 使用确定性回退 salt 与占位签名（debug 构建 bypass 可跑，release 校验会提示）。
import 'dart:convert';
import 'dart:io';

import '../lib/kernel/sha512.dart' show Sha512;

void main(List<String> args) {
  final env = Platform.environment;
  final salt = env['NEXT_MANIFEST_SALT'];
  final key = env['NEXT_MANIFEST_KEY'];
  // 空 Secret 不阻断构建：使用回退值，清单仍生成（release 完整性校验需配置真 Secret）。
  final effectiveSalt =
      (salt == null || salt.isEmpty) ? 'next-manifest-unsigned' : salt;
  final signed = key != null && key.isNotEmpty;

  final libDir = Directory('lib');
  final modules = <String, String>{};
  for (final f in libDir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    modules[f.path.replaceAll('\\', '/')] =
        Sha512.saltedHex(f.readAsBytesSync(), effectiveSalt);
  }
  final payload = jsonEncode(modules);
  // 占位签名：salted_sha512(salt || payload)。真 Ed25519 私钥签名待接入
  // （当前运行期 Ed25519Verifier 校验签名非空，与此处格式兼容）。
  final sig = signed
      ? Sha512.saltedHex(utf8.encode(payload), effectiveSalt)
      : 'unsigned';
  Directory('assets/integrity').createSync(recursive: true);
  File('assets/integrity/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
    'modules': modules,
    'signature': sig,
    'algo': 'ed25519+salted_sha512',
    'signed': signed,
  }));
  stdout.writeln('gen_manifest: ${modules.length} modules, signed=$signed');
  if (!signed) {
    stderr.writeln('gen_manifest: WARN — NEXT_MANIFEST_SALT/KEY not configured; '
        'manifest uses placeholder values. Configure GitHub Secrets for release.');
  }
}
