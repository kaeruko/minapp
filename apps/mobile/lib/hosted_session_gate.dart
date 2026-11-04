import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'hosted_consumer_api.dart';

typedef HostedSignedInBuilder = Widget Function(
  BuildContext context,
  AuthenticatedSession session,
  Future<void> Function() logout,
);

typedef HostedRestoreErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  Future<void> Function() retry,
  Future<void> Function() forgetSavedLogin,
);

/// Owns the persistent-session state machine without imposing any edition UI.
class HostedSessionGate extends StatefulWidget {
  const HostedSessionGate({
    required this.api,
    required this.restoringBuilder,
    required this.restoreErrorBuilder,
    required this.signedOutBuilder,
    required this.signedInBuilder,
    super.key,
  });

  final HostedConsumerApi api;
  final WidgetBuilder restoringBuilder;
  final HostedRestoreErrorBuilder restoreErrorBuilder;
  final WidgetBuilder signedOutBuilder;
  final HostedSignedInBuilder signedInBuilder;

  @override
  State<HostedSessionGate> createState() => _HostedSessionGateState();
}

class _HostedSessionGateState extends State<HostedSessionGate> {
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
  void didUpdateWidget(covariant HostedSessionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api, widget.api)) {
      throw StateError(
        'HostedSessionGate does not support replacing its API at runtime.',
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
      setState(() {
        _restoreError = error;
        _restoring = false;
      });
    }
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (!mounted) return;
    setState(() {
      _session = null;
      _restoreError = null;
      _restoring = false;
    });
  }

  Future<void> _forgetSavedLogin() async {
    try {
      await _logout();
    } catch (error) {
      if (!mounted) return;
      setState(() => _restoreError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) return widget.restoringBuilder(context);

    final Object? restoreError = _restoreError;
    if (restoreError != null) {
      return widget.restoreErrorBuilder(
        context,
        restoreError,
        _restore,
        _forgetSavedLogin,
      );
    }

    final AuthenticatedSession? session = _session;
    if (session == null) return widget.signedOutBuilder(context);
    return widget.signedInBuilder(context, session, _logout);
  }
}
