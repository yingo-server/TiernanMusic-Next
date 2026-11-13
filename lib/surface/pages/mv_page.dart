// L6 surface/pages · MV 页模块（批1-B · GAP_ANALYSIS #16）
// 装配方式（不动 modules.dart / assembly.dart，由主代理接线）：
//   final mvLogic = MvLogic(client: ..., cache: ...);          // boot 装配
//   SurfaceRegistry.install(buildMvModule(
//     logic: mvLogic,
//     currentMvHash: () => playerController.currentMvHash,      // 播放器联动钩子
//   ));
//   go_router 注册 route '/mv'（模块无 navEntry，非 tab）。
// 视频播放壳：本页为占位实现——封面点击 + 清晰度 chips + 外部播放器意图
// （platform url_launcher 不在本批白名单，经回调注入 onExternalPlay）。
// TODO(批5+): 视频播放壳后续接入（不扩功能、不引依赖）——本页视频播放壳属新功能，
//   集中此一条：video_player 属依赖例外白名单需评估，或按 ARCHITECTURE.md 自实现
//   ≤500 行播放壳；封面点击/清晰度 chips/外部播放器意图回调 onExternalPlay 保持现状。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart'
    show MvBrief, MvQuality, MvPlayResult;
import '../../bridges/bridge_logic.dart'
    show MvLogic, Log, LogicFacade;
import '../registry.dart';
import 'mv_player_shell.dart' show MvPlayerShell;
import '../widgets/tn_app_bar.dart' show TnAppBar, TnPagePadding;
import '../widgets/common_widgets.dart' show CoverImage;

const String _tag = 'surface.mv_page';

/// MV 页模块工厂。
SurfaceModule buildMvModule({
  required MvLogic logic,
  required String? Function() currentMvHash,
  void Function(String url)? onExternalPlay,
  Future<bool> Function(String mvHash)? onToggleFavorite,
  bool Function(String mvHash)? isFavorite,
}) {
  return _MvPageModule(
    logic: logic,
    currentMvHash: currentMvHash,
    onExternalPlay: onExternalPlay,
    onToggleFavorite: onToggleFavorite,
    isFavorite: isFavorite,
  );
}

class _MvPageModule implements SurfaceModule {
  _MvPageModule({
    required this.logic,
    required this.currentMvHash,
    this.onExternalPlay,
    this.onToggleFavorite,
    this.isFavorite,
  });

  final MvLogic logic;
  final String? Function() currentMvHash;
  final void Function(String url)? onExternalPlay;
  final Future<bool> Function(String mvHash)? onToggleFavorite;
  final bool Function(String mvHash)? isFavorite;

  @override
  String get id => 'mv';

  @override
  String get route => '/mv';

  @override
  NavEntry? get navEntry => null; // MV 页非 tab

  @override
  bool enabled(LogicFacade facade) => true;

  @override
  WidgetBuilder builder(LogicFacade facade) => (ctx) => _MvPageBody(
        logic: logic,
        initialHash: currentMvHash(),
        onExternalPlay: onExternalPlay,
        onToggleFavorite: onToggleFavorite,
        isFavorite: isFavorite,
      );
}

class _MvPageBody extends StatefulWidget {
  const _MvPageBody({
    required this.logic,
    this.initialHash,
    this.onExternalPlay,
    this.onToggleFavorite,
    this.isFavorite,
  });

  final MvLogic logic;
  final String? initialHash;
  final void Function(String url)? onExternalPlay;
  final Future<bool> Function(String mvHash)? onToggleFavorite;
  final bool Function(String mvHash)? isFavorite;

  @override
  State<_MvPageBody> createState() => _MvPageBodyState();
}

class _MvPageBodyState extends State<_MvPageBody> {
  String? _hash;
  MvBrief? _brief;
  List<MvQuality> _qualities = const <MvQuality>[];
  String? _selectedQualityId;
  MvPlayResult? _playResult;
  String? _inlineUrl;
  bool _loading = false;
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    try {
      _hash = widget.initialHash?.trim().toLowerCase();
      if (_hash != null && _hash!.isNotEmpty) {
        _favorite = widget.isFavorite?.call(_hash!) ?? false;
      }
    } catch (e, st) {
      Log.e(_tag, 'initState failed', e, st);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final h = _hash;
      if (h == null || h.isEmpty) {
        Log.d(_tag, '_load skip: no mv hash');
        return;
      }
      setState(() => _loading = true);
      final quals = await widget.logic.qualities(h);
      if (!mounted) return;
      setState(() {
        _qualities = quals;
        _selectedQualityId =
            quals.isNotEmpty ? quals.first.id : null;
        _loading = false;
      });
    } catch (e, st) {
      Log.e(_tag, '_load failed', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play() async {
    try {
      final h = _hash;
      if (h == null || h.isEmpty) return;
      setState(() => _loading = true);
      final r = await widget.logic.playUrl(h,
          requestedId: _selectedQualityId,
          title: _brief?.name ?? '');
      if (!mounted) return;
      setState(() {
        _playResult = r;
        _loading = false;
      });
      if (!r.playable) {
        Log.w(_tag, '_play not playable quality=$_selectedQualityId');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('暂无可播放的清晰度')));
        }
        return;
      }
      // 内嵌播放：优先内嵌壳；未注入外部回调时不再依赖外部播放器。
      setState(() => _inlineUrl = r.urls.first);
      widget.onExternalPlay?.call(r.urls.first);
    } catch (e, st) {
      Log.e(_tag, '_play failed', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final h = _hash;
      if (h == null || h.isEmpty) return;
      final now = await widget.onToggleFavorite?.call(h);
      if (mounted && now != null) setState(() => _favorite = now);
    } catch (e, st) {
      Log.e(_tag, '_toggleFavorite failed', e, st);
    }
  }

  String _fmtDuration(int ms) {
    try {
      final s = (ms / 1000).floor();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    } catch (e, st) {
      Log.e(_tag, '_fmtDuration failed', e, st);
      return '0:00';
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: TnAppBar(
          title: 'MV',
          leading: BackButton(onPressed: () {
            try {
              Navigator.of(context).maybePop();
            } catch (e, st) {
              Log.e(_tag, 'back failed', e, st);
            }
          }),
          actions: <Widget>[
            IconButton(
              icon: Icon(
                  _favorite ? Icons.favorite : Icons.favorite_border),
              tooltip: _favorite ? '取消收藏' : '收藏 MV',
              onPressed: _toggleFavorite,
            ),
          ],
        ),
        body: TnPagePadding(
          child: _hash == null || _hash!.isEmpty
              ? const Center(child: Text('当前歌曲无关联 MV'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: <Widget>[
                      // 封面占位壳：点击触发取 URL + 外部播放器意图（内嵌播放壳见文件头 TODO(批5+)）。
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(children: <Widget>[
                          Positioned.fill(
                            child: CoverImage(url: _brief?.coverUrl),
                          ),
                          Positioned.fill(
                            // M3 语义例外：InkWell 水波纹需 Material 透明承载层（非取色语义），保留裸值。
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _loading ? null : _play,
                                child: Center(
                                  child: _loading
                                      ? const CircularProgressIndicator()
                                      : Icon(Icons.play_circle_outline,
                                          size: 64,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                              .withValues(alpha: 0.9)),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (_inlineUrl != null && _inlineUrl!.isNotEmpty) ...<Widget>[
                        MvPlayerShell(url: _inlineUrl!),
                        const SizedBox(height: 12),
                      ],
                      if (_brief != null) ...<Widget>[
                        Text(_brief!.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium),
                        const SizedBox(height: 4),
                        Text(
                            '${_brief!.singer}  ·  '
                            '${_fmtDuration(_brief!.durationMs)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 16),
                      // 清晰度 chips。
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          for (final q in _qualities)
                            ChoiceChip(
                              label: Text(q.label.isEmpty ? q.id : q.label),
                              selected: _selectedQualityId == q.id,
                              onSelected: (sel) {
                                try {
                                  if (sel) {
                                    setState(() => _selectedQualityId = q.id);
                                  }
                                } catch (e, st) {
                                  Log.e(_tag, 'chip select failed', e, st);
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_playResult != null) ...<Widget>[
                        Text(
                            _playResult!.playable
                                ? '已解析 ${_playResult!.urls.length} 条 CDN 链路'
                                : '未取得可用播放地址',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                      ],
                      FilledButton.icon(
                        onPressed: _loading ? null : _play,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('播放'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    } catch (e, st) {
      Log.e(_tag, 'build crashed', e, st);
      return Scaffold(appBar: TnAppBar(title: 'MV'), body: const SizedBox());
    }
  }
}
