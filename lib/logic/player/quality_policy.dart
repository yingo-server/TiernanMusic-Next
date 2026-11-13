// L5 logic · 音质降级策略（纯 Dart，无 flutter、无 IO、无网络直连）。
// 仅经 ../../bridges/bridge_kernel.dart 门面留痕（Log / logW），不跨层 import。
//
// ── 降级规则 ─────────────────────────────────────────────────────────────
// 1. 档位阶梯：flac → 320 → 128（可选 high/magic 仅作可播放档位，不改变
//    降级顺序）；降级只能沿阶梯向低档走，禁止越级上行或循环。
// 2. VIP 档（flac/high/magic 等）请求失败时，结果一律如实上报
//    （needVerify / noPrivilege / downgrade），绝不得冒充成功播放。
// 3. 降级只降音质档位，绝不改换曲目；曲目是否可播由上层依据本策略结果决定。
// 4. 每个档位最多尝试 1 次：attemptIndex 按「本次会话内该曲目的尝试序号」
//    递增，超过 maxAttempts 即判 exhausted，返回 null 终止。
// 5. 未知/空档位回退到安全链 ['320', '128']，并去重保证链内档位唯一。
// ────────────────────────────────────────────────────────────────────────
library;

import '../../bridges/bridge_kernel.dart' show Log, logW;

const String kTag = 'quality_policy';

/// 音质阶梯（高→低排列；降级链按此顺序向后截取，flac→320→128）。
/// 可扩展 'high'/'magic' 等官方档位，但降级链仍按 ladder 顺序截取。
const List<String> kQualityLadder = <String>[
  'magic',
  'high',
  'flac',
  '320',
  '128',
];

/// 未知档位的安全回退链。
const List<String> kFallbackChain = <String>['320', '128'];

/// 播放决策结果。
enum PlayDecision {
  /// 直接播放。
  play,

  /// 降档重试（沿 downgradeChain 向下一档）。
  downgrade,

  /// 需要验证（服务端返回 status==2，通常为风控/验证流程）。
  needVerify,

  /// 无权限（privStatus==0，VIP 档未授权，不得冒充成功）。
  noPrivilege,

  /// 无网络阻断（由上层在调用前注入；本策略保留该语义位）。
  blockedNoNetwork,

  /// 降级链耗尽（超过 maxAttempts 或链尾越界）。
  exhausted,
}

/// 单次音质请求的结果快照（由 L4 core 网络域回填，经桥传入）。
class QualityAttempt {
  const QualityAttempt({
    required this.quality,
    required this.status,
    required this.privStatus,
    required this.hasUrl,
    this.privKnown = true,
  });

  final String quality;

  /// 服务端 status：1=正常，2=需验证。
  final int status;

  /// 权限状态：0=无权限（VIP 档未授权）。
  final int privStatus;

  /// privStatus 是否真实存在于响应中。匿名免费曲常无该键，
  /// 此时不得把缺失值 0 当作「无权限」（批02 复核修正）。
  final bool privKnown;

  /// 是否拿到了可用播放地址。
  final bool hasUrl;
}

/// 从 preferred 开始截取到底档的降级链；未知档位回退安全链；去重。
List<String> downgradeChain(String preferred) {
  try {
    final String p = preferred.trim().toLowerCase();
    // preferred 在阶梯中（含等价大写），从其位置截到底。
    final int idx = kQualityLadder.indexOf(p);
    if (idx < 0) {
      return List<String>.from(kFallbackChain);
    }
    final List<String> chain = <String>[];
    for (int i = idx; i < kQualityLadder.length; i++) {
      final String q = kQualityLadder[i];
      if (!chain.contains(q)) {
        chain.add(q);
      }
    }
    if (chain.isEmpty) {
      return List<String>.from(kFallbackChain);
    }
    return chain;
  } catch (e, st) {
    logW(kTag, 'downgradeChain failed: preferred=$preferred err=$e st=$st');
    return List<String>.from(kFallbackChain);
  }
}

/// 按单次尝试快照给出播放决策。
/// 规则：VIP 档失败如实上报，不冒充成功；无权限直接拒绝。
PlayDecision decide(QualityAttempt a) {
  try {
    // 1) 已拿到 url 且 status==1：可播（优先于 priv 判定，
    //    因匿名免费曲可能不返回 priv_status，缺失不得当作无权限）。
    if (a.status == 1 && a.hasUrl) {
      Log.d(kTag, 'decide: play quality=${a.quality}');
      return PlayDecision.play;
    }
    // 2) status==2 且无 url：需要验证（风控/验证流程），不降级、不冒充成功。
    if (a.status == 2 && !a.hasUrl) {
      Log.w(kTag, 'decide: needVerify quality=${a.quality}');
      return PlayDecision.needVerify;
    }
    // 3) 明确 priv_status==0：无权限（VIP 档未授权），不得冒充成功。
    if (a.privKnown && a.privStatus == 0) {
      Log.w(kTag, 'decide: noPrivilege quality=${a.quality}');
      return PlayDecision.noPrivilege;
    }
    // 正常但无 url：降档重试。
    if (a.status == 1 && !a.hasUrl) {
      Log.w(kTag, 'decide: downgrade(no url) quality=${a.quality}');
      return PlayDecision.downgrade;
    }
    // 其它：一律降档，不冒充成功。
    Log.w(kTag, 'decide: downgrade(other) '
        'quality=${a.quality} status=${a.status}');
    return PlayDecision.downgrade;
  } catch (e, st) {
    logW(kTag, 'decide failed err=$e st=$st');
    return PlayDecision.downgrade;
  }
}

/// 取降级链中的下一档位。
/// [attemptIndex]：本次尝试序号（0 基）。[maxAttempts]：最大尝试次数。
/// 越界（链尾）或超次数（attemptIndex+1 >= maxAttempts）返回 null → exhausted。
String? nextQuality(String current, int attemptIndex, int maxAttempts) {
  try {
    if (maxAttempts <= 0) {
      Log.d(kTag, 'nextQuality: exhausted(maxAttempts<=0)');
      return null;
    }
    final int nextIdx = attemptIndex + 1;
    if (nextIdx >= maxAttempts) {
      Log.d(kTag, 'nextQuality: exhausted(nextIdx=$nextIdx max=$maxAttempts)');
      return null;
    }
    final List<String> chain = downgradeChain(current);
    // current 必须位于链内；不在则回退链首（安全档 320）。
    final int pos = chain.indexOf(current.trim().toLowerCase());
    if (pos < 0) {
      Log.w(kTag, 'nextQuality: current=$current not in chain, fallback head');
      return chain.first;
    }
    if (pos + 1 >= chain.length) {
      Log.d(kTag, 'nextQuality: chain end, exhausted');
      return null;
    }
    final String next = chain[pos + 1];
    Log.d(kTag, 'nextQuality: $current -> $next');
    return next;
  } catch (e, st) {
    logW(kTag, 'nextQuality failed err=$e st=$st');
    return null;
  }
}
