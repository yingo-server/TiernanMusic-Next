// L7 surface/theme · 启动失败错误页主题。
// UI 重写（森林翡翠）：与主页统一走 v2 语义主题工厂，不再分裂。
library;

import 'package:flutter/material.dart';

import '../design/tokens_v2.dart' show TnPalette;

/// 启动失败错误页主题（深色基底，与主应用同一套语义 token）。
ThemeData spErrorThemeData() => TnPalette.dark.toThemeData();
