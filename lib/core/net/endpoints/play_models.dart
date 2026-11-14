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
      return errcode == 20028 ||
          (status == 2 && !privKnown && urls.isEmpty);
    } catch (e, st) {
      Log.e(_tag, 'PlayResult.needsVerification failed', e, st);
      return false;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'status': status, 'privStatus': privStatus, 'errcode': errcode,
        'error': error, 'urls': urls, 'backupUrls': backupUrls,
        'bitrate': bitrate, 'extName': extName,
        'timeLengthSec': timeLengthSec, 'isVipTrack': isVipTrack,
        'isFreePart': isFreePart, 'hash': hash, 'privKnown': privKnown,
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
  const PrivilegeItem({
    this.hash = '',
    this.privilege = 0,
    this.status = 0,
  });
  final String hash;
  final int privilege; // int 标量
  final int status;

  Map<String, Object?> toMap() => <String, Object?>{
        'hash': hash, 'privilege': privilege, 'status': status,
      };
}

