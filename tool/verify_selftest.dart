import 'dart:convert';
// 独立自检：模拟 CI gen_manifest → 运行期 verify 全链路
import '../lib/kernel/sha512.dart' show Sha512;
import '../lib/kernel/kernel.dart' show IntegrityVerifier;

void main() {
  const salt = 'ci-secret-salt-sim';
  final fake = utf8.encode('fake module bytes');
  final modules = <String, String>{
    'lib/init/main.dart': Sha512.saltedHex(fake, salt),
  };
  final payload = jsonEncode(modules);
  final sig = Sha512.saltedHex(utf8.encode(payload), salt);
  final manifest = <String, dynamic>{
    'algo': 'salted_sha512+payload_sig',
    'salt': salt,
    'signed': true,
    'signature': sig,
    'modules': modules,
  };

  var ok = IntegrityVerifier.verify(manifest,
      moduleBytes: {'lib/init/main.dart': fake});
  print('verify(tamper-free) = $ok (expect true)');

  final tampered = IntegrityVerifier.verify(manifest,
      moduleBytes: {'lib/init/main.dart': utf8.encode('TAMPERED')});
  print('verify(tampered)    = $tampered (expect false)');

  final unsigned = IntegrityVerifier.verify({
    'algo': 'x', 'salt': salt, 'signed': false,
    'signature': 'unsigned', 'modules': modules,
  }, moduleBytes: {'lib/init/main.dart': fake});
  print('verify(unsigned)    = $unsigned (expect false)');
}
