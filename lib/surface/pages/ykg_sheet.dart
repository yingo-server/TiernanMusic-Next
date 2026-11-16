// L7 surface/pages · YKG 链接登录弹层（导出 / 导入）
// 铁律：只画控件；能力经 bridge_session.appGraph.ykg；文案走 S.of(context).t。
// 设计权威：docs/YKG_LINK_CRYPTO_DESIGN.md
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../bridges/bridge_session.dart' show appGraph;
import '../design/tokens.dart';
import '../l10n/s.dart' show S;

enum _YkgMode { export, import }

/// 显示 YKG 弹层。entry=导出/导入。
Future<void> showYkgSheet(BuildContext context, _YkgMode mode) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Sp.bgElevated,
      isScrollControlled: true,
      builder: (_) => _YkgSheet(mode: mode),
    );

/// 便捷入口（供登录页调用，避免暴露内部枚举）。
Future<void> showYkgExport(BuildContext context) =>
    showYkgSheet(context, _YkgMode.export);
Future<void> showYkgImport(BuildContext context) =>
    showYkgSheet(context, _YkgMode.import);

class _YkgSheet extends StatefulWidget {
  const _YkgSheet({required this.mode});
  final _YkgMode mode;

  @override
  State<_YkgSheet> createState() => _YkgSheetState();
}

class _YkgSheetState extends State<_YkgSheet> {
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
    final logic = appGraph.ykg;
    if (logic == null || !logic.canExport) {
      _set(S.of(context).t('ykgNotLoggedIn'));
      return;
    }
    if (_pwd.text.isEmpty) {
      _set(S.of(context).t('ykgPasswordHint'));
      return;
    }
    setState(() => _busy = true);
    try {
      final link = await logic.exportLink(password: _pwd.text);
      if (link == null) {
        _set(S.of(context).t('ykgNotLoggedIn'));
        return;
      }
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        _link.text = link;
        _set(S.of(context).t('ykgCopied'));
      }
    } catch (e) {
      _set(S.of(context).t('errorGeneric'));
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
      _set(S.of(context).t('ykgInvalidLink'));
      return;
    }
    if (_pwd.text.isEmpty) {
      _set(S.of(context).t('ykgPasswordHint'));
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
        // 底层错误统一为「密码错/链接损坏」，按 i18n 文案展示，不直显底层串
        // （避免 oracle 与硬编码）。
        _set(s.t('ykgWrongPassword'));
      }
    } catch (e) {
      _set(S.of(context).t('ykgWrongPassword'));
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
    final isExport = widget.mode == _YkgMode.export;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Sp.gapL,
          right: Sp.gapL,
          top: Sp.gapM,
          bottom: MediaQuery.of(context).viewInsets.bottom + Sp.gapL,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                isExport ? s.t('ykgExport') : s.t('ykgImport'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Sp.gapM),
              // 风险提示（强制）：凭据链接 + 密码 = 可登录，勿公开分享。
              Container(
                padding: const EdgeInsets.all(Sp.gapM),
                decoration: BoxDecoration(
                  color: Sp.cardHigh,
                  borderRadius: BorderRadius.circular(Sp.rCard),
                ),
                child: Text(s.t('ykgRisk'), style: TextStyle(color: Sp.orange)),
              ),
              const SizedBox(height: Sp.gapM),
              if (!isExport) ...<Widget>[
                TextField(
                  controller: _link,
                  decoration: InputDecoration(labelText: s.t('ykgPasteHint')),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: Sp.gapS),
              ],
              TextField(
                controller: _pwd,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: s.t('ykgPassword'),
                  helperText: s.t('ykgPasswordHint'),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: Sp.gapM),
              FilledButton(
                onPressed: _busy ? null : (isExport ? _doExport : _doImport),
                child: Text(isExport ? s.t('ykgCopy') : s.t('ykgImport')),
              ),
              if (_result.isNotEmpty) ...<Widget>[
                const SizedBox(height: Sp.gapS),
                Text(_result, style: TextStyle(color: Sp.textSub)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
