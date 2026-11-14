// L4 core/net · 封面 URL 工具（唯一收口点）
// 酷狗封面 URL 带 {size} 模板（实测：
//   http://imge.kugou.com/stdmusic/{size}/20250125/xxx.jpg
//   http://c1.kgimg.com/custom/{size}/20230131/xxx.jpg ）。
// {size} 原样透传 = 无效 URL = UI 全占位图（R2 事故根因）。
// 收口规则：模型层 fromMap 统一经 [normalizeCoverUrl] 归一化，UI 层零处理。
// 档位：thum(90) / square(120) / stdmusic(240) / hdpic(400) / custom(480)。
import '../../../bridges/bridge_kernel.dart' show Log;

const String _tag = 'net.cover';

/// 预置尺寸档位（与酷狗 CDN 实测一致）。
const int kCoverStandard = 240;

/// 归一化封面 URL：替换 {size} 模板为具体像素档。
/// - 空 / 非 http → 返回空串（UI 显示占位）
/// - 无 {size} → 原样返回
/// - 已是合法尺寸路径 → 原样返回（幂等）
String normalizeCoverUrl(Object? raw, {int size = kCoverStandard}) {
  try {
    final u = (raw ?? '').toString().trim();
    if (u.isEmpty || !u.startsWith('http')) return '';
    if (!u.contains('{size}')) return u;
    final fixed = u.replaceFirst('{size}', '$size');
    return fixed;
  } catch (e, st) {
    Log.e(_tag, 'normalizeCoverUrl failed', e, st);
    return '';
  }
}
