import 'package:flutter/material.dart';

import 'api.dart';
import 'app_visual.dart';
import 'app_webview.dart';
import 'ugc_safety.dart';
import 'ui.dart';

const Color _brandBlue = Color(0xFF2563EB);
const Color _brandDark = Color(0xFF1E3A8A);
const Color _brandLight = Color(0xFFEFF6FF);

class AppDetailPage extends StatefulWidget {
  const AppDetailPage({
    required this.api,
    required this.session,
    required this.app,
    required this.onHideCreator,
    required this.onLogout,
    super.key,
  });

  final MinAppApi api;
  final AuthenticatedSession session;
  final PublishedApp app;
  final Future<void> Function(PublishedApp app) onHideCreator;
  final VoidCallback onLogout;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  bool _launching = false;
  bool _safetyBusy = false;
  String? _error;

  Future<void> _launch() async {
    if (_launching) return;
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      final LaunchGrant grant = await widget.api.createLaunch(
        widget.session.accessToken,
        widget.app,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => AppWebViewPage(
            title: widget.app.title,
            launchUrl: grant.url,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        widget.onLogout();
        Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
        return;
      }
      setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _reportApp() async {
    if (_safetyBusy) return;
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('この作品を報告'),
        children: <Widget>[
          for (final String reason in <String>[
            '不適切な表現・内容',
            '嫌がらせ・いじめ',
            '個人情報が含まれている',
            '危険な内容',
            'その他',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(reason),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(reason),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('キャンセル'),
            ),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    setState(() {
      _safetyBusy = true;
      _error = null;
    });
    try {
      await openAppReportEmail(app: widget.app, reason: reason);
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _safetyBusy = false);
    }
  }

  Future<void> _hideCreator() async {
    if (_safetyBusy) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('この作成者の作品を非表示'),
        content: Text(
          '「${widget.app.ownerLoginId}」さんの作品を、この端末の一覧から非表示にしますか？\n'
          'あとでメニューから再表示できます。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirm-hide-creator'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('非表示にする'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _safetyBusy = true;
      _error = null;
    });
    try {
      await widget.onHideCreator(widget.app);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _safetyBusy = false);
    }
  }

  String _dateLabel(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year}年${local.month}月${local.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final PublishedApp app = widget.app;
    final AppVisual visual = appVisualFor(app);
    final String? description = app.description;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 92,
        leading: TextButton.icon(
          key: const Key('app-detail-back'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          label: const Text(
            '戻る',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: visual.backgroundColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: visual.borderColor, width: 4),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        visual.icon,
                        size: 58,
                        color: visual.foregroundColor,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      app.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _brandDark,
                        fontSize: 30,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.account_circle_rounded,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              '作成者：${app.ownerLoginId}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: _brandLight,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                                color: _brandBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                description == null ? 'アプリの情報' : 'アプリの説明',
                                style: const TextStyle(
                                  color: _brandBlue,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            description ??
                                '「${app.title}」は ${app.groupName} で公開されているアプリです。'
                                    '${_dateLabel(app.reviewedAt)}に先生の承認を受けた最新版です。',
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 16,
                              height: 1.65,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              Icon(
                                Icons.shield_outlined,
                                color: Color(0xFFB45309),
                              ),
                              SizedBox(width: 8),
                              Text(
                                '安全に使うために',
                                style: TextStyle(
                                  color: Color(0xFF92400E),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '不適切な作品は運営へ報告できます。見たくない作成者の作品はこの端末で非表示にできます。',
                            style: TextStyle(
                              color: Color(0xFF78350F),
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            key: const Key('app-detail-report'),
                            onPressed: _safetyBusy ? null : _reportApp,
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('この作品を報告'),
                          ),
                          TextButton.icon(
                            key: const Key('app-detail-hide-creator'),
                            onPressed: _safetyBusy ? null : _hideCreator,
                            icon: const Icon(Icons.visibility_off_outlined),
                            label: const Text('この作成者の作品を非表示'),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFF1F5F9)),
                ),
              ),
              child: SizedBox(
                height: 62,
                child: FilledButton.icon(
                  key: const Key('app-detail-launch'),
                  onPressed: _launching || _safetyBusy ? null : _launch,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF93C5FD),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  icon: _launching
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_circle_outline_rounded, size: 27),
                  label: Text(_launching ? '開いています…' : 'このアプリを開く'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
