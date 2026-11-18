// L7 surface/theme · 启动失败错误页主题。
// 审查修复（阶段B B6/B7）：旧实现是**第二套 ThemeData 构造**（独立 fromSeed
// 亮色板），与主应用的 Sp.theme() 分裂——错误页配色与主应用不一致，且亮色板
// 下同样存在深色假设失效问题。现统一走 Sp.theme(dark: true)（App 视觉基底），
// 保证全 App 只有一套主题构造与单一事实源。
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart' show Sp;

/// 启动失败错误页主题（与主应用同一套构造，见 Sp.theme）。
ThemeData spErrorThemeData() => Sp.theme(dark: true);
