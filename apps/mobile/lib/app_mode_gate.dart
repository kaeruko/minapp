import 'package:flutter/material.dart';

import 'app_mode_store.dart';
import 'directory.dart';
import 'hosted_api.dart';
import 'hosted_app.dart';
import 'session_app.dart';
import 'tenant_store.dart';
import 'ugc_safety.dart';

typedef HostedBaseUriLoader = Future<Uri> Function();
typedef MinAppDirectoryLoader = Future<MinAppDirectory> Function();

class MinAppModeGate extends StatefulWidget {
  const MinAppModeGate({
    required this.modeStore,
    required this.hostedBaseUriLoader,
    required this.directoryLoader,
    required this.tenantStore,
    required this.apiFactory,
    this.officialJoinBaseUri,
    this.creatorPortalBaseUri,
    this.webViewDataClearer,
    this.creatorSafetyStore,
    super.key,
  });

  final MinAppLaunchModeStore modeStore;
  final HostedBaseUriLoader hostedBaseUriLoader;
  final MinAppDirectoryLoader directoryLoader;
  final TenantStore tenantStore;
  final MinAppApiFactory apiFactory;
  final Uri? officialJoinBaseUri;
  final Uri? creatorPortalBaseUri;
  final WebViewDataClearer? webViewDataClearer;
  final CreatorSafetyStore? creatorSafetyStore;

  @override
  State<MinAppModeGate> createState() => _MinAppModeGateState();
}

class _MinAppModeGateState extends State<MinAppModeGate> {
  MinAppLaunchMode? _mode;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MinAppLaunchMode? mode = await widget.modeStore.load();
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectMode(MinAppLaunchMode mode) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.modeStore.save(mode);
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _clearMode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final WebViewDataClearer? clearer = widget.webViewDataClearer;
      if (clearer != null) await clearer();
      await widget.modeStore.clear();
      if (!mounted) return;
      setState(() {
        _mode = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _ModeErrorPage(error: _error!, onRetry: _loadMode),
      );
    }

    switch (_mode) {
      case MinAppLaunchMode.classroom:
        return _ClassroomModeLoader(
          loader: widget.directoryLoader,
          tenantStore: widget.tenantStore,
          apiFactory: widget.apiFactory,
          officialJoinBaseUri: widget.officialJoinBaseUri,
          creatorPortalBaseUri: widget.creatorPortalBaseUri,
          webViewDataClearer: widget.webViewDataClearer,
          creatorSafetyStore: widget.creatorSafetyStore,
          onChangeMode: _clearMode,
        );
      case MinAppLaunchMode.hosted:
        return _HostedModeLoader(
          loader: widget.hostedBaseUriLoader,
          onChangeMode: _clearMode,
        );
      case null:
        return MaterialApp(
          title: 'みんアプ',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
            useMaterial3: true,
          ),
          home: _ModeSelectionPage(onSelected: _selectMode),
        );
    }
  }
}

class _ClassroomModeLoader extends StatefulWidget {
  const _ClassroomModeLoader({
    required this.loader,
    required this.tenantStore,
    required this.apiFactory,
    required this.officialJoinBaseUri,
    required this.creatorPortalBaseUri,
    required this.webViewDataClearer,
    required this.creatorSafetyStore,
    required this.onChangeMode,
  });

  final MinAppDirectoryLoader loader;
  final TenantStore tenantStore;
  final MinAppApiFactory apiFactory;
  final Uri? officialJoinBaseUri;
  final Uri? creatorPortalBaseUri;
  final WebViewDataClearer? webViewDataClearer;
  final CreatorSafetyStore? creatorSafetyStore;
  final Future<void> Function() onChangeMode;

  @override
  State<_ClassroomModeLoader> createState() => _ClassroomModeLoaderState();
}

class _ClassroomModeLoaderState extends State<_ClassroomModeLoader> {
  MinAppDirectory? _directory;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MinAppDirectory directory = await widget.loader();
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingApp();
    final Object? error = _error;
    if (error != null) {
      return _ModeDependencyErrorApp(
        title: '教室Directoryを確認できません',
        error: error,
        onRetry: _load,
        onChangeMode: widget.onChangeMode,
      );
    }
    final MinAppDirectory? directory = _directory;
    if (directory == null) {
      throw StateError('Classroom Directory loader completed without a client.');
    }
    return MinApp(
      directory: directory,
      tenantStore: widget.tenantStore,
      apiFactory: widget.apiFactory,
      officialJoinBaseUri: widget.officialJoinBaseUri,
      creatorPortalBaseUri: widget.creatorPortalBaseUri,
      webViewDataClearer: widget.webViewDataClearer,
      creatorSafetyStore: widget.creatorSafetyStore,
      onChangeMode: widget.onChangeMode,
    );
  }
}

class _HostedModeLoader extends StatefulWidget {
  const _HostedModeLoader({required this.loader, required this.onChangeMode});

  final HostedBaseUriLoader loader;
  final Future<void> Function() onChangeMode;

  @override
  State<_HostedModeLoader> createState() => _HostedModeLoaderState();
}

class _HostedModeLoaderState extends State<_HostedModeLoader> {
  Uri? _baseUri;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Uri baseUri = await widget.loader();
      if (!mounted) return;
      setState(() {
        _baseUri = baseUri;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingApp();
    final Object? error = _error;
    if (error != null) {
      return _ModeDependencyErrorApp(
        title: 'Hosted環境を確認できません',
        error: error,
        onRetry: _load,
        onChangeMode: widget.onChangeMode,
      );
    }
    final Uri? baseUri = _baseUri;
    if (baseUri == null) {
      throw StateError('Hosted endpoint loader completed without a base URI.');
    }
    return HostedApp(
      api: HostedApi(baseUri: baseUri),
      onChangeMode: widget.onChangeMode,
    );
  }
}

class _LoadingApp extends StatelessWidget {
  const _LoadingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class _ModeDependencyErrorApp extends StatelessWidget {
  const _ModeDependencyErrorApp({
    required this.title,
    required this.error,
    required this.onRetry,
    required this.onChangeMode,
  });

  final String title;
  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onChangeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('みんアプ')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.cloud_off_rounded, size: 48),
                  const SizedBox(height: 12),
                  Text(title),
                  const SizedBox(height: 8),
                  SelectableText(error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: onRetry, child: const Text('もう一度確認')),
                  TextButton(
                    onPressed: onChangeMode,
                    child: const Text('利用方法を切り替える'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSelectionPage extends StatelessWidget {
  const _ModeSelectionPage({required this.onSelected});

  final Future<void> Function(MinAppLaunchMode mode) onSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('みんアプ')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.apps_rounded,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'どうやってはじめる？',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: ListTile(
                      key: const Key('mode-hosted'),
                      leading: const Icon(Icons.person_rounded),
                      title: const Text('自分ではじめる'),
                      subtitle: const Text('アカウントを作って、友達とグループでアプリを使う'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => onSelected(MinAppLaunchMode.hosted),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      key: const Key('mode-classroom'),
                      leading: const Icon(Icons.school_rounded),
                      title: const Text('教室に参加する'),
                      subtitle: const Text('先生からもらった教室コードを使う'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => onSelected(MinAppLaunchMode.classroom),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeErrorPage extends StatelessWidget {
  const _ModeErrorPage({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('みんアプ')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: 12),
              SelectableText(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('もう一度確認')),
            ],
          ),
        ),
      ),
    );
  }
}
