import 'package:flutter/material.dart';

import 'api.dart';
import 'app_webview.dart';
import 'ui.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    required this.api,
    required this.session,
    required this.classroomName,
    required this.onChangeClassroom,
    required this.onLogout,
    super.key,
  });

  final MinAppApi api;
  final AuthenticatedSession session;
  final String classroomName;
  final Future<void> Function() onChangeClassroom;
  final VoidCallback onLogout;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  List<PublishedApp>? _apps;
  String? _error;
  String? _launchingAppId;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _error = null);
    try {
      final List<PublishedApp> apps = await widget.api.listPublishedApps(
        widget.session.accessToken,
      );
      if (mounted) setState(() => _apps = apps);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        widget.onLogout();
        return;
      }
      setState(() => _error = messageFor(error));
    }
  }

  Future<void> _openApp(PublishedApp app) async {
    if (_launchingAppId != null) return;
    setState(() {
      _launchingAppId = app.appId;
      _error = null;
    });
    try {
      final LaunchGrant grant = await widget.api.createLaunch(
        widget.session.accessToken,
        app,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => AppWebViewPage(
            title: app.title,
            launchUrl: grant.url,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        widget.onLogout();
        return;
      }
      setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _launchingAppId = null);
    }
  }

  Future<void> _confirmChangeClassroom() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('教室を変更しますか？'),
        content: const Text('ログアウトして、この端末の教室設定と作品のWebViewデータを消します。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirm-change-classroom'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('変更する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onChangeClassroom();
  }

  String _dateLabel(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.month}/${local.day} 更新';
  }

  @override
  Widget build(BuildContext context) {
    final List<PublishedApp>? apps = _apps;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: <Widget>[
          const Center(child: PhaseBadge()),
          IconButton(
            key: const Key('catalog-change-classroom'),
            tooltip: '教室を変更',
            onPressed: _confirmChangeClassroom,
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            tooltip: 'ログアウト',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadApps,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'みんなのアプリ',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text('${widget.classroomName} · 先生が承認した最新版だけがここに並びます。'),
                      ],
                    ),
                  ),
                  if (apps != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${apps.length}個'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null) ...<Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.error_outline, color: colors.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (apps == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(36),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (apps.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Column(
                      children: <Widget>[
                        Icon(Icons.web_asset_off_outlined, size: 36),
                        SizedBox(height: 10),
                        Text('まだ承認済みのアプリがありません。'),
                        SizedBox(height: 4),
                        Text('Webポータルから公開申請して、先生に承認してもらってね。'),
                      ],
                    ),
                  ),
                )
              else
                for (final PublishedApp app in apps) ...<Widget>[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _launchingAppId == null ? () => _openApp(app) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: colors.primaryContainer,
                              foregroundColor: colors.onPrimaryContainer,
                              child: const Icon(Icons.web_asset_outlined),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    app.title,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 7,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: <Widget>[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.secondaryContainer,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          app.groupName,
                                          style: TextStyle(
                                            color: colors.onSecondaryContainer,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '作者: ${app.ownerLoginId}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      Text(
                                        _dateLabel(app.reviewedAt),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_launchingAppId == app.appId)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            else
                              const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.shield_outlined, color: colors.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '作品にはログイン情報・カメラ・位置情報・マイクを渡しません。外部サイトへの移動も拒否します。',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
