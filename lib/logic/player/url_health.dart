// L5 logic · url_health：URL 健康检查（可达性探测）。
// 只判可达性，不判权限（不做登录态/防盗链校验）；HEAD 不被支持（405/501 或
// 连接异常）时自动降级为 GET + Range: bytes=0-0；超时阈值 timeout 可配置。
// 不读 DNS、不做 ICMP；HttpClient 每次 close(force: true) 释放，禁止泄漏。
library;

import 'dart:async';
import 'dart:io';

import '../../bridges/bridge_kernel.dart' show logD, logE;

/// 健康结论：healthy 可达；redirect 指向重定向；dead 失效；
/// timeout 超时；unsupported 非 http/https。
enum UrlHealth { healthy, redirect, dead, timeout, unsupported }

/// 单次探测结果。
class UrlProbeResult {
  final UrlHealth health;
  final int statusCode;
  final int ms;
  final String? finalUrl; // 重定向后的最终 URL
  final String? error;

  const UrlProbeResult({
    required this.health,
    required this.statusCode,
    required this.ms,
    this.finalUrl,
    this.error,
  });

  const UrlProbeResult.unsupported(String url)
      : this(
          health: UrlHealth.unsupported,
          statusCode: 0,
          ms: 0,
          finalUrl: url,
          error: 'non-http(s) scheme',
        );
}

class UrlHealthChecker {
  final Duration timeout;
  final int maxRedirects;
  final HttpClient Function()? clientFactory;

  UrlHealthChecker({
    Duration? timeout,
    this.maxRedirects = 3,
    this.clientFactory,
  }) : timeout = timeout ?? const Duration(seconds: 3);

  HttpClient _newClient() {
    final c = clientFactory != null
        ? clientFactory!()
        : HttpClient();
    c.connectionTimeout = timeout;
    c.autoUncompress = false;
    return c;
  }

  Future<UrlProbeResult> _probe(String url) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        logD('UrlHealth', 'unsupported scheme: $url');
        return UrlProbeResult.unsupported(url);
      }
    } catch (e, st) {
      logE('UrlHealth', 'parse failed: $url', e, st);
      return UrlProbeResult(
        health: UrlHealth.dead,
        statusCode: 0,
        ms: sw.elapsedMilliseconds,
        error: 'parse: $e',
      );
    }

    try {
      final r = await _probeOnce(url, head: true);
      // 405/501：HEAD 不被支持，降级 Range GET。
      if (r.statusCode == 405 || r.statusCode == 501) {
        logD('UrlHealth', 'HEAD 405/501, fallback GET+Range: $url');
        return await _probeOnce(url, head: false);
      }
      return r;
    } catch (e) {
      // HEAD 阶段异常（如部分服务器直接断连）：降级 Range GET。
      try {
        return await _probeOnce(url, head: false);
      } catch (e2, st2) {
        logE('UrlHealth', 'probe failed: $url', e2, st2);
        return UrlProbeResult(
          health: sw.elapsed > timeout
              ? UrlHealth.timeout
              : UrlHealth.dead,
          statusCode: 0,
          ms: sw.elapsedMilliseconds,
          error: '$e2',
        );
      }
    } finally {
      sw.stop();
    }
  }

  Future<UrlProbeResult> _probeOnce(
    String url, {
    required bool head,
    int redirects = 0,
  }) async {
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = _newClient();
      final req = await client
          .openUrl(head ? 'HEAD' : 'GET', Uri.parse(url))
          .timeout(timeout);
      if (!head) req.headers.set('Range', 'bytes=0-0');
      final rsp = await req.close().timeout(timeout);
      final status = rsp.statusCode;
      final loc = rsp.headers.value(HttpHeaders.locationHeader);
      // 丢弃响应体，尽快释放连接。
      try {
        await rsp.drain<void>().timeout(timeout);
      } catch (_) {
        // drain 失败不致命：连接由 close(force:true) 兜底释放，不静默吞业务错误。
      }

      // 重定向链：301/302/307/308，最多 maxRedirects 次。
      if ((status == 301 || status == 302 || status == 307 || status == 308) &&
          loc != null &&
          loc.isNotEmpty) {
        if (redirects >= maxRedirects) {
          return UrlProbeResult(
            health: UrlHealth.redirect,
            statusCode: status,
            ms: sw.elapsedMilliseconds,
            finalUrl: url,
            error: 'too many redirects',
          );
        }
        final next = Uri.parse(url).resolve(loc).toString();
        return await _probeOnce(
          next,
          head: head,
          redirects: redirects + 1,
        );
      }

      final health = (status >= 200 && status < 300)
          ? UrlHealth.healthy
          : UrlHealth.dead;
      logD('UrlHealth',
          'probe $url -> $status ($health, ${sw.elapsedMilliseconds}ms)');
      return UrlProbeResult(
        health: health,
        statusCode: status,
        ms: sw.elapsedMilliseconds,
        finalUrl: url,
      );
    } on TimeoutException {
      return UrlProbeResult(
        health: UrlHealth.timeout,
        statusCode: 0,
        ms: sw.elapsedMilliseconds,
        finalUrl: url,
        error: 'timeout after ${timeout.inMilliseconds}ms',
      );
    } catch (e, st) {
      logE('UrlHealth', 'request failed: $url', e, st);
      return UrlProbeResult(
        health: UrlHealth.dead,
        statusCode: 0,
        ms: sw.elapsedMilliseconds,
        finalUrl: url,
        error: '$e',
      );
    } finally {
      sw.stop();
      try {
        client?.close(force: true);
      } catch (e) {
        logE('UrlHealth', 'client close failed', e, StackTrace.current);
      }
    }
  }

  /// 按顺序探测候选列表，返回第一个 healthy 的【原始 URL】
  /// （非重定向后地址，避免 CDN 跳转篡改）；最多尝试 maxTries 个，全失败返回 null。
  Future<String?> firstHealthy(
    List<String> candidates, {
    int maxTries = 3,
  }) async {
    var tried = 0;
    for (final url in candidates) {
      if (tried >= maxTries) break;
      tried++;
      try {
        final r = await _probe(url);
        if (r.health == UrlHealth.healthy) return url;
      } catch (e, st) {
        logE('UrlHealth', 'firstHealthy item failed: $url', e, st);
      }
    }
    return null;
  }
}
