import 'dart:async';

import 'package:http/http.dart' as http;

import '../api.dart';
import '../hosted_api.dart';
import '../hosted_runtime_bridge.dart';
import '../refreshable_auth_client.dart';
import 'girls_session_store.dart';

export '../hosted_api.dart';

/// Girls presentation compatibility wrapper.
///
/// Hosted protocol, validation, groups, apps and Runtime behavior live in the
/// neutral [HostedApi]. Girls must not fork the platform contract.
class HostedGirlsApi {
  factory HostedGirlsApi({
    required Uri baseUri,
    http.Client? client,
    GirlsSessionStore? sessionStore,
  }) {
    final http.Client resolvedClient = client ?? http.Client();
    return HostedGirlsApi._(
      delegate: HostedApi(baseUri: baseUri, client: resolvedClient),
      authClient: RefreshableAuthClient(
        baseUri: baseUri,
        client: resolvedClient,
      ),
      sessionStore: sessionStore ?? SecureGirlsSessionStore(),
    );
  }

  HostedGirlsApi._({
    required HostedApi delegate,
    required RefreshableAuthClient authClient,
    required GirlsSessionStore sessionStore,
  })  : _delegate = delegate,
        _authClient = authClient,
        _sessionStore = sessionStore;

  final HostedApi _delegate;
  final RefreshableAuthClient _authClient;
  final GirlsSessionStore _sessionStore;
  final StreamController<AuthenticatedSession> _authenticatedSessions =
      StreamController<AuthenticatedSession>.broadcast(sync: true);

  Uri get baseUri => _delegate.baseUri;
  HostedApiClient get runtimeClient => _delegate.runtimeClient;
  Stream<AuthenticatedSession> get authenticatedSessions =>
      _authenticatedSessions.stream;

  Future<AuthResult> login(String loginId, String password) async {
    final RefreshableAuthResult result = await _authClient.login(
      loginId,
      password,
    );
    if (result is RefreshablePasswordChallenge) {
      return result.toChallenge();
    }
    if (result is! RefreshableAuthenticatedResult) {
      throw StateError('Refreshable auth client returned an unknown result.');
    }

    // Persist before reporting authentication success. If secure storage fails,
    // the login fails visibly instead of creating a session that cannot resume.
    await _sessionStore.writeRefreshToken(result.refreshToken);
    final AuthenticatedSession session = result.toSession();
    _authenticatedSessions.add(session);
    return session;
  }

  Future<AuthenticatedSession?> restoreSession() async {
    final String? refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      final RefreshableAuthenticatedResult result =
          await _authClient.refresh(refreshToken);
      return result.toSession();
    } on ApiException catch (error) {
      if (error.statusCode == 401 && error.code == 'invalid_refresh_token') {
        // The server has explicitly declared this credential invalid. This is
        // the only restore failure that automatically removes the saved token.
        await _sessionStore.clearRefreshToken();
        return null;
      }
      rethrow;
    }
  }

  Future<void> logout() => _sessionStore.clearRefreshToken();

  Future<HostedLegalBundle> fetchLegal() => _delegate.fetchLegal();

  Future<HostedRegistrationResult> register({
    required String loginId,
    required String password,
    required HostedLegalBundle legal,
  }) {
    return _delegate.register(
      loginId: loginId,
      password: password,
      legal: legal,
    );
  }

  Future<HostedRecoveryResult> recover({
    required String loginId,
    required String recoveryCode,
    required String newPassword,
  }) {
    return _delegate.recover(
      loginId: loginId,
      recoveryCode: recoveryCode,
      newPassword: newPassword,
    );
  }

  Future<HostedEmailStatus> fetchEmailStatus(String accessToken) {
    return _delegate.fetchEmailStatus(accessToken);
  }

  Future<HostedEmailLinkResult> requestEmailLink({
    required String accessToken,
    required String email,
  }) {
    return _delegate.requestEmailLink(
      accessToken: accessToken,
      email: email,
    );
  }

  Future<HostedEmailStatus> verifyEmailLink({
    required String accessToken,
    required String code,
  }) {
    return _delegate.verifyEmailLink(accessToken: accessToken, code: code);
  }

  Future<List<HostedGroup>> listGroups(String accessToken) {
    return _delegate.listGroups(accessToken);
  }

  Future<HostedGroup> createGroup({
    required String accessToken,
    required String name,
  }) {
    return _delegate.createGroup(accessToken: accessToken, name: name);
  }

  Future<HostedGroup> joinGroup({
    required String accessToken,
    required String code,
  }) {
    return _delegate.joinGroup(accessToken: accessToken, code: code);
  }

  Future<List<HostedMember>> listMembers({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.listMembers(accessToken: accessToken, groupId: groupId);
  }

  Future<HostedInvite> createInvite({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.createInvite(accessToken: accessToken, groupId: groupId);
  }

  Future<void> revokeInvite({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.revokeInvite(accessToken: accessToken, groupId: groupId);
  }

  Future<List<HostedBuiltin>> listBuiltins() => _delegate.listBuiltins();

  Future<List<HostedGroupApp>> listGroupApps({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.listGroupApps(accessToken: accessToken, groupId: groupId);
  }

  Future<HostedGroupApp> installBuiltin({
    required String accessToken,
    required String groupId,
    required String builtinId,
  }) {
    return _delegate.installBuiltin(
      accessToken: accessToken,
      groupId: groupId,
      builtinId: builtinId,
    );
  }

  Future<HostedLaunchGrant> createLaunch({
    required String accessToken,
    required String groupId,
    required String appId,
  }) {
    return _delegate.createLaunch(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
    );
  }
}
