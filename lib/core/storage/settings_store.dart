// L4 core/storage 级 · 键值设置持久化（JSON 文件 + 全内存缓存）
// 职责：settings.json 读写；内存缓存为主，落盘为证；零 Flutter import。
import 'dart:convert';
import 'dart:io';

import '../../bridges/bridge_kernel.dart' show Log;
import 'paths.dart';

/// KV 设置门面。
///
/// 职责：getString/setString/getBool/getInt/remove 等键值操作；进程内 Map 缓存，
/// 每次变更即原子落盘（.part → rename）。所有公开方法 try/catch 失败必 Log.e 留痕。
class KeyValueSettings {
  /// 批2-F3：进程内共享实例入口，同 paths（以 settings.json 绝对路径为键）
  /// 恒返回同一对象，消除多处 `new KeyValueSettings(StoragePaths.I)` 各持一份
  /// 内存缓存、写读互盲的问题。用法：
  /// `KeyValueSettings.shared(StoragePaths.I)`。
  /// 说明：bootloader 仍按原样 `new`（L2 已保证单实例，本批次按约束不改其
  /// 装配逻辑）；构造器把自身登记进共享表，故 shared() 在启动后拿到的正是
  /// L2 那一份。player_controller._fallbackSettings 属 F1 文件，本批次禁止
  /// 改动 —— F1 完成后由主会话把该处 `new KeyValueSettings(...)` 改为
  /// `KeyValueSettings.shared(...)` 即可完成全局收口。
  static final Map<String, KeyValueSettings> _sharedByPath = {};

  static KeyValueSettings shared(StoragePaths paths) {
    final key = paths.fileIn('db', 'settings.json').path;
    final hit = _sharedByPath[key];
    if (hit != null) return hit;
    final created = KeyValueSettings(paths);
    _sharedByPath[key] = created;
    return created;
  }

  KeyValueSettings(this._paths) : _file = _paths.fileIn('db', 'settings.json') {
    // 登记自身，使 shared() 能命中任何已构造的同路径实例（尤其 L2 的那份）。
    _sharedByPath[_file.path] ??= this;
  }

  final StoragePaths _paths;
  final File _file;
  final Map<String, dynamic> _cache = {};
  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) return;
    try {
      if (_file.existsSync()) {
        final raw = _file.readAsStringSync();
        final j = jsonDecode(raw);
        if (j is Map) _cache.addAll(j.cast<String, dynamic>());
      }
      _loaded = true;
      Log.d('kvsettings', 'loaded ${_cache.length} keys');
    } catch (e, st) {
      Log.e('kvsettings', 'load failed', e, st);
      _loaded = true; // 损坏文件不阻塞启动，按空表继续
    }
  }

  bool _flush() {
    try {
      final tmp = File('${_file.path}.part');
      tmp.writeAsStringSync(jsonEncode(_cache), flush: true);
      if (_file.existsSync()) _file.deleteSync();
      tmp.renameSync(_file.path);
      return true;
    } catch (e, st) {
      Log.e('kvsettings', 'flush failed', e, st);
      return false;
    }
  }

  // ─── 字符串 ───

  String? getString(String key) {
    try {
      _ensureLoaded();
      return _cache[key] as String?;
    } catch (e, st) {
      Log.e('kvsettings', 'getString($key) failed', e, st);
      return null;
    }
  }

  bool setString(String key, String value) {
    try {
      _ensureLoaded();
      _cache[key] = value;
      return _flush();
    } catch (e, st) {
      Log.e('kvsettings', 'setString($key) failed', e, st);
      return false;
    }
  }

  // ─── 布尔 ───

  bool? getBool(String key) {
    try {
      _ensureLoaded();
      final v = _cache[key];
      return v is bool ? v : (v is String ? v == 'true' : null);
    } catch (e, st) {
      Log.e('kvsettings', 'getBool($key) failed', e, st);
      return null;
    }
  }

  bool setBool(String key, bool value) {
    try {
      _ensureLoaded();
      _cache[key] = value;
      return _flush();
    } catch (e, st) {
      Log.e('kvsettings', 'setBool($key) failed', e, st);
      return false;
    }
  }

  // ─── 整数 ───

  int? getInt(String key) {
    try {
      _ensureLoaded();
      final v = _cache[key];
      return v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
    } catch (e, st) {
      Log.e('kvsettings', 'getInt($key) failed', e, st);
      return null;
    }
  }

  bool setInt(String key, int value) {
    try {
      _ensureLoaded();
      _cache[key] = value;
      return _flush();
    } catch (e, st) {
      Log.e('kvsettings', 'setInt($key) failed', e, st);
      return false;
    }
  }

  // ─── 浮点（倍速等 UI 偏好；内部按 num 存取） ───

  double? getDouble(String key) {
    try {
      _ensureLoaded();
      final v = _cache[key];
      return v is double ? v : (v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null));
    } catch (e, st) {
      Log.e('kvsettings', 'getDouble($key) failed', e, st);
      return null;
    }
  }

  bool setDouble(String key, double value) {
    try {
      _ensureLoaded();
      _cache[key] = value;
      return _flush();
    } catch (e, st) {
      Log.e('kvsettings', 'setDouble($key) failed', e, st);
      return false;
    }
  }

  // ─── 删除 / 清空 ───

  bool remove(String key) {
    try {
      _ensureLoaded();
      _cache.remove(key);
      return _flush();
    } catch (e, st) {
      Log.e('kvsettings', 'remove($key) failed', e, st);
      return false;
    }
  }

  bool clear() {
    try {
      _cache.clear();
      return _flush();
    } catch (e, st) {
      Log.e('kvsettings', 'clear failed', e, st);
      return false;
    }
  }
}
