// api_matrix_probe.dart — 批01-C 契约矩阵骨架（纯 Dart，不 import flutter）。
// 职责：定义三态枚举 / 探针行数据类 / CSV 写出器；main() 只打印用法与端点清单加载入口。
// ⚠️ 不发真实请求 —— 网络层实现留给主会话填充（六五规则：网络属 L4 core 域）。
// 凭据来源（不得进仓库、日志脱敏）：.test_creds/cj_vip.txt / cj_nonvip.txt / 匿名。
// 用法：dart run tool/api_matrix_probe.dart [--out <csv-path>]

import 'dart:convert';
import 'dart:io';

/// 三态测试凭据来源。
enum TestState {
  anonymous('anonymous', '.test_creds/ 无凭据'),
  nonvip('nonvip', '.test_creds/cj_nonvip.txt'),
  vip('vip', '.test_creds/cj_vip.txt');

  const TestState(this.label, this.credSource);
  final String label;
  final String credSource;
}

/// verdict 枚举（与 docs/API_CONTRACT_MATRIX.md 对齐）。
enum Verdict { ok, noPriv, needVerify, empty, risk, skip }

/// 矩阵一行。
class ProbeRow {
  ProbeRow({
    required this.endpoint,
    required this.method,
    required this.url,
    required this.state,
    this.http = -1,
    this.ms = -1,
    this.envelopeKeys = const [],
    this.successExpr = '',
    this.keyFields = '',
    this.verdict = Verdict.skip,
    this.note = '',
  });

  final String endpoint;
  final String method;
  final String url;
  final TestState state;
  final int http;
  final int ms;
  final List<String> envelopeKeys;
  final String successExpr;
  final String keyFields;
  final Verdict verdict;
  final String note;

  String get verdictLabel => switch (verdict) {
        Verdict.ok => 'OK',
        Verdict.noPriv => 'NO_PRIV',
        Verdict.needVerify => 'NEED_VERIFY(20028)',
        Verdict.empty => 'EMPTY',
        Verdict.risk => 'RISK',
        Verdict.skip => 'SKIP',
      };

  /// CSV 行（RFC4180 转义）。
  String toCsv() {
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    return [
      esc(endpoint),
      esc(method),
      esc(url),
      esc(state.label),
      http.toString(),
      ms.toString(),
      esc(envelopeKeys.join('|')),
      esc(successExpr),
      esc(keyFields),
      esc(verdictLabel),
      esc(note),
    ].join(',');
  }

  static List<String> header() => const [
        'endpoint', 'method', 'url', 'state', 'http', 'ms',
        'envelope_keys', 'success_expr', 'key_fields', 'verdict', 'note',
      ];
}

/// CSV 写出器：UTF-8 BOM 便于 Excel 直接打开。
class MatrixWriter {
  MatrixWriter(this.path);
  final String path;
  final List<ProbeRow> rows = [];

  void add(ProbeRow row) => rows.add(row);

  void write() {
    final buf = StringBuffer('\uFEFF'); // BOM
    buf.writeln(ProbeRow.header().map((h) => '"$h"').join(','));
    for (final r in rows) {
      buf.writeln(r.toCsv());
    }
    final f = File(path);
    if (f.parent.existsSync() == false) {
      f.parent.createSync(recursive: true);
    }
    f.writeAsStringSync(buf.toString(), encoding: utf8);
    stdout.writeln('[api_matrix_probe] wrote ${rows.length} rows -> $path');
  }
}

/// 端点模块清单（取自 lib/core/net/endpoints/ ls 结果，23 个 dart 模块）。
const endpointModules = <String>[
  'album_endpoints.dart',
  'artist_endpoints.dart',
  'auth_endpoints.dart',
  'collect_endpoints.dart',
  'comment_endpoints.dart',
  'fm_endpoints.dart',
  'lyric_models.dart',
  'misc_endpoints.dart',
  'models.dart',
  'models_util.dart',
  'mv_endpoints.dart',
  'play_endpoints.dart',
  'play_models.dart',
  'playlist_endpoints.dart',
  'playlist_models.dart',
  'playlist_write_endpoints.dart',
  'quality_endpoints.dart',
  'recommend_endpoints.dart',
  'search_endpoints.dart',
  'search_typed_endpoints.dart',
  'song_models.dart',
  'translation_endpoints.dart',
  'user_endpoints.dart',
];

/// 加载端点清单（骨架：静态清单；主会话可改为读
/// lib/core/net/endpoints/ 目录 + EndpointRegistry 展开为逐端点行）。
List<String> loadEndpointModules({String dir = 'lib/core/net/endpoints'}) {
  final d = Directory(dir);
  if (d.existsSync()) {
    return d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();
  }
  return endpointModules;
}

/// 凭据读取入口（骨架：只校验存在性，绝不打印内容 —— 日志脱敏铁律）。
void checkCreds() {
  for (final s in TestState.values) {
    if (s == TestState.anonymous) continue;
    final f = File(s.credSource);
    final ok = f.existsSync();
    stdout.writeln(
        '[creds] state=${s.label} source=${s.credSource} present=$ok');
  }
}

void main(List<String> args) {
  stdout.writeln('API Contract Matrix Probe (skeleton)');
  stdout.writeln('====================================');
  stdout.writeln('用法: dart run tool/api_matrix_probe.dart [--out <csv-path>]');
  stdout.writeln('');
  stdout.writeln('三态: anonymous(无凭据) / nonvip(.test_creds/cj_nonvip.txt) / '
      'vip(.test_creds/cj_vip.txt)');
  stdout.writeln('凭据不进仓库；日志输出一律脱敏（只留键名/长度，不留 token/cookie/t1/mid/p/key）');
  stdout.writeln('');
  checkCreds();
  final mods = loadEndpointModules();
  stdout.writeln('');
  stdout.writeln('端点模块清单 (${mods.length}):');
  for (final m in mods) {
    stdout.writeln('  - $m');
  }
  stdout.writeln('');
  stdout.writeln('骨架态：不发真实请求。网络层实现（L4 core/net）由主会话填充；'
      '填充后逐端点×三态产生 ProbeRow 并经 MatrixWriter 落 CSV。');

  // --out: 演示写出骨架 CSV（仅清单行，verdict=SKIP 待实测）。
  final outIdx = args.indexOf('--out');
  if (outIdx >= 0 && outIdx + 1 < args.length) {
    final w = MatrixWriter(args[outIdx + 1]);
    for (final m in mods) {
      w.add(ProbeRow(
        endpoint: m,
        method: '?',
        url: '?',
        state: TestState.anonymous,
        verdict: Verdict.skip,
        note: '待实测(骨架)',
      ));
    }
    w.write();
  }
}
