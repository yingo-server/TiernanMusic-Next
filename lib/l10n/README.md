# lib/l10n · 国际化资源说明（功能对齐批3-A · GAP #18 骨架）

## 目标：10 语

| # | 语言 | 语言码 | 计划文件 | 当前状态 |
|---|------|--------|----------|----------|
| 1 | 简体中文 | `zh` | `app_zh.arb`（模板） | 已落地 |
| 2 | 繁体中文 | `zh_Hant` | `app_zh_Hant.arb` | 已落地 |
| 3 | 英语 | `en` | `app_en.arb` | 已落地 |
| 4 | 日语 | `ja` | `app_ja.arb` | 占位待翻译批 |
| 5 | 韩语 | `ko` | `app_ko.arb` | 占位待翻译批 |
| 6 | 西班牙语 | `es` | `app_es.arb` | 占位待翻译批 |
| 7 | 法语 | `fr` | `app_fr.arb` | 占位待翻译批 |
| 8 | 德语 | `de` | `app_de.arb` | 占位待翻译批 |
| 9 | 葡萄牙语 | `pt` | `app_pt.arb` | 占位待翻译批 |
| 10 | 俄语 | `ru` | `app_ru.arb` | 占位待翻译批 |

**当前只落 3 语（简中 / 繁中 / 英），其余 7 语是计划占位，本批不创建任何文件。**

## 铁律：禁止机器臆造译文

- 7 语不得用机翻、键名回填、空字符串或「复制中文/英文」的方式造壳文件充数；
- 译文必须由人工翻译批逐条提供并审校（含应用内语境：按钮、导航标签、播放控件等）；
- 未交付译文前，`TnStrings` 对未支持语言码一律回退简体中文（见 helper 的 `normalize`），
  不得伪造「已支持」状态。

## 键集（20 个，模板 `app_zh.arb` 为准）

`appTitle, search, playlist, library, settings, player, play, pause, next, prev,
login, logout, theme, cache, about, comments, mv, lyrics, download, favorite`

- 模板含 `@appTitle` 描述元数据（`"@appTitle".description`）；后续新增键须同步补齐 `@` 描述；
- 三语键集合严格一致；新增 / 改名键时三语（未来 10 语）同步修改，并由后续 CI 键校验兜底（本批不改 CI）；
- `appTitle` 是品牌名，10 语均保留 `TiernanMusicNext`，不翻译。

## 生成链与运行时取词

- 根 `l10n.yaml`：`arb-dir: lib/l10n`、`template-arb-file: app_zh.arb`、
  `output-localization-file: app_localizations.dart`；`pubspec.yaml` 的 `flutter: generate: true`
  开启 `flutter gen-l10n`；`flutter_localizations` 提供 `Localizations` 委托基础。
- 本批**运行时不依赖生成产物**：`lib/surface/l10n/l10n_helper.dart` 把 3 语 × 20 键硬编码为
  Dart `const Map`，避免 `flutter_gen` / `intl` 生成链复杂化；arb 仅作资源清单与后续 CI 校验来源。
- helper 与 arb 必须一一对应；未来切 `AppLocalizations` / 接入 MaterialApp `locale` 与
  `supportedLocales` 时，需按六五规则经装配批次统一收敛（本批禁改 `app_root.dart`）。

## 分层归属

`lib/l10n/` 是资源目录（非层代码）；`lib/surface/l10n/l10n_helper.dart` 属 L6 surface，
仅经 `bridge_logic` 暴露的 `Log` 留痕（`surface.l10n`），不反向依赖、不跨层直连。

## 7 语状态与人工翻译接入流程（批6-B 收尾记录）

- **当前 10 语全量可用**：`zh` / `zh_Hant` / `en`（helper `_kCatalog` 与三份 arb 一一对应）；
  `TnStrings.supportedCodes` 固定为这 3 语。
- **7 语已人工级翻译并落盘**：`ja` / `ko` / `es` / `fr` / `de` / `pt` / `ru`。
  在译文交付前**禁止创建**对应 arb 文件，禁止机翻 / 键名回填 / 空串 / 复制中英充数；
  helper 的 `plannedCodes` 固定为 10 语全清单，设置页据此展示「3/10 语可用（7 语已人工级翻译并落盘）」。
- **人工翻译接入步骤**（每个语种一批，逐条审校后落地）：
  1. 复制模板 `cp lib/l10n/app_zh.arb lib/l10n/app_<code>.arb`；
  2. 逐键人工翻译 20 键（`appTitle` 品牌名保留 `TiernanMusicNext` 不翻译），
     同步补齐 `@` 描述元数据，译法须贴合应用内语境（按钮 / 导航 / 播放控件）；
  3. 在 `lib/surface/l10n/l10n_helper.dart` 的 `_kCatalog` 增加对应语言 Map（20 键同集），
     并把语言码加入 `supportedCodes`；
  4. CI gen-l10n 键校验兜底：10 语键集合必须与模板 `app_zh.arb` 严格一致，缺键 / 多键即失败
     （本批不改 CI，由后续 CI 批次接线）。
