// L4 core/database · Isar 3.x 实体定义
// 铁律：本文件仅依赖 isar，禁止 import core/net、logic、surface、flutter。
// 注：part 文件 entities.g.dart 由 build_runner 生成（Isar 代码生成）。

import 'package:isar/isar.dart';

part 'entities.g.dart';

/// 歌曲记录（本地曲库唯一事实源）。
/// hash 为酷狗歌曲哈希，业务唯一键；id 由 Isar 自动自增。
@collection
class SongRecord {
  Id id = Isar.autoIncrement;

  /// 文件名（展示用，通常为 "歌手 - 标题"）。
  @Index(type: IndexType.value)
  String fileName = '';

  /// 歌手名。
  @Index(type: IndexType.value)
  String singerName = '';

  /// 专辑名。
  String albumName = '';

  /// 音频时长（毫秒）。
  int durationMs = 0;

  /// 酷狗歌曲哈希，唯一业务键。
  @Index(unique: true, replace: true)
  String hash = '';

  /// 酷狗 mixSongId（在线标识）。
  String mixSongId = '';

  /// 酷狗 albumAudioId（在线标识）。
  String albumAudioId = '';

  /// 音质标签（如 128/320/flac）。
  String quality = '';

  /// 本地缓存路径；null = 仅在线，未下载。
  String? localPath;

  /// 入库时间（epoch ms）。
  @Index()
  int addedAt = 0;

  /// 播放次数。
  @Index()
  int playCount = 0;

  /// 最近一次播放时间（epoch ms），null = 从未播放。
  @Index()
  int? lastPlayedAt;
}

/// 歌单元数据。
@collection
class PlaylistMeta {
  Id id = Isar.autoIncrement;

  /// 歌单业务 id，唯一。
  @Index(unique: true, replace: true)
  String playlistId = '';

  /// 歌单名。
  String name = '';

  /// 封面 URL（可空语义用空串表示）。
  String coverUrl = '';

  /// 歌单内歌曲 hash 有序列表。
  List<String> songHashes = [];

  /// 创建时间（epoch ms）。
  int createdAt = 0;

  /// 最近更新时间（epoch ms）。
  int updatedAt = 0;

  /// 来源：'online' | 'local'。
  @Index()
  String source = 'local';
}

/// 播放历史条目（一条 = 一次播放事件，去重逻辑在 HistoryDao.record）。
@collection
class PlayHistoryEntry {
  Id id = Isar.autoIncrement;

  /// 歌曲哈希。
  @Index()
  String hash = '';

  /// 文件名快照。
  String fileName = '';

  /// 歌手名快照。
  String singerName = '';

  /// 播放时间（epoch ms）。
  @Index()
  int playedAt = 0;

  /// 本次实际播放时长（毫秒）。
  int durationPlayedMs = 0;
}

/// 账号档案（多账号 · 批2-A）：凭据与激活态的本地持久化。
/// accountId 为业务唯一键；id 由 Isar 自动自增。
@collection
class AccountRecord {
  Id id = Isar.autoIncrement;

  /// 账号业务 id，唯一。
  @Index(unique: true, replace: true)
  String accountId = '';

  /// 展示名（昵称）。
  String displayName = '';

  /// 登录态 token。
  String token = '';

  /// 酷狗 mid。
  String mid = '';

  /// 酷狗 dfid。
  String dfid = '';

  /// Cookie 序列化快照（可空语义用空串表示）。
  String cookieBlob = '';

  /// VIP 类型标签。
  String vipType = '';

  /// 是否为当前激活账号；全库至多一条为 true（AccountDao.setActive 保证）。
  bool isActive = false;

  /// 创建时间（epoch ms）。
  int createdAt = 0;

  /// 最近使用时间（epoch ms）。
  int lastUsedAt = 0;
}
