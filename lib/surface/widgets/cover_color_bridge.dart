// L6 surface/widgets · 「封面字节 → 取色」接线契约（装配由主会话执行）
// ⚠️ 本文件不是五桥之一：桥文件唯一存在于 lib/bridges/，本文件只做
//    surface 同层接线（WidgetRef → dynamicThemeProvider），不做跨层转发。
//    收敛期真桥为 lib/bridges/bridge_surface.dart（见 dynamic_theme.dart 头注释）。
//
// ── 接线契约 ──
// 1) 来源：player_page.dart 大封面（约 200 行 CoverImage(url: null,
//    size: Size(240,240))）当前 url 空回退占位、SongBrief 无封面 url；
//    主会话需在封面可获取时，把已解码的 RGBA8888 字节传进来。本能力
//    纯 Dart、禁引 palette_generator/image，不做网络/文件 IO 直连。
// 2) 参数：bytes 为 r,g,b,a 每像素 4 字节，长度 ≥ w*h*4；w/h 为像素数且 > 0。
// 3) 时机：切歌/封面加载成功后用 ref.read（非 build 内 ref.watch 写入）；
//    封面缺失或切回占位时调 clearCoverTheme(ref) 回落品牌紫。
// 4) 效果：dynamicThemeProvider.notifier.updateFromImageBytes →
//    extractDominant（32 级色桶直方图）→ fromSeed（HSL 四色）；
//    app_root 消费 dynamicThemeProvider 覆盖 MiuixThemeData.colors。
// 5) 本批不改 player_page.dart / app_root.dart，装配由主会话完成。
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;

import '../../bridges/bridge_logic.dart' show Log;
import '../theme/dynamic_theme.dart' show dynamicThemeProvider;

const String _tag = 'surface.cover_color';

/// 把封面 RGBA 字节送入动态主题（失败必 Log 留痕，不抛给 UI）。
void applyCoverToTheme(WidgetRef ref, List<int> bytes, int w, int h) {
  try {
    if (bytes.isEmpty || w <= 0 || h <= 0) {
      Log.w(_tag, 'applyCoverToTheme: empty/invalid input, skip '
          '(${bytes.length} bytes, ${w}x$h)');
      return;
    }
    final notifier = ref.read(dynamicThemeProvider.notifier);
    notifier.updateFromImageBytes(bytes, w, h);
    Log.d(_tag, 'applyCoverToTheme: ${bytes.length} bytes ${w}x$h sent');
  } catch (e, st) {
    Log.e(_tag, 'applyCoverToTheme failed', e, st);
  }
}

/// 封面失效/回占位时清空动态主题。
void clearCoverTheme(WidgetRef ref) {
  try {
    ref.read(dynamicThemeProvider.notifier).clear();
    Log.d(_tag, 'clearCoverTheme: palette cleared');
  } catch (e, st) {
    Log.e(_tag, 'clearCoverTheme failed', e, st);
  }
}
