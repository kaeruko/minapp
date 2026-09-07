import 'package:flutter/material.dart';

import 'api.dart';
import 'hosted_api.dart';
import 'hosted_app.dart';
import 'hosted_my_apps_page.dart';

class HostedNormalApp extends StatelessWidget {
  const HostedNormalApp({
    required this.api,
    required this.onChangeMode,
    super.key,
  });

  final HostedPlatformApi api;
  final Future<void> Function() onChangeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
      ),
      home: _HostedNormalSessionRoot(
        api: api,
        onChangeMode: onChangeMode,
      ),
    );
  }
}

class _HostedNormalSessionRoot extends StatefulWidget {
  const _HostedNormalSessionRoot({
    required this.api,
    required this.onChangeMode,
  });

  final HostedPlatformApi api;
  final Future<void> Function() onChangeMode;

  @override
  State<_HostedNormalSessionRoot> createState() =>
      _HostedNormalSessionRootState();
}

class _HostedNormalSessionRootState extends State<_HostedNormalSessionRoot> {
  AuthenticatedSession? _session;

  @override
  Widget build(BuildContext context) {
    final AuthenticatedSession? session = _session;
    if (session == null) {
      return HostedAuthPage(
        api: widget.api,
        onAuthenticated: (AuthenticatedSession value) {
          setState(() => _session = value);
        },
        onChangeMode: widget.onChangeMode,
      );
    }

    return _HostedNormalAuthenticatedHome(
      api: widget.api,
      session: session,
      onLogout: () => setState(() => _session = null),
      onChangeMode: widget.onChangeMode,
    );
  }
}

class _HostedNormalAuthenticatedHome extends StatelessWidget {
  const _HostedNormalAuthenticatedHome({
    required this.api,
    required this.session,
    required this.onLogout,
    required this.onChangeMode,
  });

  final HostedPlatformApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;
  final Future<void> Function() onChangeMode;

  Future<void> _openMyApps(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedMyAppsPage(
          baseUri: api.baseUri,
          session: session,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        HostedHomePage(
          api: api,
          session: session,
          onLogout: onLogout,
          onChangeMode: onChangeMode,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: FloatingActionButton.extended(
              key: const Key('hosted-my-apps-open'),
              onPressed: () => _openMyApps(context),
              icon: const Icon(Icons.manage_accounts_rounded),
              label: const Text('自分のアプリ'),
            ),
          ),
        ),
      ],
    );
  }
}
