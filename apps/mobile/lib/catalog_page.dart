import 'package:flutter/material.dart';

import 'api.dart';
import 'app_webview.dart';
import 'ui.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    required this.api,
    required this.session,
    required this.onLogout,
    super.key,
  });

  final MinAppApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  List<PublishedApp>? _apps;
  String? _error;
  bool _launching = false;

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
    if (_launching) return;
    setState(() {
      _launching = true;
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
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<PublishedApp>? apps = _apps;
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: <Widget>[
          const Center(child: PhaseBadge()),
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
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Text(
                'みんなのアプリ',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('参加しているグループで先生が承認した作品だけを表示します。'),
              const SizedBox(height: 22),
              if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
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
                    padding: EdgeInsets.all(20),
                    child: Text('まだ承認済みのアプリがありません。'),
                  ),
                )
              else
                for (final PublishedApp app in apps) ...<Widget>[
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: const CircleAvatar(
                        child: Icon(Icons.web_asset_outlined),
                      ),
                      title: Text(app.title),
                      subtitle: Text('${app.groupName} · 作者: ${app.ownerLoginId}'),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_launching,
                      onTap: () => _openApp(app),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.shield_outlined),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '作品にはログイン情報や端末機能を渡しません。外部サイトへの移動もWebViewで拒否します。',
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
