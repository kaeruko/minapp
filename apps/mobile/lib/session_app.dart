import 'package:flutter/material.dart';

import 'api.dart';
import 'app_webview.dart';
import 'catalog_page.dart';
import 'classroom_setup_page.dart';
import 'directory.dart';
import 'login_page.dart';
import 'tenant_store.dart';
import 'ui.dart';

typedef MinAppApiFactory = MinAppApi Function(Uri baseUri);
typedef WebViewDataClearer = Future<void> Function();

class MinApp extends StatelessWidget {
  const MinApp({
    required this.directory,
    required this.tenantStore,
    required this.apiFactory,
    this.officialJoinBaseUri,
    this.webViewDataClearer,
    super.key,
  });

  final MinAppDirectory directory;
  final TenantStore tenantStore;
  final MinAppApiFactory apiFactory;
  final Uri? officialJoinBaseUri;
  final WebViewDataClearer? webViewDataClearer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3767C8)),
        useMaterial3: true,
      ),
      home: _SessionRoot(
        directory: directory,
        tenantStore: tenantStore,
        apiFactory: apiFactory,
        officialJoinBaseUri: officialJoinBaseUri,
        webViewDataClearer: webViewDataClearer ?? clearMinAppWebViewData,
      ),
    );
  }
}

class _SessionRoot extends StatefulWidget {
  const _SessionRoot({
    required this.directory,
    required this.tenantStore,
    required this.apiFactory,
    required this.officialJoinBaseUri,
    required this.webViewDataClearer,
  });

  final MinAppDirectory directory;
  final TenantStore tenantStore;
  final MinAppApiFactory apiFactory;
  final Uri? officialJoinBaseUri;
  final WebViewDataClearer webViewDataClearer;

  @override
  State<_SessionRoot> createState() => _SessionRootState();
}

class _SessionRootState extends State<_SessionRoot> {
  ConfiguredTenant? _tenant;
  MinAppApi? _api;
  AuthenticatedSession? _session;
  Object? _bootError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTenant();
  }

  Future<void> _loadTenant() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _bootError = null;
      });
    }
    try {
      final ConfiguredTenant? stored = await widget.tenantStore.load();
      ConfiguredTenant? configured = stored;
      if (stored != null && stored.isExpiredAt(DateTime.now().toUtc())) {
        final TenantDescriptor descriptor = await widget.directory.refreshTenant(
          stored.tenantId,
        );
        if (descriptor.configRevision < stored.configRevision) {
          throw const FormatException(
            'Directory config_revision moved backwards.',
          );
        }
        await widget.directory.verifyTenantEndpoint(descriptor);
        configured = ConfiguredTenant.fromVerifiedDescriptor(
          descriptor,
          verifiedAt: DateTime.now().toUtc(),
        );
        await widget.tenantStore.save(configured);
      }
      if (!mounted) return;
      setState(() {
        _tenant = configured;
        _api = configured == null
            ? null
            : widget.apiFactory(configured.apiBaseUrl);
        _session = null;
        _loading = false;
        _bootError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tenant = null;
        _api = null;
        _session = null;
        _loading = false;
        _bootError = error;
      });
    }
  }

  void _onConfigured(ConfiguredTenant tenant) {
    setState(() {
      _tenant = tenant;
      _api = widget.apiFactory(tenant.apiBaseUrl);
      _session = null;
      _bootError = null;
    });
  }

  void _logout() {
    setState(() => _session = null);
  }

  Future<void> _changeClassroom() async {
    setState(() {
      _loading = true;
      _bootError = null;
      _session = null;
    });
    try {
      await widget.webViewDataClearer();
      await widget.tenantStore.clear();
      if (!mounted) return;
      setState(() {
        _tenant = null;
        _api = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _bootError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final Object? bootError = _bootError;
    if (bootError != null) {
      return _TenantBootErrorPage(
        error: bootError,
        onRetry: _loadTenant,
        onReset: _changeClassroom,
      );
    }

    final ConfiguredTenant? tenant = _tenant;
    if (tenant == null) {
      return ClassroomSetupPage(
        directory: widget.directory,
        tenantStore: widget.tenantStore,
        officialJoinBaseUri: widget.officialJoinBaseUri,
        onConfigured: _onConfigured,
      );
    }

    final MinAppApi? api = _api;
    if (api == null) {
      throw StateError('Configured tenant has no API client.');
    }

    final AuthenticatedSession? session = _session;
    if (session == null) {
      return LoginPage(
        api: api,
        classroomName: tenant.displayName,
        onChangeClassroom: _changeClassroom,
        onAuthenticated: (AuthenticatedSession value) {
          setState(() => _session = value);
        },
      );
    }
    return CatalogPage(
      api: api,
      session: session,
      classroomName: tenant.displayName,
      onChangeClassroom: _changeClassroom,
      onLogout: _logout,
    );
  }
}

class _TenantBootErrorPage extends StatelessWidget {
  const _TenantBootErrorPage({
    required this.error,
    required this.onRetry,
    required this.onReset,
  });

  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: PhaseBadge()),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(Icons.error_outline, size: 42, color: colors.error),
                      const SizedBox(height: 12),
                      Text(
                        '教室設定を確認できません',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(messageFor(error), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const Key('tenant-retry'),
                        onPressed: onRetry,
                        child: const Text('もう一度確認'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('tenant-reset'),
                        onPressed: onReset,
                        child: const Text('教室設定をやり直す'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
