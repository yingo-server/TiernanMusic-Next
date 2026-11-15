# 批1-C1 只读检查报告

## 1. home_page.dart（lib/surface/pages/home_page.dart）
- 首页 ListView（L150-165）：`itemCount: 4`（L151），i==0 每日推荐 / 1 推荐歌单 / 2 排行榜 / 3 热搜（L152-154）。
- `_playlistSection`：约 L200-245（FutureBuilder 推荐歌单 3 列 GridView，`itemCount: items.length`，卡片 `HomePlaylistCard`）。
- `_rankSection`：约 L247-282（FutureBuilder 排行榜横滑 ListView，`itemCount: items.length`，卡片 `_RankCard`，`_openRank` 直接 playAll）。
- `_hotSection`：约 L284-327（FutureBuilder 热搜 Wrap + ActionChip，点击仅 `_goSearch`，**未传关键词**）。
- 删除热搜的影响行清单：
  - L37 `_hotF` future 声明；L50 `_hotF = g.search?.hotSearch()...`；L59 catch 兜底 `_hotF`；
  - L152-154 itemBuilder 分支 `return _hotSection(c)`；L151 `itemCount: 4 → 3`；
  - L284-327 `_hotSection` 整段方法；
  - L11 import 的 `SearchSuggestItem`（若 search_page 仍用则保留 import 来源，本文件不再需要 show 该项）。
- 瘦身歌单/排行：各删对应 Future 字段（L34/L35）、_load 赋值（L48-49）、catch 兜底（L57-58）、itemBuilder 分支（L152-153）、itemCount 减 1、整段方法（L200-282），以及 `_openPlaylist`/`_openRank` 方法与 `PlaylistDetailSheet` import、`RankBrief`/`PlaylistBrief` show 项。

## 2. search_page.dart（lib/surface/pages/search_page.dart）
- 热搜数据源：**未接入** `appGraph.search.hotSearch()`。页面只有前端硬编码 `kHotCategories`（L29-32，8 个常量词），显示在 `_hotCategories()`（L333-364）。logic 层确有 `hotSearch()`（lib/logic/catalog/search_logic.dart L73，直通不缓存，返回 List<SearchSuggestItem>），bridge_logic.dart 已导出 SearchLogic，可直接 `appGraph.search?.hotSearch()`。
- 点击传关键词链路：热搜/分类/历史 chip 均 `_ctrl.text = kw; _doSearch(kw)` → `appGraph.search?.search(q, 1)`（L72-88），链路已通，只差把 kHotCategories 换成 hotSearch 数据。
- 建议：新增 `_hotF = appGraph.search?.hotSearch()`，_idleBody 加热搜区（itemCount 2→3），chip onPressed 复用 `_doSearch(it.keyword)`。

## 3. module_registry.dart
- `active()` 排序：L40-41 `..sort((a, b) => a.id.compareTo(b.id))`（按 id 字母序）。
- NavEntry（lib/session/contracts.dart L5-10）现只有 label/icon。最小方案：**推荐 NavEntry 加 `navWeight`**——`const NavEntry(this.label, this.icon, {this.navWeight = 0})` + `final int navWeight;`（contracts 零依赖单测不受影响）；registry 排序改 `..sort((a,b)=> (b.navEntry?.navWeight??0).compareTo(a.navEntry?.navWeight??0) 非零时优先，否则 a.id.compareTo(b.id))`。改 registry 加 navOrder 需动 SurfaceModule 契约，波及所有模块，不推荐。
- 默认 navWeight=0 保持现有行为，仅首页/搜索给正权重即可。

## 4. 搜索历史持久化
- **无持久化**：`_history` 是内存 `List<String>`（L41），仅 `_doSearch` 插入去重、上限 12（L80-83），退出页面即丢失；无 SharedPreferences/storage key。

## 必修 TOP5
1. search_page 热搜区仍用硬编码 kHotCategories，未接 `appGraph.search.hotSearch()`（logic 已导出）。
2. 首页热搜 chip 点击只 `_goSearch`，未把关键词传给搜索页（缺 NavState 传参/全局 pending query）。
3. 搜索历史纯内存，无持久化 key，重启即失。
4. NavEntry 无排序权重，导航顺序依赖 id 字母序；需加 navWeight（默认 0）+ registry 排序。
5. home_page 删热搜/瘦身区块需同步清 future 字段、catch 兜底、itemCount 与 import，避免留死代码。
