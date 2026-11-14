// PLACEHOLDER — 由独立 UI 模型重写，禁止在此堆逻辑。
// bridge_surface 与 init/main.dart 的启动错误页只需要 lightThemeData()。
library;

import 'package:flutter/material.dart';

ThemeData tnLightThemeData() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954)),
    );
