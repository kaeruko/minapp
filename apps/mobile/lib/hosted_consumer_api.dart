import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'hosted_api.dart';
import 'hosted_edition.dart';
import 'hosted_runtime_bridge.dart';
import 'hosted_session_store.dart';
import 'refreshable_auth_client.dart';

export 'hosted_api.dart';

/// Edition-neutral authenticated API used by hosted consumer applications.
class HostedConsumerApi implements HostedPlatformApi {
  HostedConsumerApi({
    required Uri baseUri,
    required HostedEdition edition,
    http.Client? client,
    HostedSessionStore? sessionStore,
  })  : edition = edition,
        httpClient = client ?? http.Client(),
        _sessionStore = sessionStore ??
            SecureHostedSessionStore(
              refreshTokenStorageKey: edition.refreshTokenStorageKey,
            ) {
    _delegate = HostedApi(baseUri: baseUri, client: httpClient);
    _authClient = RefreshableAuthClient(
      baseUri: baseUri,
      client: httpClient,
    );
  }

  final HostedEdition edition;
  late final HostedApi _delegate;
  final http.Client httpClient;
  late final RefreshableAuthClient _authClient;
  final HostedSessionStore _sessionStore;
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

    final AuthenticatedSession session = result.toSession();
    await _ensureCommunity(session);

    final String? refreshToken = result.refreshToken;
    if (refreshToken == null) {
      await _sessionStore.clearRefreshToken();
    } else {
      await _sessionStore.writeRefreshToken(refreshToken);
    }

    debugPrint(
      '${edition.displayName} session login: refresh token '
      '${refreshToken == null ? 'unavailable' : 'saved'}; '
      'access expires in ${session.expiresIn}s.',
    );
    _authenticatedSessions.add(session);
    return session;
  }

  Future<AuthenticatedSession?> restoreSession() async {
    final String? refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null) {
      debugPrint(
        '${edition.displayName} session restore: no saved refresh token.',
      );
      return null;
    }

    debugPrint('${edition.displayName} session restore: refreshing token.');
    try {
      final RefreshableAuthenticatedResult result =
          await _authClient.refresh(refreshToken);
      final AuthenticatedSession session = result.toSession();
      await _ensureCommunity(session);
      debugPrint('${edition.displayName} session restore: succeeded.');
      return session;
    } on ApiException catch (error) {
      if (error.statusCode == 401 && error.code == 'invalid_refresh_token') {
        debugPrint(
          '${edition.displayName} session restore: invalid refresh token; '
          'clearing saved login.',
        );
        await _sessionStore.clearRefreshToken();
        return null;
      }
      debugPrint(
        '${edition.displayName} session restore: API failure preserved saved '
        'login (HTTP ${error.statusCode}, code=${error.code}).',
      );
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        '${edition.displayName} session restore: ${error.runtimeType} '
        'preserved saved login.',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _ensureCommunity(AuthenticatedSession session) async {
    final List<HostedGroup> groups =
        await _delegate.listGroups(session.accessToken);
    edition.community.requireFrom(groups);
  }

  Future<void> logout() => _sessionStore.clearRefreshToken();

  Future<HostedLegalBundle> fetchLegal() => _delegate.fetchLegal();

  Future<HostedRegistrationResult> register({
    required String loginId,
    required String password,
    required HostedLegalBundle legal,
  }) =>
      _delegate.register(loginId: loginId, password: password, legal: legal);

  Future<HostedRecoveryResult> recover({
    required String loginId,
    required String recoveryCode,
    required String newPassword,
  }) =>
      _delegate.recover(
        loginId: loginId,
        recoveryCode: recoveryCode,
        newPassword: newPassword,
      );

  Future<void> deleteAccount(String accessToken) =>
      _delegate.deleteAccount(accessToken);

  Future<HostedEmailStatus> fetchEmailStatus(String accessToken) =>
      _delegate.fetchEmailStatus(accessToken);

  Future<HostedEmailLinkResult> requestEmailLink({
    required String accessToken,
    required String email,
  }) =>
      _delegate.requestEmailLink(accessToken: accessToken, email: email);

  Future<HostedEmailStatus> verifyEmailLink({
    required String accessToken,
    required String code,
  }) =>
      _delegate.verifyEmailLink(accessToken: accessToken, code: code);

  Future<List<HostedGroup>> listGroups(String accessToken) =>
      _delegate.listGroups(accessToken);

  Future<HostedGroup> createGroup({
    required String accessToken,
    required String name,
  }) =>
      _delegate.createGroup(accessToken: accessToken, name: name);

  Future<HostedGroup> joinGroup({
    required String accessToken,
    required String code,
  }) =>
      _delegate.joinGroup(accessToken: accessToken, code: code);

  Future<List<HostedMember>> listMembers({
    required String accessToken,
    required String groupId,
  }) =>
      _delegate.listMembers(accessToken: accessToken, groupId: groupId);

  Future<HostedInvite> createInvite({
    required String accessToken,
    required String groupId,
  }) =>
      _delegate.createInvite(accessToken: accessToken, groupId: groupId);

  Future<void> revokeInvite({
    required String accessToken,
    required String groupId,
  }) =>
      _delegate.revokeInvite(accessToken: accessToken, groupId: groupId);

  Future<List<HostedBuiltin>> listBuiltins() => _delegate.listBuiltins();

  Future<List<HostedGroupApp>> listGroupApps({
    required String accessToken,
    required String groupId,
  }) =>
      _delegate.listGroupApps(accessToken: accessToken, groupId: groupId);

  Future<HostedGroupApp> installBuiltin({
    required String accessToken,
    required String groupId,
    required String builtinId,
  }) =>
      _delegate.installBuiltin(
        accessToken: accessToken,
        groupId: groupId,
        builtinId: builtinId,
      );

  Future<HostedGroupApp> forkApp({
    required String accessToken,
    required String groupId,
    required String appId,
    required String title,
  }) =>
      _delegate.forkApp(
        accessToken: accessToken,
        groupId: groupId,
        appId: appId,
        title: title,
      );

  Future<HostedLaunchGrant> createLaunch({
    required String accessToken,
    required String groupId,
    required String appId,
  }) =>
      _delegate.createLaunch(
        accessToken: accessToken,
        groupId: groupId,
        appId: appId,
      );
}
