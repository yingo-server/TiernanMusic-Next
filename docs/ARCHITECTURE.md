# TiernanMusic-Next 架构规范

## 六层五桥

```
L6 surface  交互/UI (miuix)          ⇅ bridge_surface.dart
L5 logic    纯后端逻辑（无UI无IO直连）  ⇅ bridge_logic.dart
L4 core     存储/数据库/内存/网络      ⇅ bridge_core.dart
L3 kernel   生命周期/注册表/日志/校验   ⇅ bridge_kernel.dart
L2 bootloader 启动序列/依赖装配        ⇅ bridge_boot.dart
L1 init     main 入口/完整性校验触发
```

铁律：
1. 跨层只能经桥文件（lib/bridges/），tool/layer_audit.py CI 强制。
2. 桥函数统一承担日志与异常捕获：每个公开函数 try/catch，失败必留痕（Log.e），不静默吞。
3. 网络层 core/net/endpoints/ 每端点一 dart 模块 + EndpointRegistry 声明式配置，改 API 不动调用方。
4. 零源仓库代码复用。酷狗原生 API 知识仅来自 docs/KUGOU_API.md。
5. 依赖纪律：SDK 可实现（≤500行）不引库；例外仅 miuix/riverpod/just_audio/audio_service/isar/path_provider。
6. UI 层热插拔：L6 surface 按「模块注册表」组织——每个页面/组件模块实现 SurfaceModule 接口（id、路由、Widget builder、依赖的 logic 能力），由 SurfaceRegistry 在启动时装配。模块间零直接 import（只经桥与 riverpod provider 通信），增删/替换模块只改注册表一行，不破坏层审计。

## 完整性
- 构建期 tool/gen_manifest.dart 对 lib/**/*.dart 算加盐 SHA-512（salt=NEXT_MANIFEST_SALT），
  Ed25519 私钥（NEXT_MANIFEST_KEY）签清单。
- 运行期 L1 init 校验，失败拒绝启动；--bypass-integrity 或 NEXT_DEBUG_BYPASS 仅 debug 构建生效。

## CI
- analyze/test/layer_audit 报错不妥协，一次跑完暴露全部错误，末尾 verdict 判定。
- build 矩阵 split-per-abi（arm64-v8a/armeabi-v7a/x86_64），极限包体。
- workflow_dispatch 参数：release(bool)、debug(bool)。
- 更新日志：release body 取 changed/<版本>.md，不存在则用最近 20 条 commit。

## 版本
26.11.10.N（日期.序号）
