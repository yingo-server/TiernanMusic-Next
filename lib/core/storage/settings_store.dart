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
  KeyValueSettings(this._paths) : _file = _paths.fileIn('db', 'settings.json');

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
