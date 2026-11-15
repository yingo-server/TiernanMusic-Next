// L7 surface/theme · 启动失败错误页的浅色主题（L1 经 bridge_surface 取）。
// 仅此一个纯 ThemeData 函数；主应用主题在 design/tokens.dart 的 Sp.theme()。
library;

import 'package:flutter/material.dart';

ThemeData spLightThemeData() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954)),
);
