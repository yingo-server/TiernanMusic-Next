# 底栏/主题分裂问题 · 修复链（2026-11-18，用户截图反馈）

> 用户反馈：底部 bar 坏了（截图：底部一大块浅灰白、盖住排行榜卡片、底栏图标文字不可见）。
> 本文档记录根因链与修复，供追溯。

## 症状
- 屏幕底部一大块浅灰白区域（约 200px 高），把首页「排行榜」卡片（TOP500 / 日臻星艺榜）截断
- 底栏图标与文字完全不可见
- 页面上半部分（推荐歌单、封面图）正常深色

## 根因链（4 层）

### 1. 组件主题与页面用了两套颜色来源（核心）
`Sp.theme()` 里给 M3 组件（NavigationBar / AppBar / ListTile / Chip / SnackBar / TextTheme）配置的颜色，
用的是**函数内局部常量** `dark ? Sp.bgElevated : _bgElevatedLight` 这类"按参数选深浅"的值；
而页面元素用的是 `context.cs.*`（= 实际生效的 `Theme.of(context).colorScheme`）。
两者**不是同一来源** → 当 MaterialApp 的生效板与 `theme(dark:)` 参数不一致时（`themeMode=system` 时会发生），
底栏取到亮色常量、页面取到暗色 scheme → **底栏浅、内容深的分裂**。

**修复**：组件主题一律改用 `scheme.*` 语义角色（appBar/navBar/listTile/chip/snackBar/textTheme/scaffold/divider），
单一来源，永不分裂。

### 2. scheme 的角色被局部常量覆盖
`copyWith(surface: bg, onSurface: text, surfaceContainer*: card...)` 把 fromSeed 派生的 tonal 角色抹成自定义常量，
导致 surface 阶梯不再是规范的 tonal 序列（也毁掉了动态取色）。
**修复**：只覆盖 `primary/onPrimary/error/onError`，surface 系列交给 fromSeed 按 brightness 派生。

### 3. themeMode 0「跟随系统」引入亮色板
本 App 视觉基底是深色（Spotify 深色风），我把 0 档从"强制暗色"改成 `ThemeMode.system` 后，
系统浅色 → 整个 App 走亮色板，而大量深色假设（卡片、徽章、渐变）失效 → 底部出现浅色块。
**修复**：0 档恢复暗色基底（设置页文案由「跟随系统」改为「默认」），用户要浅色显式选「亮」。

### 4. 排行榜卡片渐变末端是浅 tonal 色
`primary → primaryContainer` 渐变，暗色板的 primaryContainer 是**中灰**（tone≈38），
卡片下半截渐变成浅灰色块。
**修复**：改为 primary 同族 alphaBlend 渐变（`Color.alphaBlend(onPrimary@35%, primary)`），保持品牌深绿。

## 附带修复
- `navigationBarTheme.height` 64 → **80**（M3 NavigationBar 标准高；64 会裁切图标+指示器+标签文字）
- `onPrimary` 恒为黑（品牌绿 #1DB954 上黑字对比 ≈8.7，白字仅 ≈2.8 不足 WCAG AA）
- `library_music` 图标 key 未在 `iconFor()` 映射 → 落 default（音乐库显示错图标）
- shell 外层 Scaffold 补 `backgroundColor`（同源），避免导航栏周围露默认底色

## 离线验证（不依赖 CI）
`verify_theme_contrast.py`（模拟 M3 tonal 明度）：
```
DARK:
  底栏 vs 内容背景 对比 = 1.48   (轻微分层，符合 M3 层级表达)
  底栏标签 onSurface vs 底栏底 = 11.91  ✓
  正文 onSurface vs 内容底      = 17.67  ✓
  primary 文字 vs primary 底   = 11.60  ✓
```
修复后底栏与内容**同源同板**，不再出现浅块/深底分裂。

## 相关提交
41aca04 → 0c5823c（navH 80）→ cdd2dd3（onPrimary/图标 key）→ eee8699（渐变）
