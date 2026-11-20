// L7 surface/pages · YKG 链接登录弹层（导出 / 导入）
//
// 铁律：只用官方 Material 3 控件；不手写控件类（弹层本身为页面容器）；
// 颜色只来自语义 token（Theme.of(context).colorScheme / context.cs）；
// 能力经 bridge_session.appGraph.ykg；文案走 S.of(context).t。
// 设计权威：docs/YKG_LINK_CRYPTO_DESIGN.md
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../bridges/bridge_logic.dart' show Log;
import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens_v2.dart';
import '../design/layout.dart' show TnBreakpoint, TnRadius, TnSize, TnSpace;
import '../l10n/s.dart' show S;

/// 显示 YKG 弹层。export=true 导出，false 导入。
Future<void> showYkgSheet(BuildContext context, {required bool export}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext c) => YkgSheet(export: export),
    );

/// 便捷入口（供登录页调用，避免暴露内部枚举）。
Future<void> showYkgExport(BuildContext context) =>
    showYkgSheet(context, export: true);

Future<void> showYkgImport(BuildContext context) =>
    showYkgSheet(context, export: false);

/// YKG 弹层容器（页面容器，允许有状态）。
class YkgSheet extends StatefulWidget {
  const YkgSheet({super.key, required this.export});
  final bool export;
  @override
  State<YkgSheet> createState() => _YkgSheetState();
}

class _YkgSheetState extends State<YkgSheet> {
  final TextEditingController _pwd = TextEditingController();
  final TextEditingController _link = TextEditingController();
  String _result = '';
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _pwd.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _doExport() async {
    final s = S.of(context);
    final logic = appGraph.ykg;
    if (logic == null || !logic.canExport) {
      _set(s.t('ykgNotLoggedIn'));
      return;
    }
    if (_pwd.text.isEmpty) {
      _set(s.t('ykgPasswordHint'));
      return;
    }
    setState(() => _busy = true);
    try {
      final link = await logic.exportLink(password: _pwd.text);
      if (link == null) {
        _set(s.t('ykgNotLoggedIn'));
        return;
      }
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        _link.text = link;
        _set(s.t('ykgCopied'));
      }
    } catch (e, st) {
      Log.e('surface.ykg', 'export failed', e, st);
      _set(s.t('errorGeneric'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doImport() async {
    final s = S.of(context);
    final logic = appGraph.ykg;
    if (logic == null) {
      _set(s.t('favoriteUnavailable'));
      return;
    }
    final text = _link.text.trim();
    if (!logic.isYkgLink(text)) {
      _set(s.t('ykgInvalidLink'));
      return;
    }
    if (_pwd.text.isEmpty) {
      _set(s.t('ykgPasswordHint'));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await logic.importLink(text, _pwd.text);
      if (!mounted) return;
      if (r.$1) {
        _set(s.t('ykgImportOk'));
        Navigator.of(context).pop();
      } else {
        // 底层错误统一为「密码错/链接损坏」，按 i18n 文案展示，不直显底层串。
        _set(s.t('ykgWrongPassword'));
      }
    } catch (e, st) {
      Log.e('surface.ykg', 'import failed', e, st);
      _set(s.t('ykgWrongPassword'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _set(String msg) {
    if (!mounted) return;
    setState(() => _result = msg);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isExport = widget.export;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: TnSpace.xl,
          right: TnSpace.xl,
          top: TnSpace.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + TnSpace.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                isExport ? s.t('ykgExport') : s.t('ykgImport'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: TnSpace.lg),
              // 风险提示（强制）：凭据链接 + 密码 = 可登录，勿公开分享。
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(TnSpace.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        color: context.cs.secondary,
                      ),
                      const SizedBox(width: TnSpace.md),
                      Expanded(
                        child: Text(
                          s.t('ykgRisk'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: TnSpace.lg),
              if (!isExport) ...<Widget>[
                TextField(
                  controller: _link,
                  decoration: InputDecoration(labelText: s.t('ykgPasteHint')),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: TnSpace.sm),
              ],
              TextField(
                controller: _pwd,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: s.t('ykgPassword'),
                  helperText: s.t('ykgPasswordHint'),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '显示密码' : '隐藏密码',
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: TnSpace.lg),
              FilledButton(
                onPressed: _busy ? null : (isExport ? _doExport : _doImport),
                child: _busy
                    ? const SizedBox(
                        width: TnSpace.lg,
                        height: TnSpace.lg,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isExport ? s.t('ykgCopy') : s.t('ykgImport')),
              ),
              if (_result.isNotEmpty) ...<Widget>[
                const SizedBox(height: TnSpace.sm),
                Text(_result, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
