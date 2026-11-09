// L6 surface 级 · miuix 主题封装（亮/暗两套）+ 设计常量
// 仅 surface 层允许 import flutter_miuix；上层不得引用本文件里的 miuix 类型。
import 'package:flutter/material.dart' show Brightness, Curves, Duration;
import 'package:flutter_miuix/flutter_miuix.dart';

// ── 品牌色 ──
const Color tnPrimary = Color(0xFF7C4DFF); // 音乐紫
const Color tnPrimaryAlt = Color(0xFF3D5AFE); // 备选主色（蓝色）
const Color tnOnPrimary = Color(0xFFFFFFFF);

// ── 圆角常量 ──
const double tnRadiusS = 8;
const double tnRadiusM = 12;
const double tnRadiusL = 16;

// ── 间距常量 ──
const double tnPadS = 8;
const double tnPadM = 12;
const double tnPadL = 16;

// ── 动效常量表：统一曲线 easeOutCubic ──
class TnMotion {
  TnMotion._();
  static const Curve curve = Curves.easeOutCubic;
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
}

/// miuix 亮色主题
ThemeData tnLightTheme() => _theme(Brightness.light);

/// miuix 暗色主题
ThemeData tnDarkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness b) {
  try {
    final base = ColorThemes.defaultThemeData(brightness: b);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: tnPrimary,
        onPrimary: tnOnPrimary,
        secondary: tnPrimary,
        secondaryContainer: b == Brightness.light
            ? const Color(0xFFEDE7FF)
            : const Color(0xFF372A5E),
      ),
      cardConfig: base.cardConfig.copyWith(
        borderRadius: tnRadiusM,
      ),
      buttonConfig: base.buttonConfig.copyWith(
        borderRadius: tnRadiusM,
      ),
      inputConfig: base.inputConfig.copyWith(
        borderRadius: tnRadiusM,
      ),
      listConfig: base.listConfig.copyWith(
        itemBorderRadius: tnRadiusM,
      ),
    );
  } catch (e) {
    // 主题装配失败兜底：返回默认主题，不静默吞（由调用方 log 由 widget 树抛出日志）
    assert(() {
      // ignore: avoid_print
      print('surface.tn_theme: theme build failed, fallback: $e');
      return true;
    }());
    return ColorThemes.defaultThemeData(brightness: b);
  }
}

/// 文本主题分级：标题 / 正文 / 辅助。取用方式：
///   final t = TnText.of(context);
///   Text('标题', style: t.title); Text('正文', style: t.body); ...
class TnText {
  TnText._(this.title, this.body, this.aux);
  final TextStyle title;
  final TextStyle body;
  final TextStyle aux;

  static TnText of(BuildContext context) {
    final cs = MiuixTheme.colorScheme.of(context);
    final onSurface = cs.onPrimaryContainer;
    final base = MiuixTheme.textStyles.of(context);
    return TnText._(
      base.title.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      base.body.copyWith(fontSize: 15),
      base.body
          .copyWith(fontSize: 12, color: onSurface.withValues(alpha: 0.55)),
    );
  }
}
