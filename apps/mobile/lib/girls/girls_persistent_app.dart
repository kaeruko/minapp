import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'girls_app.dart';
import 'girls_app_core.dart' as core;
import 'girls_home_page.dart';
import 'hosted_girls_api.dart';

const Color _lavender = Color(0xFFB39DDB);
const Color _lavenderDark = Color(0xFF745B9E);
const Color _text = Color(0xFF5D4037);

/// Launch wrapper that restores the Girls refresh token before showing auth.
///
/// The existing [GirlsApp] remains the login/registration UI. Successful
/// authentication is announced by [HostedGirlsApi], which lets this wrapper
/// switch to the authenticated home without duplicating the auth screens.
class GirlsPersistentApp extends StatefulWidget {
  const GirlsPersistentApp({required this.api, super.key});

  final HostedGirlsApi api;

  @override
  State<GirlsPersistentApp> createState() => _GirlsPersistentAppState();
}

class _GirlsPersistentAppState extends State<GirlsPersistentApp> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<AuthenticatedSession>? _authenticatedSubscription;
  AuthenticatedSession? _session;
  bool _restoring = true;
  Object? _restoreError;

  @override
  void initState() {
    super.initState();
    _authenticatedSubscription = widget.api.authenticatedSessions.listen(
      (AuthenticatedSession session) {
        if (!mounted) return;
        setState(() {
          _session = session;
          _restoring = false;
          _restoreError = null;
        });
      },
    );
    _restore();
  }

  @override
  void didUpdateWidget(covariant GirlsPersistentApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api, widget.api)) {
      throw StateError(
        'GirlsPersistentApp does not support replacing HostedGirlsApi at runtime.',
      );
    }
  }

  @override
  void dispose() {
    _authenticatedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _restoreError = null;
    });
    try {
      final AuthenticatedSession? session = await widget.api.restoreSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _restoring = false;
      });
    } catch (error) {
      if (!mounted) return;
      // Keep the saved credential. Network/server/format/storage errors are not
      // equivalent to an expired refresh token and must not silently log out.
      setState(() {
        _restoreError = error;
        _restoring = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (error) {
      if (!mounted) return;
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('ログアウトできませんでした。${core.girlsMessageFor(error)}'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _session = null;
      _restoreError = null;
      _restoring = false;
    });
  }

  Future<void> _forgetSavedLogin() async {
    try {
      await widget.api.logout();
    } catch (error) {
      if (!mounted) return;
      setState(() => _restoreError = error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _session = null;
      _restoreError = null;
      _restoring = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return _authenticatedMaterialApp(
        home: const _RestoreProgressPage(),
      );
    }

    final Object? restoreError = _restoreError;
    if (restoreError != null) {
      return _authenticatedMaterialApp(
        home: _RestoreErrorPage(
          message: core.girlsMessageFor(restoreError),
          onRetry: _restore,
          onForgetSavedLogin: _forgetSavedLogin,
        ),
      );
    }

    final AuthenticatedSession? session = _session;
    if (session == null) {
      return GirlsApp(api: widget.api);
    }

    return _authenticatedMaterialApp(
      home: GirlsHomePage(
        api: widget.api,
        session: session,
        onLogout: () {
          _logout();
        },
      ),
    );
  }

  MaterialApp _authenticatedMaterialApp({required Widget home}) {
    return MaterialApp(
      title: 'みんアプ Girls',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _lavender,
          primary: _lavenderDark,
          secondary: const Color(0xFFE987A8),
          surface: const Color(0xFFFFFBFD),
        ),
        scaffoldBackgroundColor: const Color(0xFFFDF9EE),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: _text,
              displayColor: _text,
            ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: .82),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7DDF2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7DDF2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _lavender, width: 2),
          ),
        ),
      ),
      home: home,
    );
  }
}

class _RestoreProgressPage extends StatelessWidget {
  const _RestoreProgressPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 34,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _RestoreErrorPage extends StatelessWidget {
  const _RestoreErrorPage({
    required this.message,
    required this.onRetry,
    required this.onForgetSavedLogin,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onForgetSavedLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: _lavenderDark,
                    size: 44,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ログイン情報を更新できませんでした',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF8C7893)),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('もう一度'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onForgetSavedLogin,
                    child: const Text('保存したログイン情報を消してログインし直す'),
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
