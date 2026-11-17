// L7 surface/pages · 首页共享状态组件（骨架/空态/错误重试）。
// 从 home_page.dart 拆出（≤500 行门禁）；本文件无业务逻辑。
import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 骨架占位。
class HomeSkeletonBox extends StatelessWidget {
  const HomeSkeletonBox({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
        itemCount: 3,
        itemBuilder: (BuildContext c, int i) => Container(
          width: 124,
          margin: const EdgeInsets.only(right: Sp.gapM),
          decoration: BoxDecoration(
            color: context.cs.surfaceContainer,
            borderRadius: BorderRadius.circular(Sp.rCard),
          ),
        ),
      ),
    );
  }
}

/// 空态。
class HomeEmptyBox extends StatelessWidget {
  const HomeEmptyBox(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Sp.pagePad,
      vertical: Sp.gapXL,
    ),
    child: Text(
      message,
      style: TextStyle(fontSize: Sp.fSub, color: context.cs.onSurfaceVariant),
    ),
  );
}

/// 错误 + 重试。
class HomeErrorRetry extends StatelessWidget {
  const HomeErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Sp.pagePad,
      vertical: Sp.gapXL,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: Sp.fSub, color: context.cs.error),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(
            '重试',
            style: TextStyle(fontSize: Sp.fSub, color: context.cs.primary),
          ),
        ),
      ],
    ),
  );
}
