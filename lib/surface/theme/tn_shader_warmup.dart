// L6 surface/theme · 着色器编译调度（批11-B + 主会话 7 天重触发）
// 目标：消除「首帧后首次出现渐变/圆角/头像材质」时的 GPU 端 SkSL 编译卡顿——
// 把 App 实际使用的材质（品牌紫渐变 / 圆角矩形 / 圆形头像）在首帧结束后的
// 空闲窗口用 PictureRecorder 离屏绘制一次，raster 线程提前完成编译并缓存，
// 真实界面首次上屏时零编译开销。
// 7 天重触发：Impeller/SkSL 缓存随引擎/资源变化可能失效，持久化
// `shader.lastWarmupAt` 时间戳，超过 7 天（604800s）自动再跑一轮。
// 纪律：
// 1. 幂等：一次会话只调度/执行一轮（_scheduled/_done 双闸）+ 跨会话 7 天窗口。
// 2. 失败 Log 留痕且不重试——运行期自然编译兜底，不影响任何功能。
// 3. 非动效组件：无 AnimationController；不引裸动效时长。
// 4. 仅 surface 层引用；Log 经 bridge_logic、持久化经 bridge_core（合法跨层）。
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;
import '../../bridges/bridge_core.dart' show KeyValueSettings;
import 'tn_theme.dart' show tnPrimary, tnPrimaryAlt;

const String _tag = 'surface.tn_shader_warmup';
const String _kLastWarmupAt = 'shader.lastWarmupAt';
const int _kWarmupIntervalSec = 7 * 24 * 3600; // 每 7 天重触发

/// 着色器编译调度器：首帧后空闲窗口离屏预编译 App 常用材质。
/// 用法：AppRoot initState 里 `TnShaderWarmup.schedule(settings)`（幂等 + 7 天窗口）。
abstract final class TnShaderWarmup {
  static bool _scheduled = false;
  static bool _done = false;

  /// 首帧结束后调度一轮预编译（会话内幂等；距上次成功超过 7 天才真正执行）。
  static void schedule({KeyValueSettings? settings}) {
    if (_scheduled || _done) return;
    if (settings != null && !_intervalElapsed(settings)) {
      Log.d(_tag, 'warmup skipped (within 7-day window)');
      _done = true; // 本会话不再跑
      return;
    }
    _scheduled = true;
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 让出当前帧给首帧渲染，再于下一空闲微任务执行离屏编译。
        Future<void>.delayed(Duration.zero, () => _run(settings));
      });
      Log.d(_tag, 'shader warmup scheduled');
    } catch (e, st) {
      Log.e(_tag, 'schedule failed', e, st);
      _scheduled = false; // 允许下次再试
    }
  }

  /// 距上次成功预热是否超过 7 天（无记录 = 首次 = 执行）。
  static bool _intervalElapsed(KeyValueSettings settings) {
    try {
      final last = settings.getInt(_kLastWarmupAt);
      if (last == null) return true;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now - last >= _kWarmupIntervalSec;
    } catch (e, st) {
      Log.e(_tag, 'interval check failed (assume elapsed)', e, st);
      return true; // 读不到记录宁可多跑一次，不漏预热
    }
  }

  static Future<void> _run(KeyValueSettings? settings) async {
    try {
      _warmGradient();
      _warmRoundedRect();
      _warmCircle();
      _done = true;
      try {
        settings?.setInt(_kLastWarmupAt,
            DateTime.now().millisecondsSinceEpoch ~/ 1000);
        Log.d(_tag, 'warmup done, timestamp persisted');
      } catch (e, st) {
        Log.w(_tag, 'timestamp persist failed (预热已完成): $e\n$st');
      }
      Log.d(_tag, 'shader warmup done');
    } catch (e, st) {
      // 兜底语义：漏编的材质在真实首绘时由运行期自然编译，仅多一次 jank。
      Log.e(_tag, 'warmup failed (runtime 编译兜底)', e, st);
    }
  }

  /// 通用离屏绘制：Recorder → draw → endRecording 提交图层，
  /// 提交后由引擎在 raster 线程光栅化时完成着色器编译（无需 toImage/显式释放，
  /// Picture 由引擎持有并在帧结束后回收）。
  static void _draw(int w, int h, void Function(Canvas, Rect) paint) {
    final recorder = PictureRecorder();
    try {
      final canvas = Canvas(recorder);
      final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      paint(canvas, rect);
      recorder.endRecording(); // 提交即触发后续光栅化编译
    } catch (e, st) {
      try {
        recorder.endRecording(); // 异常路径也要 end，避免未关闭的 Recorder
      } catch (_) {}
      Log.w(_tag, 'warm draw failed: $e\n$st');
    }
  }

  /// 品牌紫线性渐变（对应动效/骨架屏/装饰渐变材质）。
  static void _warmGradient() => _draw(64, 64, (canvas, rect) {
        final shader = const LinearGradient(
          colors: [tnPrimary, tnPrimaryAlt],
        ).createShader(rect);
        final paint = Paint()..shader = shader;
        canvas.drawRect(rect, paint);
      });

  /// 圆角矩形（对应 TnAppBar 底部圆角 / 卡片 / Chip 材质）。
  static void _warmRoundedRect() => _draw(64, 64, (canvas, rect) {
        final rrect = RRect.fromRectAndRadius(
            rect.deflate(8), const Radius.circular(12));
        canvas.drawRRect(
            rrect,
            Paint()
              ..color = const Color(0xFFEDE7FF)
              ..style = PaintingStyle.fill);
      });

  /// 圆形（对应头像 CircleAvatar / 进度环材质）。
  static void _warmCircle() => _draw(64, 64, (canvas, rect) {
        canvas.drawCircle(rect.center, 24, Paint()..color = tnPrimary);
      });
}
