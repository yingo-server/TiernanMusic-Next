// L6 surface/widgets · QrView：data 字符串 → QrMatrix → CustomPaint(QrPainter)。
// 失败（数据过长/编码异常）显示错误占位；try/catch + Log('surface.qr')。
import 'package:flutter/material.dart';

import '../../bridges/bridge_logic.dart' show Log;
import 'qr_painter.dart';

const String _tag = 'surface.qr';

/// 二维码视图（纯 Dart 编码，无第三方依赖）。
class QrView extends StatelessWidget {
  const QrView({
    super.key,
    required this.data,
    this.backgroundColor = Colors.white,
    this.rounded = false,
    this.ecLevelM = false,
  });

  final String data;
  final Color backgroundColor;
  final bool rounded;
  final bool ecLevelM;

  @override
  Widget build(BuildContext context) {
    try {
      if (data.isEmpty) {
        return Container(
          color: backgroundColor,
          alignment: Alignment.center,
          child: const Text('二维码生成中…'),
        );
      }
      final matrix = encodeQr(data, ecLevelM: ecLevelM);
      return Container(
        color: backgroundColor,
        child: CustomPaint(
          painter: QrPainter(matrix, rounded: rounded),
          child: const SizedBox.expand(),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'QrView build failed len=${data.length}', e, st);
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Text(
          '二维码编码失败\n数据过长或格式异常',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
  }
}
