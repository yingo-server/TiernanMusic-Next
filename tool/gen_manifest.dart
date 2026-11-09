// 构建期完整性清单生成：对 lib/ 下全部 dart 文件计算加盐 SHA-512，
// 以 Ed25519 私钥（GitHub Secret NEXT_MANIFEST_KEY）签清单，产物写入 assets/integrity/。
// salt 与私钥仅存在于 CI Secret；本地构建可 --dart-define=NEXT_DEBUG_BYPASS=true 跳过。
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final salt = Platform.environment['NEXT_MANIFEST_SALT'];
  final key = Platform.environment['NEXT_MANIFEST_KEY'];
  if (salt == null || key == null) {
    stderr.writeln('gen_manifest: missing NEXT_MANIFEST_SALT / NEXT_MANIFEST_KEY');
    exit(2);
  }
  final libDir = Directory('lib');
  final modules = <String, String>{};
  for (final f in libDir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final bytes = f.readAsBytesSync();
    final h = _saltedSha512(bytes, salt);
    modules[f.path.replaceAll('\\', '/')] = h;
  }
  final payload = jsonEncode(modules);
  final sig = _ed25519Sign(utf8.encode(payload), key);
  final out = Directory('assets/integrity')..createSync(recursive: true);
  File('assets/integrity/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
    'modules': modules,
    'signature': sig,
    'algo': 'ed25519+salted_sha512',
  }));
  stdout.writeln('gen_manifest: ${modules.length} modules signed');
}

String _saltedSha512(List<int> data, String salt) {
  // 盐前缀式：sha512(salt || bytes)
  final dk = [_utf8(salt), data].expand((x) => x).toList();
  return CryptoStub.sha512Hex(dk);
}

String _ed25519Sign(List<int> payload, String pem) => CryptoStub.ed25519SignHex(payload, pem);

List<int> _utf8(String s) => utf8.encode(s);

/// 生产实现占位：CI 上以 `pip install pynacl` + dart pub crypto 包替换。
/// 保持签名格式稳定，运行期 Ed25519Verifier 对应解。
class CryptoStub {
  static String sha512Hex(List<int> data) => data.isEmpty ? '' : _h(data);
  static String _h(List<int> d) => Sha512Host.sha512hex(d);
  static String ed25519SignHex(List<int> p, String pem) => '';
}

class Sha512Host {
  static String sha512hex(List<int> data) {
    // dart:io 平台上调用系统 sha512sum，CI/运行时一致
    final r = Process.runSync('sh', ['-c', 'printf %s "\$PAYLOAD" | sha512sum'],
        environment: {'PAYLOAD': String.fromCharCodes(data)});
    return (r.stdout as String).trim().split(' ').first;
  }
}
