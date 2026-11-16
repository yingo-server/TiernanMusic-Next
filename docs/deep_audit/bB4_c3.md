# B4 批 · C3 用户痛点专项（MV 播放跨层）

> 范围：L7 `mv_page.dart` / `player_page.dart`(查看MV段) · L5 `mv_logic.dart` · L4 `mv_endpoints.dart` / `mv_anonymous.dart` / `algorithms/qr_codec.dart`(仅二维码能力)
> 纪律：只读（file_read + rg/ls/wc）；未改任何源码；未跑 dart/analyze/test；未联网。
> 本文件为 append 写入。

---

## [2026-11-17 00:35] 第一轮：MV 体验走查 + 文案接线 + 动画/M3 + QR 旁证

## <视角 C3> · lib/surface/pages/player_page.dart:226-237 · P0 · 用户痛点/入口可用性
证据：`player_page.dart:226` `title: const Text('查看 MV')`（硬编码中文，无 `S.of`）；`onTap` 顺序为 `Navigator.of(ctx).pop()` → `registerMvModule()` → 取 `PlaybackSession.instance.snapshot.player.current?.albumAudioId ?? 0` → `Navigator.of(context).push(MaterialPageRoute(builder: (_) => MvPage(albumAudioId: aid)))`。菜单项**无条件可点**：当前无歌曲时 `aid = 0`，仍会 push 出 MV 页，落到 `mv_page.dart:90-92` 的 `_fail(_Phase.empty, '缺少歌曲信息，无法查询 MV')`。
问题：点「查看 MV」后用户会看到「暂无 MV / 缺少歌曲信息，无法查询 MV」，而不是「当前没有在播放歌曲」或菜单项置灰——这是「点了没反应/点了报错」的第一落点，也是「MV 用不了」最容易被误认为 App 坏了的场景。
建议：入口处判定 `current == null || albumAudioId <= 0` 时禁用该 ListTile（`onTap: null` + 灰化），或点按后给 SnackBar「当前没有在播放的歌曲」；文案统一走 `S.of(context).t('mvNoSong')`。
76 合规：涉及（L7 在 Widget 内做业务判定，正确做法是编排下沉 L6/L5，但入口守卫属 L7 允许范围）。

## <视角 C3> · lib/surface/pages/player_page.dart:229 + mv_page.dart:14-22 · P1 · 用户痛点/入口可达性
证据：`player_page.dart:229` 在 onTap 里**再次**调用 `registerMvModule()`，而 `shell.dart:30` 启动时已经调用过一次；`mv_page.dart:14-22` 的 `registerMvModule()` 用 `ModuleRegistry.instance.install(MvPageModule())`（重复 id 覆盖，已按 A1/A6 P0 修）。`MvPageModule.builder` 返回 `const MvPage(albumAudioId: 0)`（`mv_page.dart:31-32`），route `/mv` 若被深链/外部路由命中，永远是空态错误。
问题：① 每次点菜单都重复安装模块（无害但冗余，且掩盖模块注册失败的真实原因）；② `/mv` 路由是一个**必然报错的死路由**，用户若从系统深链或历史路径进入必然看到「缺少歌曲信息」。
建议：删除 onTap 中的重复 `registerMvModule()`；`/mv` 路由的 builder 改为「从最近播放歌曲取 albumAudioId」或直接不注册该 route（MV 只作为播放页子页面存在，不占 ModuleRegistry id）。
76 合规：涉及（L7 注册 L6 模块，边界模糊；模块注册属 L6 职责，应在 shell/bootstrap 一次完成）。

## <视角 C3> · lib/surface/pages/mv_page.dart:88-120 · P0 · 用户痛点/错误语义
证据：两段式已按阶段 A 修复为 `logic.videoIdOfSong(aid)` → `logic.qualities(videoId)`；但 `mv_logic.dart:41-52` 的 `videoIdOfSong` 对**任何异常**都 `return 0`，`mv_logic.dart:85-90` 的 `qualities` 对任何异常 `return const []`；`mv_endpoints.dart:296-300` `getMvBySong` catch 后 `return null`。因此网络超时/风控 20028/解析异常在 L5 被吞成「0 / 空列表」，L7 一律走 `_fail(_Phase.empty, '这首歌暂无可播 MV')`。
问题：**网络失败被伪装成「这首歌没有 MV」**。用户断网、弱网、被风控时看到的都是「这首歌暂无可播 MV」，永远不知道是网络问题还是真的没 MV——这是「MV 用不了」最典型的用户困惑，且必然导向错误的重试行为（无意义重试）。
建议：L5 保留异常语义（抛错或返回带 `error` 的结果对象，不要用 0/空列表兼作失败信号）；L7 分三态文案：无 MV（empty）/ 网络失败（error，提示「网络异常，请检查网络后重试」）/ 登录或权限受限（error，提示登录）。`mvEmpty` / `mvLoadingFail` 两个 arb key 已存在，正好分别承接。
76 合规：涉及（L5 吞错掩盖跨层错误态，属职责错位）。

## <视角 C3> · lib/surface/pages/mv_page.dart:135-143 · P1 · 用户痛点/错误语义
证据：`:140` `_fail(_Phase.empty, 'MV 地址不可用（可能被权限拦截）')`；`_Phase.empty` 在 UI 上渲染为 `SpStateView(icon: Icons.movie, title: '暂无 MV', subtitle: _message, actionLabel: '重试')`（`:241-247`）。
问题：权限/VIP 拦截这种**明确有原因**的失败，被放在「暂无 MV」标题下，副标题还带括号猜测（"可能被"），用户既得不到「请开通 VIP」的可执行指引，也被误导成「这歌没 MV」。
建议：新增 `_Phase.blocked`（或 error 分支），文案「高清 MV 需要会员权限，请登录/开通会员后重试」；匿名用户看到「登录后可尝试更高画质」。
76 合规：涉及（状态建模在 L7，建议由 L5 返回 `blocked/loginRequired` 语义，L7 只做映射）。

## <视角 C3> · lib/logic/catalog/mv_logic.dart:88-135 + mv_page.dart:115-134 · P1 · 用户痛点/清晰度降级方向
证据：`mv_logic.dart:110-121` 档位按 `size` **降序**排列；传入 `requestedId` 时 `ordered = sorted.sublist(idx)`（只保留 requested 及其**更低** size 的档位）；`mv_page.dart:115-134` 一律选最低档（优先 `ld`，否则 `sd`，否则 size 最小）并传 `requestedId = low.id`。当 `ld` 档存在但 trackermv 对 ld 不出链（`getVideoUrl` 返回空 urls）时，`ordered` 里没有任何可回退的档位 → 全部不可用 → `MvPlayResult` 空 → 页面报「MV 地址不可用（可能被权限拦截）」，**即使 sd/hd 有链也播不了**。
问题：降级链方向与选档策略冲突——只向更低画质降级，而最低档本身常常无链，导致「有 MV 却播不出来」。
建议：① `playUrl` 在 requested 档无链时，**回退到其余档位**（低→高依次尝试，或按 size 从小到大遍历）；② `mv_page` 选档时把「有链」而不是「档位存在」作为唯一依据。
76 合规：不涉及（纯 L5 编排逻辑）。

## <视角 C3> · lib/surface/pages/mv_page.dart:286-312 · P1 · 用户痛点/清晰度不可选 + 文案不可读
证据：`_quality = r.quality` 写入的是**档位 id**（`mv_endpoints.dart:220` 注释「实际命中的档位 id」，取值形如 `ld` / `hd_265`）；`:306` 显示 `_quality.isEmpty ? 'MV 内嵌播放' : '档位 $_quality'`。同时 `mv_endpoints.dart:120-124` 的 `MvQuality.label`（如「流畅 270P」「超高清 540P」）在整个仓库**没有任何 UI 消费点**（rg 仅命中定义与 toMap）。
问题：① 用户在播放页看到的是「档位 ld」这种工程 id，完全看不懂；② 页面没有任何清晰度选择入口，永远最低画质，VIP 用户也无法提档——「VIP 高清」既无入口也无提示。
建议：`:306` 改为展示 `MvQuality.label`（把 id→label 的映射随 `MvPlayResult` 一起返回，例如 `MvPlayResult.label`）；页面加一行档位选择（ld/sd/hd/fhd），VIP 用户可切高档，被拦时提示「该画质需会员」。
76 合规：不涉及（数据透传）。

## <视角 C3> · lib/core/net/endpoints/mv_endpoints.dart:147-152 · P1 · 文案/命名倒挂（用户点名核查项）
证据：档位标签表 `const tiers = <String,String>{ 'ld':'流畅 270P','sd':'标清 432P','hd':'高清 720P','fhd':'全高清 1080P','qhd':'超高清 540P' }`。
问题：**命名倒挂仍然存在**——`超高清 540P` 的分辨率低于 `全高清 1080P`，「超高清」字面高于「全高清」却对应更低分辨率；且 `mkv_qhd` 标签写作「MKV 超高清」（`:181`）进一步加重混乱。用户一旦看到档位列表（未来做选择器时）必然困惑。
建议：按分辨率而非 id 命名（如 `hd 720P` / `fhd 1080P` / `qhd 540P`，或统一「流畅/标清/高清/超清/蓝光」并显式带分辨率），去掉「超高清」这种与数值冲突的表述；同一处 label 表同时是 UI 文案来源，**必须同时进入 arb**（当前 label 硬编码在 L4，10 语无法覆盖）。
76 合规：涉及（用户可见文案硬编码在 L4 端点层，L4 不该持有展示文案；应改为 L4 只出 id，L7/文案层出 label）。

## <视角 C3> · lib/surface/pages/mv_page.dart · P1 · 文案未接 S.of（用户点名核查项）
证据：`mv_page.dart` 中 `rg -c "'[^']*[一-龥]"` 命中 **19 处**用户可见中文串（含 `'缺少歌曲信息，无法查询 MV'`、`'这首歌暂无可播 MV'`、`'MV 地址不可用（可能被权限拦截）'`、`'http 明文链接已升级为 https'`、`'不支持的 MV 链接协议：$url'`、`'MV 加载失败：$e'`、`'正在加载 MV…'`、`'暂无 MV'`、`'MV 不可用'`、`'重试'`×3、`'播放器已释放'`、`'MV 内嵌播放'`、`'档位 $_quality'`、`'暂停'/'播放'`），`rg 'S\.of|AppLocalizations'` 在 mv_page 命中 **0**。而 `lib/l10n/app_zh.arb:56-58` 已有 `mvEmpty` / `mvNoSong` / `mvLoadingFail` 三键，`lib/core/l10n/strings.dart` 亦已同步，**完全未被消费**。
问题：阶段 A 补的 i18n 键没有接到 MV 页面上；切换语言时 MV 页仍是中文，用户看到「文案没改」的现象在 MV 这一页原样存在。
建议：MV 页所有可见串改 `S.of(context).t(...)`，并补齐缺失键：`mvUnavailable`、`mvRetry`、`mvLoading`、`mvBlockedNeedVip`、`mvNetworkFailed`、`mvNoSongInPlayback`、`mvQualityFormat`（含 `{quality}` 占位）。
76 合规：涉及（文案资源在 L4 正确、消费在 L7 应接 S 门面，此处是断链而非越层）。

## <视角 C3> · lib/surface/pages/mv_page.dart:157,185 · P2 · 用户痛点/技术细节外泄
证据：`:157` `_fail(_Phase.error, '不支持的 MV 链接协议：$url')` 把完整 URL（可能带签名参数）抛给用户；`:185` `_fail(_Phase.error, 'MV 加载失败：$e')` 把异常原文（含 `KugouApiException` 等堆栈前串）直接展示。
问题：错误文案把内部技术细节暴露给普通用户，还可能泄露带 token 签名的 URL；用户也无从判断能做什么。
建议：用户侧只给「MV 加载失败，请稍后重试」+ 错误码（如 `E_MV_02`），细节写 `debugPrint`/日志；URL 不外显。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/player_page.dart:229-237 + lib/session/playback_session.dart · P1 · 用户痛点/双声冲突
证据：`player_page.dart:229-237` push `MvPage` 前**没有**对 `PlaybackSession` 调 pause/stop；`mv_page.dart:167` `await c.play()` 起播 MV 自带音轨，而底层音频引擎仍在播当前歌曲。
问题：看 MV 时歌曲原声与 MV 音轨同时外放（双重人声/回声），是典型的「体验很糙」投诉点；且用户看完 MV 返回播放页时歌曲可能已跳到下一首。
建议：进入 MV 页前 `PlaybackSession.instance.pause()`（或切到「MV 音轨」为唯一音源），退出 MV 页时恢复原播放。
76 合规：涉及（L7 直接编排 L6 播放会话，建议由 L6 提供 `enterMvMode/exitMvMode`）。

## <视角 C3> · lib/surface/pages/mv_page.dart:206-320 · P2 · 用户痛点/全屏与退出
证据：MV 页 `AppBar`（`:213-221`）标题固定字面量 `'MV'`（不显示歌曲名），无返回以外的退出控件；播放器区域 `:268-283` 是 `ClipRRect + AspectRatio` 内嵌，**没有全屏按钮、没有横屏/竖屏切换、没有双击暂停**；只有 `:294-300` 一个播放/暂停 IconButton + `:282-287` 进度条。页面也无「小窗/后台播放」按钮。
问题：MV 是竖屏视频还是横屏 MV 未知，用户若拿到横屏 MV 只能在竖屏小窗里看，**无法全屏**，这是最直接的功能性缺失（用户点名核查项）。
建议：增加全屏按钮（`SystemChrome.setPreferredOrientations` + 路由 push 全屏页），标题展示当前歌曲名，并提供「回到播放页」出口。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/mv_page.dart:210-320 · P2 · 动画/M3 局部
证据：`mv_page.dart` 全文件 `rg 'Animated|Hero|Tween|PageController|Curve'` 命中 **0**；加载态只有裸 `CircularProgressIndicator`（`:231`），切换 loading→ready 是硬切；无骨架屏、无淡入、无 `AnimatedSwitcher`。
问题：加载→播放瞬间黑屏硬切，用户感知「卡了一下/没反应」；与 A7 的 Motion 2/10 结论一致，MV 页是动画最缺失的页面之一。
建议：加 `AnimatedSwitcher`/`FadeTransition`（时长走统一 motion 令牌，当前 `Sp.fast=120ms`/`Sp.normal=220ms` 偏离 MD3 Standard/Emphasized 档），播放器就绪用 200ms 淡入 + 轻微缩放；加载态用骨架占位而非纯 spinner。
76 合规：不涉及。

## <视角 C3> · lib/surface/pages/mv_page.dart:212-311 · P2 · MD3/主题
证据：`rg -c 'Sp\.'` 命中 **20** 处（`Sp.bg`/`Sp.text`/`Sp.green`/`Sp.bgElevated`/`Sp.divider`/`Sp.textFaint`/`Sp.textSub`/`Sp.rCard`/`Sp.fSection`/`Sp.fSub`/`Sp.fTiny`/`Sp.gapM`…），`rg 'ColorScheme|Theme.of'` 命中 **0** —— MV 页完全走 `Sp.*` 静态色，绕过 `ColorScheme` 语义角色；`CircularProgressIndicator(color: Sp.green)`、`VideoProgressColors(playedColor: Sp.green, ...)` 也直接吃静态色。
问题：亮色主题下沿用深色静态色 → 白底白字（延续 A7 的致命对比度问题）；进度条/按钮不随主题色变化。
建议：改用 `Theme.of(context).colorScheme.primary / onSurface / surfaceContainerHighest / outlineVariant`；`Sp.*` 仅保留尺寸类常量。
76 合规：不涉及（L7 用 ThemeData 合规，消费方式不合规）。

## <视角 C3> · lib/core/net/endpoints/mv_anonymous.dart · P1 · 匿名三态（用户点名核查项）
证据：`mv_anonymous.dart` 提供 `registerDevice`（`:54-125`，取真实 dfid）与 `anonymousPlayUrl`（`:139-190`，匿名试听音频 URL），二者**均与 MV 视频链路无关**；MV 视频链路走 `mv_endpoints.getMvBySong` / `getVideoQualities` / `getVideoUrl`，其中 `getVideoQualities`（`mv_endpoints.dart:325-352`）请求体带 `token: client.session.token`、`mid`、`uuid`、`dfid`，`getVideoUrl` 依赖 `encryptKey` 注入的 `key=md5(hash+salt+appid+mid+userid||0)`（`endpoint_registry.dart:303-313`）。
问题：MV 视频**没有专门的匿名通道**，未登录时 `client.session.token` 为空、`userid` 为 0，`/v1/video` 与 `/v2/interface/index` 是否放行取决于服务端风控；一旦被拦，页面只会显示「暂无 MV / 可能被权限拦截」，**没有任何「登录后观看」的引导**——匿名用户因此完全无法自救。三态（未登录低清 / 登录高清 / 权限拦截）在 MV 侧**实际不存在**，只有「能播」与「看起来像没 MV」两种。
建议：① 明确产品口径：MV 视频是否允许匿名低清；② 页面引入 `AuthSession.instance.isLoggedIn` 三态渲染——未登录→「登录后可观看 MV 并解锁高清」+ 登录按钮；已登录高档被拦→「该画质需会员」；③ 端点侧若匿名不通，落地 `registerDevice` 拿真实 dfid 后再试（当前 `registerDevice` 是死代码，无调用点）。
76 合规：涉及（匿名/VIP 判定应来自 L6 session 快照，L7 只读取渲染）。

## <视角 C3> · lib/surface/pages/mv_page.dart:118-134 · P2 · 匿名/VIP 提示缺失
证据：`:118-134` 选档注释写「最低档优先：ld → sd → 按 size 取最小（**避开 VIP 高画质档**）」，即代码**刻意**只走免费档；页面无任何「高清需 VIP」提示，也无「低清免费/高清会员」的标注。
问题：VIP 用户也被强制低清且毫不知情；非 VIP 用户看到低清也不知道存在高清选项——VIP 权益在 MV 侧完全不可见、不可用。
建议：按 `AuthSession` + `vip_token` 状态计算可选档位集合（高清档对 VIP 开放、免费档对所有人开放），并在播放器下方标注「高清 1080P（会员）」；被拦时明确提示升级。
76 合规：涉及（VIP 状态取自 L6 session，L7 不应自行读 settings）。

## <视角 C3> · lib/core/net/endpoints/mv_endpoints.dart:147-186 · P2 · 文案层归属
证据：档位 label（`'流畅 270P'`…`'MKV 超高清'`）硬编码在 **L4 端点层**的 `MvQuality.fromFlat` 内。
问题：用户可见文案放在 L4，L4 不做本地化，10 语无法覆盖；且 L4 持有展示语义违反分层（端点只应出结构化事实）。
建议：L4 只出 `id` + `size` + `hash`；label 由 L5/L7 或文案资源按 id 查表提供，并入 arb。
76 合规：涉及（L4 越界持有 UI 文案职责）。

## <视角 C3> · lib/core/algorithms/qr_codec.dart:286 · P2 · 二维码能力盘点（用户点名旁证）
证据：阶段 A 修复已落地——`qr_codec.dart:286` 现为 `for (var right = size - 1; right >= 8; right -= 2)`（A4 裁定要求的标准起点），配对含 `(8,7)`，列对相位已与 Nayuki 对齐（此前 `size-2` 起、漏列 7 与最右列的 off-by-one 已消除）。能力现状：仅编码器（`encodeQr` v1-4 / Byte 模式 / EC L·M / 固定 mask 0），`rg 'encodeQr|QrMatrix'` 全仓仅命中定义与 `bridge_core.dart:46` 的 export，**零业务调用**；文件 `:350` 仍是悬空注释「黑白模块绘制…」——**无 Painter 实现**；全仓**无任何解码/扫码能力**（无 camera 依赖）。
问题（能力边界，非 bug）：作为 YKG 扫码入口只可复用「**导出**二维码」方向：① 需补 Painter（把 `QrMatrix` 画成 `CustomPainter`）；② 容量上限 V4-L **78B** / V4-M 62B，而 YKG 载荷是 base64(cookie)+盐值，典型 >78B → 会抛 `QrException`（`:70-74`），需扩版本或改短链；③ 固定 mask 0、无最优掩码，非标准最佳实践（可解码）；④ **导入侧（扫码）本层不具备**，需另接成熟扫码库。
建议：按 YKG §9「倾向要二维码」——导出侧复用 `encodeQr` + 补 Painter + 载荷长度评估（必要时提高版本上限或用短链 ID）；导入侧引入成熟扫码库（遵循 76§9 成熟库优先），不要自研 decoder。
76 合规：涉及（能力盘点）；QR 编码器归 L4 纯算法合理，仅经 `bridge_core` 导出，无越级 import。

---

## MV体验走查（用户视角逐步）

| # | 步骤 | 现状 | 用户感受 | 判定 |
|---|---|---|---|---|
| 1 | 播放页 ⋮ 菜单点「查看 MV」 | `player_page.dart:226-237` 有 `onTap`，会 push 页面；但**无歌曲时也点得进去**，且菜单项是硬编码中文 | 没在播歌时点了 → 得到一个错误页 | ⚠️ 入口无守卫 |
| 2 | 是否有反应 | 有：pop 菜单 + push `MvPage`；`registerMvModule()` 每次重复调用 | 有页面跳转，但可能立刻是空态 | ⚠️ |
| 3 | 加载态 | `mv_page.dart:228-241` `CircularProgressIndicator` + 「正在加载 MV…」 | 知道在加载，但没有骨架/进度细节 | ✅（动画缺失） |
| 4 | 无 MV 的空态 | `_Phase.empty` → `SpStateView(title:'暂无 MV', subtitle:_message, actionLabel:'重试')` | 文案对，但**网络失败也长这样** | ❌ 语义混淆 |
| 5 | 清晰度选择 | **不存在**。代码固定最低档（`:115-134`），UI 无任何选择器 | 用户无法提档；VIP 与免费用户一样 | ❌ 缺失 |
| 6 | 档位显示 | 「档位 ld」（`:306`，显示 id 而非 label） | 看不懂 | ❌ |
| 7 | 全屏 / 退出 | **无全屏**，只有 AppBar 返回 | 横屏 MV 无法正常观看 | ❌ 缺失 |
| 8 | 网络失败提示 | 被吞成「暂无 MV」（L5 catch → 0/[]） | 断网也提示没 MV，无从判断 | ❌ 缺失 |
| 9 | VIP 高档提示 | 无 | 不知道存在高清 | ❌ 缺失 |
| 10 | 播放中声音 | 未暂停原音频，双声 | 嘈杂 | ❌ |
| 11 | 阶段 A 后能否播 | **链路已修通**（videoId 两段式正确：`getMvBySong` 以 `video_id` 为门槛、`/v1/video` 传数字 videoId、`getVideoUrl` 带 encryptKey），但**仍有三重可致命点**：① L5 吞错把网络/风控变成「没 MV」；② 降级链只向更低档回退、最低档无链即全灭；③ `ld` 档出链失败是常见情形 | 「MV 还是用不了」在弱网/低档无链场景仍会复现 | ⚠️ 部分可用 |

**结论（能不能播）**：主链路（阶段 A 的四重断点）已修复，**正常网络 + 有 ld/sd 链时可以播**；但只要出现「网络/风控异常」「最低档无链」「MV 为横屏」三种情形之一，用户看到的仍是「暂无 MV」或一个看不了的全屏体验 → **用户口径的「MV 用不了」未彻底闭环**。修复优先级：L5 错误语义透传（P0）> 降级回退（P1）> 清晰度选择 + 全屏（P1）> 文案接线（P1）。

## 文案接线清单（MV 相关，全部未接 S.of）

| 文件:行 | 现有硬编码文案 | 建议 arb key | 状态 |
|---|---|---|---|
| player_page.dart:226 | `查看 MV` | `viewMv` | 未接 |
| mv_page.dart:92 | `缺少歌曲信息，无法查询 MV` | `mvNoSong`（已有） | 未接 |
| mv_page.dart:106 | `这首歌暂无可播 MV` | `mvEmpty`（已有） | 未接 |
| mv_page.dart:112 | `这首歌暂无可播 MV` | `mvEmpty`（已有） | 未接 |
| mv_page.dart:140 | `MV 地址不可用（可能被权限拦截）` | `mvBlocked` / `mvNeedVip` | 未接（且语义错位到 empty） |
| mv_page.dart:154 | `http 明文链接已升级为 https` | `mvUpgradedToHttps` | 未接 |
| mv_page.dart:157 | `不支持的 MV 链接协议：$url` | `mvBadProtocol`（不外显 URL） | 未接 |
| mv_page.dart:185 | `MV 加载失败：$e` | `mvLoadingFail`（已有） | 未接 |
| mv_page.dart:218 | `MV`（AppBar 标题） | `mv`（已有） | 未接 |
| mv_page.dart:234 | `正在加载 MV…` | `mvLoading` | 未接 |
| mv_page.dart:243 | `暂无 MV` | `mvEmptyTitle` | 未接 |
| mv_page.dart:245,253,263 | `重试` ×3 | `retry`（strings.dart:53 已存在） | 未接 |
| mv_page.dart:251,261 | `MV 不可用` ×2 | `mvUnavailable` | 未接 |
| mv_page.dart:262 | `播放器已释放` | `mvPlayerReleased` | 未接 |
| mv_page.dart:299 | `暂停` / `播放` tooltip | `pause` / `play` | 未接 |
| mv_page.dart:306 | `MV 内嵌播放` / `档位 $_quality` | `mvInlinePlayback` / `mvQualityFormat` | 未接 |
| mv_endpoints.dart:148-152,181 | `流畅 270P`…`MKV 超高清` | `mvQualityLd/Sd/Hd/Fhd/Qhd/Mkv`（并修正命名倒挂） | 未接（且属 L4 越界） |

已存在但零消费的 arb 键：`mv` / `mvEmpty` / `mvNoSong` / `mvLoadingFail`（`app_zh.arb:22,56-58`）。

---

## 本视角结论

1. **阶段 A 的四重断点确已修通**（videoId 两段式、模块注册、video_player 渲染），主链路正常情况下**可以播**；但用户口径的「MV 用不了」**未闭环**，残余三大杀手：L5 吞错把网络/风控伪装成「没 MV」（P0）、降级链只向更低档回退导致最低档无链即全灭（P1）、无清晰度选择/无全屏导致 VIP 与横屏 MV 实际不可用（P1）。
2. **MV 错误语义三态缺失**：无 MV / 网络失败 / 权限（VIP·登录）被压成同一个「暂无 MV」空态，用户无从判断该重试、该登录还是该放弃。
3. **匿名/VIP 三态在 MV 侧不存在**：无登录判定、无 VIP 判定、无任何引导文案；`mv_anonymous.dart` 的两个函数与 MV 视频链路无关且 `registerDevice` 是死代码。
4. **文案零接线**：MV 相关 19 处硬编码中文（mv_page）+ 1 处（player_page 菜单），而 `mv`/`mvEmpty`/`mvNoSong`/`mvLoadingFail` 四个 arb 键**早已存在却零消费** —— 「文案没改」在 MV 页成立。
5. **命名倒挂仍在**：`mv_endpoints.dart:150-151` `fhd='全高清 1080P'` vs `qhd='超高清 540P'`，且 label 全仓无 UI 消费点。
6. **MD3/动画局部**：mv_page 20 处 `Sp.*` 静态色、0 处 `ColorScheme`；0 处动画（无 AnimatedSwitcher/骨架），loading→ready 硬切。
7. **二维码旁证**：off-by-one 已修（`right = size - 1`），能力上**只能做「导出」**（需补 Painter），**不能做「扫码导入」**（无 decoder）；容量上限 V4-L 78B 对 YKG base64 载荷大概率不够。

## 未覆盖

- 未运行任何 dart/flutter/analyze/test/门禁（纪律禁止），未联网实测端点；「能否播」的判定为**静态链路推导**，不是实机播放录像。
- 未验证 `video_player` 2.9.2 在本项目 Android 端的实际表现：ExoPlayer 硬解、H.265(`*_265` 档) 支持度、`http→https` 强改后 CDN 是否仍可访问（`:152` 直接把 `http://` 替换成 `https://`，**若原 CDN 只支持 http 反而会失败**，这一风险静态无法判定）。
- 未做真机视频分辨率/横竖屏样本统计（MV 素材横竖比例）。
- 未逐条校对 10 份 arb 的译文语义质量（仅确认键存在与未被消费）。
- 未审 `player_page.dart` 非 MV 段（属 B3 批）、`playback_session` 的 `mv-audio` 兜底全链路（属 B3）、`mv_logic` 缓存失效策略的端到端（属 B5/B7）。
- 未核 Android 端 `usesCleartextTraffic`/网络安全配置（仓库内无 `android/` 目录，只有 `lib/`、`assets/`、`tool/`——**无法确认明文策略**）。

## 76 合规小结

- **L7 越级/编排外溢**：`mv_page.dart` 在 Widget 内做两段式编排、选档策略、http→https 协议改写、错误分类（应由 L5/L6 产出语义结果，L7 只渲染）；`player_page.dart` 直接 `registerMvModule()`（L6 模块注册职责）并直接编排播放会话暂停。
- **L4 越界**：`mv_endpoints.dart` 持有用户可见中文 label（档位命名），L4 应只出结构化事实。
- **L4 吞错掩盖跨层错误态**：`mv_logic`/`mv_endpoints` 用 0/空列表兼作失败信号，跨层接缝处错误语义丢失（这是本批最重要的 76 接缝问题）。
- **断链（非越级）**：arb 资源与 `S` 门面齐备、MV 页零消费；`encodeQr` 导出齐备、业务零调用；`registerDevice` 能力齐备、零调用。
- **符合**：L7 使用 `ThemeData`/`ColorScheme` 本身合规（问题在消费方式）；QR 编码器归 L4 纯算法合理且仅经 `bridge_core` 导出。
