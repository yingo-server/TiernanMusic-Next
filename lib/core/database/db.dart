// L4 core/database · DatabaseService
// Isar 3.x 实例的懒单例持有者；所有公开方法 try/catch + kernel Log 留痕。
// 铁律：仅依赖 isar 与 kernel Log，禁止 import core/net、logic、surface、flutter。

import 'dart:io';

import 'package:isar/isar.dart';

import '../../bridges/bridge_kernel.dart' show Log;
import 'entities.dart';

/// 数据库服务：open(dir) 注册四 schema，close 释放；懒单例持有 Isar。
class DatabaseService {
  DatabaseService._();

  static const String _tag = 'db';

  static DatabaseService? _instance;
  static Isar? _isar;

  /// 获取单例（不自动打开，open 由 bootloader 显式调用）。
  static DatabaseService get instance => _instance ??= DatabaseService._();

  /// 已打开的 Isar 实例；未打开时抛错（调用方应先 open）。
  static Isar get isar {
    final i = _isar;
    if (i == null) {
      Log.e(_tag, 'isar accessed before open');
      throw StateError('DatabaseService: isar not opened');
    }
    return i;
  }

  /// 是否已打开。
  static bool get isOpen => _isar != null && _isar!.isOpen;

  /// 打开数据库并注册四 schema。幂等：已打开则直接返回。
  Future<void> open(String dir) async {
    try {
      if (isOpen) {
        Log.d(_tag, 'open skipped, already open dir=$dir');
        return;
      }
      _isar = await Isar.open(
        // 四 schema：歌曲 / 歌单 / 播放历史 / 多账号档案（批2-A）。
        [
          SongRecordSchema,
          PlaylistMetaSchema,
          PlayHistoryEntrySchema,
          AccountRecordSchema,
        ],
        directory: dir,
        name: 'tiernan_music_next',
      );
      Log.d(_tag, 'opened dir=$dir');
    } catch (e, st) {
      Log.e(_tag, 'open failed dir=$dir', e, st);
      rethrow;
    }
  }

  /// 关闭数据库并清空引用（不删除文件）。幂等。
  Future<void> close() async {
    try {
      final i = _isar;
      if (i == null) {
        Log.d(_tag, 'close skipped, not open');
        return;
      }
      await i.close();
      _isar = null;
      Log.d(_tag, 'closed');
    } catch (e, st) {
      Log.e(_tag, 'close failed', e, st);
      rethrow;
    }
  }

  /// 关闭并删除数据库文件（用于登出/清库）。危险操作。
  Future<void> deleteAll(String dir) async {
    try {
      await close();
      // 批2-F3：旧实现 delete(recursive: true) 会把整个 db 目录连同
      // settings.json 一起删掉（清库/登出丢全部用户设置）。改为只删 Isar
      // 数据文件；目录本身与非 Isar 文件一律保留。
      // Isar 3.x 实际文件名：open(name: 'tiernan_music_next') →
      // <dir>/tiernan_music_next.isar（name 缺省时为 default.isar），
      // 可能伴随 <name>.isar.lock 锁文件。
      final d = Directory(dir);
      if (!d.existsSync()) {
        Log.d(_tag, 'deleteAll skipped, dir absent=$dir');
        return;
      }
      var removed = 0;
      for (final entity in d.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name == 'settings.json') continue; // 用户设置必须保留
        if (!(name.endsWith('.isar') || name.endsWith('.isar.lock'))) continue;
        await entity.delete();
        removed++;
        Log.d(_tag, 'removed isar file=$name');
      }
      Log.w(_tag, 'deleted $removed isar file(s) dir=$dir (settings.json kept)');
    } catch (e, st) {
      Log.e(_tag, 'deleteAll failed dir=$dir', e, st);
      rethrow;
    }
  }
}
