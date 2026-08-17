import 'package:flutter/material.dart';

import 'api.dart';
import 'catalog_page.dart';
import 'login_page.dart';

class MinApp extends StatelessWidget {
  const MinApp({required this.api, super.key});

  final MinAppApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3767C8)),
        useMaterial3: true,
      ),
      home: _SessionRoot(api: api),
    );
  }
}

class _SessionRoot extends StatefulWidget {
  const _SessionRoot({required this.api});

  final MinAppApi api;

  @override
  State<_SessionRoot> createState() => _SessionRootState();
}

class _SessionRootState extends State<_SessionRoot> {
  AuthenticatedSession? _session;

  @override
  Widget build(BuildContext context) {
    final AuthenticatedSession? session = _session;
    if (session == null) {
      return LoginPage(
        api: widget.api,
        onAuthenticated: (AuthenticatedSession value) {
          setState(() => _session = value);
        },
      );
    }
    return CatalogPage(
      api: widget.api,
      session: session,
      onLogout: () => setState(() => _session = null),
    );
  }
}
