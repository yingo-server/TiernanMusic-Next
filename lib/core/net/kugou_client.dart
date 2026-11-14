// L4 core/net 级 · HTTP 传输与端点声明注册表
// 原则：SDK 优先（dart:io HttpClient），每端点一模块声明式配置。
import 'dart:convert';
import 'dart:io';

import 'signing.dart';
import 'endpoint_registry.dart';

import '../../bridges/bridge_kernel.dart' show Log;

export 'endpoint_registry.dart' show Endpoint, EndpointRegistry;
import '../storage/resource_cache.dart' show ResourceCache;
import 'inflight.dart' show InFlight;

/// 端点声明：路径、方法、签名类型、x-router、默认参数开关。
/// 会话态（token/userid/mid/dfid），由 logic 层注入。
class KugouSession {
  String token = '';
  String userid = '';
  String mid = '';
  Map<String, String> cookies = {};

  String _dfid = '';

  /// dfid：首次访问生成随机 24 位（A-Z0-9），并回写缓存。
  /// 实测契约（docs/KUGOU_API.md §3.1）：play_url v5 必须随机 24 位 dfid
  /// + Cookie(t1)，恒 '-' 时匿名/登录态均 20028。
  String get dfid {
    if (_dfid.isEmpty) {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = DateTime.now().microsecondsSinceEpoch;
      _dfid = String.fromCharCodes(List.generate(
          24, (i) => chars.codeUnitAt((rnd >> (i % 31)) % chars.length)));
    }
    return _dfid;
  }

  set dfid(String v) => _dfid = v;
}

/// 端点注册表：所有端点在此声明，改 API 只改这里。
class KugouClient {
  KugouClient(this.session,
      {ResourceCache? cache, InFlight<Map<String, dynamic>>? inflight})
      : _cache = cache,
        _inflight = inflight;
  final KugouSession session;

  /// L2 磁盘缓存（可选；null = 不缓存）。
  final ResourceCache? _cache;

  /// 并发合并（可选；null = 不合并）。
  final InFlight<Map<String, dynamic>>? _inflight;
  HttpClient? _http;
  HttpClient get _h => _http ??= HttpClient()
    ..userAgent = KugouSign.defaultUa
    ..connectionTimeout = const Duration(seconds: 10);

  /// 执行端点请求。params：查询参数；body：POST JSON 体（参与签名）。
  /// rawBody（批F1-B）：非 null 时原样作为请求体发送并参与 android 签名
  /// （出处 KuGouMusicApi util/request.js：data 为字符串时直接签名/发送，
  /// delete_list 的 AES Base64 密文即此类）；响应非 JSON 时回退返回
  /// {'_raw_text': text} 交由端点层解密，不抛形状异常。
  Future<Map<String, dynamic>> request(
    Endpoint ep,
    Map<String, Object?> params, {
    Map<String, Object?> body = const {},
    String? rawBody,
  }) async {
    // 缓存/合并键：method + path + 排序 query + userid（键维度唯一真源）。
    final String cacheKey = _cacheKeyOf(ep, params, body: body);
    final bool cacheable = ep.cacheable && _cache != null && rawBody == null;
    if (cacheable) {
      final hit = await _cache!.getJson(cacheKey);
      if (hit != null) {
        Log.d('core.net', 'cache hit $cacheKey');
        return hit;
      }
      Log.d('core.net', 'cache miss $cacheKey');
    }
    Future<Map<String, dynamic>> run() => _requestRaw(
          ep,
          params,
          body: body,
          rawBody: rawBody,
        );
    // 并发同键合并：只发一次真实请求，其余等待同一结果。
    final res = _inflight == null
        ? await run()
        : await _inflight!.run(cacheKey, run);
    if (cacheable) {
      try {
        await _cache!.putJson(cacheKey, res);
      } catch (e, st) {
        Log.e('core.net', 'cache store failed $cacheKey', e, st);
      }
    }
    return res;
  }

  /// 缓存键：method + path + 排序后的 query + body 摘要 + userid + token 态。
  /// 修复（批R2 审计）：旧键不含 body（同 query 不同 body 的 POST 会错误
  /// 合并/命中）也不含 token 维度（匿名↔登录脏命中）。
  String _cacheKeyOf(Endpoint ep, Map<String, Object?> params,
      {Map<String, Object?> body = const {}}) {
    try {
      final keys = params.keys.toList()..sort();
      final q = keys.map((k) => '$k=${params[k]}').join('&');
      final b = body.isEmpty
          ? ''
          : '&body=${body.hashCode}';
      return '${ep.method} ${ep.base}${ep.path}?$q$b'
          '&uid=${session.userid}'
          '&tk=${session.token.isEmpty ? 'anon' : session.token.hashCode}';
    } catch (e, st) {
      Log.e('core.net', 'cacheKey build failed', e, st);
      return '${ep.method} ${ep.path}';
    }
  }

  /// 真实请求（不含缓存/合并）。
  Future<Map<String, dynamic>> _requestRaw(
    Endpoint ep,
    Map<String, Object?> params, {
    Map<String, Object?> body = const {},
    String? rawBody,
  }) async {
    final p = Map<String, Object?>.from(params);
    final bodyStr =
        rawBody ?? (ep.method == 'POST' ? jsonEncode(body) : '');
    if (!ep.clearDefaultParams) {
      p..putIfAbsent('dfid', () => session.dfid)
        ..putIfAbsent('uuid', () => '-')
        ..putIfAbsent('appid', () => KugouSign.appid)
        ..putIfAbsent('clientver', () => KugouSign.clientver);
      // 实测（A6 + 批05 复测）：srcappid 参与签名会让搜索/cloudlist 等
      // 端点返回 20006；不带则 status=1。默认不注入，仅 includeSrcappid 开启。
      if (ep.includeSrcappid) {
        p.putIfAbsent('srcappid', () => KugouSign.srcappid);
      }
      p..putIfAbsent('mid', () => session.mid.isEmpty ? '0' : session.mid)
        ..putIfAbsent('clienttime',
            () => DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if (session.token.isNotEmpty) p.putIfAbsent('token', () => session.token);
      if (session.userid.isNotEmpty) {
        p.putIfAbsent('userid', () => session.userid);
      }
    }
    if (ep.encryptKey && p['hash'] != null) {
      p['key'] = KugouSign.playKey(
          '${p['hash']}'.toLowerCase(), session.mid, session.userid);
    }
    switch (ep.signType) {
      case SignType.android:
        p['signature'] = KugouSign.android(p, body: bodyStr);
      case SignType.web:
        p['signature'] = KugouSign.web(p);
      case SignType.register:
        p['signature'] = KugouSign.register(p);
      case SignType.none:
        break;
    }
    final q = p.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value.toString())}')
        .join('&');
    // 实测注意：签名串用原始类型（数字不带引号），发送统一字符串化。
    // 参数多参不缺参：默认参数恒显式在场并参与签名（FINDINGS.md §4-5）。
    final uri = Uri.parse('${ep.base}${ep.path}?$q');
    final req = await _h.openUrl(ep.method, uri);
    if (ep.router != null) req.headers.set('x-router', ep.router!);
    if (ep.tid != null) req.headers.set('kg-tid', ep.tid!);
    final ct = DateTime.now().millisecondsSinceEpoch;
    req.headers
      ..set('dfid', session.dfid)
      ..set('clienttime', '${ct ~/ 1000}')
      ..set('mid', session.mid)
      ..set('kg-rc', '1')
      ..set('kg-thash', '5d816a0')
      ..set('kg-rec', '1')
      ..set('kg-rf', 'B9EDA08A64250DEFFBCADDEE00F8F25F');
    // Cookie 一次性拼接（旧实现对每条 cookie 全量重写整头，效率低且易错）。
    if (session.cookies.isNotEmpty) {
      req.headers.set('Cookie', session.cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; '));
    }
    if (bodyStr.isNotEmpty) {
      req.headers.contentType = ContentType.json;
      req.write(bodyStr);
    }
    // 审查修复：响应整体超时（旧代码只限连接超时，服务器挂起时
    // join 永久悬挂且 InFlight 会让所有同键等待者一起悬挂）。
    const responseTimeout = Duration(seconds: 15);
    // 批2-F3：响应头阶段超时同样归一为 KugouApiException(-2)。旧版裸
    // timeout 抛 TimeoutException，与 body join 侧的 -2 语义不一致，上层
    // 无法按错误码分类重试；两段 15s 时长与 dfid 生成算法均不变。
    final res = await req.close().timeout(responseTimeout, onTimeout: () {
      Log.e('core.net', 'response header timeout ${ep.id}');
      throw KugouApiException(-2, 'response header timeout (${ep.id})');
    });
    final text = await res
        .transform(utf8.decoder)
        .join()
        .timeout(responseTimeout, onTimeout: () {
      Log.e('core.net', 'response body timeout ${ep.id}');
      throw KugouApiException(-2, 'response body timeout (${ep.id})');
    });
    if (res.statusCode != 200) {
      throw KugouApiException(res.statusCode, 'http ${res.statusCode}: $text');
    }
    // 审查修复：解析错归一为 KugouApiException（旧代码 FormatException
    // 直接外抛，HTTP 错/业务错/解析错混流，上层无法分类重试）。
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e, st) {
      Log.e('core.net', 'json decode failed ${ep.id} len=${text.length}', e, st);
      throw KugouApiException(-3,
          'invalid json from ${ep.id}: ${text.substring(0, text.length < 80 ? text.length : 80)}');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    // rawBody 端点（加密响应如 delete_list）回退原文，由端点层解密。
    if (rawBody != null) return <String, dynamic>{'_raw_text': text};
    // 实测（FINDINGS.md §1）：play_url 等端点成功时顶层即数据，
    // 调用方按端点自行取 url/status/priv_status 等顶层字段。
    throw KugouApiException(res.statusCode, 'unexpected response shape');
  }

  void close() => _http?.close();
}

class KugouApiException implements Exception {
  KugouApiException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'KugouApiException($code): $message';
}
