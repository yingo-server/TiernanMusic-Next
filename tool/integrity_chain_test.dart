// 完整性校验链路自检：manifest + .dat 副本 + kernel.IntegrityVerifier.verify
// 模拟 main() 的 rootBundle 加载（这里用文件系统代替 asset bundle）。
import 'dart:convert';
import 'dart:io';
import '../lib/kernel/kernel.dart' show IntegrityVerifier;

void main() {
  final manifest = jsonDecode(
      File('assets/integrity/manifest.json').readAsStringSync()) as Map;
  final mods = (manifest['modules'] as Map).cast<String, dynamic>();
  final bytes = <String, List<int>>{};
  var missing = 0;
  for (final p in mods.keys) {
    final f = File('assets/integrity/modules/$p.dat');
    if (!f.existsSync()) {
      missing++;
      continue;
    }
    bytes[p] = f.readAsBytesSync();
  }
  print('modules=${mods.length} blobs=${bytes.length} missing=$missing');
  final ok = IntegrityVerifier.verify(manifest, moduleBytes: bytes);
  print('integrity verify = $ok (expect true)');
  if (!ok || missing > 0) {
    print('INTEGRITY-CHAIN-FAIL');
    exitCode = 1;
  } else {
    print('INTEGRITY-CHAIN-OK');
  }
}
