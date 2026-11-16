
---
## 2026-11-16 A7 · C2 实现正确性审查开始（L7 surface 全 18 文件，功能可达性优先）

### 背景核对（读 summary）
- A1/A3/A5/A6 summary 已读：MV 四重断点、收藏假按钮、下载 enqueue 零调用、登录端点待实测均列为已知断点。本视角在 UI 侧逐条核实是否真的坏掉。

## <视角 C2> · lib/surface/pages/player_page.dart:60-89 · <P1> · <收藏假按钮/功能断点>
证据：
```
// 收藏按钮：状态本地维护（收藏域写端点尚未经桥暴露，故不写远端）。
class FavoriteButton extends StatefulWidget {
  bool _fav = false;
  ...
  onPressed: () { setState(() => _fav = !_fav); widget.onChanged?.call(); },
  icon: Icon(_fav ? Icons.favorite : Icons.favorite_border),
```
且 `rg` 全 surface：除本文件 `_fav` 外 `CollectLogic.toggle` 零调用；`FavoriteButton()` 在 player_page.dart:319 以无参构造，`onChanged` 恒 null；`_fav` 初值恒 false 且无任何读取真实收藏态的加载逻辑。
问题：播放页收藏按钮是纯本地 setState 假开关——不读真实收藏态、不落库、不调 CollectLogic.toggle、重开页面即丢失，与 A1/A5「收藏 logic 零调用」结论一致，UI 侧确认用户收藏功能完全无效。
建议：FavoriteButton 接收当前歌曲 hash 与 CollectLogic 门面；initState 查询真实收藏态初始化 `_fav`，onPressed 调 `collect.toggle(hash)` 并按返回值 setState，失败给 SnackBar；禁止纯本地假态。
76 合规：按钮自身属 L7 控件合规；但假态属功能未接通，不涉及越级 import。

## <视角 C2> · lib/surface/pages/player_page.dart:148-205,192-201 · <P0> · <MV 入口 songHash 语义错配 + 注册守卫恒真>
证据：
```
// _openMenu → 查看 MV：
Navigator.of(ctx).pop();
registerMvModule();
final current = PlaybackSession.instance.snapshot.player.current;
final hash = current?.hash ?? '';
Navigator.of(context).push(MaterialPageRoute(builder: (_) => MvPage(songHash: hash)));
```
`current.hash` 是歌曲音频 hash（32 位），而 mv_page 把它当 MV 查询键传 `logic.qualities(hash)`；A3/A5 已确认正确链路须先 getMvBySong(albumAudioId)→mvBrief.hash，再把 mv hash/video_id 传 qualities。此 UI 传参把歌曲 hash 当 MV hash，是 A1 X2 的 UI 端确证。
问题：「查看 MV」按钮传错参数（歌曲 hash 冒充 MV 查询键），即使下层修好也恒查不到对应 MV，是用户点名「MV 用不了」的直接 UI 断点之一。
建议：MvPage 入参改为结构化（如 songHash+albumAudioId 或直接 mvHash），由 logic 先用 albumAudioId 查 MvBrief，再用 brief.hash/video_id 走 qualities；UI 不得自行猜测 hash 语义。
76 合规：仅参数传递错误，无越级依赖。

## <视角 C2> · lib/surface/pages/mv_page.dart:12-20 + lib/session/bootstrap.dart:216-232 + lib/surface/shell.dart:22-30 · <P0> · <MV 模块注册守卫恒真，真实页面永不接管>
证据：
```
// mv_page.dart
void registerMvModule() {
  final reg = ModuleRegistry.instance;
  if (reg.byId('mv') != null) return;   // 守卫
  reg.install(MvPageModule());
}
// bootstrap.dart
const moduleIds = [..., 'mv', ...];
for (final id in moduleIds) {
  ModuleRegistry.instance.install(_PlaceholderModule(id));  // 先占位
}
// main.dart:95 → installServices → registerModules → registerMvModule()
```
时序：bootstrap 先把 id='mv' 的 `_PlaceholderModule` 装进注册表，随后 main 才调 installServices→registerMvModule；守卫 `byId('mv') != null` 此刻必为真 → 直接 return，真实 MvPageModule 永不安装。
问题：shell.dart:30 与 player_page.dart:192 两次调用 registerMvModule 都被占位模块挡回，「查看 MV」即使 push 也是直接 new MvPage（见下一节），注册表里的 mv 仍是占位空壳；UI 侧确认模块注册链彻底断。与 A1 X1、A6 X3 跨批一致。
建议：registerMvModule 由幂等守卫改为「按 id 覆盖安装真实模块」；或 bootstrap 不再预装 'mv' 占位，使真实模块首次注册即为真。修复后校验 `reg.byId('mv').builder` 指向 MvPageModule。
76 合规：L7 经 bridge_session 访问注册表，层次合规；bug 属逻辑守卫错误。

## <视角 C2> · lib/surface/pages/mv_page.dart:78-120,27-32 · <P0> · <MV playUrl 用 low.id/low.hash 冒充 video_id，档位恒空>
证据：
```
final requested = low.id.isNotEmpty ? low.id : low.hash;
final r = await logic.playUrl(hash, requestedId: requested);  // hash=songHash, requestedId=档位id/hash
```
MvPage 把 songHash 传作 logic.playUrl 的第一参，把 chosen quality 的 `id`/`hash` 传作 requestedId；A5 X3 已确认 mv_logic.playUrl 内部把 hash 当数字 video_id 送 getVideoQualities/getPlayUrl，且 qualities(hash) 同样以歌曲 hash 为键。UI 侧这里把 `low.hash`（MV 档位 hash，非 video_id）也混入，进一步加重语义混乱。
问题：「查看 MV」页从查询到取流全程用错键（歌曲 hash / 档位 hash 冒充 MV video_id），与 A3 X1/X2、A5 X3 叠加构成 MV 至少四重断点；用户实际点击后只会看到「这首歌暂无可播 MV」或加载失败。
建议：MvPage 的数据获取统一收口到 logic 的一个 `loadPlayableMv(songAlbumAudioId)` 门面，内部完成 getMvBySong→brief.hash→qualities(videoId)→playUrl(videoId, qualityId)；UI 只消费 URL 与档位标签。
76 合规：跨层调用经 bridge_session.appGraph.mv，合规；问题在参数语义。

## <视角 C2> · lib/surface/pages/player_page.dart:175-211（FM 菜单）+ lib/surface/pages/login_sheet.dart:412-434（密码登录） · <P1> · <UI 承诺「待实测」端点冒充可用>
证据：
```
// FM 菜单：
final songs = await appGraph.fm?.start();
... ScaffoldMessenger... Text('FM 暂无可用曲目（端点待实测）')
// 密码登录：
await auth.signInByPwd(pwd);  // 忽略返回值
// 就绪后此处接 onLoginSuccess（由批2-F1 定义返回形态）
catch (e) { ... Text('密码登录待后端就绪') }
```
问题：FM 入口调用 `appGraph.fm?.start()`（graph.dart:88 仅声明字段，A5 标记 fm 空壳/端点待实测），失败提示直接把「端点待实测」暴露给用户；密码登录调 `signInByPwd(pwd)` 后完全忽略返回值、不接 onLoginSuccess、不关闭弹层、不给成功反馈，catch 里明文告诉用户「待后端就绪」——两个入口均为「点了没反应/假可用」，兑现用户「什么功能都用不了」痛点。
建议：FM/密码登录若端点未就绪，UI 应显式禁用入口并标「即将上线」而非按钮可点；端点就绪后按真实返回值接成功路径（bumpAuth+pop）与失败反馈，删除「待实测/待后端就绪」用户可见串。
76 合规：无越级 import；属功能未接通与文案诚信。

## <视角 C2> · lib/surface/（全 18 文件 rg 证据）+ lib/surface/pages/player_page.dart / library_page.dart · <P1> · <下载功能零入口，空态文案指向不存在的菜单>
证据：
```
$ rg -n 'enqueue|addTask|startDownload|download\(' lib/surface/   → (exit 1，零命中)
```
全 surface 18 文件仅 library_page.dart 有 `appGraph.downloads` 的**只读**消费（`listTasks()` 显示已下载列表 + 空态），无任何新增下载任务的入口：
```
// library_page.dart:291-305
Widget _downloadsTab() {
  if (appGraph.downloads == null) return SpStateView(icon: Icons.download_outlined, ...);
  if (_downloads.isEmpty) return SpStateView(... subtitle: ...);  // 空态有文案
  ...
}
```
结合 A1/A3「download enqueue 零调用」结论：DownloadManager 有 enqueue 实现但整个 UI 无处可点，用户「下载功能用不了」在 UI 侧核实为真——列表永远是空的，且没有任何「下载」按钮触发新增任务。
问题：surface 全部 18 文件中下载只有「查看列表」，没有「发起下载」入口；下载功能对用户完全不可用，与 A1/A5 结论互证。
建议：在 player_page 更多菜单与 library/playlist 每首歌的溢出菜单加「下载」项，调 `appGraph.downloads.enqueue(song)`（经桥暴露），建立成功后刷新列表的反馈链；空态文案改为指向真实存在的入口。
76 合规：无越级依赖；属功能未接通。

## <视角 C2> · lib/surface/pages/player_page.dart:174-181（评论菜单）+ lib/session/bootstrap.dart:221,247 + shell.dart:22-29 · <P1> · <评论入口 requestTab('comment') 指向占位模块>
证据：
```
// player_page _openMenu：
ListTile(title: Text('评论'), onTap: () { navState().requestTab('comment'); ... });
// bootstrap.moduleIds 含 'comment'，for 循环 install _PlaceholderModule('comment')
// shell.registerModules() 只装 home/search/playlist/library/settings/player/lyrics/mv，无 comment
// shell._modules = active().where(navEntry != null)
```
`_PlaceholderModule` 的 navEntry 为 null（A1 已确认），comment 只存在占位实现且不在底部导航；`requestTab('comment')` 在 shell._modules 中 `indexWhere(m.id=='comment')` 恒 -1 → 不切页、无任何反馈。
问题：播放页「评论」菜单点了没反应——目标模块是占位空壳且不在导航列表，requestTab 找不到索引静默失败，用户可见死链。
建议：要么为 comment 注册真实页面并纳入导航/或让 requestTab 对无 navEntry 的模块改用 push 路由；在切页失败时给用户 SnackBar 反馈而非静默。
76 合规：符合 L7→L6 调用；属功能断点。

## <视角 C2> · lib/surface/pages/login_sheet.dart:296-334 与 412-434 · <P1> · <验证码/密码登录输入校验缺失、返回值处理错误>
证据：
```
// _SmsTab._sendCode：仅 phone.isEmpty 检查，无手机号格式正则（任意字符串可发）
// _SmsTab._login：仅 phone/code isEmpty 检查，无验证码位数/格式校验
// _PwdTab._login：
final dynamic auth = appGraph.auth;
await auth.signInByPwd(pwd);   // 返回 Future<LoginResult> 被丢弃；dynamic 绕过静态检查
// 无 onLoginSuccess、无 pop、无失败 SnackBar（失败全靠 catch）
catch (e) { ... Text('密码登录待后端就绪') }
```
`signInByPwd` 真实签名 `Future<LoginResult>`（auth_logic.dart:286），失败时 rethrow KugouApiException；UI 用 `dynamic` 接住并丢弃结果，成功路径完全没接（注释自承认「由批2-F1 定义返回形态」），账号栏输入 acc 也没传给端点（signInByPwd 只有 pwd 位参）。
问题：密码登录无论后端成功失败，UI 都停在弹层无成功反馈/不关弹层；SMS 无格式校验导致垃圾输入外发到待实测端点；`dynamic` 绕过类型系统掩盖返回值丢弃。
建议：去掉 dynamic，按 `Future<LoginResult>` 消费返回值：ok 则 `_onLoginSuccess()`，否则用 `res.error` 反馈；补手机号/验证码格式校验；把账号输入框值纳入登录参数（若端点支持）或明确改为纯密码登录 UI。
76 合规：L7 经 original appGraph 访问 auth 合规；但 dynamic 与返回值丢弃属实现缺陷。

## <视角 C2> · lib/surface/pages/search_page.dart:74-97,110-134,372-421 · <P1> · <搜索无分页 + 分段搜索结果被当作歌曲列表渲染>
证据：
```
void _doSearch(String kw) {
  final SearchType type = kSearchSegmentTypes[_segment];
  _resultF = (_segment == 0) ? se?.search(q, 1) : typed?.typed(type, q, 1);  // page 恒 1
}
...
// _resultBody 无论 _segment 为何，都按 List<SongBrief> items 渲染 SearchSongTile
for (...) SearchSongTile(song: items[i], onAlbum: () => _openAlbum(items[i].albumId));
```
`kSearchSegments` 有「歌曲/歌单/专辑/歌手/歌词」5 段，`kSearchSegmentTypes` 映射到 special/album/author/lyric 五种 SearchType；但 `_resultBody` 只取 `r.items`（SongBrief 列表）统一按歌曲 tile 渲染，歌单/专辑/歌手/歌词分段即便端点返回数据也被强行当歌曲显示（albumId 可能为空、 lyric 段根本无歌曲字段）；`search(q, 1)`/`typed(type,q,1)` 页码硬编码 1，无滚动加载更多/分页触发。
问题：搜索分段切换是假分段——所有段都按歌曲渲染，非歌曲段结果丢失/错显；且无分页，用户只能看第一页，属「搜索功能用不了」的 UI 侧断点。
建议：按 SearchType 分支渲染不同 tile（歌单/专辑/歌手/歌词各有模型），或明确只保留「歌曲」段并隐藏其余；加 ScrollController 触底加载 page+1 并拼接结果。
76 合规：数据经 bridge_logic/bridge_session，层次合规；属实现错位。

## <视角 C2> · lib/surface/pages/search_page.dart:74-97,195-223（_suggestBox）· <P2> · <搜索联想与结果 Future 竞态，旧请求可覆盖新结果>
证据：
```
void _onChanged(String text) { ... setState(() => _suggestF = se?.suggestions(t) ...); }
void _doSearch(String kw) { ... setState(() { _suggestF = null; _resultF = se?.search(q,1) ...; }); }
Widget _suggestBox / _resultBody: FutureBuilder(future: f)  // 直接用 setState 时的 future 引用
```
无请求序号/token 校验：用户快速输入 „a"→„ab"→„abc"，每次 onChanged 都 setState 新 `_suggestF`，FutureBuilder 对已完成旧 future 仍可能先 build 并把旧联想显示；_doSearch 后 _resultF 亦然，旧搜索先返回会短暂/持久覆盖新查询的分段结果。另 `_doSearch` 用 try/catch 包住的是「创建 Future」而非 await，端点异步抛错由 FutureBuilder 的 snap.hasError 兜底（结果有重试），但联想 `suggestions()` 的 snap 未处理 hasError（只 `snap.data ?? []`），失败静默吞。
问题：搜索联想/结果存在异步竞态与联想错误静默吞，快速输入时用户可能看到与当前关键词不符的列表。
建议：给每次请求加单调递增 seq，FutureBuilder 完成后校验 seq==当前才 setState；联想分支补 `if (snap.hasError) return SizedBox.shrink()` 或重试入口。
76 合规：无越级依赖；属异步实现缺陷。

## <视角 C2> · lib/surface/pages/lyrics_page.dart:36-58,60-105,121-135 · <P1> · <歌词页生命周期与切歌同步缺陷（Timer 无 mounted 保护 + 轮询重复触发加载）>
证据：
```
initState: _timer = Timer.periodic(200ms, (_) => _tick());  // 不检查 mounted
dispose: _timer?.cancel(); ...  // 有 cancel（正面）
void _tick() {
  final snap = playbackSession().snapshot;
  final song = snap.current;
  if (song == null || _rows.isEmpty) return;
  if (song.hash != _hash) { _load(); return; }   // 200ms×重复调用 _load，无 in-flight 保护
  ...
}
Future<void> _load() async { ... if (!mounted) return; setState(...); }  // 内部有 mounted 检查（正面）
```
`_tick` 每 200ms 触发：切歌后 `_hash` 仍是旧值且 `_rows` 非空 → 在新歌歌词加载完成前，每 200ms 重复调 `_load()`，产生并发重复网络/解析请求；`_load()` 内 `setState(() => _loading = true)` 在异步开始前未检查 mounted（虽 await 后有检查）；Timer 回调 `_tick` 自身无 mounted 检查，dispose 后理论上残留一帧（cancel 基本覆盖）。`_translation.displayFor` 依赖 A3 已确认恒空的 fetchTranslation（A5 X8），翻译开关在 `_hasTranslation` 恒 false 时禁用——翻译功能实质不可用。
问题：歌词页切歌时 200ms 轮询重复发起同一首歌的加载，竞态下可能旧歌回调覆盖新歌歌词；翻译依赖恒空端点，用户永远看不到译文。
建议：`_load` 加 `_loadingFuture` 去重（in-flight 复用）；`_tick` 首行加 `if (!mounted) return;`；翻译开关在端点恒空期间显式隐藏/禁用并标「暂不可用」，不要摆一个永远按不动的开关。
76 合规：无越级 import；属状态/竞态与死链。

## <视角 C2> · lib/surface/app_root.dart:61-68 · <P2> · <主题模式 0 跟随系统/3 纯黑均被错误映射为暗色，设置项假开关>
证据：
```
themeMode: switch (mode) {
  1 => ThemeMode.light,
  _ => ThemeMode.dark,   // 0=跟随系统、2=暗、3=纯黑 全落 dark
},
```
`settings_page.dart:225-240` 提供 4 档：0 跟随系统 / 1 亮 / 2 暗 / 3 纯黑；AppRoot 只区分 1 与其余，mode=0（跟随系统）被强制 dark（系统亮色时不跟随），mode=3（纯黑）落 dark 但代码注释自承「纯黑暂用暗色板，TODO 更深色板」——3 档中 2 档语义不兑现。
问题：设置页主题模式选项中「跟随系统」「纯黑」是假开关，用户切换后行为与标注不符（跟随系统恒暗、纯黑=普通暗）。
建议：mode 0 映射 ThemeMode.system；mode 3 提供独立纯黑 ThemeData（ bgcolor #000000 ）或明确禁用该选项，避免假承诺。
76 合规：层次合规；属状态映射缺陷。

## <视角 C2> · lib/surface/pages/player_page.dart:401-417 + settings_page.dart:210-214 · <P2> · <音质档位选中态硬编码 '128'，与实际播放音质脱节>
证据：
```
// player_page _badges：
ActionChip(label: const Text('音质'), onPressed: () => _openQualitySheet('128'));  // 硬编码
// _openQualitySheet trailing: qualityParam(q) == current → 永远勾选 '128'
// settings_page 音质 ListTile subtitle 亦硬编码 '128（标准）'
```
`playbackSession().setQuality(...)` 设置后并未回读到 badge/subtitle，sheet 的 current 恒为 '128'，用户选了 320 后 chip/设置页仍显示 128、重开 sheet 勾选仍停在 128——音质状态展示是假的。
问题：音质档位展示不读真实 session 质量值而是硬编码 128，用户无法确认当前音质，选中态永远错。
建议：从 PlaybackSession 快照/质量设置读取当前 quality 传入 _openQualitySheet 与 subtitle，切换后经 AnimatedBuilder 自动刷新。
76 合规：层次合规；属 UI 状态一致性缺陷。

## <视角 C2> · lib/surface/（YKG 全量 rg）+ settings_page.dart:19,205-212 · <P1> · <YKG 登录方式在 UI 无任何入口，用户原话需求零兑现>
证据：
```
$ rg -ni "ykg|导出|导入|解锁" lib/surface/
  → 仅 lyrics_page.dart 的 GAP 注释与 library_page.dart:210 "下载或导入歌曲后会显示在这里"（非 YKG）
```
登录弹层（login_sheet.dart）只有 扫码/验证码/密码 三 Tab，设置页账号区只有「扫码登录」按钮 + 已登录账号列表；根据 A1/A5/A6 汇总，YKG 协议（base64 cookie + md5 加盐密码、导出/导入解锁）全仓零实现、零 UI 入口。用户「登录方式支持 ykg 协议浏览器链接」的需求在 surface 层完全无表面。
问题：用户点名要求的 YKG 登录方式在 UI 侧无任何按钮/入口/文案，用户根本无法使用/感知该功能（即便下层密码学已设计，UI 也未接线）。
建议：在 login_sheet 增加「YKG 链接」Tab：输入链接+密码 → 调 L5 ykg_logic 解析/校验/解锁（成熟库封装），错误给明确反馈；设置页账号区增加「导出 YKG 链接」入口。入口何时可用需与底层实现状态对齐，未就绪时显式置灰标注。
76 合规：层次合规；属需求功能缺失（非越级）。

## <视角 C2> · lib/surface/pages/library_page.dart:299-305 + player_page.dart 全文件 · <P2> · <下载空态文案「在歌曲菜单里选择下载」指向不存在的菜单>
证据：
```
// library_page.dart:299-305 下载空态：
SpStateView(title: '暂无下载任务', subtitle: '在歌曲菜单里选择下载');
```
但全 surface 无任何「下载」菜单项：player_page 更多菜单只有 歌词/评论/查看MV/个人FM（player_page.dart:160-211），search_tile_widgets / playlist_page / home_page 的歌曲行都无 onMore 下载动作；全 surface rg `enqueue|addTask|startDownload` 零命中。
问题：下载空态明确告诉用户「在歌曲菜单里选择下载」，但该菜单项在所有页面都不存在——死链文案误导用户，与 A1/A3「下载 enqueue 零调用」一致。
建议：要么补上歌曲菜单的「下载」入口使文案为真，要么在入口未就绪前把空态文案改为「下载功能即将上线」避免误导。
76 合规：层次合规；属功能断点+文案误导。

## <视角 C2> · lib/surface/pages/login_sheet.dart:22-35 · <P2> · <showLoginSheet 无 onAuthChanged 传参，登录成功后父页可能不刷新（设置页未传回调）>
证据：
```
Future<void> showLoginSheet(BuildContext context, {void Function()? onAuthChanged}) {...}
// login_sheet.dart:94-105 _onLoginSuccess() → widget.onAuthChanged?.call(); Navigator.pop()
// settings_page.dart:186 onPressed: () => showLoginSheet(context),  // 未传 onAuthChanged
```
SettingsPage 的登录按钮调用 showLoginSheet 不传 onAuthChanged；虽然 settings_page 自身在 initState 注册了 navState 监听 `_onAuthChanged`（login_sheet._onLoginSuccess 内调 navState().bumpAuth()），登录刷新经由 navState 广播间接成立（正面），但 showLoginSheet 提供的 onAuthChanged 回调契约在此调用点形同虚设；其它未来调用点若不注册 navState 监听会漏刷新。
问题：登录成功回调机制依赖 navState 广播的隐式约定，showLoginSheet 的显式 onAuthChanged 参数在当前唯一调用点未被使用，契约不一致（低危、可健壮性改进）。
建议：统一登录后刷新单一路径——要么 settings_page 传 `onAuthChanged: _loadAccount` 并移除重复 navState 监听，要么废弃 onAuthChanged 参数只保留 bumpAuth，避免双机制并存。
76 合规：层次合规；属接口一致性小缺陷。

## <视角 C2> · lib/surface/pages/search_page.dart:65-71,372-421（_resultBody snap.hasError 分支）· <P2> · <搜索结果 hasError 的「重试」闭包捕获可变 _query，重试可能打空>
证据：
```
void _doSearch(String kw) { final q = kw.trim(); if (q.isEmpty) return; setState(() => _query = q ...); }
// _resultBody：
if (snap.hasError) return SearchErrorRetry(message:'搜索失败', onRetry: () => _doSearch(_query));
```
`_query` 是实例可变字段，重试闭包读的是当前值而非发起该失败请求的关键词；若用户在失败后改了输入框/切了分段，点击「重试」会用新 `_query` + 当前 `_segment` 重搜，而非重试原失败查询——通常无害但语义不精确；对比 home/playlist 的重试 `_reload` 重建同一 future（更正确）。
问题：搜索错误重试不锁定失败时的查询词与分段，行为随 UI 当前状态漂移，属小的重试语义缺陷。
建议：在 setState 时把 `{query, segment}` 一起存入 `_lastQuery/_lastSegment`，重试闭包用快照值重建 future。
76 合规：层次合规；属实现细节。

## <视角 C2> · 状态/监听器泄漏专项核查（全 18 文件）· <P2> · <正面结论 + 个别缺口>
证据（rg + 逐文件）：
- 正面：search_page `_ctrl.dispose()`、lyrics_page `_timer.cancel()/_active.dispose()/_scroll.dispose()`、mv_page `_release()` 内 `removeListener+dispose` + `mounted` 防护、login_sheet `_SmsTab/_PwdTab` 全部 controller.dispose + timer.cancel、_QrTab timer.cancel、settings_page navState.removeListener、shell.dart NavState.removeListener、app_root ValueListenableBuilder（自动）——主要 StatefulWidget 均正确释放。
- 缺口1：player_page.dart:53-58 `_SeekSliderState.didUpdateWidget` 用 `(widget.positionMs - (_preview ?? 0).round()).abs() < 900`，`_preview` 为 double 毫秒，比较时把 `_preview.round()` 当 int 与 positionMs 相减——逻辑上可行但阈值 900ms 是 magic number，且 `(_preview ?? 0)` 在已确认非 null 分支里冗余；不是泄漏，属可读性。
- 缺口2：mv_page.dart:56 `_onCtrl` 监听在 `_release()`（dispose/didUpdateWidget/替换 controller）中正确 removeListener（正面），但 `_load()` 中 `c.initialize()` 后至 `_release()` 之间若 `!mounted` 有 `await c.dispose()`（正面），无泄漏。
- 缺口3：settings_page.dart:41 `_onAuthChanged` → `_loadAccount()` 无 mounted 检查：方法内部 `if (!mounted) return;`（settings_page.dart:57）已覆盖（正面）。
问题：监听器/控制器泄漏总体控制良好，无 P0/P1 级泄漏；仅个别 magic number/冗余判断，不构成功能断点。
建议：无需修复阻断项；可将 900ms 阈值提为常量并加注释说明「容差覆盖一轮位置刷新周期」。
76 合规：层次合规。

---
## 本视角结论（A7 · C2 实现正确性）
1. **MV 功能在 UI 侧确认彻底不可用（P0，四重叠加）**：①注册守卫 `byId('mv')!=null` 被 bootstrap 占位模块恒真挡回，真实 MvPageModule 永不安装（mv_page.dart:12-20 / bootstrap.dart:216-232）；②「查看 MV」传入 `current.hash`（歌曲 hash）而非 MV 查询键（player_page.dart:192-201）；③`qualities(hash)/playUrl(hash, requestedId:low.id|low.hash)` 用歌曲 hash 与档位 hash 冒充 MV video_id（mv_page.dart:78-120）；④叠加 A3/A5 下层端点恒 null。用户点「查看 MV」只会看到「暂无 MV」或加载失败，与用户点名痛点完全吻合。
2. **收藏/下载功能在 UI 侧确认全断（P1）**：FavoriteButton 纯本地 setState 假开关、不读真实态/不落库/不调 CollectLogic.toggle（player_page.dart:60-89）；全 surface `enqueue|addTask|startDownload` 零命中，下载空态文案「在歌曲菜单里选择下载」指向不存在的菜单（library_page.dart:299-305）。
3. **登录三 Tab 均有断点（P1）**：密码登录用 dynamic 丢弃 `Future<LoginResult>` 返回值、成功路径未接、账号输入未参与认证（login_sheet.dart:412-434）；验证码无格式校验且提示「端点待实测」；YKG 协议登录 UI 无任何入口（全 surface 零命中），用户点名需求零兑现。
4. **搜索/首页等列表页功能半残（P1/P2）**：搜索 5 分段统一按歌曲渲染、页码硬编码 1 无分页、联想 hasError 静默吞、Future 竞态无 seq 保护（search_page.dart）；「评论」菜单 requestTab('comment') 指向 enabled=false 的占位模块，点了没反应（player_page.dart:174-181）。
5. **歌词页同步与翻译（P1）**：200ms 轮询切歌无 in-flight 去重可重复发请求，翻译开关依赖恒空端点永不可用（lyrics_page.dart:36-135）；但 Timer/Controller 释放与 mounted 检查总体到位。
6. **状态一致性小缺陷（P2）**：主题 0 跟随系统/3 纯黑被错误映射为暗色（app_root.dart:61-68）；播放页/设置页音质档位硬编码 '128' 不读真实 session 值。
7. **生命周期/监听器专项**：全 18 文件 Controller/Timer/Listener/VideoPlayerController 释放与 mounted 检查总体正确，无 P0/P1 级泄漏。
8. 三态（加载/空/错误+重试）在 home/search/playlist/library/lyrics/mv 页均已具备，覆盖较完整。

## 未覆盖
- 未验证 `lib/l10n/*.arb` 与 README（本子代理任务书口径为「A7 surface 全 18 文件」，文案 arb 由 C3 视角覆盖，本报告未读）。
- 未验证各 logic/端点端在运行时的真实网络返回（仅静态核对 UI 调用与返回值语义；「恒 null/端点待实测」结论引自 A1/A3/A5/A6 汇总，未独立重测）。
- 未覆盖 `NavState.setAlbum(albumId)` 之后是否有真实专辑页面消费（bootstrap 仅装了 enabled=false 的 album 占位模块，推断为死链，但未逐文件追踪 session 侧监听器，留给 B7）。
- 未做 M3/动画/硬编码色值打分（C3 视角职责）。
- 未运行任何编译/分析/测试（工具纪律禁止）。

## 76 合规小结
- **层归属**：18 文件均为纯 UI 控件/令牌/状态组件，未发现 surface 内嵌状态机或业务逻辑越界（播放器进度预览 `_SeekSlider._preview` 属控件局部态，合规）。
- **依赖方向**：全部经 `bridge_core / bridge_logic / bridge_session` 访问下层，无 surface→非桥 logic/core 直连、无反向依赖、无影子桥——76 §0 铁律 1/3/4 合规。
- **bridge 前置**：未发现 surface 内 try/catch 静默吞下层异常不 Log 的情形（page 内 catch 均 debugPrint 或 Log.e）；login_sheet `_poll` catch(_) 静默容错轮询瞬时失败有注释说明，属可接受容错（P2 未单列）。
- **1500 行门禁**：18 文件最长 player_page 442 行，全过。
- **成熟库**：video_player（MV）、just_audio（经 session）使用成熟库，合规。
- **主要债**：本视角发现均为功能可达性/状态一致性缺陷（MV/收藏/下载/登录/YKG/搜索/评论），非 76 架构违规；架构层违规以 A6 C1 结论（main 跨 5 层直连 bridge_surface、playback_session 越界持状态机）为准，本视角无新增架构违规。
