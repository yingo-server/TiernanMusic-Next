// L5 logic/catalog · 收藏体系门面（功能对齐批2-C · 逻辑层，窄任务）
// 契约：本地镜像为单一事实源（settings['favorites'] JSON 数组）；
//   写端点成功才改镜像；登录守卫在此层（端点层不判）；同 hash 并发防重复提交。
// 铁律：无 UI、无 IO 直连；每方法 try/catch + Log('logic.collect')；
//   每个 async 分支显式 return（避免 body_might_complete_normally）。
import 'dart:convert';

import '../../kernel/kernel.dart' show Log;
import '../../core/net/kugou_client.dart';
import '../../core/net/endpoints/collect_endpoints.dart' as ep;
import '../../core/storage/settings_store.dart';

const String _tag = 'logic.collect';
const String _kFavoritesKey = 'favorites';

/// 收藏逻辑门面。构造注入（沿用 L5 门面风格，见 rank_logic.dart）：
/// - client：L4 网络执行器；settings：L4 KV 持久化；
/// - isLoggedIn：登录守卫回调（由装配层提供，避免反向依赖 auth 模块）；
/// - onChanged：镜像/计数变化后的可选通知（surface 刷新用）。
class CollectLogic {
  CollectLogic({
    required KugouClient client,
    required KeyValueSettings settings,
    required bool Function() isLoggedIn,
    void Function()? onChanged,
  })  : _client = client,
        _settings = settings,
        _isLoggedIn = isLoggedIn,
        _onChanged = onChanged {
    _load();
    Log.d(_tag, 'init size=${_favorites.length} count=$_count');
  }

  final KugouClient _client;
  final KeyValueSettings _settings;
  final bool Function() _isLoggedIn;
  final void Function()? _onChanged;

  /// 本地收藏镜像（hash 恒小写）。
  final Set<String> _favorites = <String>{};

  /// 收藏计数：优先服务端返回，缺失则以镜像条数为准。
  int _count = 0;

  /// 同 hash 在途写操作：并发复用同一 Future（防重锁 / 幂等去重键 = hash）。
  final Map<String, Future<ep.CollectResult>> _inFlight = {};

  /// 当前计数（同步；镜像变化或端点返回 count 时更新）。
  int get count {
    try {
      return _count;
    } catch (e, st) {
      Log.e(_tag, 'count getter failed', e, st);
      return 0;
    }
  }

  /// 在途写操作数量（诊断用）。
  int get inFlightCount => _inFlight.length;

  /// 是否已收藏（同步，查询本地镜像，不打网络）。
  bool isCollected(String hash) {
    try {
      return _favorites.contains(_norm(hash));
    } catch (e, st) {
      Log.e(_tag, 'isCollected failed hash=$hash', e, st);
      return false;
    }
  }

  /// 收藏列表快照（排序后不可变，供 surface 渲染）。
  List<String> listFavorites() {
    try {
      final list = _favorites.toList(growable: false)..sort();
      return List<String>.unmodifiable(list);
    } catch (e, st) {
      Log.e(_tag, 'listFavorites failed', e, st);
      return const <String>[];
    }
  }

  /// 收藏/取消切换。
  /// - 未登录：直接返回 needsLogin=true，不写镜像、不发请求、不进防重锁；
  /// - 空 hash：返回默认失败结果；
  /// - 同 hash 并发：putIfAbsent 复用同一 Future，whenComplete 释放锁；
  /// - 端点成功：更新镜像 + 计数 + _flush() + onChanged?；失败不写镜像。
  Future<ep.CollectResult> toggle(String hash, int mixSongId) {
    try {
      final h = _norm(hash);
      if (h.isEmpty) {
        Log.w(_tag, 'toggle empty hash');
        return Future.value(const ep.CollectResult());
      }
      if (!_isLoggedIn()) {
        Log.w(_tag, 'toggle needsLogin hash=$h');
        return Future.value(const ep.CollectResult(needsLogin: true));
      }
      final running = _inFlight[h];
      if (running != null) {
        Log.d(_tag, 'toggle joined in-flight hash=$h');
        return running;
      }
      // putIfAbsent：唯一在途写；whenComplete 无论成功/失败/异常都释放锁。
      final shared = _inFlight.putIfAbsent(h, () {
        return _doToggle(h, mixSongId).whenComplete(() {
          try {
            _inFlight.remove(h);
            Log.d(_tag, 'toggle lock released hash=$h');
          } catch (e, st) {
            Log.e(_tag, 'toggle lock release failed hash=$h', e, st);
          }
        });
      });
      Log.d(_tag, 'toggle start hash=$h collected=${_favorites.contains(h)}');
      return shared;
    } catch (e, st) {
      Log.e(_tag, 'toggle failed hash=$hash', e, st);
      return Future.value(const ep.CollectResult());
    }
  }

  /// 实际写流程（每个分支显式 return）。
  Future<ep.CollectResult> _doToggle(String h, int mixSongId) async {
    try {
      final wasCollected = _favorites.contains(h);
      final ep.CollectResult r;
      if (wasCollected) {
        r = await ep.cancelCollectByHash(_client, h);
      } else {
        r = await ep.collectSongByHash(_client, h, mixSongId);
      }
      if (!r.ok) {
        Log.w(_tag, 'toggle rejected hash=$h cancel=$wasCollected '
            'count=${r.count} (mirror unchanged)');
        return r;
      }
      // 写成功后才动镜像：失败/未登录绝不落本地状态。
      if (wasCollected) {
        _favorites.remove(h);
      } else {
        _favorites.add(h);
      }
      _count = r.count > 0 ? r.count : _favorites.length;
      final flushed = _flush();
      _notify();
      Log.d(_tag, 'toggle ok hash=$h cancel=$wasCollected '
          'size=${_favorites.length} count=$_count flushed=$flushed');
      return ep.CollectResult(ok: true, count: _count);
    } catch (e, st) {
      Log.e(_tag, '_doToggle failed hash=$h', e, st);
      return const ep.CollectResult();
    }
  }

  /// 用服务端收藏计数校准本地计数（不覆盖镜像内容；失败保留原计数）。
  Future<int> refreshCount() async {
    try {
      final n = await ep.getFavoriteCount(_client);
      if (n > 0) {
        _count = n;
        _notify();
      }
      Log.d(_tag, 'refreshCount server=$n count=$_count');
      return _count;
    } catch (e, st) {
      Log.e(_tag, 'refreshCount failed', e, st);
      return _count;
    }
  }

  /// 读镜像：settings.getString('favorites') → JSON 数组 → Set<String>。
  void _load() {
    try {
      final raw = _settings.getString(_kFavoritesKey);
      if (raw == null || raw.isEmpty) {
        _count = 0;
        return;
      }
      final j = jsonDecode(raw);
      if (j is List) {
        for (final v in j) {
          final h = _norm('$v');
          if (h.isNotEmpty) _favorites.add(h);
        }
      } else {
        Log.w(_tag, 'favorites not a JSON array, ignored');
      }
      _count = _favorites.length;
      return;
    } catch (e, st) {
      Log.e(_tag, '_load failed', e, st);
      _count = _favorites.length;
      return;
    }
  }

  /// 写回镜像：JSON 数组字符串。失败必 Log 留痕，不静默吞。
  bool _flush() {
    try {
      final ok = _settings.setString(
          _kFavoritesKey, jsonEncode(_favorites.toList(growable: false)));
      if (!ok) Log.w(_tag, '_flush setString returned false');
      return ok;
    } catch (e, st) {
      Log.e(_tag, '_flush failed', e, st);
      return false;
    }
  }

  void _notify() {
    try {
      final cb = _onChanged;
      if (cb != null) cb();
      return;
    } catch (e, st) {
      Log.e(_tag, 'onChanged callback failed', e, st);
      return;
    }
  }

  String _norm(String hash) {
    try {
      return hash.trim().toLowerCase();
    } catch (e, st) {
      Log.e(_tag, '_norm failed', e, st);
      return '';
    }
  }
}
