// L5 logic/player · 播放源解析编排（纯逻辑，IO 全部由注入的 fetch/health 承担）
//
// 组合三件已落地模块：
//   play_source_parser（顶层结构解析 + 三态 verdict）
//   quality_policy（flac→320→128 降级链、每档 1 次）
//   url_health（可选：主/备链可达性探测，断链降档）
//
// 语义（与 docs/API_FIELDS_TRUTH §A3-1 对齐）：
//   - status=2 + 20028 → needVerify，立即返回，不降级、不冒充成功
//   - priv_status=0（键存在）→ noPrivilege，立即返回
//   - status=1 + url → play（可选健康检查；全部断链则降档）
//   - 其余 → 降档重试，链尾或超次数 → exhausted
// 铁律：每方法 try/catch + Log；不 import flutter；不直连网络（fetch 注入）。

import '../../bridges/bridge_kernel.dart' show Log;
import 'play_source_parser.dart';
import 'quality_policy.dart';
import 'url_health.dart';

const String _tag = 'logic.playResolve';

/// 解析编排结果。
class PlayResolveResult {
  const PlayResolveResult({
    required this.decision,
    required this.quality,
    this.urls = const <String>[],
    this.backupUrls = const <String>[],
    this.endByte = 0,
    this.isFreePart = false,
    this.timeLengthSec = 0,
    this.attempts = 0,
    this.error,
  });

  final PlayDecision decision;

  /// 最终命中的音质档位（未命中时为最后尝试档）。
  final String quality;

  /// 主链 + 已通过健康检查的顺序（未做健康检查时 = 原始 urls）。
  final List<String> urls;

  /// 备用链（原始 backupUrl）。
  final List<String> backupUrls;

  /// 试听截断字节（0 = 完整）。
  final int endByte;

  /// IsFreePart=1 时为 true（试听/免费片段标记，最终仍以 endByte/timeLength 为准）。
  final bool isFreePart;

  /// 曲目时长（秒）。
  final int timeLengthSec;

  /// 实际尝试档位数。
  final int attempts;

  /// 诊断信息（最后一次失败原因），成功时为 null。
  final String? error;

  bool get isPlayable => decision == PlayDecision.play && urls.isNotEmpty;

  @override
  String toString() =>
      'PlayResolveResult(${decision.name}, q=$quality, urls=${urls.length}, '
      'attempts=$attempts, err=$error)';
}

/// 播放源解析编排器。
class PlayResolver {
  PlayResolver({
    this.healthChecker,
    this.checkHealth = false,
    this.maxAttempts = 3,
  });

  /// 可达性探测器（为 null 或 checkHealth=false 时跳过）。
  final UrlHealthChecker? healthChecker;

  /// 是否对 url 做 HEAD/Range 健康检查（默认关：省一次往返，失败由播放器兜底）。
  final bool checkHealth;

  /// 最多尝试档位数（含首选档）。
  final int maxAttempts;

  /// 按降级链解析：[fetch] 负责真正取响应（quality → 原始 Map）。
  Future<PlayResolveResult> resolve({
    required String preferredQuality,
    required Future<Map<String, dynamic>?> Function(String quality) fetch,
  }) async {
    var attempts = 0;
    var lastQuality = preferredQuality;
    String? lastError;
    try {
      final chain = downgradeChain(preferredQuality);
      for (final q in chain) {
        if (attempts >= maxAttempts) break;
        attempts++;
        lastQuality = q;

        Map<String, dynamic>? res;
        try {
          res = await fetch(q);
        } catch (e, st) {
          lastError = 'fetch($q): $e';
          Log.w(_tag, 'fetch $q failed: $e');
          Log.e(_tag, 'fetch $q stack', e, st);
          continue;
        }
        if (res == null || res.isEmpty) {
          lastError = 'empty response($q)';
          continue;
        }

        final parsed = parse(res);
        final decision = decide(QualityAttempt(
          quality: q,
          status: parsed.status,
          privStatus: parsed.privStatus,
          hasUrl: parsed.urls.isNotEmpty,
          // priv_status 键缺失时不得当作 0（匿名免费曲）
          privKnown: res.containsKey('priv_status') &&
              res['priv_status'] != null,
        ));

        if (decision == PlayDecision.needVerify ||
            decision == PlayDecision.noPrivilege) {
          Log.w(_tag, 'resolve $q → ${decision.name}');
          return PlayResolveResult(
            decision: decision,
            quality: q,
            urls: parsed.urls,
            backupUrls: parsed.backupUrls,
            endByte: parsed.endByte,
            isFreePart: parsed.isFreePart,
            timeLengthSec: parsed.timeLengthSec,
            attempts: attempts,
            error: lastError,
          );
        }

        if (decision == PlayDecision.play) {
          var urls = parsed.urls;
          if (checkHealth && healthChecker != null) {
            final healthy = await healthChecker!.firstHealthy(
              <String>[...parsed.urls, ...parsed.backupUrls],
              maxTries: 3,
            );
            if (healthy == null) {
              lastError = 'all urls unhealthy($q)';
              Log.w(_tag, 'resolve $q: all urls unhealthy, downgrade');
              continue; // 断链 → 降一档
            }
            // 命中项前置，其余保序保留（播放器仍可自行回退）
            urls = <String>[
              healthy,
              ...parsed.urls.where((u) => u != healthy),
            ];
          }
          Log.d(_tag,
              'resolve ok q=$q urls=${urls.length} attempts=$attempts');
          return PlayResolveResult(
            decision: PlayDecision.play,
            quality: q,
            urls: urls,
            backupUrls: parsed.backupUrls,
            endByte: parsed.endByte,
            isFreePart: parsed.isFreePart,
            timeLengthSec: parsed.timeLengthSec,
            attempts: attempts,
            error: null,
          );
        }

        // downgrade：继续下一档
        lastError = 'status=${parsed.status} priv=${parsed.privStatus} no url($q)';
        Log.d(_tag, 'resolve $q → downgrade');
      }
      Log.w(_tag, 'resolve exhausted after $attempts attempts');
      return PlayResolveResult(
        decision: PlayDecision.exhausted,
        quality: lastQuality,
        attempts: attempts,
        error: lastError,
      );
    } catch (e, st) {
      Log.e(_tag, 'resolve failed', e, st);
      return PlayResolveResult(
        decision: PlayDecision.exhausted,
        quality: lastQuality,
        attempts: attempts,
        error: '$e',
      );
    }
  }
}
