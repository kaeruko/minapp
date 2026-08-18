import 'package:flutter/material.dart';

import 'api.dart';
import 'app_visual.dart';
import 'app_webview.dart';
import 'ui.dart';

const Color _brandBlue = Color(0xFF2563EB);
const Color _brandDark = Color(0xFF1E3A8A);
const Color _brandLight = Color(0xFFEFF6FF);

class AppDetailPage extends StatefulWidget {
  const AppDetailPage({
    required this.api,
    required this.session,
    required this.app,
    required this.onLogout,
    super.key,
  });

  final MinAppApi api;
  final AuthenticatedSession session;
  final PublishedApp app;
  final VoidCallback onLogout;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  bool _launching = false;
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

  String _dateLabel(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year}年${local.month}月${local.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final PublishedApp app = widget.app;
    final AppVisual visual = appVisualFor(app);
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
                          const Row(
                            children: <Widget>[
                              Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                                color: _brandBlue,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'アプリの情報',
                                style: TextStyle(
                                  color: _brandBlue,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
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
                  onPressed: _launching ? null : _launch,
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
