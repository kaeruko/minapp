import 'package:flutter/material.dart';

typedef HostedAuthenticationLauncher = Future<void> Function(
  BuildContext context,
);

/// Common contract for the implicit guest mode used by hosted editions.
///
/// Guest-facing pages own their visual design. This scope owns the behavioral
/// boundary: opening authentication and explaining account-only actions.
class HostedGuestAccessScope extends InheritedWidget {
  const HostedGuestAccessScope({
    required this.onAuthenticationRequested,
    required super.child,
    super.key,
  });

  final HostedAuthenticationLauncher onAuthenticationRequested;

  static HostedGuestAccessScope of(BuildContext context) {
    final HostedGuestAccessScope? scope = context
        .dependOnInheritedWidgetOfExactType<HostedGuestAccessScope>();
    if (scope == null) {
      throw StateError(
        'Guest UI must be hosted inside HostedGuestAccessScope.',
      );
    }
    return scope;
  }

  static Future<void> openAuthentication(BuildContext context) {
    return of(context).onAuthenticationRequested(context);
  }

  static Future<void> requireAuthentication(
    BuildContext context, {
    required String feature,
  }) async {
    final HostedGuestAccessScope scope = of(context);
    final bool? continueToAuth = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('$featureには登録が必要です'),
        content: const Text(
          '登録前に遊んだ記録は、この端末にそのまま残ります。'
          '登録済みの場合はログインしてください。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('今はしない'),
          ),
          FilledButton(
            key: const Key('hosted-registration-continue'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('登録・ログインへ'),
          ),
        ],
      ),
    );
    if (continueToAuth != true || !context.mounted) return;
    await scope.onAuthenticationRequested(context);
  }

  @override
  bool updateShouldNotify(HostedGuestAccessScope oldWidget) =>
      oldWidget.onAuthenticationRequested != onAuthenticationRequested;
}
