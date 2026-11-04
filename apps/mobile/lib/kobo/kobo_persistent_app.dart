import 'package:flutter/material.dart';

import '../hosted_consumer_errors.dart';
import '../hosted_session_gate.dart';
import 'hosted_kobo_api.dart';
import 'kobo_auth_page.dart';
import 'kobo_shell.dart';
import 'kobo_theme.dart';

class KoboPersistentApp extends StatelessWidget {
  KoboPersistentApp({required this.api, super.key});

  final HostedKoboApi api;

  @override
  Widget build(BuildContext context) {
    return HostedSessionGate(
      api: api,
      authenticationLauncher: (BuildContext context) {
        return Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext authContext) => KoboAuthPage(
              api: api,
              onAuthenticated: (_) => Navigator.of(authContext).pop(),
            ),
          ),
        );
      },
      restoringBuilder: (_) => _materialApp(
        home: const _KoboRestoreProgressPage(),
      ),
      restoreErrorBuilder: (_, Object error, retry, forgetSavedLogin) =>
          _materialApp(
        home: _KoboRestoreErrorPage(
          message: hostedConsumerMessageFor(error),
          onRetry: retry,
          onForgetSavedLogin: forgetSavedLogin,
        ),
      ),
      guestBuilder: (_) => _materialApp(
        home: KoboShell(api: api, session: null, onLogout: null),
      ),
      signedInBuilder: (_, session, logout) => _materialApp(
        home: KoboShell(api: api, session: session, onLogout: logout),
      ),
    );
  }

  MaterialApp _materialApp({required Widget home}) {
    return MaterialApp(
      title: 'みんアプ工房',
      debugShowCheckedModeBanner: false,
      theme: KoboTheme.light(),
      home: home,
    );
  }
}

class _KoboRestoreProgressPage extends StatelessWidget {
  const _KoboRestoreProgressPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _KoboRestoreErrorPage extends StatelessWidget {
  const _KoboRestoreErrorPage({
    required this.message,
    required this.onRetry,
    required this.onForgetSavedLogin,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onForgetSavedLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('みんアプ工房')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(KoboSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: KoboColors.navy,
                ),
                const SizedBox(height: KoboSpacing.md),
                const Text(
                  'ログイン情報を更新できませんでした',
                  textAlign: TextAlign.center,
                  style: KoboTextStyles.sectionTitle,
                ),
                const SizedBox(height: KoboSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: KoboTextStyles.body,
                ),
                const SizedBox(height: KoboSpacing.lg),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('もう一度試す'),
                ),
                TextButton(
                  onPressed: onForgetSavedLogin,
                  child: const Text('保存したログイン情報を消す'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
