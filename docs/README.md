# 文档索引（docs/）

> 最近审阅：2026-11-19 · 分类法：Diátaxis（每篇文档只属于一种模式）
> 当前架构事实以 [`architecture/`](architecture/) 下的文档为准；其余为带「已归档」标注的历史记录。

## Tutorial（教程 · 学会）

本项目尚无独立教程页。首次上手请按 [构建指南 · 前置与本地门禁](architecture/BUILD_GUIDE.md) 走通本地检查；
运行环境为「构建全部在 CI、本地仅纯 Dart 检查」，见该指南「前置条件」。

## How-to（操作指南 · 做事）

- [构建指南：本地门禁 / Android / Windows / Linux AppImage / 发布](architecture/BUILD_GUIDE.md)
  —— 怎么跑门禁、怎么出各平台产物、四步版本路线怎么走。

## Reference（参考 · 查事实）

- 架构总览的解释见上节；具体事实查下面三篇：
- [层与桥参考：七层六桥、依赖方向、缓存域、端点注册表、例外登记](architecture/LAYERS_AND_BRIDGES.md)
- [设计语言参考：森林翡翠语义色 token、明暗成对、标题栏 token](architecture/DESIGN_LANGUAGE.md)
- [平台能力参考：能力集合、权限网关、窗口服务、条件导入](architecture/PLATFORM_CAPABILITIES.md)

## Explanation（解释 · 理解为什么）

- [架构总览：76 原则的形状、横切关注点落位、诚实现状](architecture/ARCHITECTURE_OVERVIEW.md)
- [四步版本路线（为什么这样切版本）](FOUR_RELEASE_ROADMAP.md)
- [文档工作流审计与改动清单](DOCS_WORKFLOW_AUDIT.md)

## 已归档（历史记录，仅供追溯，勿作为事实源）

下列文档描述的是重写前的六层五桥 / Sp.* 自绘控件 / Spotify 深色系统等旧状态，
均已加「已归档」横幅并指向上面的新文档：`ARCHITECTURE.md`、`SEVEN_SIX_RULE.md`、
`SIX_FIVE_RULE.md`、`UI_REWRITE_PLAN.md`、`UI_IA_PLAN.md`、`DESIGN_LANGUAGE.md`、
`FINAL_VERIFICATION.md`、`ARCHITECTURE_REVIEW.md`、`deep_audit/`（见其 README）。
