// L4 core/net · 封面字节获取（供动态主题取色）
// 只负责取字节，不解码、不取色（解码需 Flutter 侧，职责分层）。
// 铁律：try/catch + Log 留痕；限制体积与超时；不缓存到磁盘（内存即可）。
import 'dart:io';
import 'dart:typed_data';

import '../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'core.coverColor';

/// 获取封面字节（失败返回 null，不抛）。
/// [maxBytes] 超过则截断并返回 null（避免大图吃内存）；[timeout] 超时返回 null。
Future<Uint8List?> fetchCoverBytes(
  String url, {
  int maxBytes = 800 * 1024,
  Duration timeout = const Duration(seconds: 8),
}) async {
  HttpClient? client;
  try {
    final u = url.trim();
    if (u.isEmpty || !u.startsWith('http')) {
      Log.w(_tag, 'fetchCoverBytes invalid url');
      return null;
    }
    client = HttpClient();
    final req = await client.getUrl(Uri.parse(u)).timeout(timeout);
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode != 200) {
      Log.w(_tag, 'fetchCoverBytes http ${resp.statusCode}');
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        Log.w(_tag, 'fetchCoverBytes too large >$maxBytes');
        return null;
      }
    }
    if (bytes.isEmpty) {
      Log.w(_tag, 'fetchCoverBytes empty body');
      return null;
    }
    Log.d(_tag, 'fetchCoverBytes ok bytes=${bytes.length}');
    return Uint8List.fromList(bytes);
  } catch (e, st) {
    Log.e(_tag, 'fetchCoverBytes failed', e, st);
    return null;
  } finally {
    try {
      client?.close(force: true);
    } catch (e, st) {
      Log.e(_tag, 'close client failed', e, st);
    }
  }
}
