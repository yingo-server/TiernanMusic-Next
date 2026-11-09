// L4 core/database · DatabaseService
// Isar 3.x 实例的懒单例持有者；所有公开方法 try/catch + kernel Log 留痕。
// 铁律：仅依赖 isar 与 kernel Log，禁止 import core/net、logic、surface、flutter。

import 'dart:io';

import 'package:isar/isar.dart';

import '../../kernel/kernel.dart' show Log;
import 'entities.dart';

/// 数据库服务：open(dir) 注册三 schema，close 释放；懒单例持有 Isar。
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

  /// 打开数据库并注册三 schema。幂等：已打开则直接返回。
  Future<void> open(String dir) async {
    try {
      if (isOpen) {
        Log.d(_tag, 'open skipped, already open dir=$dir');
        return;
      }
      _isar = await Isar.open(
        [SongRecordSchema, PlaylistMetaSchema, PlayHistoryEntrySchema],
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
      // Isar 3.x 无静态 deleteInstance：直接删除目录下数据库文件。
      final d = Directory(dir);
      if (d.existsSync()) {
        await d.delete(recursive: true);
      }
      Log.w(_tag, 'deleted database dir=$dir');
    } catch (e, st) {
      Log.e(_tag, 'deleteAll failed dir=$dir', e, st);
      rethrow;
    }
  }
}
