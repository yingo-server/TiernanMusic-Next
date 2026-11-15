# 项目整理与目标（2026-11-15）

> 状态快照：HEAD `0a27f45`，工作区干净；本地门禁 `FINAL-OK`；正式 LTS 待发。

## 1. 项目定位
`TiernanMusic-Next` = 归档 v5.5.0 音乐 App 的 Flutter 完全重写版。
- 酷狗原生 API 直连，不依赖 Node 包装网关；只读参考 `/var/minis/workspace/KuGouMusicApi` 源码提取官方端点。
- 零旧 lib 源码复用；图标资源按用户许可复用。
- 目标：Spotify 风格深色 UI、76 原则架构、三态（匿名/非VIP/VIP）可用、正式 LTS 发布。

## 2. 架构（权威：docs/SEVEN_SIX_RULE.md）
```
L1 init → L2 bootloader → L3 kernel → L4 core → L5 logic → L6 session → L7 surface
六桥：boot / kernel / core / logic / session / surface
依赖 surface→session→logic→core，禁止反向
```
- L7 只画控件；L6 播放编排/队列/装配图/导航；L4 缓存⊃预读/成熟库音频网关/纯算法/端点；L5 纯逻辑。
- 门禁：layer_audit(strict seven-six) / smoke_check / analyze_gate / 各纯 Dart 契约。
- 新规：单文件 >1500 行才拆；允许 dart format；禁工具次数限制、限范围+实时落盘。

## 3. 已完成
- 六批（3 检查+3 修复/批）全部整理提交，summary 在 docs/six_b1..b6_summary.md。
  1 三态字段捕获 | 2 登录链 | 3 匿名MV音频+权益最大URL | 4 UI功能补全 | 5 缓存专项 | 6 网络专项+收口。
- CI 优化：pub/gradle/build 缓存；R8 minify+shrinkResources；obfuscate+split-debug-info；tree-shake-icons；
  APK 命名 `TiernanMusicNext-v<VER>-<stable|preview>-<ABI>.apk`。
- 上游端点全表：docs/plan_upstream_endpoints_a.md / _b.md；三态/字段/UI 调研报告齐全。
- 本地：bash tool/local_gate.sh = FINAL-OK；analyze_gate ok。

## 4. 当前状态（诚实）
- `0a27f45` push CI in_progress；定时器 911f17a8 瞬时查。
- 最新 release 仍 `v26.11.15.03` prerelease=true；**正式 LTS 未产出**。
- 历轮 CI 红因逐层收敛：并发代理编译错 → verdict 假红 → R8 缺 Play Core 类；最后修复 `0a27f45` 加 `-dontwarn com.google.android.play.core.**`。
- CI 绿后由定时器自动 workflow_dispatch `stable=true` 发正式版。

## 5. 计划目标
### 近期（唯一）
1. 等 `0a27f45` CI 绿；红则按 VERDICT-FAIL / build 日志收口。
2. `stable=true` 发正式 LTS；确认 `prerelease=false` + 3 个新命名 APK + verification.json + 体积/耗时对比。
3. 写 docs/FINAL_RELEASE.md（版本、产物、压缩前后体积、CI 耗时、未覆盖项）。

### 发布后（不冒充完成）
- 真机 44 项验收：docs/ACCEPTANCE_CHECKLIST.md（评论写/点赞、歌词行 seek、音质档回显、FM/云盘/高潮、MV mp4 音频解码）。
- api_field_probe_v2 未实跑、docs/api_samples_v2 未产出；写操作/登录三态未实测。
- 版本变体 vN±1 全标待实测；微信开放平台按超时默认不接。
- L4 磁盘缓存仍 dart:io 自研（异步原子 rename），未换成熟库。

## 6. 执行纪律
- 子代理仅在必要时派（客观审查/并发/重复工作）；小问题主线修。
- 任务书禁写工具调用次数；只限功能/文件范围 + 实时落盘 + 用已有发现收口 + 未覆盖不补齐。
- 汇报 <500 字（按轮次可更短），完整报告落盘。
- 每批整理一次（summary+全门禁+提交）再推进；不通知中间进度。
- >60 秒等待禁用 sleep，一律 minis-scheduled 单次瞬时检查。
- 全部完成后才发正式 LTS；push main 自动 pre，stable=true 才正式。
