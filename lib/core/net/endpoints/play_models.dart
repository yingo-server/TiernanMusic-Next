// L4 core/net/endpoints · 播放域模型（PlayResult/PrivilegeItem）
// 来源拆分：models.dart（614 行超行拆分，R2-A）；类体逐字搬移，零逻辑改动。
import '../../../bridges/bridge_kernel.dart' show Log;
import 'models_util.dart';

const String _tag = 'net.models.play';

class PlayResult {
  const PlayResult({
    this.status = 0,
    this.privStatus = 0,
    this.errcode = 0,
    this.error = '',
    this.urls = const <String>[],
    this.backupUrls = const <String>[],
    this.bitrate = 0,
    this.extName = '',
    this.timeLengthSec = 0,
    this.isVipTrack = false,
    this.isFreePart = false,
    this.hash = '',
    this.privKnown = false,
    // 批1-F3：play_url 顶层键真正落公开字段（此前 Expando 侧挂，下游读不到）。
    this.hashOffset,
    this.endByte,
    this.failProcess,
    this.responseQuality = '',
    this.fileSizeBytes = 0,
    this.volume = 0.0,
    this.classMap = const <String, String>{},
    this.transParam = const <String, String>{},
    this.authThrough = const <String>[],
    this.fileName = '',
    this.fileHead = '',
    this.stdHash = '',
    this.hashToken = '',
    this.topLevelKeys = const <String>[],
    this.variantFields = const <String, String>{},
  });

  final int status; // 1=出URL；2=err（20028 匿名风控等）
  final int privStatus; // 1=有权限；0=无权限（VIP 曲非 VIP 号）
  final int errcode; // 20028 …
  final String error;
  final List<String> urls; // url 数组（顶层 url）
  final List<String> backupUrls; // backupUrl
  final int bitrate; // bitRate
  final String extName; // mp3/flac …
  final int timeLengthSec; // timeLength
  final bool isVipTrack; // tracker_through.musicpack_advance==1
  final bool isFreePart; // 试听片段
  final String hash;

  /// 响应是否真的带了 priv_status；缺失时 privStatus=safeInt(null)=0 只是默认值，
  /// 不得据此判定 noPrivilege（否则匿名/错盐响应被误判为无权限）。
  final bool privKnown;

  /// 供 L5（PlaybackService，批3）直接回填 PlaySource.quality：
  /// 已是「响应 q 优先、缺省才用请求档」的最终值，无需再解析。
  /// 注：PlaySource 定义在禁改的 playback_service.dart（批3范围），
  /// 本批只提供可直接读的落点，实际接线留批3（docs/six_b1_f3.md 标未覆盖）。
  String get quality => responseQuality;

  // 批1-F3（docs/six_b1_f3.md）：play_url 响应顶层键公开落点（默认值不破坏现构造）。
  /// hash_offset / end_byte / fail_process：试听分片 / 断点 / 风控诊断；L5 可直接读。
  final int? hashOffset;
  final int? endByte;
  final int? failProcess;

  /// 响应 `q`：服务端实际回档；'' = 响应未带，quality 回填应优先用响应 q，缺省才用请求档。
  final String responseQuality;

  /// fileSize（字节）。
  final int fileSizeBytes;

  /// volume 响应均衡（0.0 = 未带/不适用）。
  final double volume;

  /// classmap 扁平化为 k=v 字符串映射（容错解析）。
  final Map<String, String> classMap;

  /// trans_param（含 qualitymap）扁平化映射。
  final Map<String, String> transParam;

  /// auth_through[] 扁平化字符串列表。
  final List<String> authThrough;

  /// fileName / fileHead（缺省空串）。
  final String fileName;
  final String fileHead;

  /// std_hash / hash_token（登录态相关键，缺省空串）。
  final String stdHash;
  final String hashToken;

  /// 响应全部顶层键名（只留键，脱敏；供三态实测/字段核对用）。
  final List<String> topLevelKeys;

  /// q/fileSize/volume 等键的 camelCase 变体（如 file_size / vol）标量兜底。
  final Map<String, String> variantFields;

  bool get playable {
    try {
      return status == 1 && privStatus == 1 && urls.isNotEmpty;
    } catch (e, st) {
      Log.e(_tag, 'PlayResult.playable failed', e, st);
      return false;
    }
  }

  bool get needsVerification {
    try {
      // 20028 = 明确风控验证；31833 是签名失败（单列，由上层映射 network）。
      // status=2 且无 URL 时只有 priv_status 缺失（privKnown=false）才是验证态；
      // 明确带 priv_status=0 属 noPrivilege，不得混入验证态。
      return errcode == 20028 || (status == 2 && !privKnown && urls.isEmpty);
    } catch (e, st) {
      Log.e(_tag, 'PlayResult.needsVerification failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'status': status,
    'privStatus': privStatus,
    'errcode': errcode,
    'error': error,
    'urls': urls,
    'backupUrls': backupUrls,
    'bitrate': bitrate,
    'extName': extName,
    'timeLengthSec': timeLengthSec,
    'isVipTrack': isVipTrack,
    'isFreePart': isFreePart,
    'hash': hash,
    'privKnown': privKnown,
    'hashOffset': hashOffset,
    'endByte': endByte,
    'failProcess': failProcess,
    'responseQuality': responseQuality,
    'fileSizeBytes': fileSizeBytes,
    'volume': volume,
    'classMap': classMap,
    'transParam': transParam,
    'authThrough': authThrough,
    'fileName': fileName,
    'fileHead': fileHead,
    'stdHash': stdHash,
    'hashToken': hashToken,
    'topLevelKeys': topLevelKeys,
    'variantFields': variantFields,
    'playable': playable,
  };

  @override
  String toString() {
    try {
      return 'PlayResult(${toMap()})';
    } catch (e, st) {
      Log.e(_tag, 'PlayResult.toString failed', e, st);
      return 'PlayResult(<unavailable>)';
    }
  }
}

/// 权益批量（privilege_lite）单资源结果。
/// 注意 FINDINGS.md §10：privilege 是 int 标量（非数组），权限判定不依赖此接口。
class PrivilegeItem {
  const PrivilegeItem({this.hash = '', this.privilege = 0, this.status = 0});
  final String hash;
  final int privilege; // int 标量
  final int status;

  Map<String, Object?> toMap() => <String, Object?>{
    'hash': hash,
    'privilege': privilege,
    'status': status,
  };
}
