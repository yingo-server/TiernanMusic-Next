# 批1-F2 首页瘦身 + 热搜搬迁 修改说明

## home_page.dart（lib/surface/pages/home_page.dart，500→457 行）
1. **删 _hotSection 整块**：方法整段删除；`_hotF` 字段（原 L37）、`_load()` 内赋值（原 L50）、catch 兜底（原 L59）、itemBuilder 分支（原 L152-154）全部同步清除；`itemCount: 4→3`；bridge_logic import 去掉 `SearchSuggestItem` show 项；类注释改为「三区块流」。
2. **推荐歌单改单行横滑**：`_playlistSection` 由 shrinkWrap GridView（全展开）改为 `SizedBox(height: 210) + ListView.builder(horizontal)`，每卡 `SizedBox(width: 150)` 包 `HomePlaylistCard`；`_openPlaylist`/PlaylistDetailSheet 链路不变。
3. **排行榜卡压缩**：`_rankSection` 容器高 150→110（骨架同步 110），`_RankCard` 宽 168→120、内边距 gapM→gapS；字号保持 Sp.fSection（标题）/Sp.fTiny，符合 Sp.* 令牌要求。
4. HomePageModule 的 id/route/navEntry/builder 未动；仍 extends SurfaceModule；future 一律 initState/_load 持有，build 内不新建。

## search_page.dart（lib/surface/pages/search_page.dart，476→500 行）
1. **真实热搜区块**：新增 `_hotF`（initState 持有 `appGraph.search?.hotSearch()`，bridge_logic 已导出 SearchLogic，返回 `Future<List<SearchSuggestItem>>`）；`_idleBody` itemCount 2→3，顺序：热搜 `_hotKeywords()` → 热门分类 `_hotCategories()`（kHotCategories 保留并存）→ 历史。热搜布局按要求为 `SizedBox(height: 40) + ListView.builder(horizontal)` 单行横滑（10 个可视即一行），ActionChip 点击 `_ctrl.text=kw; _doSearch(kw)`。空/错/加载三态沿用页面现有 FutureBuilder 模式（加载转圈、错误/空灰字提示）。
2. **搜索历史持久化**：key=`'search.history'`（静态 `_kHistoryKey`），存 JSON 数组；读经 `KeyValueSettings.shared(StoragePaths.I).getString`，写在 `_doSearch` 插入去重/上限 12（`_kHistoryMax`）后及 `_clearHistory` 时 `setString(jsonEncode(_history))`；initState `_history.addAll(_loadHistory())` 读回；读写均 try/catch + Log，UI 结构不变。新增 import：`dart:convert`、`bridge_core.dart show KeyValueSettings, StoragePaths`。
3. 为控行数（≤500 硬限）对若干方法做了等价的紧凑排版（合并单行、去冗余空行），无逻辑变更；kHotCategories 注释/顺序等其余代码保持原样。

## 验收自检（file_read/rg 回读）
- home_page 无 `_hotSection`/`_hotF`/`SearchSuggestItem`/GridView/shrinkWrap 残留；`itemCount: 3` ✓
- 两文件行数：home 457、search 500，均 ≤500 ✓
- search_page 真实调用 `appGraph.search?.hotSearch()`（initState，L77）✓
- 历史 key `'search.history'`（L57）✓
