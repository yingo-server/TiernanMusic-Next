# README 重写说明（sota-copywriting · 2026-11-19）

按 `/var/minis/skills/sota-copywriting/SKILL.md` BUILD 模式执行；只改 README.md，未动任何代码，未 commit/push。

## 价值主张（模板推导）

> For 想自己掌控播放/下载/凭据的用户，TiernanMusic-Next 是一款离线优先的酷狗第三方 Flutter 客户端，直连原生 API、不依赖第三方网关。
> 参照替代：依赖 Node 网关或旧 v5.5.0 App。

首段 = above-fold 契约：是什么 / 给谁 / 下一步（下载链接）。一句话主张落在标题下第一段。

## 结构

1. 一句话价值主张 + 合规免责（学习研究用途）
2. 核心特性（benefit-first：播放/下载/歌词/MV、离线缓存、YKG+QR 登录、三态）
3. "为什么 UI 可信"（差异点：只写色彩不写控件，门禁可证）
4. 76 原则架构
5. 快速开始（真实 release 与构建命令）
6. 文档索引（10 篇权威文档）
7. 项目状态（四步路线进度 + 诚实清单）
8. 贡献与许可

## 引用的真实事实与出处

- 功能/架构：docs/ARCHITECTURE.md、SEVEN_SIX_RULE.md、UI_REWRITE_PLAN.md（M3+GetWidget 契约、平台层 lib/platform/、权限网关 lib/core/capability/ 实存）、DESIGN_LANGUAGE.md（森林翡翠、4.5:1）
- YKG 登录算法：docs/YKG_LINK_CRYPTO_DESIGN.md + pubspec.yaml 注释
- Release：GitHub API 核对 —— 最近稳定版 v26.11.13.06（prerelease=false，3 架构 APK + verification.json）；其后 tag 均为 prerelease。桌面构建经 desktop-build.yml workflow_dispatch，产物尚未进常规 Release（诚实标注）
- 版本格式 26.11.10.N、changed/ changelog、十道门禁 FINAL-OK：旧 README 与 docs
- 许可证：LICENSE 实存 Apache-2.0

## 审计要点落实

- 零 superlative / "最强" 类不可证词；量化主张（50 端点、42 条验收、4.5:1）均来自文档原文
- 未编造任何链接、tag、命令；桌面 Release 状态如实说明
- 无虚构社会证明（无 star 数/用户数引用）
