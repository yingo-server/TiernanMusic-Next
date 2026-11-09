// L4 core/storage 级 · 存储根路径解析与子目录管理
// 铁律：纯 dart:io，不依赖 flutter/path_provider；rootDir 由外部（L5 logic 装配时）注入。
import 'dart:io';

import '../../kernel/kernel.dart' show Log;

/// 存储路径门面。
///
/// 职责：持有存储根目录（注入），按用途解析子目录（downloads/cache/lyrics/db），
/// 子目录懒创建（首次访问时 ensure 存在）。所有公开方法 try/catch 失败必 Log.e 留痕。
class StoragePaths {
  StoragePaths._(this.rootDir);

  /// 注入式构造：root 必须由调用方给出（L2 bootloader 装配时来自 path_provider 桥）。
  static StoragePaths? _instance;

  /// 装配入口。重复调用以最后一次为准（bootloader 幂等装配）。
  static StoragePaths init(String rootPath) {
    final inst = StoragePaths._(Directory(rootPath));
    _instance = inst;
    Log.d('paths', 'storage root injected: $rootPath');
    return inst;
  }

  /// 获取当前实例；未 init 时抛出（bootloader 装配纪律，fail-fast 而非静默默认路径）。
  static StoragePaths get I {
    final inst = _instance;
    if (inst == null) {
      const msg = 'StoragePaths not initialized: call StoragePaths.init(root) first';
      Log.e('paths', msg);
      throw StateError(msg);
    }
    return inst;
  }

  final Directory rootDir;

  static const _subs = ['downloads', 'cache', 'lyrics', 'db'];

  /// 存储根目录（懒创建）。
  Directory root() => _ensureDir(rootDir, 'root');

  /// 解析子目录并懒创建。name 仅允许固定集合，防任意路径注入。
  Directory resolveSub(String name) {
    try {
      if (!_subs.contains(name)) {
        throw ArgumentError('unknown storage sub name: $name (allowed: $_subs)');
      }
      return _ensureDir(Directory(_join(rootDir.path, name)), name);
    } catch (e, st) {
      Log.e('paths', 'resolveSub($name) failed', e, st);
      rethrow;
    }
  }

  Directory downloads() => resolveSub('downloads');
  Directory cache() => resolveSub('cache');
  Directory lyrics() => resolveSub('lyrics');
  Directory db() => resolveSub('db');

  /// 在子目录下解析文件路径（不创建文件，仅拼路径；目录由调用方 ensure）。
  File fileIn(String subName, String fileName) {
    try {
      return File(_join(resolveSub(subName).path, fileName));
    } catch (e, st) {
      Log.e('paths', 'fileIn($subName, $fileName) failed', e, st);
      rethrow;
    }
  }

  Directory _ensureDir(Directory d, String tag) {
    try {
      if (!d.existsSync()) {
        d.createSync(recursive: true);
        Log.d('paths', 'created dir [$tag]: ${d.path}');
      }
      return d;
    } catch (e, st) {
      Log.e('paths', 'ensureDir($tag) failed', e, st);
      rethrow;
    }
  }
}

/// 纯路径拼接（不引入 package:path）。
String _join(String a, String b) =>
    a.endsWith(Platform.pathSeparator) ? '$a$b' : '$a${Platform.pathSeparator}$b';
