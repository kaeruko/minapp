import 'package:flutter/material.dart';

import '../hosted_session_gate.dart';
import 'girls_app.dart';
import 'girls_errors.dart';
import 'girls_guest_home_page.dart';
import 'girls_home_shop_shell.dart';
import 'hosted_girls_api.dart';

const Color _lavender = Color(0xFFB39DDB);
const Color _lavenderDark = Color(0xFF745B9E);
const Color _text = Color(0xFF5D4037);

/// Girls presentation around the shared hosted session state machine.
class GirlsPersistentApp extends StatelessWidget {
  GirlsPersistentApp({required this.api, super.key});

  final HostedGirlsApi api;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return HostedSessionGate(
      api: api,
      authenticationLauncher: (BuildContext context) {
        return Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => GirlsAuthPage(
              api: api,
              canCancel: true,
              onAuthenticated: (_) {},
            ),
          ),
        );
      },
      restoringBuilder: (_) => _authenticatedMaterialApp(
        home: const _RestoreProgressPage(),
      ),
      restoreErrorBuilder: (_, Object error, retry, forgetSavedLogin) =>
          _authenticatedMaterialApp(
        home: _RestoreErrorPage(
          message: girlsMessageFor(error),
          onRetry: () {
            retry();
          },
          onForgetSavedLogin: () {
            forgetSavedLogin();
          },
        ),
      ),
      guestBuilder: (_) => _authenticatedMaterialApp(
        home: GirlsGuestHomePage(api: api),
      ),
      signedInBuilder: (_, session, logout) => _authenticatedMaterialApp(
        home: GirlsHomeShopShell(
          api: api,
          session: session,
          onLogout: () async {
            try {
              await logout();
            } catch (error) {
              _scaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(
                  content: Text(
                    'ログアウトできませんでした。${girlsMessageFor(error)}',
                  ),
                ),
              );
            }
          },
        ),
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
